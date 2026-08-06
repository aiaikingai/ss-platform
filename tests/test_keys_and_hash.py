from domains.lab import build_unique_key
from core.hashers import build_record_hash
from core.schema import MDR_SOURCE_COLUMNS


def test_unique_key_stable_when_results_change():
    source_id = "MDR_PC_01"
    row1 = {
    "MethodName": "195℃测试15分钟",
    "ID": "999",
    "SampleName": "H39Q1",
    "Batch": "14",
    "TestDate": "2025-10-15 00:00:00",
    "TestTime": "14:52:55",
    "ML": "5.596",
    "MH": "16.477",}
    row2 = {**row1, "ML": "5.700", "MH": "16.900"}  # corrected results

    assert build_unique_key(row1, source_id) == build_unique_key(row2, source_id)


def test_record_hash_changes_when_any_included_field_changes():
    row1 = {"ML": "5.596", "MH": "16.477"}
    row2 = {"ML": "5.700", "MH": "16.477"}

    h1 = build_record_hash(row1, include_fields=MDR_SOURCE_COLUMNS)
    h2 = build_record_hash(row2, include_fields=MDR_SOURCE_COLUMNS)

    assert h1 != h2
