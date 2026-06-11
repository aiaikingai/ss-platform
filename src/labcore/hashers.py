from __future__ import annotations

import hashlib
import json
from typing import Iterable, Mapping


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def build_record_hash(row: Mapping[str, str], include_fields: Iterable[str]) -> str:
    payload: dict[str, str] = {}
    for f in include_fields:
        v = (row.get(f) or "").strip()
        if v:
            payload[f] = v

    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return sha256_text(canonical)
