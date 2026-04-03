use clap::{Parser, Subcommand};
use serde::Serialize;
use tracing::{error, info};

mod config;
mod error;
mod platform;
mod push;
mod storage;

use config::{AppConfig, BilibiliAccount};
use platform::bilibili::DynamicSummary;
use platform::bilibili::types::DynamicItem;
use storage::DynamicStore;

#[derive(Parser)]
#[command(name = "qq-client", about = "社媒动态监控与QQ推送")]
struct Cli {
    /// 配置文件路径
    #[arg(short, long, default_value = "config.toml")]
    config: String,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// 拉取 B站动态
    Fetch {
        /// 指定 UID 拉取
        #[arg(long)]
        uid: Option<u64>,

        /// 拉取所有已配置账号
        #[arg(long)]
        all: bool,

        /// 最大拉取页数
        #[arg(long, default_value = "1")]
        pages: usize,

        /// 输出格式: text / json
        #[arg(long, default_value = "text")]
        format: String,

        /// 显示所有动态（包括已入库的）
        #[arg(long)]
        show_all: bool,
    },

    /// 查询适合在 QQ / OpenClaw 中展示的最新动态摘要
    Latest {
        /// 指定游戏，如：原神 / 星铁 / 绝区零 / genshin / hsr / zzz
        #[arg(long)]
        game: Option<String>,

        /// 查询所有已配置账号；不传时默认也是全部
        #[arg(long)]
        all: bool,

        /// 每个游戏返回的条数
        #[arg(long, default_value = "2")]
        count: usize,

        /// 最大拉取页数
        #[arg(long, default_value = "1")]
        pages: usize,

        /// 输出格式: text / json
        #[arg(long, default_value = "text")]
        format: String,

        /// 包含低价值转发动态（默认会过滤抽奖/开奖类转发）
        #[arg(long)]
        include_forwards: bool,
    },

    /// 查看数据库统计
    Stats,
}

#[derive(Debug, Serialize)]
struct LatestAccountOutput {
    game: String,
    game_key: String,
    uid: u64,
    items: Vec<DynamicSummary>,
    error: Option<String>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_writer(std::io::stderr)
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("qq_client=info".parse()?)
        )
        .init();

    let cli = Cli::parse();
    let cfg = AppConfig::load(&cli.config)?;
    let store = DynamicStore::new(&cfg.storage.db_path)?;
    let mut client = platform::bilibili::BiliClient::new(
        &cfg.bilibili.user_agent,
        cfg.bilibili.cookie.clone(),
    )?;

    match cli.command {
        Commands::Fetch { uid, all, pages, format, show_all } => {
            cmd_fetch(&cfg, &mut client, &store, uid, all, pages, &format, show_all).await?;
        }
        Commands::Latest {
            game,
            all,
            count,
            pages,
            format,
            include_forwards,
        } => {
            cmd_latest(
                &cfg,
                &mut client,
                &store,
                game.as_deref(),
                all,
                count,
                pages,
                &format,
                include_forwards,
            )
            .await?;
        }
        Commands::Stats => {
            cmd_stats(&cfg, &store)?;
        }
    }

    Ok(())
}

async fn cmd_fetch(
    cfg: &AppConfig,
    client: &mut platform::bilibili::BiliClient,
    store: &DynamicStore,
    uid: Option<u64>,
    all: bool,
    pages: usize,
    format: &str,
    show_all: bool,
) -> anyhow::Result<()> {
    let accounts: Vec<_> = if all {
        cfg.bilibili.accounts.iter().collect()
    } else if let Some(uid) = uid {
        let matched: Vec<_> = cfg.bilibili.accounts.iter().filter(|a| a.uid == uid).collect();
        if matched.is_empty() {
            anyhow::bail!("未找到 UID={} 对应的账号，请检查 config.toml", uid);
        }
        matched
    } else {
        anyhow::bail!("请指定 --uid <UID> 或 --all");
    };

    for account in &accounts {
        info!(name = %account.name, uid = account.uid, "开始拉取动态");

        match client.get_all_dynamics(account.uid, pages).await {
            Ok(items) => {
                info!(count = items.len(), "获取到动态");

                let mut new_count = 0;
                for item in &items {
                    let text = platform::bilibili::DynamicFormatter::format_dynamic(item);
                    let is_new = persist_dynamic(store, account.uid, item)?;

                    if is_new {
                        new_count += 1;
                    }

                    if is_new || show_all {
                        match format {
                            "json" => println!("{}", serde_json::to_string_pretty(item)?),
                            _ => {
                                println!("{}", "=".repeat(60));
                                println!("{}", text);
                            }
                        }
                    }
                }

                info!(
                    name = %account.name,
                    new = new_count,
                    skipped = items.len() - new_count,
                    "拉取完成"
                );
            }
            Err(e) => {
                error!(name = %account.name, err = %e, "拉取失败");
            }
        }
    }

    Ok(())
}

