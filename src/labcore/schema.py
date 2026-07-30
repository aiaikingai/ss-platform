# src/labcore/schema.py
from __future__ import annotations

import hashlib
from pathlib import Path
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


def check_schema_fingerprint(columns: Iterable[str], fingerprint_path: Path) -> None:
    """
    Warn when the CSV column layout changes between runs.

    Computes a fingerprint of the sorted column list and compares it to the
    last-seen fingerprint stored at fingerprint_path. If they differ, prints a
    warning — a column was added or removed, which will change record hashes
    for any row that populates the new column, producing a CORRECTION wave.
    Always writes the current fingerprint so the warning fires only once per
    schema change.
    """
    current = hashlib.sha256(
        ",".join(sorted(columns)).encode("utf-8")
    ).hexdigest()[:16]

    if fingerprint_path.exists():
        previous = fingerprint_path.read_text(encoding="utf-8").strip()
        if previous != current:
            print(
                f"WARNING: CSV column layout changed (was {previous}, now {current}). "
                "Any rows that populate the new/removed column will produce CORRECTION entries."
            )

    fingerprint_path.write_text(current + "\n", encoding="utf-8")
