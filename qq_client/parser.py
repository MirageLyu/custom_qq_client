"""动态摘要提取 & 格式化

将 B站 API 返回的 DynamicItem 转换为 DynamicSummary，
供 Skill 使用的 headline_source / thumbnail_url / stats 等字段在这里生成。
"""

from datetime import datetime, timezone, timedelta
from typing import Optional

from .types import (
    DynamicItem, DynamicSummary, StatsSummary
)

CST = timezone(timedelta(hours=8))

# 抽奖关键词
LOTTERY_KEYWORDS = ["抽奖", "开奖", "转发抽奖", "互动抽奖", "恭喜"]


def type_label(dynamic_type: str) -> str:
    _map = {
        "DYNAMIC_TYPE_DRAW": "图文动态",
        "DYNAMIC_TYPE_AV": "视频投稿",
        "DYNAMIC_TYPE_WORD": "纯文字",
        "DYNAMIC_TYPE_FORWARD": "转发",
        "DYNAMIC_TYPE_ARTICLE": "专栏",
        "DYNAMIC_TYPE_LIVE_RCMD": "直播",
        "DYNAMIC_TYPE_COMMON_SQUARE": "通用卡片",
        "DYNAMIC_TYPE_COMMON_VERTICAL": "通用竖版",
        "DYNAMIC_TYPE_PGC": "番剧/影视",
        "DYNAMIC_TYPE_COURSES": "课程",
        "DYNAMIC_TYPE_MUSIC": "音乐",
        "DYNAMIC_TYPE_NONE": "已删除/不可见",
    }
    return _map.get(dynamic_type, dynamic_type)


def is_low_value_forward(item: DynamicItem) -> bool:
    if item.dynamic_type != "DYNAMIC_TYPE_FORWARD":
        return False
    text = (extract_text(item) or "").replace(" ", "").lower()
    return any(kw in text for kw in LOTTERY_KEYWORDS)


def extract_title(item: DynamicItem) -> Optional[str]:
    md = item.modules.module_dynamic if item.modules else None
    if not md or not md.major:
        return None
    major = md.major
    mt = major.major_type
    if mt == "MAJOR_TYPE_ARCHIVE" and major.archive:
        return major.archive.title
    if mt == "MAJOR_TYPE_ARTICLE" and major.article:
        return major.article.title
    if mt == "MAJOR_TYPE_OPUS" and major.opus:
        return major.opus.title
    if mt == "MAJOR_TYPE_COMMON" and major.common:
        return major.common.title
    return None


def extract_text(item: DynamicItem) -> Optional[str]:
    md = item.modules.module_dynamic if item.modules else None
    if not md:
        return None

    # 1. desc.text
    if md.desc and md.desc.text:
        t = md.desc.text.strip()
        if t:
            return t

    # 2. desc.rich_text_nodes
    if md.desc and md.desc.rich_text_nodes:
        combined = "".join(
            n.get("text", "") or (n.get("orig_text") or "")
            for n in md.desc.rich_text_nodes
            if isinstance(n, dict)
        )
        combined = combined.strip()
        if combined:
            return combined

    # 3. major 各类型摘要
    if not md.major:
        return None
    major = md.major
    mt = major.major_type
    text = None
    if mt == "MAJOR_TYPE_ARCHIVE" and major.archive:
        text = major.archive.desc
    elif mt == "MAJOR_TYPE_ARTICLE" and major.article:
        text = major.article.desc
    elif mt == "MAJOR_TYPE_OPUS" and major.opus and major.opus.summary:
        text = major.opus.summary.text
    elif mt == "MAJOR_TYPE_COMMON" and major.common:
        text = major.common.desc

    if text:
        text = text.strip()
        if text:
            return text
    return None


def extract_thumbnail(item: DynamicItem) -> Optional[str]:
    md = item.modules.module_dynamic if item.modules else None
    if not md or not md.major:
        return None
    major = md.major
    url = None
    mt = major.major_type
    if mt == "MAJOR_TYPE_ARCHIVE" and major.archive:
        url = major.archive.cover
    elif mt == "MAJOR_TYPE_DRAW" and major.draw and major.draw.items:
        url = major.draw.items[0].src
    elif mt == "MAJOR_TYPE_ARTICLE" and major.article and major.article.covers:
        url = major.article.covers[0]
    elif mt == "MAJOR_TYPE_OPUS" and major.opus and major.opus.pics:
        pic0 = major.opus.pics[0]
        if hasattr(pic0, 'url'):
            url = pic0.url
        elif isinstance(pic0, dict):
            url = pic0.get("url")
    elif mt == "MAJOR_TYPE_COMMON" and major.common:
        url = major.common.cover

    if url:
        url = url.strip()
        if url.startswith("//"):
            url = f"https:{url}"
        if url:
            return url
    return None


def _truncate(s: str, max_chars: int) -> str:
    if len(s) <= max_chars:
        return s
    return s[:max_chars] + "…"


def build_headline_source(item: DynamicItem) -> str:
    """合并类型、标题、正文、话题，生成 ≤800 字的 headline_source"""
    parts = [f"类型: {type_label(item.dynamic_type)}"]

    title = extract_title(item)
    if title:
        parts.append(f"标题: {title}")

    text = extract_text(item)
    if text:
        parts.append(f"正文: {text}")

    # 话题
    md = item.modules.module_dynamic if item.modules else None
    if md and md.topic and md.topic.name:
        parts.append(f"话题: #{md.topic.name}")

    # 图文动态补充图片数量
    if item.dynamic_type == "DYNAMIC_TYPE_DRAW":
        if md and md.major and md.major.draw:
            cnt = len(md.major.draw.items)
            if cnt > 0:
                parts.append(f"图片数量: {cnt}")

    # 转发原文
    if item.dynamic_type == "DYNAMIC_TYPE_FORWARD" and item.orig:
        parts.append("---转发原文---")
        ot = extract_title(item.orig)
        if ot:
            parts.append(f"标题: {ot}")
        ox = extract_text(item.orig)
        if ox:
            parts.append(f"正文: {ox}")

    result = "\n".join(parts)
    return _truncate(result, 800)


def summarize(item: DynamicItem) -> DynamicSummary:
    author = None
    timestamp = None
    published_at = None

    if item.modules and item.modules.module_author:
        a = item.modules.module_author
        author = a.name if a.name else None
        timestamp = a.pub_ts
        if timestamp:
            dt = datetime.fromtimestamp(timestamp, tz=CST)
            published_at = dt.strftime("%Y-%m-%d %H:%M:%S")

    stats = StatsSummary()
    if item.modules and item.modules.module_stat:
        s = item.modules.module_stat
        if s.like and s.like.count:
            stats.likes = s.like.count
        if s.comment and s.comment.count:
            stats.comments = s.comment.count
        if s.forward and s.forward.count:
            stats.forwards = s.forward.count

    return DynamicSummary(
        id=item.id_str,
        url=f"https://t.bilibili.com/{item.id_str}",
        dynamic_type=item.dynamic_type,
        dynamic_type_label=type_label(item.dynamic_type),
        author=author,
        published_at=published_at,
        timestamp=timestamp,
        title=extract_title(item),
        text=extract_text(item),
        thumbnail_url=extract_thumbnail(item),
        headline_source=build_headline_source(item),
        stats=stats,
    )
