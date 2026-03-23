use serde::{Deserialize, Serialize};

/// B站 API 返回的数值字段可能是 number 或 string，此模块处理这种不一致性
mod lenient {
    use serde::{Deserialize, Deserializer};

    pub fn opt_i64<'de, D>(deserializer: D) -> Result<Option<i64>, D::Error>
    where
        D: Deserializer<'de>,
    {
        let v: Option<serde_json::Value> = Option::deserialize(deserializer)?;
        Ok(v.and_then(|v| match v {
            serde_json::Value::Number(n) => n.as_i64(),
            serde_json::Value::String(s) => s.parse().ok(),
            _ => None,
        }))
    }

    pub fn opt_f64<'de, D>(deserializer: D) -> Result<Option<f64>, D::Error>
    where
        D: Deserializer<'de>,
    {
        let v: Option<serde_json::Value> = Option::deserialize(deserializer)?;
        Ok(v.and_then(|v| match v {
            serde_json::Value::Number(n) => n.as_f64(),
            serde_json::Value::String(s) => s.parse().ok(),
            _ => None,
        }))
    }
}

// ── API 响应包装 ──

#[derive(Debug, Serialize, Deserialize)]
pub struct BiliApiResponse<T> {
    pub code: i64,
    pub message: String,
    pub data: Option<T>,
}

// ── 动态列表响应 ──

#[derive(Debug, Serialize, Deserialize)]
pub struct DynamicFeedResponse {
    pub has_more: bool,
    pub offset: Option<String>,
    pub update_baseline: Option<String>,
    #[serde(default)]
    pub items: Vec<DynamicItem>,
}

// ── 单条动态 ──

#[derive(Debug, Serialize, Deserialize)]
pub struct DynamicItem {
    pub id_str: String,
    #[serde(rename = "type", default)]
    pub dynamic_type: String,
    pub visible: Option<bool>,
    pub basic: Option<serde_json::Value>,
    pub modules: DynamicModules,
    pub orig: Option<Box<DynamicItem>>,
}

// ── 模块容器 ──

#[derive(Debug, Serialize, Deserialize)]
pub struct DynamicModules {
    pub module_author: Option<ModuleAuthor>,
    pub module_dynamic: Option<ModuleDynamic>,
    pub module_stat: Option<ModuleStat>,
    #[serde(flatten)]
    pub extra_modules: serde_json::Map<String, serde_json::Value>,
}

// ── 作者模块 ──

#[derive(Debug, Serialize, Deserialize)]
pub struct ModuleAuthor {
    #[serde(default, deserialize_with = "lenient::opt_i64")]
    pub mid: Option<i64>,
    pub name: String,
    pub face: Option<String>,
    #[serde(default, deserialize_with = "lenient::opt_i64")]
    pub pub_ts: Option<i64>,
    pub pub_action: Option<String>,
    pub pub_time: Option<String>,
    #[serde(rename = "type")]
    pub author_type: Option<String>,
    pub jump_url: Option<String>,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, serde_json::Value>,
}

// ── 动态内容模块 ──

