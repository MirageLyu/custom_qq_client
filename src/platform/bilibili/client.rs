use reqwest::Client;
use serde::Deserialize;
use tracing::{debug, info};

use crate::error::AppError;
use super::types::*;

#[derive(Debug, Deserialize)]
struct SpiResponse {
    #[allow(dead_code)]
    code: i64,
    data: Option<SpiData>,
}

#[derive(Debug, Deserialize)]
struct SpiData {
    b_3: Option<String>,
    b_4: Option<String>,
}

pub struct BiliClient {
    client: Client,
    cookie: Option<String>,
    buvid3: Option<String>,
    buvid4: Option<String>,
}

impl BiliClient {
    pub fn new(user_agent: &str, cookie: Option<String>) -> anyhow::Result<Self> {
        let client = Client::builder()
            .user_agent(user_agent)
            .build()?;
        let cookie = cookie.filter(|c| !c.is_empty());
        Ok(Self { client, cookie, buvid3: None, buvid4: None })
    }

    async fn ensure_buvid(&mut self) -> Result<(), AppError> {
        if self.buvid3.is_some() {
            return Ok(());
        }

        debug!("acquiring buvid from SPI endpoint");

        let resp = self.client
            .get("https://api.bilibili.com/x/frontend/finger/spi")
            .header("Referer", "https://www.bilibili.com")
            .send()
            .await?;

        let spi: SpiResponse = resp.json().await.map_err(|e| {
            AppError::Other(format!("failed to parse SPI response: {}", e))
        })?;

        if let Some(data) = spi.data {
            self.buvid3 = data.b_3;
            self.buvid4 = data.b_4;
            info!(buvid3 = ?self.buvid3, "acquired buvid");
        }

        Ok(())
    }

    fn build_cookie(&self) -> String {
        let mut parts = Vec::new();

        if let Some(b3) = &self.buvid3 {
            parts.push(format!("buvid3={}", b3));
        }
        if let Some(b4) = &self.buvid4 {
            parts.push(format!("buvid4={}", b4));
        }
        if let Some(cookie) = &self.cookie {
            parts.push(cookie.clone());
        }

        parts.join("; ")
    }

    pub async fn get_space_dynamics(
        &mut self,
        uid: u64,
        offset: Option<&str>,
    ) -> Result<DynamicFeedResponse, AppError> {
        self.ensure_buvid().await?;

        let mut url = format!(
            "https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/space?host_mid={}",
            uid
        );
        if let Some(offset) = offset {
            url.push_str(&format!("&offset={}", offset));
        }

        debug!(url = %url, "fetching dynamics");

        let cookie = self.build_cookie();
        let resp = self.client
            .get(&url)
            .header("Referer", "https://www.bilibili.com")
            .header("Origin", "https://www.bilibili.com")
            .header("Cookie", &cookie)
            .send()
            .await?;

        let status = resp.status();
        let body = resp.text().await?;

        if !status.is_success() {
            return Err(AppError::Other(format!(
                "HTTP {} - body: {}",
                status,
                &body[..body.len().min(500)]
            )));
        }

        let api_resp: BiliApiResponse<DynamicFeedResponse> =
            serde_json::from_str(&body).map_err(|e| {
                debug!(body = &body[..body.len().min(1000)], "failed to parse response");
                AppError::Other(format!("JSON parse error: {} | body prefix: {}", e, &body[..body.len().min(300)]))
            })?;

        if api_resp.code != 0 {
            return Err(AppError::BiliApi {
                code: api_resp.code,
                message: api_resp.message,
            });
        }

        api_resp.data.ok_or_else(|| AppError::BiliApi {
            code: -1,
            message: "response data is null".to_string(),
        })
    }

    pub async fn get_all_dynamics(
        &mut self,
        uid: u64,
        max_pages: usize,
    ) -> Result<Vec<DynamicItem>, AppError> {
        let mut all_items = Vec::new();
        let mut offset: Option<String> = None;

        for page in 0..max_pages {
            info!(page = page + 1, uid, "fetching page");

            let resp = self.get_space_dynamics(uid, offset.as_deref()).await?;

            if resp.items.is_empty() {
                break;
            }

            all_items.extend(resp.items);

            if !resp.has_more {
                break;
            }

            offset = resp.offset;
            tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        }

        Ok(all_items)
    }
}
