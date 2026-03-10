import argparse
import csv
import datetime as dt
import os
import sys
import traceback
import time
# ---- Optional tzdata: robust China local time ----
def get_china_tz():
    """
    Try Asia/Shanghai via zoneinfo. If tzdata missing, fall back to fixed UTC+8.
    """
    try:
        from zoneinfo import ZoneInfo  # Python 3.9+
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
    print("ERROR: pyodbc not installed. Install it first:", file=sys.stderr)
    print("  py -m pip install pyodbc", file=sys.stderr)
    sys.exit(1)

# ---- Tunables ----
DRIVER_NAMES = [
    "Microsoft Access Driver (*.mdb, *.accdb)",
    "Microsoft Access Driver (*.mdb)",
]
CSV_ENCODING = "utf-8-sig"   # Excel-friendly
CSV_DIALECT = "excel"
TABLE_CANDIDATES = ["Values", "Data", "Result", "Results"]  # try in this order
ID_CANDIDATES = ["id", "ID", "Id", "index", "Index", "recordid", "RecordID",
                 "RECID", "NO", "No", "no", "SN", "sn", "序号", "编号"]
# -------------------

def find_access_driver():
    available = [d for d in pyodbc.drivers()]
    for t in DRIVER_NAMES:
        if t in available:
            return t
    raise RuntimeError(f"No suitable Access ODBC driver found. Available: {available}")

def list_user_tables(cursor):
    names = []
    for row in cursor.tables(tableType="TABLE"):
        n = row.table_name
        if n.startswith("MSys") or n.startswith("~TMP") or n.startswith("~TMPCLP"):
            continue
        names.append(n)
    return names

def pick_table(cursor, forced_table=None):
    if forced_table:
        return forced_table
    tbls = list_user_tables(cursor)
    for cand in TABLE_CANDIDATES:
        if cand in tbls:
            return cand
    return tbls[0] if tbls else None

def get_columns(cursor, table):
    probe = cursor.execute(f"SELECT * FROM [{table}] WHERE 1=0")
    return [d[0] for d in probe.description] if probe.description else []

def pick_order_column(cols, forced=None):
    if not cols:
        return None
    lower = {c.lower(): c for c in cols}
    if forced and forced.lower() in lower:
        return lower[forced.lower()]
    for c in ID_CANDIDATES:
        if c.lower() in lower:
            return lower[c.lower()]
    return None

def read_rows(cursor, table, order_col):
    sql = f"SELECT * FROM [{table}]"
    if order_col:
        sql += f" ORDER BY [{order_col}]"
    return cursor.execute(sql)

def file_modified_utc_iso(path: str) -> str:
    try:
        ts = os.path.getmtime(path)
        return dt.datetime.utcfromtimestamp(ts).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        return ""

def file_modified_local_cn(path: str) -> str:
    """Return China local time (Asia/Shanghai) as 'YYYY-MM-DD HH:MM:SS CST'."""
    try:
        ts = os.path.getmtime(path)
        local_dt = dt.datetime.fromtimestamp(ts, CHINA_TZ)
        # show CST explicitly; Asia/Shanghai handles DST (China has none currently)
        return local_dt.strftime("%Y-%m-%d %H:%M:%S CST")
    except Exception:
        return ""

