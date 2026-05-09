"""B站 API 数据类型"""

from dataclasses import dataclass, field
from typing import Optional


# ─── 动态摘要（对外输出） ───

@dataclass
class StatsSummary:
    likes: int = 0
    comments: int = 0
    forwards: int = 0


@dataclass
class DynamicSummary:
    id: str
    url: str
    dynamic_type: str
    dynamic_type_label: str
    author: Optional[str]
    published_at: Optional[str]
    timestamp: Optional[int]
    title: Optional[str]
    text: Optional[str]
    thumbnail_url: Optional[str]
    headline_source: str
    stats: StatsSummary


@dataclass
class AccountOutput:
    game: str
    game_key: str
    uid: int
    items: list  # list[DynamicSummary]
    error: Optional[str] = None


# ─── B站 API 响应类型 ───

@dataclass
class BiliApiResponse:
    code: int = 0
    message: str = ""
    data: Optional[dict] = None


# ─── 空间动态列表 (旧格式: feed/space) ───

@dataclass
class AuthorInfo:
    mid: Optional[int] = None
    name: str = ""
    face: Optional[str] = None
    pub_ts: Optional[int] = None
    pub_action: Optional[str] = None
    pub_time: Optional[str] = None


@dataclass
class StatItem:
    count: Optional[int] = None
    forbidden: Optional[bool] = None


@dataclass
class ModuleStat:
    comment: Optional[StatItem] = None
    forward: Optional[StatItem] = None
    like: Optional[StatItem] = None


@dataclass
class RichTextNode:
    node_type: str = ""
    text: str = ""
    orig_text: Optional[str] = None
    jump_url: Optional[str] = None


@dataclass
class DynamicDesc:
    text: Optional[str] = None
    rich_text_nodes: list = field(default_factory=list)


@dataclass
class DrawItem:
    src: str = ""
    width: Optional[int] = None
    height: Optional[int] = None


@dataclass
class MajorDraw:
    items: list = field(default_factory=list)  # list[DrawItem]


@dataclass
class ArchiveStat:
    danmaku: Optional[str] = None
    play: Optional[str] = None


@dataclass
class MajorArchive:
    aid: Optional[str] = None
    bvid: Optional[str] = None
    title: Optional[str] = None
    desc: Optional[str] = None
    cover: Optional[str] = None
    duration_text: Optional[str] = None


@dataclass
class MajorArticle:
    id: Optional[int] = None
    title: Optional[str] = None
    desc: Optional[str] = None
    covers: Optional[list] = None


@dataclass
class OpusPic:
    url: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None


@dataclass
class OpusText:
    text: Optional[str] = None
    rich_text_nodes: Optional[list] = None


@dataclass
class MajorOpus:
    title: Optional[str] = None
    summary: Optional[OpusText] = None
    pics: Optional[list] = None  # list[OpusPic]


@dataclass
class MajorCommon:
    cover: Optional[str] = None
    title: Optional[str] = None
    desc: Optional[str] = None


@dataclass
class DynamicMajor:
    major_type: str = ""
    draw: Optional[MajorDraw] = None
    archive: Optional[MajorArchive] = None
    article: Optional[MajorArticle] = None
    opus: Optional[MajorOpus] = None
    common: Optional[MajorCommon] = None


@dataclass
class TopicInfo:
    id: Optional[int] = None
    name: Optional[str] = None


@dataclass
class ModuleDynamic:
    desc: Optional[DynamicDesc] = None
    major: Optional[DynamicMajor] = None
    topic: Optional[TopicInfo] = None


@dataclass
class DynamicModules:
    module_author: Optional[AuthorInfo] = None
    module_dynamic: Optional[ModuleDynamic] = None
    module_stat: Optional[ModuleStat] = None


@dataclass
class DynamicItem:
    id_str: str = ""
    dynamic_type: str = ""
    modules: Optional[DynamicModules] = None
    orig: Optional['DynamicItem'] = None


# ─── Opus 格式动态列表 (opus/feed/space) ───

@dataclass
class OpusCover:
    url: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None


@dataclass
class OpusFeedItem:
    opus_id: Optional[str] = None
    content: Optional[str] = None
    cover: Optional[OpusCover] = None
    jump_url: Optional[str] = None
    stat: Optional[dict] = None
