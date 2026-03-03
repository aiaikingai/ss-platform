from __future__ import annotations

import csv
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List

from labcore.hashers import build_record_hash
from labcore.keys import build_unique_key
from labcore.schema import MDR_SOURCE_COLUMNS
from labcore.state import StateStore


def read_source_id(path: Path) -> str:
    value = path.read_text(encoding="utf-8").strip()
    if not value:
        raise ValueError(f"source_id is empty: {path}")
    return value


def split_and_build_delta(
    input_csv: Path,
    source_id_file: Path,
    out_root: Path,
) -> dict:
    """
    Reads one CSV, splits by stream_id (= source_id__MethodName),
    writes snapshots and per-stream delta files (NEW/CORRECTION).
    """
    source_id = read_source_id(source_id_file)

    snapshots_dir = out_root / "snapshots"
    delta_dir = out_root / "delta"
    state_db = out_root / "state" / "index.sqlite"

    snapshots_dir.mkdir(parents=True, exist_ok=True)
    delta_dir.mkdir(parents=True, exist_ok=True)

    state = StateStore(state_db)

    with input_csv.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    day = datetime.now().strftime("%Y-%m-%d")
    delta_day_dir = delta_dir / day
    delta_day_dir.mkdir(parents=True, exist_ok=True)

    grouped: Dict[str, List[dict]] = defaultdict(list)
    for row in rows:
        method = (row.get("MethodName") or "").strip()
        if not method:
            continue
        stream_id = f"{source_id}__{method}"
        grouped[stream_id].append(row)

    new_count = 0
    corrected_count = 0

    for stream_id, stream_rows in grouped.items():
        # Snapshot: full content (debug)
        snapshot_path = snapshots_dir / f"{stream_id}__snapshot.csv"
        _write_snapshot(snapshot_path, stream_rows, source_id, stream_id, now)

        delta_rows: List[dict] = []
        pending_updates = []
        for row in stream_rows:
            unique_key = build_unique_key(row, source_id=source_id)
            rec_hash = build_record_hash(row, include_fields=MDR_SOURCE_COLUMNS)

            last_hash = state.get_last_hash(unique_key)
            if last_hash is None:
                change_type = "NEW"
                new_count += 1
            elif last_hash != rec_hash:
                change_type = "CORRECTION"
                corrected_count += 1
            else:
                continue

            out_row = dict(row)
            out_row["source_id"] = source_id
            out_row["stream_id"] = stream_id
            out_row["ingest_time"] = now
            out_row["unique_key"] = unique_key
            out_row["record_hash"] = rec_hash
            out_row["change_type"] = change_type
            delta_rows.append(out_row)

            pending_updates.append((unique_key, rec_hash))

        if delta_rows:
            delta_path = delta_day_dir / f"{stream_id}__delta.csv"
            _write_delta(delta_path, delta_rows)
            state.set_last_hash_many(pending_updates)
    return {
        "streams": sorted(grouped.keys()),
        "total_rows": len(rows),
        "new_rows": new_count,
        "corrected_rows": corrected_count,
    }


def _write_snapshot(path: Path, rows: List[dict], source_id: str, stream_id: str, now: str) -> None:
    if not rows:
        return

    fieldnames = list(rows[0].keys())
    for meta in ["source_id", "stream_id", "ingest_time"]:
        if meta not in fieldnames:
            fieldnames.append(meta)

    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            out = dict(r)
            out["source_id"] = source_id
            out["stream_id"] = stream_id
            out["ingest_time"] = now
            w.writerow(out)


def _write_delta(path: Path, rows: List[dict]) -> None:
    fieldnames = list(rows[0].keys())
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)
