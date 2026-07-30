# Claude Code Task Brief — ss-lab-platform

Repository: `ss-lab-platform`
Do the tasks **in order**. Stop at each VERIFY gate and report results before
continuing. Do not proceed past a failing gate.

---

# TASK A — Fix four defects

These were found by review and confirmed by execution. Fix all four, then stop.

---

## A1. `config/source_id.txt` must not be tracked by git

**Problem:** the file is committed containing `MDR_PC_01`. Deployment is
`git pull`, and this value is machine-specific. On LAB-ALPHA the pull will
either conflict or overwrite the local value, causing every ingested row
to be tagged with the wrong `source_id` and producing corrupt `unique_key`s
across two machines. Silent and unrecoverable without full re-ingest.

**Do:**
1. `git mv config/source_id.txt config/source_id.txt.example`
2. Add `config/source_id.txt` to `.gitignore`
3. In `src/labtool/split_and_delta.py`, make `read_source_id` raise a clear
   error naming the `.example` file when `config/source_id.txt` is absent.
   It already raises on empty — extend the message, do not change behaviour.
4. Add a line to `README.md` under setup: each machine must copy
   `source_id.txt.example` to `source_id.txt` and set its own value.

**Acceptance:** `git ls-files config/` lists only `source_id.txt.example`.

---

## A2. `requirements.txt` is UTF-16 with a UTF-8 line appended

**Problem:** confirmed — BOM present, 115 null bytes, fails UTF-8 decode.
`requests>=2.31` was appended as UTF-8 to a UTF-16LE file. Mixed encoding.
CI never caught it because the workflow runs `pip install pytest` instead
of installing this file.

**Do:**
1. Rewrite `requirements.txt` as UTF-8, no BOM, LF endings, preserving all
   existing pins:
   `colorama==0.4.6`, `iniconfig==2.3.0`, `packaging==26.0`, `plugny==1.6.0`
   (verify exact name — likely `pluggy`), `Pygments==2.19.2`,
   `pyodbc==5.3.0`, `pytest==9.0.2`, `requests>=2.31`
   Read the original bytes and decode as utf-16 to recover them exactly —
   do not retype from this brief, the pins above may contain a typo.
2. Split dev-only packages into `requirements-dev.txt`
   (`pytest`, `iniconfig`, `pluggy`, `Pygments`, `colorama`, `packaging`).
   Runtime keeps `pyodbc`, `requests`.
3. Update `.github/workflows/tests.yml` to run
   `pip install -r requirements-dev.txt` before pytest.
   Do NOT install `pyodbc` in CI — it needs unixODBC system packages and
   nothing under `tests/` imports it.

**Acceptance:** `python -c "open('requirements.txt',encoding='utf-8').read()"`
succeeds; CI installs the dev file and 14 tests still pass.

---

## A3. Reuse the SQLite connection in `StateStore`

**Problem:** `_connect()` opens a new connection on every `get_last_hash`
call, inside the per-row loop. Measured: 0.362s vs 0.031s per 5,000 rows —
12x slower. LAB-ALPHA has 227,270 rows.

**Do:** hold one connection on the instance. Open it in `__init__`, reuse it
in all methods, add a `close()` method and `__enter__`/`__exit__` so callers
can use it as a context manager. Keep the existing public method signatures
(`get_last_hash`, `set_last_hash`, `set_last_hash_many`) unchanged.
Keep the commit-on-write behaviour — do not batch commits across the
delta-write boundary, because delta-write-then-state-update ordering is a
hard correctness requirement.

**Acceptance:** all 14 existing tests pass unchanged.

---

## A4. Schema fingerprint logging

**Problem:** `include_fields` is derived from `rows[0].keys()`. Confirmed by
execution: if the source CSV gains a **populated** new column, every existing
record's hash changes and the entire history is re-flagged as `CORRECTION`.
An empty new column is harmless. This is §9 of the project spec
("schema fingerprint logging on each run"), currently unimplemented.

**Do:**
1. Add `schema_fingerprint(columns) -> str` to `src/labcore/schema.py` —
   SHA256 of the sorted, newline-joined column names. Deterministic.
2. Add a `schema_state` table to `StateStore`
   (`stream_id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, first_seen TEXT`).
3. In `split_and_build_delta`, compute the fingerprint per stream. If it
   differs from the stored one, print a clear warning naming the added and
   removed columns, and include `schema_changed: True` in the returned dict.
   **Do not block the run** — warn only.
4. Add a test covering: unchanged fingerprint, added column, removed column.

**Acceptance:** new test passes; existing 14 still pass.

---

## VERIFY GATE A — stop here

Run and report:

```bash
python -m pytest tests/ -q
python -c "open('requirements.txt',encoding='utf-8').read(); print('utf-8 ok')"
git ls-files config/
```

Expected: all tests pass, utf-8 ok, only `source_id.txt.example` tracked.
**Report results and wait before starting Task B.**

---

# TASK B — Scaffold the bladder service-cycle module

Only after Gate A passes.

## B1. Place the provided files

These four files are provided separately. Put them at these exact paths:

| File | Destination |
|---|---|
| `001_initial_schema.sql` | `db/migrations/001_initial_schema.sql` |
| `002_multi_factory.sql` | `db/migrations/002_multi_factory.sql` |
| `docker-compose.yml` | `docker-compose.yml` (repo root) |
| `test_architecture.py` | `tests/test_architecture.py` |

Do not modify their contents. The SQL has been verified against
PostgreSQL 16.14 and all tests pass.

## B2. Create directories

```
db/migrations/
src/adapters/__init__.py
src/ingest/__init__.py
```

Also create `db/migrations/000_create_metabase_db.sql` containing only:
`CREATE DATABASE metabase;`

## B3. Add `.gitattributes`

```
* text=auto eol=lf
*.bat text eol=crlf
```

## B4. Update `.gitignore`

Add: `backups/`, `.env`, `config/source_id.txt` (if not already present
from A1).

---

## VERIFY GATE B

```bash
python -m pytest tests/ -q
```

Expected: 14 lab tests + 6 architecture tests pass, 1 skipped
(`adapters/` is empty, so the mutual-independence test skips).

---

# DO NOT DO

- **Do not refactor `src/labtool/` into `src/adapters/`.** That is a later,
  separate task. Changing two things at once makes failures undiagnosable.
- **Do not rename `labcore`.** The name is historical and cosmetic;
  renaming touches every import for zero functional gain.
- **Do not change `unique_key` in `src/labcore/keys.py`.** There is a known
  design issue there (a corrected `TestDate` produces a duplicate record
  rather than a CORRECTION), but the fix requires a decision that has not
  been made. Leave it alone and do not "improve" it.
- **Do not edit any migration file after it has been applied anywhere.**
  Fix forward with `003_`.
- **Do not add business logic to `src/adapters/`.** Adapters map source
  fields to schema columns and validate types. Nothing else.

---

# CONSTRAINTS

- All new source files: UTF-8, no BOM, LF endings.
- Exception: CSV *exports* keep UTF-8-**with**-BOM so Chinese Windows Excel
  renders 中文 correctly. `_write_delta` already does this — do not change it.
- Preserve the delta-write-before-state-update ordering in
  `split_and_build_delta`. This is a hard correctness requirement, not a
  style preference.
- Keep every change explainable. This project doubles as a learning
  exercise — favour clear code over clever code.
