"""
Lab-domain rules: method-code derivation and lab record identity.

This module holds identity and derivation logic that applies to **lab
results only**. Other domains (bladders, Q3 materials, Banbury production,
etc.) have their own identity rules, which do NOT belong here.
"""

from __future__ import annotations

import hashlib
import re
from datetime import datetime
from typing import Mapping


def _short_hash(text: str, length: int = 6) -> str:
    """Stable short hash used for fallback method codes."""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:length].upper()


def _safe_slug(text: str) -> str:
    """
    Convert text to a safe ASCII identifier:
    - uppercase
    - non [A-Z0-9] -> underscore
    - collapse multiple underscores
    - trim underscores
    """
    s = text.upper()
    s = re.sub(r"[^A-Z0-9]+", "_", s)
    s = re.sub(r"_+", "_", s)
    s = s.strip("_")
    return s or "METHOD"


def _parse_temp_minutes(method_name: str) -> tuple[int, int] | None:
    """
    Try to parse (temp_c, minutes) from MethodName.

    Examples supported:
      - 195℃测试15分钟
      - 180℃ 测试 40分钟
      - 170C 10min
      - 165°C test 20 minutes
    """
    s = method_name.strip()

    temp_match = re.search(r"(\d{2,3})\s*(?:℃|°C|C)", s, flags=re.IGNORECASE)
    min_match = re.search(r"(\d{1,3})\s*(?:分钟|min|mins|minutes)", s, flags=re.IGNORECASE)

    if not temp_match or not min_match:
        return None

    return int(temp_match.group(1)), int(min_match.group(1))


def derive_method_code(method_name: str) -> str:
    """
    🔒 LOCKED RULES (do not drift)

    - If contains 焦烧 -> SCORCH
    - If contains 门尼 -> MOONEY
    - If temp+minutes parseable -> MDR-<temp>-<min>  (e.g., MDR-195-15)
    - Else fallback -> SAFE_SLUG + "_" + SHORT_HASH
    """
    if not method_name:
        return "METHOD_UNKNOWN"

    raw = method_name.strip()

    # Known Mooney terms
    if "焦烧" in raw:
        return "SCORCH"
    if "门尼" in raw:
        return "MOONEY"

    # MDR temp/min
    parsed = _parse_temp_minutes(raw)
    if parsed:
        temp_c, minutes = parsed
        return f"MDR-{temp_c}-{minutes}"

    # Fallback
    slug = _safe_slug(raw)
    suffix = _short_hash(raw, length=6)
    return f"{slug}_{suffix}"


def _clean(value: object) -> str:
    return "" if value is None else str(value).strip()


def _normalize_test_datetime(test_date: str, test_time: str) -> str:
    """
    Normalize TestDate + TestTime into one stable local timestamp string.

    Output format:
      YYYY-MM-DDTHH:MM:SS

    Handles common source formats such as:
      2026/1/1 0:00
      2026-01-01 00:00:00
      2026/01/01
      08/24/23 00:00:00
      08/24/2023 00:00:00
      1:42:12
      01:42
    """
    raw_date = _clean(test_date)
    raw_time = _clean(test_time)

    if not raw_date:
        raise ValueError("Missing TestDate")
    if not raw_time:
        raise ValueError("Missing TestTime")

    date_candidates = [
        "%Y/%m/%d %H:%M:%S",
        "%Y/%m/%d %H:%M",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y/%m/%d",
        "%Y-%m-%d",
        "%m/%d/%y %H:%M:%S",
        "%m/%d/%Y %H:%M:%S",
        "%m/%d/%y",
        "%m/%d/%Y",
    ]

    parsed_date = None
    for fmt in date_candidates:
        try:
            parsed_date = datetime.strptime(raw_date, fmt).date()
            break
        except ValueError:
            pass

    if parsed_date is None:
        date_part = raw_date.split()[0].replace("/", "-")
        parts = date_part.split("-")
        if len(parts) != 3:
            raise ValueError(f"Unrecognized TestDate format: {raw_date}")
        year, month, day = map(int, parts)
        parsed_date = datetime(year, month, day).date()

    parsed_time = None
    for fmt in ("%H:%M:%S", "%H:%M"):
        try:
            parsed_time = datetime.strptime(raw_time, fmt).time()
            break
        except ValueError:
            pass

    if parsed_time is None:
        raise ValueError(f"Unrecognized TestTime format: {raw_time}")

    return f"{parsed_date.isoformat()}T{parsed_time.strftime('%H:%M:%S')}"


def build_unique_key(row: Mapping[str, str], source_id: str) -> str:
    """
    🔒 LOCKED IDENTITY (updated permanent design):
      unique_key = source_id:method_code:ID:normalized_test_datetime

    Why:
    - IDs may not be future-proof forever if machine/archive behavior changes.
    - method_code is still required because IDs reset per method/mode.
    - normalized test datetime adds a stable event identity component.
    - do not use editable metadata like Batch / SampleName in the main identity.
    """

    def g(name: str) -> str:
        return _clean(row.get(name))

    if not source_id:
        raise ValueError("source_id is required (set LAB_SOURCE_ID on that PC)")

    method_name = g("MethodName")
    record_id = g("ID")
    test_date = g("TestDate")
    test_time = g("TestTime")

    if not method_name:
        raise ValueError("Missing MethodName")

    method_code = derive_method_code(method_name)

    if not record_id:
        raise ValueError("Missing ID")

    normalized_test_dt = _normalize_test_datetime(test_date, test_time)

    return f"{source_id}:{method_code}:{record_id}:{normalized_test_dt}"
