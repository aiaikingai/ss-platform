from __future__ import annotations
from typing import Mapping


def build_unique_key(row: Mapping[str, str], source_id: str) -> str:
    """
    Key v2 (ID-reset safe):
      source_id + MethodName + SampleName + Batch + TestDate + TestTime

    Assumption (per your statement): TestDate/TestTime do not get edited later.
    """
    def g(name: str) -> str:
        return (row.get(name) or "").strip()

    method = g("MethodName")
    sample = g("SampleName")
    batch = g("Batch")
    test_date = g("TestDate")
    test_time = g("TestTime")

    if not source_id:
        raise ValueError("source_id is required (set LAB_SOURCE_ID on that PC)")
    if not method:
        raise ValueError("Missing MethodName")
    if not sample:
        raise ValueError("Missing SampleName")
    if not batch:
        raise ValueError("Missing Batch")
    if not test_date or not test_time:
        raise ValueError("Missing TestDate/TestTime")

    return f"{source_id}:{method}:{sample}:{batch}:{test_date}:{test_time}"
