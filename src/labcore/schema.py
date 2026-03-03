# src/labcore/schema.py
from __future__ import annotations

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
