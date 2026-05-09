"""CLI 入口: qq-client fetch / latest / stats"""

import json
import logging
import sys
from typing import Optional

import click

from .config import AppConfig, BilibiliAccount
from .client import BiliClient
from .parser import summarize, is_low_value_forward
from .storage import DynamicStore
from .types import AccountOutput, DynamicSummary

logger = logging.getLogger(__name__)

# 游戏名称规范化
GAME_ALIASES = {
    "genshin": "原神", "原神": "原神",
    "starrail": "崩坏：星穹铁道", "hsr": "崩坏：星穹铁道",
    "星铁": "崩坏：星穹铁道", "星穹铁道": "崩坏：星穹铁道",
    "崩坏星穹铁道": "崩坏：星穹铁道",
    "zzz": "绝区零", "绝区零": "绝区零",
}


def _normalize(game: str) -> str:
    return "".join(ch.lower() for ch in game if ch.isalnum() or ch.isspace()).replace(" ", "")


def _match_game(account: BilibiliAccount, query: str) -> bool:
    nq = _normalize(query)
    candidates = [
        _normalize(account.name),
        _normalize(account.game),
        *([_normalize(alias) for alias in {
            "原神": "genshin", "genshin": "原神",
            "崩坏星穹铁道": "starrail", "hsr": "starrail",
            "星铁": "starrail", "星穹铁道": "starrail",
            "绝区零": "zzz",
        }.get(_normalize(account.game), "")] if _normalize(account.game) else []),
    ]
    return any(c == nq for c in candidates if c)


def _resolve_accounts(cfg: AppConfig, game: Optional[str], all_games: bool) -> list[BilibiliAccount]:
    if all_games or not game:
        return cfg.bilibili.accounts
    return [a for a in cfg.bilibili.accounts if _match_game(a, game)]


@click.group()
@click.option("--config", "-c", "config_path", default="config.toml", help="配置文件路径")
@click.pass_context
def cli(ctx, config_path):
    ctx.ensure_object(dict)
    ctx.obj["config"] = AppConfig.load(config_path)


@cli.command()
@click.option("--uid", type=int, help="指定 UID 拉取")
@click.option("--all", "all_games", is_flag=True, help="拉取所有已配置账号")
@click.option("--pages", default=1, help="最大拉取页数")
@click.option("--format", "-f", "fmt", default="text", type=click.Choice(["text", "json"]))
@click.option("--show-all", is_flag=True, help="显示所有动态（包括已入库的）")
@click.pass_context
def fetch(ctx, uid, all_games, pages, fmt, show_all):
    """拉取 B站动态"""
    cfg: AppConfig = ctx.obj["config"]
    store = DynamicStore(cfg.storage.db_path)
    client = BiliClient(cfg.bilibili.user_agent, cfg.bilibili.cookie)

    if all_games:
        accounts = cfg.bilibili.accounts
    elif uid:
        accounts = [a for a in cfg.bilibili.accounts if a.uid == uid]
        if not accounts:
            click.echo(f"未找到 UID={uid} 对应的账号", err=True)
            sys.exit(1)
    else:
        click.echo("请指定 --uid <UID> 或 --all", err=True)
        sys.exit(1)

    try:
        for account in accounts:
            logger.info("拉取 %s (UID=%d)", account.name, account.uid)
            items = client.get_all_dynamics(account.uid, pages)
            # 用 opus 数据丰富
            items = client.enrich_from_opus(items, account.uid, pages)
            logger.info("获取到 %d 条动态", len(items))

            new_count = 0
            for item in items:
                from .parser import extract_text as _ext
                text = _ext(item) or ""
                raw = json.dumps(_item_to_dict(item), ensure_ascii=False)
                author = item.modules.module_author.name if item.modules and item.modules.module_author else ""
                pub_ts = item.modules.module_author.pub_ts if item.modules and item.modules.module_author else None

                is_new = store.insert(item.id_str, "bilibili", account.uid, author, item.dynamic_type, text, raw, pub_ts)
                if is_new:
                    new_count += 1

                if is_new or show_all:
                    if fmt == "json":
                        click.echo(json.dumps(_item_to_dict(item), ensure_ascii=False, indent=2))
                    else:
                        click.echo("=" * 60)
                        click.echo(item.id_str)
    finally:
        client.close()
        store.close()


