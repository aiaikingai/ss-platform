from __future__ import annotations

from datetime import datetime
from typing import Mapping

from core.methods import derive_method_code


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