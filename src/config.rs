use serde::Deserialize;
use std::path::Path;

#[derive(Debug, Deserialize)]
pub struct AppConfig {
    pub bilibili: BilibiliConfig,
    pub storage: StorageConfig,
}

#[derive(Debug, Deserialize)]
pub struct BilibiliConfig {
    pub user_agent: String,
    pub cookie: Option<String>,
    pub accounts: Vec<BilibiliAccount>,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct BilibiliAccount {
    pub uid: u64,
    pub name: String,
    pub game: String,
}

#[derive(Debug, Deserialize)]
pub struct StorageConfig {
    pub db_path: String,
}

impl AppConfig {
    pub fn load(path: impl AsRef<Path>) -> anyhow::Result<Self> {
        let content = std::fs::read_to_string(path)?;
        let config: AppConfig = toml::from_str(&content)?;
        Ok(config)
    }
}
