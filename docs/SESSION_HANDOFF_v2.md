# SS Platform — Session Handoff v2
**Date:** 2026-08-05
**Supersedes:** SESSION_HANDOFF.md (2026-07-30)
**Repo:** https://github.com/aiaikingai/ss-platform
**Last commit:** `316dcb8`

---

## 1. Objective

Build a modular manufacturing intelligence platform for a tire curing bladder
manufacturer. Track material from purchased ingredient → rubber compound →
finished bladder → field service life, across two of our own plants and
multiple client sites.

**Dual goal:** working production system *and* Brian's own engineering skill
development. Explain reasoning, not just directives.

**Architecture (locked):**

```
data sources → src/adapters/ → PostgreSQL (canonical schema) → Metabase
```

- **No Flask, no FastAPI, no React** for the platform yet. Metabase reads
  Postgres directly. Frontend deferred until Metabase demonstrably fails on
  one of three triggers: chart types it can't do, real drill-down needed, or
  operator-facing UI needed.
- **No ERP.** Factory has none. Never build ERP-shaped tables
  (no `purchase_order`, `inventory`, `work_order`).
- **Adapter pattern:** every data source enters through exactly one file whose
  only job is source format → canonical schema. Nothing downstream knows where
  a row came from. This is what makes swapping Excel for a future ERP cheap.

---

## 2. Environment Facts (all verified)

| Item | Value |
|---|---|
| Repo path | `/Users/b/Projects/ss-platform` |
| Shell shortcut | `sslab` (in `~/.zshrc`), also `$REPO` |
| Mac | arm64 (Apple Silicon) |
| Correct venv | **`.venv`** (Python 3.11) — has pyodbc, pytest, requests |
| Wrong venv | `venv` (Python 3.9) — stray, both gitignored, ignore it |
| Test command | `PYTHONPATH=src .venv/bin/python3 -m pytest tests/ -q` |
| Current tests | **21 passed** |
| Docker | Docker 29.6.2, installed and running |
| `.env` password | `POSTGRES_PASSWORD` — single entry, verified clean |

**Never use plain `python3`** — that's system Python 3.9 and lacks `requests`,
producing a confusing ImportError in `test_alert_sender.py`.

---

## 3. What Is DONE

### Repo & hygiene
- Renamed `ss-lab-platform` → `ss-platform` (GitHub + local + alias updated)
- Four defects fixed and committed: `source_id.txt` untracked, `requirements.txt`
  UTF-16→UTF-8, SQLite connection reuse (12× speedup), schema fingerprint logging
- `docker-compose.yml` reads `${POSTGRES_PASSWORD}` from `.env`, no hardcoded secret
- Duplicate/compromised password removed from `.env` (leaked one deleted,
  fresh `openssl rand -hex 24` one retained)
- `.gitattributes` added (LF endings, CRLF for `.bat`)
- Architecture guard test (`tests/test_architecture.py`) — enforces dependency
  direction, verified it catches injected violations

### Schema — 8 migrations, all tested against real PostgreSQL 16.14
**22 tables, 9 views. All apply clean from scratch in order. 26 functional tests passing.**

| File | Contents |
|---|---|
| `001_sites_and_machines.sql` | `production_site`, `curing_machine`, `client`, `client_location`, `client_factory`, `production_day()`, `production_shift()` |
| `002_materials.sql` | `material_lot`, `lot_consumption`, `lot_shipment`, `process_context` |
| `003_production_qc.sql` | `production_qc_record`, `production_defect`, `defect_type` |
| `004_bladders.sql` | `bladder_instance`, `bladder_event`, `event_reason`, `source_reason_map` |
| `005_lab_and_banbury.sql` | `lab_result`, `banbury_batch`, `banbury_reading` |
| `006_ingest_audit.sql` | `ingest_run`, `ingest_quarantine` |
| `007_views.sql` | 7 views incl. `v_bladder_lifetime`, `v_qc_field_performance` |
| `008_ingredients_and_sy_lab.sql` | `RAW` stage, `ingredient_type`, `lab_result.bladder_id`, `v_ingredient_usage`, diamond-genealogy fix |