async fn cmd_latest(
    cfg: &AppConfig,
    client: &mut platform::bilibili::BiliClient,
    store: &DynamicStore,
    game: Option<&str>,
    all: bool,
    count: usize,
    pages: usize,
    format: &str,
    include_forwards: bool,
) -> anyhow::Result<()> {
    let accounts = resolve_latest_accounts(cfg, game, all)?;
    let mut outputs = Vec::new();

    for account in accounts {
        info!(name = %account.name, uid = account.uid, "开始查询最新动态");

        match client.get_all_dynamics(account.uid, pages).await {
            Ok(items) => {
                for item in &items {
                    persist_dynamic(store, account.uid, item)?;
                }

                let mut summaries: Vec<_> = items
                    .iter()
                    .filter(|item| include_forwards || !platform::bilibili::DynamicFormatter::is_low_value_forward(item))
                    .map(platform::bilibili::DynamicFormatter::summarize)
                    .collect();

                summaries.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
                summaries.truncate(count);

                outputs.push(LatestAccountOutput {
                    game: account.name.clone(),
                    game_key: account.game.clone(),
                    uid: account.uid,
                    items: summaries,
                    error: None,
                });
            }
            Err(err) => {
                error!(name = %account.name, err = %err, "查询最新动态失败");
                outputs.push(LatestAccountOutput {
                    game: account.name.clone(),
                    game_key: account.game.clone(),
                    uid: account.uid,
                    items: Vec::new(),
                    error: Some(err.to_string()),
                });
            }
        }
    }

    match format {
        "json" => println!("{}", serde_json::to_string_pretty(&outputs)?),
        _ => print!("{}", render_latest_text(&outputs)),
    }

    Ok(())
}

fn cmd_stats(cfg: &AppConfig, store: &DynamicStore) -> anyhow::Result<()> {
    println!("=== 数据库统计 ===");
    for account in &cfg.bilibili.accounts {
        let count = store.count_by_uid(account.uid)?;
        println!("[{}] (UID: {}): {} 条动态", account.name, account.uid, count);
    }
    Ok(())
}

fn persist_dynamic(store: &DynamicStore, uid: u64, item: &DynamicItem) -> anyhow::Result<bool> {
    let raw = serde_json::to_string(item)?;
    let text = platform::bilibili::DynamicFormatter::format_dynamic(item);
    let author_name = item
        .modules
        .module_author
        .as_ref()
        .map(|a| a.name.clone());
    let pub_ts = item.modules.module_author.as_ref().and_then(|a| a.pub_ts);

    Ok(store.insert_dynamic(
        &item.id_str,
        "bilibili",
        uid,
        author_name.as_deref().unwrap_or(""),
        &item.dynamic_type,
        &text,
        &raw,
        pub_ts,
    )?)
}

fn resolve_latest_accounts<'a>(
    cfg: &'a AppConfig,
    game: Option<&str>,
    all: bool,
) -> anyhow::Result<Vec<&'a BilibiliAccount>> {
    if all || game.is_none() {
        return Ok(cfg.bilibili.accounts.iter().collect());
    }

    let query = game.unwrap_or_default();
    let matched: Vec<_> = cfg
        .bilibili
        .accounts
        .iter()
        .filter(|account| account_matches_game(account, query))
        .collect();

    if matched.is_empty() {
        anyhow::bail!("未找到与 `{}` 对应的游戏，请使用原神 / 星铁 / 绝区零", query);
    }

    Ok(matched)
}

fn account_matches_game(account: &BilibiliAccount, query: &str) -> bool {
    let normalized_query = normalize_game(query);
    let mut candidates = vec![normalize_game(&account.name), normalize_game(&account.game)];

    match account.game.as_str() {
        "genshin" => candidates.extend(["原神", "genshin"].map(normalize_game)),
        "starrail" => candidates.extend(["崩坏星穹铁道", "星穹铁道", "星铁", "hsr", "starrail"].map(normalize_game)),
        "zzz" => candidates.extend(["绝区零", "zzz"].map(normalize_game)),
        _ => {}
    }

    candidates.into_iter().any(|candidate| candidate == normalized_query)
}

fn normalize_game(input: &str) -> String {
    input
        .chars()
        .filter(|ch| !ch.is_whitespace() && *ch != ':' && *ch != '：' && *ch != '-' && *ch != '_')
        .flat_map(|ch| ch.to_lowercase())
        .collect()
}

fn render_latest_text(outputs: &[LatestAccountOutput]) -> String {
    let mut lines = Vec::new();

    for (index, output) in outputs.iter().enumerate() {
        if index > 0 {
            lines.push(String::new());
        }

        lines.push(format!("【{}】最新动态", output.game));

        if let Some(error) = &output.error {
            lines.push(format!("获取失败：{}", error));
            continue;
        }

        if output.items.is_empty() {
            lines.push("暂无可展示动态".to_string());
            continue;
        }

        for (idx, item) in output.items.iter().enumerate() {
            let headline = item
                .title
                .as_ref()
                .or(item.text.as_ref())
                .map(|value| truncate_text(value, 72))
                .unwrap_or_else(|| item.dynamic_type_label.clone());

            lines.push(format!("{}. [{}] {}", idx + 1, item.dynamic_type_label, headline));

            if let Some(published_at) = &item.published_at {
                lines.push(format!("   发布时间：{}", published_at));
            }

            lines.push(format!(
                "   点赞 {} | 评论 {} | 转发 {}",
                item.stats.likes, item.stats.comments, item.stats.forwards
            ));
            lines.push(format!("   链接：{}", item.url));
        }
    }

    if lines.is_empty() {
        lines.push("暂无结果".to_string());
    }

    format!("{}\n", lines.join("\n"))
}

fn truncate_text(input: &str, max_chars: usize) -> String {
    let mut truncated = input.chars().take(max_chars).collect::<String>();
    if input.chars().count() > max_chars {
        truncated.push_str("...");
    }
    truncated.replace('\n', " ")
}