def convert_many_to_single_csv(base_dir, out_csv, log_lines, forced_table=None, forced_orderby=None,
                               retries=3, delay=3, pc_name=None, only_file_name=None):
    drv = find_access_driver()

    # Discover MDBs (filtered by filename if provided)
    all_mdbs = []
    want = only_file_name.lower() if only_file_name else None
    for root, _, files in os.walk(base_dir):
        for fn in files:
            if fn.lower().endswith((".mdb", ".accdb")):
                if want and fn.lower() != want:
                    continue
                all_mdbs.append(os.path.join(root, fn))
    all_mdbs.sort()

    if not all_mdbs:
        log_lines.append(f"[WARN] No MDBs found under {base_dir} (filter={only_file_name or 'none'})")
        return

    log_lines.append(f"[INFO] Found {len(all_mdbs)} MDB files under {base_dir} (filter={only_file_name or 'none'})")

    # Build union of columns across encountered tables (stable header)
    union_cols, union_set = [], set()
    for mdb in all_mdbs:
        for attempt in range(1, retries + 1):
            try:
                with pyodbc.connect(f"Driver={{{drv}}};DBQ={mdb};", autocommit=True) as conn:
                    cur = conn.cursor()
                    tbl = pick_table(cur, forced_table)
                    if not tbl:
                        log_lines.append(f"[WARN] {mdb}: no user tables; skipped")
                        break
                    cols = get_columns(cur, tbl)
                    if not cols:
                        log_lines.append(f"[WARN] {mdb}: no columns in table {tbl}; skipped")
                        break
                    for c in cols:
                        if c not in union_set:
                            union_set.add(c)
                            union_cols.append(c)
                    break
            except Exception as e:
                if attempt < retries:
                    time.sleep(delay)
                else:
                    log_lines.append(f"[ERR] {mdb}: could not open after {retries} tries: {e}")
                    log_lines.append(traceback.format_exc())

    # Metadata columns (minimal + China local time)
    meta_cols = ["__SourceMDB", "__FileModifiedUtc", "__FileModifiedLocal"]
    if pc_name:
        meta_cols.insert(0, "__PC")
    header = union_cols + meta_cols

    os.makedirs(os.path.dirname(out_csv), exist_ok=True)
    total_rows = 0
    with open(out_csv, "w", newline="", encoding=CSV_ENCODING, errors="replace") as f:
        w = csv.writer(f, dialect=CSV_DIALECT)
        w.writerow(header)

        for mdb in all_mdbs:
            conn = None
            # retry opening (handles temporary locks)
            for attempt in range(1, retries + 1):
                try:
                    conn = pyodbc.connect(f"Driver={{{drv}}};DBQ={mdb};", autocommit=True)
                    break
                except Exception as e:
                    if attempt < retries:
                        time.sleep(delay)
                    else:
                        log_lines.append(f"[ERR] {mdb}: open failed: {e}")
                        log_lines.append(traceback.format_exc())
            if conn is None:
                continue

            try:
                cur = conn.cursor()
                tbl = pick_table(cur, forced_table)
                if not tbl:
                    log_lines.append(f"[WARN] {mdb}: no user tables; skipped")
                    conn.close(); conn = None
                    continue

                cols = get_columns(cur, tbl)
                order_col = pick_order_column(cols, forced_orderby)
                rows = read_rows(cur, tbl, order_col)

                col_index = {c: i for i, c in enumerate(cols)}
                for r in rows:
                    # align to union header
                    out_row = []
                    for c in union_cols:
                        if c in col_index:
                            v = r[col_index[c]]
                            out_row.append("" if v is None else str(v))
                        else:
                            out_row.append("")
                    # metadata
                    meta_vals = [
                        mdb,
                        file_modified_utc_iso(mdb),
                        file_modified_local_cn(mdb),
                    ]
                    if pc_name:
                        meta_vals.insert(0, pc_name)
                    out_row += meta_vals
                    w.writerow(out_row)
                    total_rows += 1

                log_lines.append(f"[OK] {mdb} :: {tbl} exported ({order_col or 'no order'})")

            except Exception as e:
                log_lines.append(f"[ERR] {mdb}: {e}")
                log_lines.append(traceback.format_exc())
            finally:
                try:
                    conn.close()
                except Exception:
                    pass

    log_lines.append(f"[INFO] Combined CSV written: {out_csv} (rows={total_rows})")

def main():
    parser = argparse.ArgumentParser(
        description="Aggregate multiple MDR MDBs into ONE CSV (adds China local time column)."
    )
    parser.add_argument("--base", default=r"F:\Evolution\File\1",
                        help="Base directory to scan recursively for MDBs (e.g., F:\\Evolution\\File\\1)")
    parser.add_argument("-o", "--output", default=r"C:\LabTools\output_csv",
                        help="Output root folder where the single CSV will be written")
    parser.add_argument("--table", default=None,
                        help="Force table name (default: auto pick from candidates)")
    parser.add_argument("--order-by", dest="orderby", default=None,
                        help="Force ORDER BY column (default: auto-detect ID-like)")
    parser.add_argument("--pc-name", default=None,
                        help="Optional PC name tag to add into output (e.g., 'ComputerA')")
    parser.add_argument("--retries", type=int, default=5, help="Open retries for locked MDBs")
    parser.add_argument("--delay", type=int, default=5, help="Seconds between retries")
    parser.add_argument("--file-name", default="Data.mdb",
                        help="Only process MDBs whose filename matches this (case-insensitive). Default: Data.mdb")
    args = parser.parse_args()

    os.makedirs(args.output, exist_ok=True)
    today = dt.datetime.now(CHINA_TZ).strftime("%Y-%m-%d")  # keep date folder in China local time
    out_csv = os.path.join(args.output, today, "ALL_Values.csv")

    os.makedirs(os.path.dirname(out_csv), exist_ok=True)
    log_lines = []
    start = dt.datetime.now(CHINA_TZ).strftime("%Y-%m-%d %H:%M:%S CST")
    log_lines.append(f"=== MDR Aggregate Run @ {start} (Asia/Shanghai) ===")
    log_lines.append(f"[INFO] Base: {args.base}")
    log_lines.append(f"[INFO] Output root: {args.output}")
    log_lines.append(f"[INFO] File filter: {args.file_name}")

    try:
        convert_many_to_single_csv(
            base_dir=args.base,
            out_csv=out_csv,
            log_lines=log_lines,
            forced_table=args.table,
            forced_orderby=args.orderby,
            retries=args.retries,
            delay=args.delay,
            pc_name=args.pc_name,
            only_file_name=args.file_name
        )
    except Exception as e:
        log_lines.append(f"[FATAL] {e}")
        log_lines.append(traceback.format_exc())

    # write a run log beside the CSV (also local China time)
    log_path = os.path.join(args.output, today, "aggregate_log.txt")
    with open(log_path, "w", encoding="utf-8") as f:
        f.write("\n".join(log_lines))

    print("\n".join(log_lines))
    print(f"\n[INFO] Log: {log_path}")
    print(f"[INFO] Output CSV: {out_csv}")

if __name__ == "__main__":
    main()
