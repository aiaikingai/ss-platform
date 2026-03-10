import argparse
import csv
import datetime as dt
import os
import shutil
import sys
import tempfile
import traceback
import time


def get_china_tz():
    """
    Return Asia/Shanghai timezone if available.
    If zoneinfo/tzdata is missing, fall back to fixed UTC+8.
    """
    try:
        from zoneinfo import ZoneInfo
        try:
            return ZoneInfo("Asia/Shanghai")
        except Exception:
            return dt.timezone(dt.timedelta(hours=8), name="CST")
    except Exception:
        return dt.timezone(dt.timedelta(hours=8), name="CST")


CHINA_TZ = get_china_tz()

try:
    import pyodbc
except ImportError:
    print("ERROR: pyodbc is not installed.", file=sys.stderr)
    print("Install it with:", file=sys.stderr)
    print("  py -m pip install pyodbc", file=sys.stderr)
    sys.exit(1)


# ----------------------------
# Config / tunables
# ----------------------------
DRIVER_NAMES = [
    "Microsoft Access Driver (*.mdb, *.accdb)",
    "Microsoft Access Driver (*.mdb)",
]

CSV_ENCODING = "utf-8-sig"   # Excel-friendly on Windows
CSV_DIALECT = "excel"

TABLE_CANDIDATES = ["Values", "Data", "Result", "Results"]

ID_CANDIDATES = [
    "id", "ID", "Id",
    "index", "Index",
    "recordid", "RecordID",
    "RECID",
    "NO", "No", "no",
    "SN", "sn",
    "序号", "编号"
]


# ----------------------------
# Utility helpers
# ----------------------------
def now_cn_str() -> str:
    return dt.datetime.now(CHINA_TZ).strftime("%Y-%m-%d %H:%M:%S CST")


def file_modified_utc_iso(path: str) -> str:
    try:
        ts = os.path.getmtime(path)
        return dt.datetime.utcfromtimestamp(ts).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        return ""


def file_modified_local_cn(path: str) -> str:
    try:
        ts = os.path.getmtime(path)
        local_dt = dt.datetime.fromtimestamp(ts, CHINA_TZ)
        return local_dt.strftime("%Y-%m-%d %H:%M:%S CST")
    except Exception:
        return ""


def find_access_driver():
    """
    Find an installed Microsoft Access ODBC driver.
    """
    available = list(pyodbc.drivers())
    for driver in DRIVER_NAMES:
        if driver in available:
            return driver
    raise RuntimeError(
        f"No suitable Access ODBC driver found. Available drivers: {available}"
    )


def list_user_tables(cursor):
    """
    Return normal user tables only (skip MSys/temp tables).
    """
    names = []
    for row in cursor.tables(tableType="TABLE"):
        table_name = row.table_name
        if table_name.startswith("MSys"):
            continue
        if table_name.startswith("~TMP"):
            continue
        if table_name.startswith("~TMPCLP"):
            continue
        names.append(table_name)
    return names


def pick_table(cursor, forced_table=None):
    """
    Choose which MDB table to read.
    Priority:
    1) forced table
    2) known candidates
    3) first user table found
    """
    if forced_table:
        return forced_table

    tables = list_user_tables(cursor)
    for candidate in TABLE_CANDIDATES:
        if candidate in tables:
            return candidate

    return tables[0] if tables else None


def get_columns(cursor, table):
    """
    Read table columns without fetching data.
    """
    probe = cursor.execute(f"SELECT * FROM [{table}] WHERE 1=0")
    return [d[0] for d in probe.description] if probe.description else []


def pick_order_column(columns, forced=None):
    """
    Pick a sensible ORDER BY column.
    This helps keep exported row order stable.
    """
    if not columns:
        return None

    lower_map = {c.lower(): c for c in columns}

    if forced and forced.lower() in lower_map:
        return lower_map[forced.lower()]

    for candidate in ID_CANDIDATES:
        if candidate.lower() in lower_map:
            return lower_map[candidate.lower()]

    return None


def copy_mdb_to_temp(src_path: str, work_dir: str, log_lines: list[str]) -> str:
    """
    Copy the MDB to a temp location before reading.
    Reason:
    live MDB may be locked or being written by machine software.
    """
    os.makedirs(work_dir, exist_ok=True)

    base_name = os.path.basename(src_path)
    temp_name = f"tmp_read__{base_name}"
    temp_path = os.path.join(work_dir, temp_name)

    shutil.copy2(src_path, temp_path)
    log_lines.append(f"[INFO] Copied MDB to temp: {src_path} -> {temp_path}")
    return temp_path


