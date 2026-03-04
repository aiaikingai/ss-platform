from pathlib import Path
import csv

from labtool.split_and_delta import split_and_build_delta


def write_csv(path: Path, header: list[str], rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


MOONEY_HEADER = [
    "ID", "MethodName", "SampleName", "TestDate", "TestTime", "Operator",
    "Batch", "LimitData", "SampleNo", "ManufactureDate", "MV"
]

SCORCH_HEADER = [
    "ID", "MethodName", "SampleName", "TestDate", "TestTime", "Operator",
    "Batch", "LimitData", "SampleNo", "LM", "t5"
]


def test_mooney_new_then_correction(tmp_path: Path):
    source_id_file = tmp_path / "source_id.txt"
    source_id_file.write_text("MOONEY_PC_01", encoding="utf-8")
    out_root = tmp_path / "out" / "MOONEY"

    input1 = tmp_path / "mooney1.csv"
    write_csv(input1, MOONEY_HEADER, [[
        "1", "门尼", "W6039-ST", "08/24/23 00:00:00", "14:46:05", "",
        "500", "", "1", "2023/8/24", "68.603"
    ]])
    r1 = split_and_build_delta(input1, source_id_file, out_root)
    assert r1["new_rows"] == 1
    assert r1["corrected_rows"] == 0

    input2 = tmp_path / "mooney2.csv"
    write_csv(input2, MOONEY_HEADER, [[
        "1", "门尼", "W6039-ST", "08/24/23 00:00:00", "14:46:05", "",
        "500", "", "1", "2023/8/24", "69.000"
    ]])
    r2 = split_and_build_delta(input2, source_id_file, out_root)
    assert r2["new_rows"] == 0
    assert r2["corrected_rows"] == 1


def test_scorch_new_then_correction(tmp_path: Path):
    source_id_file = tmp_path / "source_id.txt"
    source_id_file.write_text("MOONEY_PC_01", encoding="utf-8")
    out_root = tmp_path / "out" / "SCORCH"

    input1 = tmp_path / "scorch1.csv"
    write_csv(input1, SCORCH_HEADER, [[
        "1", "焦烧", "W6059-TJ2", "08/24/23 00:00:00", "13:22:12", "",
        "4", "", "1", "31.163", "219.625"
    ]])
    r1 = split_and_build_delta(input1, source_id_file, out_root)
    assert r1["new_rows"] == 1
    assert r1["corrected_rows"] == 0

    input2 = tmp_path / "scorch2.csv"
    write_csv(input2, SCORCH_HEADER, [[
        "1", "焦烧", "W6059-TJ2", "08/24/23 00:00:00", "13:22:12", "",
        "4", "", "1", "31.900", "219.625"  # LM changed
    ]])
    r2 = split_and_build_delta(input2, source_id_file, out_root)
    assert r2["new_rows"] == 0
    assert r2["corrected_rows"] == 1