from pathlib import Path
import csv

from labtool.split_and_delta import split_and_build_delta


def write_csv(path: Path, header: list[str], rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


BASE_HEADER = [
    "ID", "MethodName", "SampleName", "TestDate", "TestTime",
    "Operator", "Batch", "LimitData", "SampleNo", "MV",
]

BASE_ROW = [
    "1", "门尼", "W6039-ST", "08/24/23 00:00:00", "14:46:05",
    "Zhang", "500", "", "1", "68.603",
]


def test_schema_evolution_stability(tmp_path: Path):
    """Adding a new empty column must not trigger CORRECTION rows (Test A)."""
    source_id_file = tmp_path / "source_id.txt"
    source_id_file.write_text("STABILITY_PC_01", encoding="utf-8")
    out_root = tmp_path / "out"

    input1 = tmp_path / "run1.csv"
    write_csv(input1, BASE_HEADER, [BASE_ROW])
    r1 = split_and_build_delta(input1, source_id_file, out_root)
    assert r1["new_rows"] == 1
    assert r1["corrected_rows"] == 0

    # Same data but with an extra column whose value is always empty
    extended_header = BASE_HEADER + ["NewMachineField"]
    extended_row = BASE_ROW + [""]
    input2 = tmp_path / "run2.csv"
    write_csv(input2, extended_header, [extended_row])
    r2 = split_and_build_delta(input2, source_id_file, out_root)
    assert r2["new_rows"] == 0
    assert r2["corrected_rows"] == 0


def test_empty_to_value_transition(tmp_path: Path):
    """Changing a field from empty to a real value must produce a CORRECTION (Test B)."""
    source_id_file = tmp_path / "source_id.txt"
    source_id_file.write_text("TRANSITION_PC_01", encoding="utf-8")
    out_root = tmp_path / "out"

    row_no_operator = [
        "1", "门尼", "W6039-ST", "08/24/23 00:00:00", "14:46:05",
        "", "500", "", "1", "68.603",
    ]
    input1 = tmp_path / "run1.csv"
    write_csv(input1, BASE_HEADER, [row_no_operator])
    r1 = split_and_build_delta(input1, source_id_file, out_root)
    assert r1["new_rows"] == 1
    assert r1["corrected_rows"] == 0

    row_with_operator = [
        "1", "门尼", "W6039-ST", "08/24/23 00:00:00", "14:46:05",
        "Zhang", "500", "", "1", "68.603",
    ]
    input2 = tmp_path / "run2.csv"
    write_csv(input2, BASE_HEADER, [row_with_operator])
    r2 = split_and_build_delta(input2, source_id_file, out_root)
    assert r2["new_rows"] == 0
    assert r2["corrected_rows"] == 1