#[derive(Debug, Serialize, Deserialize)]
pub struct ModuleDynamic {
    pub desc: Option<DynamicDesc>,
    pub major: Option<DynamicMajor>,
    pub topic: Option<TopicInfo>,
    pub additional: Option<serde_json::Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TopicInfo {
    #[serde(default, deserialize_with = "lenient::opt_i64")]
    pub id: Option<i64>,
    pub name: Option<String>,
    pub jump_url: Option<String>,
}

// ── 文字描述 ──

#[derive(Debug, Serialize, Deserialize)]
pub struct DynamicDesc {
    pub text: Option<String>,
    #[serde(default)]
    pub rich_text_nodes: Vec<RichTextNode>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RichTextNode {
    #[serde(rename = "type")]
    pub node_type: String,
    #[serde(default)]
    pub text: String,
    pub orig_text: Option<String>,
    pub emoji: Option<EmojiInfo>,
    pub jump_url: Option<String>,
    pub rid: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EmojiInfo {
    pub icon_url: Option<String>,
    pub text: Option<String>,
    #[serde(default, rename = "type", deserialize_with = "lenient::opt_i64")]
    pub emoji_type: Option<i64>,
    #[serde(default, deserialize_with = "lenient::opt_i64")]
    pub size: Option<i64>,
}

// ── 主要内容 ──

#[derive(Debug, Serialize, Deserialize)]
pub struct DynamicMajor {
    #[serde(rename = "type")]
    pub major_type: String,
    pub draw: Option<MajorDraw>,
    pub archive: Option<MajorArchive>,
    pub article: Option<MajorArticle>,
    pub common: Option<MajorCommon>,
    pub opus: Option<MajorOpus>,
    pub pgc: Option<serde_json::Value>,
    pub live_rcmd: Option<serde_json::Value>,
    pub courses: Option<serde_json::Value>,
    pub music: Option<serde_json::Value>,
    pub none: Option<serde_json::Value>,
}

// ── 图片类型 ──

#[derive(Debug, Serialize, Deserialize)]
pub struct MajorDraw {
    pub items: Vec<DrawItem>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DrawItem {
    pub src: String,
    #[serde(default, deserialize_with = "lenient::opt_i64")]
    pub width: Option<i64>,
    #[serde(default, deserialize_with = "lenient::opt_i64")]
    pub height: Option<i64>,
    #[serde(default, deserialize_with = "lenient::opt_f64")]
    pub size: Option<f64>,
    pub tags: Option<Vec<serde_json::Value>>,
}

// ── 视频类型 ──

#[derive(Debug, Serialize, Deserialize)]
pub struct MajorArchive {
    pub aid: Option<String>,
    pub bvid: Option<String>,
    pub title: Option<String>,
    pub desc: Option<String>,
    pub cover: Option<String>,
    pub duration_text: Option<String>,
    pub jump_url: Option<String>,
    pub stat: Option<ArchiveStat>,
    #[serde(default, rename = "type", deserialize_with = "lenient::opt_i64")]
    pub archive_type: Option<i64>,
    pub badge: Option<serde_json::Value>,
    #[serde(default, deserialize_with = "lenient::opt_i64")]
    pub disable_preview: Option<i64>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ArchiveStat {
    pub danmaku: Option<String>,
    pub play: Option<String>,
}

// ── 专栏类型 ──

#[derive(Debug, Serialize, Deserialize)]
pub struct MajorArticle {
    #[serde(default, deserialize_with = "lenient::opt_i64")]
    pub id: Option<i64>,
    pub title: Option<String>,
    pub desc: Option<String>,
    pub covers: Option<Vec<String>>,
    pub jump_url: Option<String>,
    pub label: Option<String>,
}

// ── 通用卡片类型 ──

#[derive(Debug, Serialize, Deserialize)]
pub struct MajorCommon {
    pub cover: Option<String>,
    pub title: Option<String>,
    pub desc: Option<String>,
    pub badge: Option<serde_json::Value>,
    #[serde(default, deserialize_with = "lenient::opt_i64")]
    pub biz_type: Option<i64>,
    pub jump_url: Option<String>,
    pub label: Option<String>,
    pub sketch_id: Option<String>,
    #[serde(default, deserialize_with = "lenient::opt_i64")]
    pub style: Option<i64>,
}

// ── Opus 图文类型（B站新格式） ──

#[derive(Debug, Serialize, Deserialize)]
pub struct MajorOpus {
    pub fold_action: Option<Vec<String>>,
    pub jump_url: Option<String>,
    pub pics: Option<Vec<OpusPic>>,
    pub summary: Option<OpusText>,
    pub title: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OpusPic {
    #[serde(default, deserialize_with = "lenient::opt_i64")]
    pub height: Option<i64>,
    #[serde(default, deserialize_with = "lenient::opt_i64")]
    pub width: Option<i64>,
    #[serde(default, deserialize_with = "lenient::opt_f64")]
    pub size: Option<f64>,
    pub url: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OpusText {
    pub rich_text_nodes: Option<Vec<RichTextNode>>,
    pub text: Option<String>,
}

// ── 互动数据模块 ──

#[derive(Debug, Serialize, Deserialize)]
pub struct ModuleStat {
    pub comment: Option<StatItem>,
    pub forward: Option<StatItem>,
    pub like: Option<StatItem>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct StatItem {
    #[serde(default, deserialize_with = "lenient::opt_i64")]
    pub count: Option<i64>,
    pub forbidden: Option<bool>,
}
