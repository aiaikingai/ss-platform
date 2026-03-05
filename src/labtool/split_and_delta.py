from __future__ import annotations
import os
import csv
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List

from labcore.hashers import build_record_hash
from labcore.keys import build_unique_key
from labcore.state import StateStore
from labcore.methods import derive_method_code

META_FIELDS = [
    "method_code",
    "source_id",
    "stream_id",
    "ingest_time",
    "unique_key",
    "record_hash",
    "change_type",
]


def read_source_id(path: Path) -> str:
    # strip UTF-8 BOM if present, and whitespace
    value = path.read_text(encoding="utf-8").lstrip("\ufeff").strip()
    if not value:
        raise ValueError(f"source_id is empty: {path}")
    return value


def _read_rows_with_fallback(input_csv: Path) -> list[dict]:
    """
    Read CSV/TSV exported by lab systems.
    Try UTF-8-SIG first, then fallback to CP936 (GBK).
    """
    last_err: Exception | None = None
    for enc in ("utf-8-sig", "cp936"):
        try:
            with input_csv.open("r", encoding=enc, newline="") as f:
                # delimiter will be handled later; for now keep comma-based reader
                reader = csv.DictReader(f)
                return list(reader)
        except Exception as e:
            last_err = e
    raise last_err  # type: ignore


def split_and_build_delta(
    input_csv: Path,
    source_id_file: Path,
    out_root: Path,
) -> dict:
    """
    Reads one CSV, splits by stream_id (= source_id__method_code),
    writes snapshots and per-stream delta files (append-only daily).
    """
    source_id = read_source_id(source_id_file)

    snapshots_dir = out_root / "snapshots"
    delta_dir = out_root / "delta"
    state_db = out_root / "state" / "index.sqlite"

    snapshots_dir.mkdir(parents=True, exist_ok=True)
    delta_dir.mkdir(parents=True, exist_ok=True)
    state_db.parent.mkdir(parents=True, exist_ok=True)

    state = StateStore(state_db)

    rows = _read_rows_with_fallback(input_csv)
    source_fields = [k for k in (rows[0].keys() if rows else [])]

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    day = datetime.now().strftime("%Y-%m-%d")
    delta_day_dir = delta_dir / day
    delta_day_dir.mkdir(parents=True, exist_ok=True)

    # Group rows by safe stream_id = source_id__method_code
    grouped: Dict[str, List[dict]] = defaultdict(list)
    for row in rows:
        method_name = (row.get("MethodName") or "").strip()
        if not method_name:
            continue

        method_code = derive_method_code(method_name)
        row["method_code"] = method_code

        stream_id = f"{source_id}__{method_code}"
        grouped[stream_id].append(row)

    new_count = 0
    corrected_count = 0

    for stream_id, stream_rows in grouped.items():
        # Snapshot: full content (debug)
        snapshot_path = snapshots_dir / f"{stream_id}__snapshot.csv"
        _write_snapshot(snapshot_path, stream_rows, source_id, stream_id, now)

        delta_rows: List[dict] = []
        pending_updates: List[tuple[str, str]] = []

        for row in stream_rows:
            unique_key = build_unique_key(row, source_id=source_id)

            rec_hash = build_record_hash(row, include_fields=source_fields)

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
            _write_delta(delta_path, delta_rows)          # ✅ write first
            state.set_last_hash_many(pending_updates)     # ✅ then update state

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
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            out_row = dict(row)
            out_row["source_id"] = source_id
            out_row["stream_id"] = stream_id
            out_row["ingest_time"] = now
            writer.writerow(out_row)


def _write_delta(path: Path, rows: List[dict]) -> None:
    """
    Append-only delta writer (🔒 Decision 007).
    - One delta file per day + stream.
    - Append rows each run.
    - Write header only if file is new/empty.
    - fsync to reduce risk before sqlite state commit.
    """
    if not rows:
        return

    path.parent.mkdir(parents=True, exist_ok=True)

    # stable field order: input columns first, then meta
    input_fields = [k for k in rows[0].keys() if k not in META_FIELDS]
    fieldnames = input_fields + [f for f in META_FIELDS if f not in input_fields]

    write_header = not (path.exists() and path.stat().st_size > 0)

    with path.open("a", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        if write_header:
            w.writeheader()
        w.writerows(rows)

        f.flush()
        os.fsync(f.fileno())
