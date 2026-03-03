from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Optional, Iterable, Tuple


class StateStore:
    """
    SQLite state store: remembers the last record_hash for each unique_key.

    Why this exists:
    - Prevent duplicate deltas on reruns
    - Detect corrections when hash changes
    """

    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path)

    def _init_db(self) -> None:
        with self._connect() as con:
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS record_state (
                    unique_key TEXT PRIMARY KEY,
                    last_hash  TEXT NOT NULL
                )
                """
            )

    def get_last_hash(self, unique_key: str) -> Optional[str]:
        with self._connect() as con:
            cur = con.execute(
                "SELECT last_hash FROM record_state WHERE unique_key = ?",
                (unique_key,),
            )
            row = cur.fetchone()
            return row[0] if row else None

    def set_last_hash(self, unique_key: str, record_hash: str) -> None:
        with self._connect() as con:
            con.execute(
                """
                INSERT INTO record_state (unique_key, last_hash)
                VALUES (?, ?)
                ON CONFLICT(unique_key) DO UPDATE SET last_hash=excluded.last_hash
                """,
                (unique_key, record_hash),
            )
    def set_last_hash_many(self, updates: Iterable[Tuple[str, str]]) -> None:
        updates = list(updates)
        if not updates:
            return
        with self._connect() as con:
            con.executemany(
                """
                INSERT INTO record_state (unique_key, last_hash)
                VALUES (?, ?)
                ON CONFLICT(unique_key) DO UPDATE SET last_hash=excluded.last_hash
                """,
                updates,
            )
