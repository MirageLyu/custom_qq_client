use clap::{Parser, Subcommand};
use tracing::{info, error};

mod config;
mod error;
mod platform;
mod storage;
mod push;

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

    /// 查看数据库统计
    Stats,
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
    let cfg = config::AppConfig::load(&cli.config)?;
    let store = storage::DynamicStore::new(&cfg.storage.db_path)?;
    let mut client = platform::bilibili::BiliClient::new(
        &cfg.bilibili.user_agent,
        cfg.bilibili.cookie.clone(),
    )?;

    match cli.command {
        Commands::Fetch { uid, all, pages, format, show_all } => {
            cmd_fetch(&cfg, &mut client, &store, uid, all, pages, &format, show_all).await?;
        }
        Commands::Stats => {
            cmd_stats(&cfg, &store)?;
        }
    }

    Ok(())
}

async fn cmd_fetch(
    cfg: &config::AppConfig,
    client: &mut platform::bilibili::BiliClient,
    store: &storage::DynamicStore,
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
                    let raw = serde_json::to_string(item)?;
                    let text = platform::bilibili::DynamicFormatter::format_dynamic(item);

                    let author_name = item.modules.module_author
                        .as_ref()
                        .map(|a| a.name.clone());

                    let pub_ts = item.modules.module_author
                        .as_ref()
                        .and_then(|a| a.pub_ts);

                    let is_new = store.insert_dynamic(
                        &item.id_str,
                        "bilibili",
                        account.uid,
                        author_name.as_deref().unwrap_or(""),
                        &item.dynamic_type,
                        &text,
                        &raw,
                        pub_ts,
                    )?;

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

fn cmd_stats(cfg: &config::AppConfig, store: &storage::DynamicStore) -> anyhow::Result<()> {
    println!("=== 数据库统计 ===");
    for account in &cfg.bilibili.accounts {
        let count = store.count_by_uid(account.uid)?;
        println!("[{}] (UID: {}): {} 条动态", account.name, account.uid, count);
    }
    Ok(())
}
