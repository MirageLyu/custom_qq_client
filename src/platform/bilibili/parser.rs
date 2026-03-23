use super::types::*;

pub struct DynamicFormatter;

impl DynamicFormatter {
    pub fn format_dynamic(item: &DynamicItem) -> String {
        let mut parts = Vec::new();

        if let Some(author) = &item.modules.module_author {
            let time_str = author.pub_ts
                .and_then(|ts| chrono::DateTime::from_timestamp(ts, 0))
                .map(|dt| dt.format("%Y-%m-%d %H:%M:%S").to_string())
                .unwrap_or_default();

            parts.push(format!("[{}] {}", author.name, time_str));

            if let Some(action) = &author.pub_action {
                if !action.is_empty() {
                    parts.push(format!("  {}", action));
                }
            }
        }

        parts.push(format!("类型: {}", Self::type_label(&item.dynamic_type)));

        if let Some(dynamic) = &item.modules.module_dynamic {
            if let Some(desc) = &dynamic.desc {
                if let Some(text) = &desc.text {
                    if !text.is_empty() {
                        parts.push(String::new());
                        parts.push(text.clone());
                    }
                }
            }

            if let Some(major) = &dynamic.major {
                parts.push(String::new());
                parts.push(Self::format_major(major));
            }

            if let Some(topic) = &dynamic.topic {
                if let Some(name) = &topic.name {
                    parts.push(format!("话题: #{}", name));
                }
            }
        }

        if let Some(stat) = &item.modules.module_stat {
            let likes = stat.like.as_ref().and_then(|s| s.count).unwrap_or(0);
            let comments = stat.comment.as_ref().and_then(|s| s.count).unwrap_or(0);
            let forwards = stat.forward.as_ref().and_then(|s| s.count).unwrap_or(0);
            parts.push(format!("赞:{} 评论:{} 转发:{}", likes, comments, forwards));
        }

        parts.push(format!("链接: https://t.bilibili.com/{}", item.id_str));

        if let Some(orig) = &item.orig {
            parts.push(String::new());
            parts.push("--- 转发原文 ---".to_string());
            parts.push(Self::format_dynamic(orig));
        }

        parts.join("\n")
    }

    fn format_major(major: &DynamicMajor) -> String {
        match major.major_type.as_str() {
            "MAJOR_TYPE_DRAW" => Self::format_draw(major),
            "MAJOR_TYPE_ARCHIVE" => Self::format_archive(major),
            "MAJOR_TYPE_ARTICLE" => Self::format_article(major),
            "MAJOR_TYPE_OPUS" => Self::format_opus(major),
            "MAJOR_TYPE_COMMON" => Self::format_common(major),
            "MAJOR_TYPE_LIVE_RCMD" => "[直播推荐]".to_string(),
            "MAJOR_TYPE_PGC" => "[番剧/影视]".to_string(),
            "MAJOR_TYPE_COURSES" => "[课程]".to_string(),
            "MAJOR_TYPE_MUSIC" => "[音乐]".to_string(),
            "MAJOR_TYPE_NONE" => "[无内容]".to_string(),
            other => format!("[未知类型: {}]", other),
        }
    }

    fn format_draw(major: &DynamicMajor) -> String {
        let Some(draw) = &major.draw else {
            return "[图片]".to_string();
        };
        let count = draw.items.len();
        let urls: Vec<&str> = draw.items.iter().map(|i| i.src.as_str()).collect();
        format!("[图片x{}]\n{}", count, urls.join("\n"))
    }

    fn format_archive(major: &DynamicMajor) -> String {
        let Some(archive) = &major.archive else {
            return "[视频]".to_string();
        };
        let title = archive.title.as_deref().unwrap_or("未知标题");
        let duration = archive.duration_text.as_deref().unwrap_or("");
        let desc = archive.desc.as_deref().unwrap_or("");
        let cover = archive.cover.as_deref().unwrap_or("");
        let bvid = archive.bvid.as_deref().unwrap_or("");
        format!(
            "[视频] {}\n时长: {}\n简介: {}\n封面: {}\n视频链接: https://www.bilibili.com/video/{}",
            title, duration, desc, cover, bvid
        )
    }

    fn format_article(major: &DynamicMajor) -> String {
        let Some(article) = &major.article else {
            return "[专栏]".to_string();
        };
        let title = article.title.as_deref().unwrap_or("未知标题");
        let desc = article.desc.as_deref().unwrap_or("");
        let mut s = format!("[专栏] {}\n简介: {}", title, desc);
        if let Some(covers) = &article.covers {
            for c in covers {
                s.push_str(&format!("\n封面: {}", c));
            }
        }
        s
    }

    fn format_opus(major: &DynamicMajor) -> String {
        let Some(opus) = &major.opus else {
            return "[图文]".to_string();
        };
        let mut parts = Vec::new();
        if let Some(title) = &opus.title {
            if !title.is_empty() {
                parts.push(format!("[图文] {}", title));
            }
        }
        if let Some(summary) = &opus.summary {
            if let Some(text) = &summary.text {
                if !text.is_empty() {
                    parts.push(text.clone());
                }
            }
        }
        if let Some(pics) = &opus.pics {
            parts.push(format!("[图片x{}]", pics.len()));
            for pic in pics {
                if let Some(url) = &pic.url {
                    parts.push(url.clone());
                }
            }
        }
        if parts.is_empty() {
            "[图文]".to_string()
        } else {
            parts.join("\n")
        }
    }

    fn format_common(major: &DynamicMajor) -> String {
        let Some(common) = &major.common else {
            return "[通用卡片]".to_string();
        };
        let title = common.title.as_deref().unwrap_or("未知");
        let desc = common.desc.as_deref().unwrap_or("");
        format!("[卡片] {}\n{}", title, desc)
    }

    fn type_label(t: &str) -> &str {
        match t {
            "DYNAMIC_TYPE_DRAW" => "图文动态",
            "DYNAMIC_TYPE_AV" => "视频投稿",
            "DYNAMIC_TYPE_WORD" => "纯文字",
            "DYNAMIC_TYPE_FORWARD" => "转发",
            "DYNAMIC_TYPE_ARTICLE" => "专栏",
            "DYNAMIC_TYPE_LIVE_RCMD" => "直播",
            "DYNAMIC_TYPE_COMMON_SQUARE" => "通用卡片",
            "DYNAMIC_TYPE_COMMON_VERTICAL" => "通用竖版",
            "DYNAMIC_TYPE_PGC" => "番剧/影视",
            "DYNAMIC_TYPE_COURSES" => "课程",
            "DYNAMIC_TYPE_MUSIC" => "音乐",
            "DYNAMIC_TYPE_NONE" => "已删除/不可见",
            other => other,
        }
    }
}
