from pathlib import Path
import csv

from labtool.split_and_delta import split_and_build_delta


def write_csv(path: Path, header: list[str], rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


HEADER = [
    "ID", "MethodName", "SampleName", "Batch", "ML", "MH", "ts1", "ts2", "TC10", "TC50", "TC90",
    "TestResult", "SampleNo", "Operator", "LimitData", "TestTimes", "MechineNo", "Shift", "Item",
    "CarNO", "ManufactureDate", "TestDate", "TestTime"
]


def make_row(ml_value: str) -> list[str]:
    # 23 columns, must match HEADER exactly
    return [
        "7416",                 # ID
        "195℃测试15分钟",        # MethodName
        "H39Q1",                # SampleName
        "14",                   # Batch
        ml_value,               # ML
        "16.477",               # MH
        "33.5",                 # ts1
        "54.5",                 # ts2
        "35.3",                 # TC10
        "199.0",                # TC50
        "626.4",                # TC90
        "NG",                   # TestResult
        "1",                    # SampleNo
        "",                     # Operator
        "H39Q1",                # LimitData
        "7",                    # TestTimes
        "",                     # MechineNo
        "",                     # Shift
        "",                     # Item
        "",                     # CarNO
        "2025/10/15",           # ManufactureDate
        "2025-10-15 00:00:00",  # TestDate
        "14:52:55",             # TestTime
    ]


def test_new_then_no_duplicates(tmp_path: Path):
    input_csv = tmp_path / "input.csv"
    source_id_file = tmp_path / "source_id.txt"
    source_id_file.write_text("MDR_PC_01", encoding="utf-8")
    out_root = tmp_path / "out" / "MDR"

    write_csv(input_csv, HEADER, [make_row("5.596")])

    r1 = split_and_build_delta(input_csv, source_id_file, out_root)
    assert r1["new_rows"] == 1
    assert r1["corrected_rows"] == 0

    # rerun same input => no duplicates
    r2 = split_and_build_delta(input_csv, source_id_file, out_root)
    assert r2["new_rows"] == 0
    assert r2["corrected_rows"] == 0


def test_correction_detected(tmp_path: Path):
    source_id_file = tmp_path / "source_id.txt"
    source_id_file.write_text("MDR_PC_01", encoding="utf-8")
    out_root = tmp_path / "out" / "MDR"

    input_csv1 = tmp_path / "input1.csv"
    write_csv(input_csv1, HEADER, [make_row("5.596")])
    r1 = split_and_build_delta(input_csv1, source_id_file, out_root)
    assert r1["new_rows"] == 1
    assert r1["corrected_rows"] == 0

    # same record, ML changed => CORRECTION
    input_csv2 = tmp_path / "input2.csv"
    write_csv(input_csv2, HEADER, [make_row("5.700")])
    r2 = split_and_build_delta(input_csv2, source_id_file, out_root)
    assert r2["new_rows"] == 0
    assert r2["corrected_rows"] == 1