def read_rows(cursor, table, order_col):
    """
    Read all rows from the selected table.
    """
    sql = f"SELECT * FROM [{table}]"
    if order_col:
        sql += f" ORDER BY [{order_col}]"
    return cursor.execute(sql)


def atomic_write_csv(output_csv: str, header: list[str], all_rows: list[list[str]], log_lines: list[str]):
    """
    Write CSV atomically:
    1) write temp file
    2) replace final file

    Why:
    prevents half-written ALL_Values.csv if process crashes during write.
    """
    os.makedirs(os.path.dirname(output_csv), exist_ok=True)

    temp_csv = output_csv + ".tmp"

    with open(temp_csv, "w", newline="", encoding=CSV_ENCODING, errors="replace") as f:
        writer = csv.writer(f, dialect=CSV_DIALECT)
        writer.writerow(header)
        writer.writerows(all_rows)
        f.flush()
        os.fsync(f.fileno())

    os.replace(temp_csv, output_csv)
    log_lines.append(f"[INFO] Atomic CSV replace complete: {output_csv}")


# ----------------------------
# Main extraction logic
# ----------------------------
def convert_many_to_single_csv(
    base_dir,
    output_csv,
    log_lines,
    forced_table=None,
    forced_orderby=None,
    retries=3,
    delay=3,
    pc_name=None,
    only_file_name=None,
    temp_copy_dir=None,
):
    """
    Scan MDB files under base_dir, read each, align columns, and write one canonical ALL_Values.csv.
    """
    driver = find_access_driver()

    # 1) Find MDB files
    discovered_mdbs = []
    target_name = only_file_name.lower() if only_file_name else None

    for root, _, files in os.walk(base_dir):
        for file_name in files:
            if not file_name.lower().endswith((".mdb", ".accdb")):
                continue
            if target_name and file_name.lower() != target_name:
                continue

            discovered_mdbs.append(os.path.join(root, file_name))

    discovered_mdbs.sort()

    if not discovered_mdbs:
        log_lines.append(f"[WARN] No MDB files found under: {base_dir} (filter={only_file_name or 'none'})")
        return

    log_lines.append(f"[INFO] Found {len(discovered_mdbs)} MDB file(s) under: {base_dir}")

    # 2) First pass: build union of all columns
    union_columns = []
    union_set = set()

    for mdb_path in discovered_mdbs:
        for attempt in range(1, retries + 1):
            temp_mdb = None
            try:
                # copy-before-read for safety
                temp_mdb = copy_mdb_to_temp(mdb_path, temp_copy_dir, log_lines)

                with pyodbc.connect(f"Driver={{{driver}}};DBQ={temp_mdb};", autocommit=True) as conn:
                    cursor = conn.cursor()
                    table = pick_table(cursor, forced_table)

                    if not table:
                        log_lines.append(f"[WARN] {mdb_path}: no usable user table found")
                        break

                    columns = get_columns(cursor, table)

                    # schema logging
                    log_lines.append(f"[SCHEMA] {mdb_path} :: table={table} :: columns={columns}")

                    if not columns:
                        log_lines.append(f"[WARN] {mdb_path}: table {table} has no columns")
                        break

                    for col in columns:
                        if col not in union_set:
                            union_set.add(col)
                            union_columns.append(col)

                    break

            except Exception as e:
                if attempt < retries:
                    time.sleep(delay)
                else:
                    log_lines.append(f"[ERR] {mdb_path}: could not inspect after {retries} attempts: {e}")
                    log_lines.append(traceback.format_exc())
            finally:
                if temp_mdb and os.path.exists(temp_mdb):
                    try:
                        os.remove(temp_mdb)
                    except Exception:
                        pass

    # 3) Build final header
    meta_columns = ["__SourceMDB", "__FileModifiedUtc", "__FileModifiedLocal"]
    if pc_name:
        meta_columns.insert(0, "__PC")

    header = union_columns + meta_columns

    # 4) Second pass: read and align rows
    all_output_rows = []
    total_rows = 0

    for mdb_path in discovered_mdbs:
        connection = None
        temp_mdb = None

        for attempt in range(1, retries + 1):
            try:
                temp_mdb = copy_mdb_to_temp(mdb_path, temp_copy_dir, log_lines)
                connection = pyodbc.connect(f"Driver={{{driver}}};DBQ={temp_mdb};", autocommit=True)
                break
            except Exception as e:
                if attempt < retries:
                    time.sleep(delay)
                else:
                    log_lines.append(f"[ERR] {mdb_path}: open failed after retries: {e}")
                    log_lines.append(traceback.format_exc())

        if connection is None:
            continue

        try:
            cursor = connection.cursor()
            table = pick_table(cursor, forced_table)

            if not table:
                log_lines.append(f"[WARN] {mdb_path}: no user tables found")
                continue

            columns = get_columns(cursor, table)
            order_col = pick_order_column(columns, forced_orderby)

            rows = read_rows(cursor, table, order_col)
            col_index = {col: i for i, col in enumerate(columns)}

            count_this_file = 0
            for row in rows:
                out_row = []

                # align to union header
                for union_col in union_columns:
                    if union_col in col_index:
                        value = row[col_index[union_col]]
                        out_row.append("" if value is None else str(value))
                    else:
                        out_row.append("")

                meta_values = [
                    mdb_path,
                    file_modified_utc_iso(mdb_path),
                    file_modified_local_cn(mdb_path),
                ]
                if pc_name:
                    meta_values.insert(0, pc_name)

                out_row += meta_values
                all_output_rows.append(out_row)

                total_rows += 1
                count_this_file += 1

            log_lines.append(
                f"[OK] {mdb_path} :: table={table} :: rows={count_this_file} :: order_by={order_col or 'none'}"
            )

        except Exception as e:
            log_lines.append(f"[ERR] {mdb_path}: {e}")
            log_lines.append(traceback.format_exc())
        finally:
            try:
                if connection:
                    connection.close()
            except Exception:
                pass

            if temp_mdb and os.path.exists(temp_mdb):
                try:
                    os.remove(temp_mdb)
                except Exception:
                    pass

    # 5) Write one canonical latest ALL_Values.csv
    atomic_write_csv(output_csv, header, all_output_rows, log_lines)
    log_lines.append(f"[INFO] Combined CSV written: {output_csv} (rows={total_rows})")