Old superseded schema archived in `db/migrations_old/`.

### Apps
- `banbury-dashboard` (React 19 + Vite 8, 573-line App.jsx) rescued from an
  unbacked-up standalone folder → now at `apps/banbury-dashboard/`, committed.
  Build verified working post-move (2,362 modules, single-file HTML output).

---

## 4. Verified Schema Capabilities

Each confirmed by executing tests against a live database, not by inspection:

| Capability | Result |
|---|---|
| Orphaned-segment bug (200 + 300 cycles) | **500** — fixed by construction |
| Q3 same date, different stacks | Both accepted; exact duplicate rejected |
| Grade A derived (100 − 8 − 3) | **89** — never stored, can't drift |
| **QC ↔ field performance join** | Works — the doc's "highest-value capability" |
| Ingredient blast radius | Resin batch traced to all downstream lots |
| Full genealogy: ingredient → A → Q1 → Q3 → bladder | Traced correctly |
| Blending (multiple A → one Q1) | 3 parents resolved |
| Incomplete legacy rows (48% missing 胶囊LOT) | Load fine; complete duplicates blocked |
| Production site vs client site | Neither usable as the other |
| 08:00 production-day boundary + shift A/B | Correct |
| Sentinel rejection (`ERROR`, `repeated`) | Rejected at write time |

**Bug caught by testing, not inspection:** blending creates diamond-shaped
genealogy (carbon black → two A lots → one Q1). The recursive ancestry view
returned duplicate ancestors. Fixed with `DISTINCT ON` keeping shortest path.
Would have shipped otherwise.

---

## 5. Key Design Decisions (do not relitigate)

