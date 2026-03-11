from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    src_dir = repo_root / "src"

    # Windows machine paths
    machine_output_dir = Path(r"C:\SSLab\MDR_PC_01")
    input_csv = machine_output_dir / "ALL_Values.csv"
    source_id_file = machine_output_dir / "source_id.txt"
    out_root = machine_output_dir / "out"

    # Step 1: run extractor
    extractor_cmd = [
        sys.executable,
        str(src_dir / "labtool" / "extract_aggregate_mdb.py"),
        "--base",
        r"F:\Evolution\File\1",
        "--output",
        str(machine_output_dir),
        "--pc-name",
        "MDR_PC_01",
        "--file-name",
        "Data.mdb",
        "--temp-copy-dir",
        r"C:\SSLab\temp_mdb_copy",
    ]

    print("=== STEP 1: EXTRACT MDB -> ALL_Values.csv ===")
    print("Running:", " ".join(extractor_cmd))
    result = subprocess.run(extractor_cmd, cwd=repo_root)
    if result.returncode != 0:
        print(f"\nERROR: extractor failed with exit code {result.returncode}")
        return result.returncode

    # Step 2: run split + delta
    sys.path.insert(0, str(src_dir))
    from labtool.split_and_delta import split_and_build_delta

    print("\n=== STEP 2: SPLIT + DELTA ===")
    summary = split_and_build_delta(
        input_csv=input_csv,
        source_id_file=source_id_file,
        out_root=out_root,
    )

    print("\nPipeline summary:")
    print(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
