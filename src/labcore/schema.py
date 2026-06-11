# src/labcore/schema.py
from __future__ import annotations

from typing import Iterable

# Your normalized MDR CSV columns (source columns).
# Keep this list exactly aligned with the CSV header names.
MDR_SOURCE_COLUMNS: list[str] = [
    "ID",
    "MethodName",
    "SampleName",
    "Batch",
    "ML",
    "MH",
    "ts1",
    "ts2",
    "TC10",
    "TC50",
    "TC90",
    "TestResult",
    "SampleNo",
    "Operator",
    "LimitData",
    "TestTimes",
    "MechineNo",
    "Shift",
    "Item",
    "CarNO",
    "ManufactureDate",
    "TestDate",
    "TestTime",
]

# Columns we add in our pipeline
MDR_META_COLUMNS: list[str] = [
    "source_id",
    "stream_id",
    "ingest_time",
    "unique_key",
    "record_hash",
    "change_type",  # NEW / CORRECTION
]

MDR_ALL_COLUMNS: list[str] = MDR_SOURCE_COLUMNS + MDR_META_COLUMNS


def hash_include_fields(columns: Iterable[str], meta_fields: list[str]) -> list[str]:
    """
    Return the subset of columns to include in a record hash.

    Excluded:
    - columns starting with "__"  (extractor metadata: __SourceMDB, __FileModifiedUtc, etc.)
    - columns in meta_fields      (pipeline-added columns: source_id, record_hash, etc.)

    Everything else is hashed, so result fields from any machine type are
    automatically captured without maintaining a manual allowlist.
    """
    meta_set = set(meta_fields)
    return [c for c in columns if not c.startswith("__") and c not in meta_set]
