"""B站 API 客户端"""

import json
import time
import logging
from typing import Optional

import httpx

from .types import (
    DynamicItem, DynamicModules, ModuleDynamic, ModuleStat, StatItem,
    AuthorInfo, DynamicDesc, DynamicMajor, MajorDraw, MajorArchive,
    MajorArticle, MajorOpus, MajorCommon, OpusText, OpusPic, DrawItem,
    TopicInfo, OpusFeedItem, OpusCover,
)

logger = logging.getLogger(__name__)

FEED_SPACE_URL = "https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/space"
OPUS_FEED_URL = "https://api.bilibili.com/x/polymer/web-dynamic/v1/opus/feed/space"
SPI_URL = "https://api.bilibili.com/x/frontend/finger/spi"


class BiliClient:
    def __init__(self, user_agent: str, cookie: str = ""):
        self.client = httpx.Client(
            headers={"User-Agent": user_agent},
            timeout=30.0,
            follow_redirects=True,
        )
        self.cookie = cookie
        self._buvid3: Optional[str] = None
        self._buvid4: Optional[str] = None

    def _ensure_buvid(self):
        if self._buvid3:
            return
        logger.debug("acquiring buvid from SPI endpoint")
        resp = self.client.get(SPI_URL, headers={"Referer": "https://www.bilibili.com"})
        data = resp.json()
        spi_data = data.get("data")
        if spi_data:
            self._buvid3 = spi_data.get("b_3")
            self._buvid4 = spi_data.get("b_4")
            logger.info("acquired buvid3=%s", self._buvid3)

    def _build_cookie(self) -> str:
        parts = []
        if self._buvid3:
            parts.append(f"buvid3={self._buvid3}")
        if self._buvid4:
            parts.append(f"buvid4={self._buvid4}")
        if self.cookie:
            parts.append(self.cookie)
        return "; ".join(parts)

    def _headers(self, cookie: str) -> dict:
        return {
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
            "Referer": "https://www.bilibili.com",
            "Origin": "https://www.bilibili.com",
            "Cookie": cookie,
        }

    def _parse_item(self, raw: dict) -> DynamicItem:
        """将旧格式 API 返回的原始 JSON 解析为 DynamicItem"""
        mods = raw.get("modules", {})
        author_raw = mods.get("module_author") or {}
        md_raw = mods.get("module_dynamic") or {}
        stat_raw = mods.get("module_stat") or {}

        # author
        pub_ts_val = author_raw.get("pub_ts")
        if pub_ts_val is not None and isinstance(pub_ts_val, str):
            try:
                pub_ts_val = int(pub_ts_val)
            except ValueError:
                pub_ts_val = None

        author = AuthorInfo(
            mid=author_raw.get("mid"),
            name=author_raw.get("name", ""),
            face=author_raw.get("face"),
            pub_ts=pub_ts_val,
            pub_action=author_raw.get("pub_action"),
            pub_time=author_raw.get("pub_time"),
        ) if author_raw else None

        # desc
        desc = None
        desc_raw = md_raw.get("desc")
        if desc_raw:
            nodes = desc_raw.get("rich_text_nodes") or []
            desc = DynamicDesc(
                text=desc_raw.get("text"),
                rich_text_nodes=nodes,
            )

        # topic
        topic = None
        topic_raw = md_raw.get("topic")
        if topic_raw:
            topic = TopicInfo(
                id=topic_raw.get("id"),
                name=topic_raw.get("name"),
            )

        # major
        major = None
        major_raw = md_raw.get("major")
        if major_raw:
            mt = major_raw.get("type", "")
            draw = archive = article = opus = common = None

            if mt == "MAJOR_TYPE_DRAW" and major_raw.get("draw"):
                items = [DrawItem(
                    src=i.get("src", ""),
                    width=i.get("width"),
                    height=i.get("height"),
                ) for i in major_raw["draw"].get("items", [])]
                draw = MajorDraw(items=items)

            elif mt == "MAJOR_TYPE_ARCHIVE" and major_raw.get("archive"):
                a = major_raw["archive"]
                archive = MajorArchive(
                    aid=a.get("aid"), bvid=a.get("bvid"),
                    title=a.get("title"), desc=a.get("desc"),
                    cover=a.get("cover"), duration_text=a.get("duration_text"),
                )

            elif mt == "MAJOR_TYPE_ARTICLE" and major_raw.get("article"):
                a = major_raw["article"]
                article = MajorArticle(
                    id=a.get("id"), title=a.get("title"),
                    desc=a.get("desc"), covers=a.get("covers"),
                )

            elif mt == "MAJOR_TYPE_OPUS" and major_raw.get("opus"):
                o = major_raw["opus"]
                opus_text = None
                if o.get("summary"):
                    opus_text = OpusText(
                        text=o["summary"].get("text"),
                        rich_text_nodes=o["summary"].get("rich_text_nodes"),
                    )
                opus = MajorOpus(
                    title=o.get("title"), summary=opus_text,
                    pics=o.get("pics"),
                )

            elif mt == "MAJOR_TYPE_COMMON" and major_raw.get("common"):
                c = major_raw["common"]
                common = MajorCommon(
                    cover=c.get("cover"), title=c.get("title"),
                    desc=c.get("desc"),
                )

            major = DynamicMajor(
                major_type=mt, draw=draw, archive=archive,
                article=article, opus=opus, common=common,
            )

        # stat
        stat = None
        if stat_raw:
            def _parse_stat_item(raw) -> Optional[StatItem]:
                if raw is None:
                    return None
                return StatItem(count=raw.get("count"), forbidden=raw.get("forbidden"))

            stat = ModuleStat(
                comment=_parse_stat_item(stat_raw.get("comment")),
                forward=_parse_stat_item(stat_raw.get("forward")),
                like=_parse_stat_item(stat_raw.get("like")),
            )

        module_dynamic = ModuleDynamic(desc=desc, major=major, topic=topic) if md_raw else None
        modules = DynamicModules(
            module_author=author,
            module_dynamic=module_dynamic,
            module_stat=stat,
        ) if mods else None

        return DynamicItem(
            id_str=raw.get("id_str", ""),
            dynamic_type=raw.get("type", ""),
            modules=modules,
            orig=None,  # 暂不处理嵌套转发
        )

    def fetch_space(self, uid: int, offset: Optional[str] = None) -> dict:
        """获取一页旧格式空间动态"""
        self._ensure_buvid()
        url = f"{FEED_SPACE_URL}?host_mid={uid}"
        if offset:
            url += f"&offset={offset}"

        cookie = self._build_cookie()
        resp = self.client.get(url, headers=self._headers(cookie))
        resp.raise_for_status()
        data = resp.json()
        if data.get("code") != 0:
            raise RuntimeError(f"B站 API 错误: code={data.get('code')} msg={data.get('message')}")
        return data.get("data", {})

    def get_all_dynamics(self, uid: int, max_pages: int = 1) -> list[DynamicItem]:
        """翻页拉取全部旧格式动态"""
        all_items = []
        offset: Optional[str] = None

        for page in range(max_pages):
            logger.info("fetching page %d uid=%d", page + 1, uid)
            data = self.fetch_space(uid, offset)
            items_raw = data.get("items", [])
            if not items_raw:
                break
            for raw in items_raw:
                all_items.append(self._parse_item(raw))
            if not data.get("has_more"):
                break
            offset = data.get("offset")
            time.sleep(0.5)

        return all_items

    def fetch_opus(self, uid: int, offset: Optional[str] = None) -> dict:
        """获取一页 Opus 格式动态（包含 content 文字）"""
        self._ensure_buvid()
        url = f"{OPUS_FEED_URL}?host_mid={uid}"
        if offset:
            url += f"&offset={offset}"

        cookie = self._build_cookie()
        resp = self.client.get(url, headers=self._headers(cookie))
        resp.raise_for_status()
        data = resp.json()
        if data.get("code") != 0:
            raise RuntimeError(f"Opus API 错误: code={data.get('code')} msg={data.get('message')}")
        return data.get("data", {})

    def get_all_opus(self, uid: int, max_pages: int = 1) -> list[OpusFeedItem]:
        """翻页拉取全部 Opus 格式动态"""
        all_items = []
        offset: Optional[str] = None

        for page in range(max_pages):
            logger.info("fetching opus page %d uid=%d", page + 1, uid)
            data = self.fetch_opus(uid, offset)
            items_raw = data.get("items", [])
            if not items_raw:
                break
            for raw in items_raw:
                cover = None
                cover_raw = raw.get("cover")
                if cover_raw:
                    cover = OpusCover(
                        url=cover_raw.get("url"),
                        width=cover_raw.get("width"),
                        height=cover_raw.get("height"),
                    )
                all_items.append(OpusFeedItem(
                    opus_id=str(raw.get("opus_id", "")),
                    content=raw.get("content"),
                    cover=cover,
                    jump_url=raw.get("jump_url"),
                    stat=raw.get("stat"),
                ))
            if not data.get("has_more"):
                break
            offset = data.get("offset")
            time.sleep(0.5)

        return all_items

    def build_opus_map(self, uid: int, max_pages: int = 1) -> dict[str, OpusFeedItem]:
        """返回 opus_id -> OpusFeedItem 的映射"""
        items = self.get_all_opus(uid, max_pages)
        return {item.opus_id: item for item in items if item.opus_id and item.content}

    def enrich_from_opus(self, items: list[DynamicItem], uid: int, max_pages: int = 1) -> list[DynamicItem]:
        """用 Opus API 的内容修补旧格式动态中 desc 为空的条目"""
        try:
            opus_map = self.build_opus_map(uid, max_pages)
            logger.info("opus map built: %d entries", len(opus_map))
        except Exception as e:
            logger.warning("opus fetch failed, using old format only: %s", e)
            return items

        for item in items:
            opus = opus_map.get(item.id_str)
            if not opus or not opus.content:
                continue
            text = opus.content.strip()
            if not text:
                continue

            # 确保 module_dynamic 存在
            if not item.modules:
                item.modules = DynamicModules()
            if not item.modules.module_dynamic:
                item.modules.module_dynamic = ModuleDynamic()

            md = item.modules.module_dynamic
            if md.desc is None:
                md.desc = DynamicDesc(text=text)
                logger.debug("enriched %s with opus text", item.id_str)

        return items

    def close(self):
        self.client.close()