| Decision | Rationale |
|---|---|
| **Monorepo** | Shared `labcore/schema.py` is the point. Split repos = the `HASH_FIELDS` bug at repository scale. |
| **PostgreSQL + TimescaleDB**, Python, adapter pattern | Durable. Committed. |
| **Metabase** for dashboards | Installed software, not code to maintain. Bus-factor insurance. |
| **Reject ERPNext** | Its serial model has no concept of cycles across service segments — the highest-value fix doesn't fit. |
| **Reject cloning Factbird** | It's OEE/downtime IIoT. Only 1 of 6 needs match. Wrong primitives (lines and stops, not lots and lineage). |
| **Reference standards instead** | ISA-88 (batch model), ISA-95 (material lot genealogy), GS1 Digital Link (QR payload — don't invent a format). |
| **`production_site` ≠ `client_factory`** | A bladder is MADE at SY and USED at Hankook. One column cannot hold both. |
| **`factory_id`/`site_id` are TEXT, not UUID** | Deliberate exception. <20 sites ever, stable codes, appear in every query. UUID would force a join on every ad-hoc question. |
| **`event_reason` is a table, not a CHECK** | `is_terminal` is a property of the reason. No query hardcodes the terminal/non-terminal split. |
| **`source_reason_map` for multi-vocabulary** | Adapters LOOK UP, never translate. Unknown term → NULL → **quarantine, never default to OTHER.** |
| **Ingredients are `material_lot` rows (`stage='RAW'`)** | Same shape as compound batches; `lot_consumption` already models the edge. A second table = a second genealogy mechanism. |
| **Defect counts in long format** | 9 types × 2 grades as columns would be 18 columns + `ALTER TABLE` per new type. |

### Five schema rules
1. UUID primary keys on entities (except site/client codes, see above)
2. `source_system` + `source_record_id` on every ingested row
3. Never name a table after its source
4. Event tables, not state tables (lifetime = `SUM(cycles_this_segment)`)
5. No ERP-shaped tables

---

## 6. Domain Model — Physical Flow

```
Ingredients (RAW lots, suppliers)
    ↓
JX plant  ├─ Production: Banbury mixers, sensors, A/Q1/Q3 compound records
          └─ Lab: MDR, Mooney (LAB-ALPHA SQL Server, GOTECH MDB)
    ↓  (lot_shipment — fleet transport, a real production stage)
SY plant  ├─ Production: bladder instances, A/B/C grading, defect counts
(昶安橡胶科技) └─ Lab: GOTECH re-test of Q3 samples + future finished-product tests
    ↓
Client sites  Hankook JX (Factory 1/2/3) → service events, retirement, cracks
```

**Pattern:** every plant has a production side (makes it) and a lab side
(tests it). Banbury belongs with production, NOT with lab.

**Blending:** multiple A → one Q1, multiple Q1 → one Q3. Handled by
`lot_consumption` many-to-many; creates diamond genealogy (see §4).

**Identity changes hands at each stage — this is where traceability normally breaks:**

| Stage | Identity |
|---|---|
| JX Q3 output | `Q3胶Lot` + `托盘号` (stack letter + sequence) |
| SY bladder | `(production_date, curing_machine_id, 胶囊LOT)` |
| Client service | `bladder_id` UUID, persists across all events |

---

## 7. OPEN DECISIONS — do not let an agent decide these

### 7.1 `unique_key` design flaw ⚠️ HIGHEST PRIORITY — needs Opus

Confirmed by execution: an operator correcting a mistyped `TestDate` produces
a **duplicate record** instead of a CORRECTION, because the datetime is part
of the identity key.

```
before fix : MDR_PC_01:MDR-195-15:101:2026-01-01T09:30:00
after fix  : MDR_PC_01:MDR-195-15:101:2026-01-02T09:30:00
same key? False → treated as NEW
```

Also a doc divergence, both marked 🔒 LOCKED:
- `SS-Lab-PROJECT-INSTRUCTIONS.docx` §6: `source_id : method_code : ID`
- `src/labcore/keys.py`: `source_id:method_code:ID:normalized_test_datetime`

Four options: revert to 3-part key / date-only / add `superseded_by` column /
datetime as tiebreaker only on collision.

**Decides it:** do machine IDs actually reset on LAB-ALPHA? Measurable — you
have a working query returning 227,270 rows.

### 7.2 Doc corrections needed in `MANUFACTURING_SYSTEM_DEV_CONTEXT.md`
- **§3b says 托盘号 is a "descriptive attribute" — it is NOT.** It is
  identity-bearing: Q3胶Lot + 托盘号 together define a unique Q3 rubber.
  Schema enforces `UNIQUE (stage, lot_code, stack_position, stack_sequence_no)`.
- **Add open item:** 胶囊LOT semantics confirmed for Hankook JX only.
  Korea plants unverified. `v_qc_field_performance` exposes `client_factory_id`
  specifically so queries can scope before Korea data arrives.

### 7.3 Still unresolved (need production staff / your team)
| Item | Blocks |
|---|---|
| 340k-row Feishu "Main2" vs 25k `Main2_clean` — relationship unknown | Historical import |
| B-vs-C bubble threshold undefined | Auto-classification only (grade stored as recorded, so not blocking) |
| 初回 (first-cure) meaning unconfirmed | Lookup label only |
| Whether 设备/FM/初回 can ever be grade B | Nothing — schema deliberately doesn't constrain |
| Real curing machine labels (currently M01–M19 placeholders) | Nothing — one UPDATE |
| Korea cycle-count semantics: per-segment or cumulative? | **Multi-factory ingest — high risk of double-counting** |

---

## 8. MODULAR TASK BREAKDOWN

Each module is independently completable. Suggested order, but they're
loosely coupled.

### MODULE C — Start Docker, load schema for real ⬅️ NEXT
**Status:** in progress, stopped at `docker compose up -d`
**Model: Sonnet, low effort**

1. `sslab && docker compose up -d`
2. Wait ~60s (Metabase first boot is slow), then `docker compose ps` — both running
3. Verify schema: `docker compose exec db psql -U sslab -d sslab -c "\dt"` → **22 tables**
4. `\dv` → **9 views**
5. `SELECT reason_code, is_terminal FROM event_reason;` → 17 rows (11 terminal, 6 not)
6. `SELECT * FROM ingredient_type;` → 11 rows
7. Load test fixtures: `docker compose exec -T db psql -U sslab -d sslab < tests/fixtures/test_schema.sql`
   then `test_008.sql` — expect all PASS notices, `total_cycles = 500`
8. Truncate fixtures afterward
9. Metabase at `http://localhost:3000` — connect to Postgres using host **`db`**
   (the service name, NOT `localhost` — containers talk over Docker's internal network)

**Gotcha:** if `POSTGRES_PASSWORD is not set` appears, Compose isn't finding
`.env`. Don't retry blindly — check you're in the repo root.

### MODULE D — Folder restructure + adapter scaffolding
**Model: Sonnet, medium effort**

Target structure:
```
src/adapters/
├── base.py                  shared plumbing (quarantine helper, run logging)
├── jx_production/
│   ├── banbury_1.py         CSV, one file per mixer
│   ├── banbury_2.py         placeholder — multiple mixers expected
│   ├── sensors_.py          placeholder — non-Banbury JX sensors
│   └── compound_records.py  hand-typed Excel: A/Q1/Q3 + ingredient batches
├── jx_lab/
│   ├── mdr_alpha.py         LAB-ALPHA SQL Server (pyodbc)
│   ├── mdr_gotech.py        GOTECH MDB
│   └── mooney.py
├── sy_production/
│   └── bladder_records.py   bladder + rubber + A/B/C defects
├── sy_lab/
│   └── gotech_.py           placeholder — Q3 re-test + future final product
└── client_lifecycle/
    └── feishu_hankook_jx.py retirement records
```

Rules:
- One adapter file per data source. Multiple Banburys = multiple files, never
  an `if machine == 2` branch. Adapters must never import each other
  (architecture guard enforces this).
- Adapters map fields and validate types. They compute NOTHING — no derived
  metrics, no thresholds, no business rules. Those live in `labcore/`.
- Update `tests/test_architecture.py` `ALLOWED` dict for any new top-level package.

Also in this module: move `tools/` for built deliverables
(`Banbury_Batch_Check_v2.0.html`), decide on `labcore` rename (recommend: defer).

### MODULE E — First real adapter, end to end
**Model: Sonnet, medium effort. Opus if schema questions arise.**

Suggested first: `sy_production/bladder_records.py` — it exercises the messiest
data and produces the highest-value table. Or `jx_lab/mdr_alpha.py` since the
`pyodbc` query already works.

Must include: `ingest_run` logging, quarantine on unmappable rows,
`resolve_reason()` lookup returning NULL → quarantine (never default to OTHER).

### MODULE F — `unique_key` decision
**Model: Opus, high effort.** See §7.1. Requires the LAB-ALPHA ID-reset check first.

### MODULE G — Cleanup of leftover folders
**Model: Sonnet, low effort**

- `ss-lab-poc/production_records/` → `setup_db.py` is superseded by migration 003;
  `feishu_puller_poc.py` → rewrite as `client_lifecycle/` adapter;
  `mock_production.csv` → `tests/fixtures/`
- `Waizhu/` → **contains hardcoded Feishu tokens, must strip before any commit.**
  Keep only `read_formula_range_A_K.py` + `get_token.py`, cleaned, into
  `scripts/exploration/feishu/`. Delete the rest.
- `Key Items/` → empty, delete
- Two local-only scripts (`test_bitable_insert.py`, `test_feishu_token.py`)
  stay untracked deliberately

### MODULE H — Metabase dashboards
**Model: Sonnet, low effort.** Start with `v_data_completeness` — it's the
trustworthiness KPI. Legacy baselines to beat: 胶囊LOT 48% missing,
production date 20%, Q3 lot 34%.

---

## 9. Files to Attach to the New Thread

| File | Why |
|---|---|
| **`SESSION_HANDOFF_v2.md`** (this file) | The context |
| `260805_MANUFACTURING_SYSTEM_DEV_CONTEXT.md` | Business/domain truth |
| `SS-Lab-PROJECT-INSTRUCTIONS.docx` | Already in Project files |

**Already in the repo — do NOT re-attach**, a new thread can read from GitHub:
`db/migrations/001`–`008`, `docker-compose.yml`, `tests/test_architecture.py`,
`tests/fixtures/test_schema.sql`, `tests/fixtures/test_008.sql`

---

## 10. Opening Message for the New Thread

> Copy everything below into a new Sonnet thread, attach `SESSION_HANDOFF_v2.md`
> and `260805_MANUFACTURING_SYSTEM_DEV_CONTEXT.md`.

---

Continuing the ss-platform project. Attached is `SESSION_HANDOFF_v2.md` — read
it first, plus the manufacturing context doc.

**Where I am:** 8 schema migrations written, tested against real PostgreSQL, and
pushed (commit `316dcb8`). Docker installed and running. `.env` password verified
clean. Tests: 21 passed.

**Next task: MODULE C** — run `docker compose up -d`, verify all 22 tables and
9 views load, run the test fixtures, and connect Metabase. Full steps are in §8
of the handoff.

**How I need you to work with me — important:**

- I'm a beginner. Give beginner-level hand-holding on every step.
- Never assume a file operation is obvious. Spell out exact Terminal actions,
  where files go, what to click.
- **Break into small steps and stop for my confirmation.** Not ten steps at once.
- After every command, tell me what output to expect and what to do if it looks wrong.
- For any terminal command, say exactly where to run it:
  🖥️ MACHINE NAME → Terminal / regular CMD / 管理员 CMD / PowerShell.
- **Before anything hard to reverse** (deleting files, `git push`, dropping or
  altering a database, overwriting a file, `rm -rf`, force operations) — flag it
  clearly as hard-to-reverse and give me more context before I run it.
- Don't make me paste output after every single line — only at checkpoints
  that matter.
- **When you finish a task or hand off the next one, recommend which Claude
  model and effort level to use**, so I can manage token usage.

**Facts you'll need:**
- Repo: `/Users/b/Projects/ss-platform` (type `sslab` to get there)
- Mac: arm64. Docker 29.6.2 installed and running.
- Use `.venv/bin/python3`, NOT plain `python3`
- Tests: `PYTHONPATH=src .venv/bin/python3 -m pytest tests/ -q` → expect 21 passed
- `docker-compose.yml` reads the password from `.env` — do NOT edit it to add one

**Do NOT** decide anything in §7 of the handoff — especially the `unique_key`
design. Those need dedicated sessions.

Start with MODULE C, step 1.

---

## 11. Working Preferences

- **Tone:** analytical, direct, no flattery. Challenge flawed ideas.
- **Structure:** Summary → Key Facts → Analysis → Implications → Risks →
  Recommendation → Confidence.
- **Depth:** explain WHY — causal mechanisms, first principles. This project
  doubles as learning Python and system design.
- **Verification:** verify independently rather than trusting summaries.
  (Two real bugs this session were caught by running code, not reading it.)
- **Numbers:** exact, correct units, preserve symbols (±, ≤, ~).
- **Avoid over-engineering:** defer non-critical complexity.
- **Terminal commands:** always specify machine + shell type.
- **Hand-holding:** beginner level, small steps, confirm in the middle.
- **Hard-to-reverse steps:** flag explicitly, explain more, then ask.
- **Model recommendations:** give one with every handoff.