@cli.command()
@click.option("--game", default=None, help="指定游戏：原神 / 星铁 / 绝区零")
@click.option("--all", "all_games", is_flag=True, help="查询所有游戏")
@click.option("--count", default=2, help="每个游戏返回条数")
@click.option("--pages", default=1, help="最大拉取页数")
@click.option("--format", "-f", "fmt", default="json", type=click.Choice(["text", "json"]))
@click.option("--include-forwards", is_flag=True, help="包含低价值转发动态")
@click.pass_context
def latest(ctx, game, all_games, count, pages, fmt, include_forwards):
    """查询最新动态摘要"""
    cfg: AppConfig = ctx.obj["config"]
    store = DynamicStore(cfg.storage.db_path)
    client = BiliClient(cfg.bilibili.user_agent, cfg.bilibili.cookie)
    accounts = _resolve_accounts(cfg, game, all_games)

    if not accounts:
        click.echo(f"未找到匹配 '{game}' 的游戏", err=True)
        sys.exit(1)

    outputs = []
    try:
        for account in accounts:
            logger.info("查询最新动态: %s (UID=%d)", account.name, account.uid)
            try:
                items = client.get_all_dynamics(account.uid, pages)

                # 入库
                for item in items:
                    from .parser import extract_text as _ext
                    text = _ext(item) or ""
                    raw = json.dumps(_item_to_dict(item), ensure_ascii=False)
                    author = item.modules.module_author.name if item.modules and item.modules.module_author else ""
                    pub_ts = item.modules.module_author.pub_ts if item.modules and item.modules.module_author else None
                    store.insert(item.id_str, "bilibili", account.uid, author, item.dynamic_type, text, raw, pub_ts)

                # 用 opus 数据丰富文字
                items = client.enrich_from_opus(items, account.uid, pages)

                # 过滤 + 摘要
                summaries: list[DynamicSummary] = []
                for item in items:
                    if not include_forwards and is_low_value_forward(item):
                        continue
                    summaries.append(summarize(item))

                summaries.sort(key=lambda s: s.timestamp or 0, reverse=True)
                summaries = summaries[:count]

                outputs.append(AccountOutput(
                    game=account.name,
                    game_key=account.game,
                    uid=account.uid,
                    items=summaries,
                ))

            except Exception as err:
                logger.error("查询失败: %s", err)
                outputs.append(AccountOutput(
                    game=account.name,
                    game_key=account.game,
                    uid=account.uid,
                    items=[],
                    error=str(err),
                ))

        if fmt == "json":
            click.echo(json.dumps(
                [_account_output_to_dict(o) for o in outputs],
                ensure_ascii=False, indent=2,
            ))
        else:
            for o in outputs:
                click.echo(f"【{o.game}】最新动态")
                if o.error:
                    click.echo(f"获取失败：{o.error}")
                    continue
                for idx, item in enumerate(o.items, 1):
                    headline = item.title or item.text or item.dynamic_type_label
                    if headline and len(headline) > 72:
                        headline = headline[:72] + "..."
                    click.echo(f"{idx}. [{item.dynamic_type_label}] {headline}")
                    if item.published_at:
                        click.echo(f"   发布时间：{item.published_at}")
                    click.echo(f"   点赞 {item.stats.likes} | 评论 {item.stats.comments} | 转发 {item.stats.forwards}")
                    click.echo(f"   链接：{item.url}")

    finally:
        client.close()
        store.close()


@cli.command()
@click.pass_context
def stats(ctx):
    """查看数据库统计"""
    cfg: AppConfig = ctx.obj["config"]
    store = DynamicStore(cfg.storage.db_path)
    click.echo("=== 数据库统计 ===")
    for account in cfg.bilibili.accounts:
        cnt = store.count_by_uid(account.uid)
        click.echo(f"[{account.name}] (UID: {account.uid}): {cnt} 条动态")
    store.close()


# ─── JSON 序列化辅助 ───

def _to_serializable(obj):
    """递归转换 dataclass / 对象为 JSON 兼容的 dict"""
    if obj is None:
        return None
    if isinstance(obj, (str, int, float, bool)):
        return obj
    if isinstance(obj, list):
        return [_to_serializable(v) for v in obj]
    if isinstance(obj, dict):
        return {k: _to_serializable(v) for k, v in obj.items()}
    if hasattr(obj, '__dataclass_fields__'):
        return {f.name: _to_serializable(getattr(obj, f.name)) for f in obj.__dataclass_fields__.values()}
    if hasattr(obj, '__dict__'):
        return {k: _to_serializable(v) for k, v in obj.__dict__.items() if not k.startswith('_')}
    return str(obj)


def _item_to_dict(item) -> dict:
    return _to_serializable(item)


def _account_output_to_dict(o: AccountOutput) -> dict:
    return {
        "game": o.game,
        "game_key": o.game_key,
        "uid": o.uid,
        "items": [
            {
                "id": s.id,
                "url": s.url,
                "dynamic_type": s.dynamic_type,
                "dynamic_type_label": s.dynamic_type_label,
                "author": s.author,
                "published_at": s.published_at,
                "timestamp": s.timestamp,
                "title": s.title,
                "text": s.text,
                "thumbnail_url": s.thumbnail_url,
                "headline_source": s.headline_source,
                "stats": {
                    "likes": s.stats.likes,
                    "comments": s.stats.comments,
                    "forwards": s.stats.forwards,
                },
            }
            for s in o.items
        ],
        "error": o.error,
    }
