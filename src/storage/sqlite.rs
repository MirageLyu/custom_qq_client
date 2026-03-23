use rusqlite::{Connection, params};
use std::path::Path;

use crate::error::AppError;

pub struct DynamicStore {
    conn: Connection,
}

#[derive(Debug)]
#[allow(dead_code)]
pub struct StoredDynamic {
    pub id: String,
    pub platform: String,
    pub uid: u64,
    pub author_name: Option<String>,
    pub dynamic_type: Option<String>,
    pub content_text: Option<String>,
    pub raw_json: String,
    pub created_at: Option<i64>,
    pub fetched_at: i64,
}

impl DynamicStore {
    pub fn new(db_path: impl AsRef<Path>) -> Result<Self, AppError> {
        if let Some(parent) = db_path.as_ref().parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| AppError::Other(format!("failed to create db directory: {}", e)))?;
        }

        let conn = Connection::open(db_path)?;
        let store = Self { conn };
        store.init_tables()?;
        Ok(store)
    }

    fn init_tables(&self) -> Result<(), AppError> {
        self.conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS dynamics (
                id          TEXT PRIMARY KEY,
                platform    TEXT NOT NULL,
                uid         INTEGER NOT NULL,
                author_name TEXT,
                dynamic_type TEXT,
                content_text TEXT,
                raw_json    TEXT NOT NULL,
                created_at  INTEGER,
                fetched_at  INTEGER NOT NULL,
                pushed      INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_dynamics_uid ON dynamics(uid);
            CREATE INDEX IF NOT EXISTS idx_dynamics_created ON dynamics(created_at);
            CREATE INDEX IF NOT EXISTS idx_dynamics_pushed ON dynamics(pushed);"
        )?;
        Ok(())
    }

    pub fn exists(&self, id: &str) -> Result<bool, AppError> {
        let count: i64 = self.conn.query_row(
            "SELECT COUNT(*) FROM dynamics WHERE id = ?1",
            params![id],
            |row| row.get(0),
        )?;
        Ok(count > 0)
    }

    pub fn insert_dynamic(
        &self,
        id: &str,
        platform: &str,
        uid: u64,
        author_name: &str,
        dynamic_type: &str,
        content_text: &str,
        raw_json: &str,
        created_at: Option<i64>,
    ) -> Result<bool, AppError> {
        if self.exists(id)? {
            return Ok(false);
        }

        let now = chrono::Utc::now().timestamp();
        self.conn.execute(
            "INSERT INTO dynamics (id, platform, uid, author_name, dynamic_type, content_text, raw_json, created_at, fetched_at, pushed)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 0)",
            params![id, platform, uid as i64, author_name, dynamic_type, content_text, raw_json, created_at, now],
        )?;
        Ok(true)
    }

    #[allow(dead_code)]
    pub fn get_unpushed(&self) -> Result<Vec<StoredDynamic>, AppError> {
        let mut stmt = self.conn.prepare(
            "SELECT id, platform, uid, author_name, dynamic_type, content_text, raw_json, created_at, fetched_at
             FROM dynamics WHERE pushed = 0 ORDER BY created_at ASC"
        )?;

        let rows = stmt.query_map([], |row| {
            Ok(StoredDynamic {
                id: row.get(0)?,
                platform: row.get(1)?,
                uid: row.get::<_, i64>(2)? as u64,
                author_name: row.get(3)?,
                dynamic_type: row.get(4)?,
                content_text: row.get(5)?,
                raw_json: row.get(6)?,
                created_at: row.get(7)?,
                fetched_at: row.get(8)?,
            })
        })?;

        let mut results = Vec::new();
        for row in rows {
            results.push(row?);
        }
        Ok(results)
    }

    #[allow(dead_code)]
    pub fn mark_pushed(&self, id: &str) -> Result<(), AppError> {
        self.conn.execute(
            "UPDATE dynamics SET pushed = 1 WHERE id = ?1",
            params![id],
        )?;
        Ok(())
    }

    pub fn count_by_uid(&self, uid: u64) -> Result<i64, AppError> {
        let count: i64 = self.conn.query_row(
            "SELECT COUNT(*) FROM dynamics WHERE uid = ?1",
            params![uid as i64],
            |row| row.get(0),
        )?;
        Ok(count)
    }
}