# ----------------------------
# CLI entrypoint
# ----------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Aggregate multiple MDBs into one canonical ALL_Values.csv"
    )
    parser.add_argument(
        "--base",
        default=r"F:\Evolution\File\1",
        help="Base directory to scan recursively for MDB files"
    )
    parser.add_argument(
        "-o",
        "--output",
        default=r"C:\SSLab\MDR_PC_01",
        help="Stable machine output folder (ALL_Values.csv will be written here)"
    )
    parser.add_argument(
        "--table",
        default=None,
        help="Force table name instead of auto-pick"
    )
    parser.add_argument(
        "--order-by",
        dest="orderby",
        default=None,
        help="Force ORDER BY column instead of auto-pick"
    )
    parser.add_argument(
        "--pc-name",
        default=None,
        help="Optional PC tag written into metadata columns (example: MDR_PC_01)"
    )
    parser.add_argument(
        "--retries",
        type=int,
        default=5,
        help="Open retries for locked MDBs"
    )
    parser.add_argument(
        "--delay",
        type=int,
        default=5,
        help="Seconds between retries"
    )
    parser.add_argument(
        "--file-name",
        default="Data.mdb",
        help="Only process MDBs whose filename matches this (case-insensitive)"
    )
    parser.add_argument(
        "--temp-copy-dir",
        default=r"C:\SSLab\temp_mdb_copy",
        help="Temporary folder used for copy-before-read safety"
    )

    args = parser.parse_args()

    os.makedirs(args.output, exist_ok=True)

    output_csv = os.path.join(args.output, "ALL_Values.csv")
    log_path = os.path.join(args.output, "extract_log.txt")

    log_lines = []
    log_lines.append(f"=== Aggregate Run @ {now_cn_str()} ===")
    log_lines.append(f"[INFO] Base directory: {args.base}")
    log_lines.append(f"[INFO] Output folder: {args.output}")
    log_lines.append(f"[INFO] Output CSV: {output_csv}")
    log_lines.append(f"[INFO] File filter: {args.file_name}")
    log_lines.append(f"[INFO] Temp copy dir: {args.temp_copy_dir}")

    try:
        convert_many_to_single_csv(
            base_dir=args.base,
            output_csv=output_csv,
            log_lines=log_lines,
            forced_table=args.table,
            forced_orderby=args.orderby,
            retries=args.retries,
            delay=args.delay,
            pc_name=args.pc_name,
            only_file_name=args.file_name,
            temp_copy_dir=args.temp_copy_dir,
        )
    except Exception as e:
        log_lines.append(f"[FATAL] {e}")
        log_lines.append(traceback.format_exc())

    with open(log_path, "w", encoding="utf-8") as f:
        f.write("\n".join(log_lines))

    print("\n".join(log_lines))
    print(f"\n[INFO] Log written to: {log_path}")
    print(f"[INFO] Output CSV written to: {output_csv}")


if __name__ == "__main__":
    main()