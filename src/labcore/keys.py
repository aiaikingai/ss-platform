from __future__ import annotations

from typing import Mapping

from labcore.methods import derive_method_code


def build_unique_key(row: Mapping[str, str], source_id: str) -> str:
    """
    🔒 LOCKED IDENTITY (do not drift):
      unique_key = source_id:method_code:ID

    Why:
    - IDs reset per method/mode, so method_code is required.
    - DB overwrites rows, so we must not depend on row position.
    - method_code is auto-derived => zero-maintenance.
    """

    def g(name: str) -> str:
        return (row.get(name) or "").strip()

    if not source_id:
        raise ValueError("source_id is required (set LAB_SOURCE_ID on that PC)")

    method_name = g("MethodName")
    record_id = g("ID")

    if not method_name:
        raise ValueError("Missing MethodName")

    method_code = derive_method_code(method_name)
    if record_id:
        return f"{source_id}:{method_code}:{record_id}"

    sample_name = g("SampleName")
    batch = g("Batch")
    test_date = g("TestDate")
    test_time = g("TestTime")

    if not sample_name:
        raise ValueError("Missing SampleName")
    if not batch:
        raise ValueError("Missing Batch")
    if not test_date or not test_time:
        raise ValueError("Missing TestDate/TestTime")

    return f"{source_id}:{method_code}:{sample_name}:{batch}:{test_date}:{test_time}"
