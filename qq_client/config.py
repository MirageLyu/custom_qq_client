"""配置加载"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

try:
    import tomllib
except ImportError:
    import tomli as tomllib


@dataclass
class BilibiliAccount:
    uid: int
    name: str
    game: str


@dataclass
class BilibiliConfig:
    user_agent: str
    cookie: str = ""
    accounts: list = field(default_factory=list)  # list[BilibiliAccount]


@dataclass
class StorageConfig:
    db_path: str = "data/dynamics.db"


@dataclass
class AppConfig:
    bilibili: BilibiliConfig
    storage: StorageConfig = field(default_factory=StorageConfig)

    @classmethod
    def load(cls, path: str = "config.toml") -> "AppConfig":
        raw: dict = {}
        with open(path, "rb") as f:
            raw = tomllib.load(f)

        bili = raw.get("bilibili", {})

        accounts = []
        for acct in bili.get("accounts", []):
            accounts.append(BilibiliAccount(
                uid=acct["uid"],
                name=acct["name"],
                game=acct["game"],
            ))

        storage = StorageConfig(
            db_path=raw.get("storage", {}).get("db_path", "data/dynamics.db")
        )

        return cls(
            bilibili=BilibiliConfig(
                user_agent=bili.get("user_agent", ""),
                cookie=bili.get("cookie", ""),
                accounts=accounts,
            ),
            storage=storage,
        )
