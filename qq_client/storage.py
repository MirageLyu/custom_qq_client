"""SQLite 存储"""

import json
import sqlite3
from pathlib import Path
from typing import Optional


class DynamicStore:
    def __init__(self, db_path: str):
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(db_path)
        self.conn.execute("""
            CREATE TABLE IF NOT EXISTS dynamics (
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
            )
        """)
        self.conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_dynamics_uid ON dynamics(uid)
        """)
        self.conn.commit()

    def exists(self, dynamic_id: str) -> bool:
        row = self.conn.execute(
            "SELECT 1 FROM dynamics WHERE id = ?", (dynamic_id,)
        ).fetchone()
        return row is not None

    def insert(self, dynamic_id: str, platform: str, uid: int,
               author_name: str, dynamic_type: str, text: str,
               raw_json: str, created_at: Optional[int] = None) -> bool:
        if self.exists(dynamic_id):
            return False
        import time as _time
        self.conn.execute(
            """INSERT INTO dynamics
               (id, platform, uid, author_name, dynamic_type, content_text, raw_json, created_at, fetched_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (dynamic_id, platform, uid, author_name, dynamic_type, text, raw_json,
             created_at, int(_time.time()))
        )
        self.conn.commit()
        return True

    def count_by_uid(self, uid: int) -> int:
        row = self.conn.execute(
            "SELECT COUNT(*) FROM dynamics WHERE uid = ?", (uid,)
        ).fetchone()
        return row[0] if row else 0

    def close(self):
        self.conn.close()
