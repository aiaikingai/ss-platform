-- =====================================================================
-- ss-lab-platform — canonical schema, migration 001
-- =====================================================================
-- DESIGN RULES (see docs/SCHEMA_RULES.md):
--   1. UUID primary keys on every entity
--   2. source_system + source_record_id on every ingested row
--   3. No table named after its source system
--   4. Event tables, not state tables
--   5. No ERP-shaped tables (no purchase_order, inventory, work_order)
--
-- Target: PostgreSQL 16. TimescaleDB is OPTIONAL and isolated to §7.
-- Verified against PostgreSQL 16.14.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()

-- =====================================================================
-- §0  SHARED VOCABULARY
-- =====================================================================
-- TEXT + CHECK is used instead of native ENUM types on purpose:
-- native enums cannot have values removed and are awkward to alter,
-- whereas a CHECK constraint is changed with an ordinary migration.

-- Lookup table (not a CHECK) because event reasons will grow over time
-- AND because is_terminal is a PROPERTY of the reason. Storing it here
-- means no query ever hardcodes which reasons end a bladder's life.
-- This is the crux of the orphaned-segment fix.
CREATE TABLE event_reason (
    reason_code     TEXT PRIMARY KEY,
    label_zh        TEXT NOT NULL,
    label_en        TEXT NOT NULL,
    is_terminal     BOOLEAN NOT NULL,
    notes           TEXT
);

COMMENT ON COLUMN event_reason.is_terminal IS
  'TRUE = bladder retired, cycles_this_segment closes the lifecycle. '
  'FALSE = bladder returns to service, cycles_this_segment is a PARTIAL count. '
  'Summing partials without this flag is the documented understatement bug.';

INSERT INTO event_reason (reason_code, label_zh, label_en, is_terminal, notes) VALUES
  ('AGING',            '老化',       'Aging / normal wear',      TRUE,  'Baseline expected end-of-life'),
  ('CRACK_UPPER',      '上部裂开',    'Upper crack (EAR crack)',  TRUE,  'Bead/clamp-ring zone. Distinct from RB — NOT a subtype'),
  ('CRACK_INTERNAL',   '内部裂开',    'Internal crack',           TRUE,  NULL),
  ('CRACK_SURFACE',    '表面裂开',    'Surface crack',            TRUE,  NULL),
  ('CRACK_LOWER',      '下部裂开',    'Lower crack',              TRUE,  NULL),
  ('CRACK_MIDDLE',     '中部裂开',    'Middle crack',             TRUE,  NULL),
  ('CRACK_GROOVE',     '花纹槽裂开',  'Tread groove crack',       TRUE,  NULL),
  ('DELAMINATION',     '分层',       'Delamination',             TRUE,  NULL),
  ('PEELING',          '脱皮',       'Peeling',                  TRUE,  NULL),
  ('RB',               'RB',        'Rough Bladder',            TRUE,  'Sulfur-migration microcrack. NOT safety-critical — do not alert as high severity'),
  ('LEB',              'LEB',       'Low-cycle early failure',  TRUE,  NULL),
  ('MOLD_CHANGE',      '模具交替',    'Mold change',              FALSE, 'Bladder continues in service — PARTIAL cycle count'),
  ('MOLD_CLEANING',    '模具清扫',    'Mold cleaning',            FALSE, 'Bladder continues in service — PARTIAL cycle count'),
  ('EQUIPMENT_FAULT',  '故障',       'Equipment fault',          FALSE, 'Bladder continues in service — PARTIAL cycle count'),
  ('DEPLOY',           '新装',       'New deployment',           FALSE, 'No cycle data yet'),
  ('TRIAL',            '试验',       'Trial unit',               FALSE, 'Exclude from lifecycle statistics'),
  ('OTHER',            '其他',       'Unspecified',              FALSE, NULL);


-- =====================================================================
-- §1  MATERIAL LOTS  —  the A / Q1 / Q3 compound batches
-- =====================================================================
CREATE TABLE material_lot (
    lot_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Natural key. lot_code is what humans write (Q3 uses YYMMDD).
    -- Stored as TEXT, never numeric: '260105' must never become 260105.0
    stage               TEXT NOT NULL CHECK (stage IN ('A','Q1','Q3')),
    lot_code            TEXT NOT NULL CHECK (lot_code <> '' AND lot_code !~* '^(error|repeated|n/?a)$'),

    compound_code       TEXT,           -- H39, H01, TC16, TC45, LC02
    produced_on         DATE,

    -- The filtration asymmetry stored as DATA, not as logic in code.
    -- A = filtered, Q1 = NOT filtered, Q3 = filtered (filter head 过滤头).
    -- Any Q1-origin agglomerate survives to Q3; this column makes that queryable.
    filtered            BOOLEAN,

    quantity_kg         NUMERIC(10,2) CHECK (quantity_kg IS NULL OR quantity_kg >= 0),

    -- Provenance — rule 2. Enables re-ingest, dedupe, and running
    -- Excel + a future ERP in parallel during cutover.
    source_system       TEXT NOT NULL,
    source_record_id    TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    data_quality_flag   TEXT,           -- NULL = clean; else why it is suspect
    notes               TEXT,

    -- Genealogy resolves lot_code -> lot_id. If a code is ambiguous within
    -- a stage, genealogy is ambiguous. Enforce it so violations fail LOUDLY
    -- at ingest rather than silently corrupting lineage.
    CONSTRAINT material_lot_natural_key UNIQUE (stage, lot_code),
    -- Idempotency: re-running an adapter must not duplicate rows.
    CONSTRAINT material_lot_source_key  UNIQUE (source_system, source_record_id)
);

CREATE INDEX idx_material_lot_compound  ON material_lot (compound_code, produced_on);
CREATE INDEX idx_material_lot_produced  ON material_lot (produced_on);


-- =====================================================================
-- §2  LOT CONSUMPTION  —  the genealogy edge table
-- =====================================================================
-- This ONE table is what turns "which Q1 batch caused this defect?"
-- from an investigation into a query. Many-to-many: a Q3 lot may consume
-- several Q1 lots; a Q1 lot may feed several Q3 lots.
CREATE TABLE lot_consumption (
    consumption_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_lot_id       UUID NOT NULL REFERENCES material_lot(lot_id) ON DELETE RESTRICT,
    child_lot_id        UUID NOT NULL REFERENCES material_lot(lot_id) ON DELETE RESTRICT,
    quantity_kg         NUMERIC(10,2) CHECK (quantity_kg IS NULL OR quantity_kg >= 0),

    source_system       TEXT NOT NULL,
    source_record_id    TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT lot_consumption_no_self  CHECK (parent_lot_id <> child_lot_id),
    CONSTRAINT lot_consumption_edge_key UNIQUE (parent_lot_id, child_lot_id)
);

CREATE INDEX idx_lot_consumption_parent ON lot_consumption (parent_lot_id);
CREATE INDEX idx_lot_consumption_child  ON lot_consumption (child_lot_id);


-- =====================================================================
-- §3  BLADDER INSTANCE  —  one row per physical bladder, ever
-- =====================================================================
-- UUID PK, NOT a composite of physical attributes. The existing composite
-- key produced 356 IDs across 2,811 records — it is not unique in practice.
CREATE TABLE bladder_instance (
    bladder_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- NULLABLE on purpose: ~34% of historical records have no Q3 lot.
    -- NULL means "unknown", never a sentinel string.
    q3_lot_id           UUID REFERENCES material_lot(lot_id) ON DELETE SET NULL,

    spec_code           TEXT,       -- BG36BP, BE26AN, BD0150 ...
    compound_code       TEXT,
    produced_on         DATE,

    -- TWO SEPARATE DIMENSIONS. Never one column called "lot".
    tray_position       SMALLINT CHECK (tray_position IS NULL
                                        OR (tray_position BETWEEN 0 AND 147)),
    tray_id             TEXT,

    press_id            TEXT,       -- 硫化机号 — strong independent signal
    factory_id          TEXT,

    source_system       TEXT NOT NULL,
    source_record_id    TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    data_quality_flag   TEXT,

    CONSTRAINT bladder_instance_source_key UNIQUE (source_system, source_record_id)
);

COMMENT ON COLUMN bladder_instance.tray_position IS
  '胶囊LOT — a tray POSITION 0-147. Not a batch identifier. Repeats freely.';
COMMENT ON COLUMN bladder_instance.q3_lot_id IS
  'Q3胶Lot — the real material batch dimension. NULL = genuinely unknown.';

CREATE INDEX idx_bladder_q3_lot   ON bladder_instance (q3_lot_id);
CREATE INDEX idx_bladder_spec     ON bladder_instance (spec_code, produced_on);
CREATE INDEX idx_bladder_press    ON bladder_instance (press_id);


-- =====================================================================
-- §4  BLADDER EVENT  —  the orphaned-segment fix
-- =====================================================================
-- Each service segment is a CHILD row under a persistent instance.
-- Lifetime = SUM(cycles_this_segment) across all events for one bladder.
-- The documented 200 + 300 = 500 case becomes correct BY CONSTRUCTION.
CREATE TABLE bladder_event (
    event_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bladder_id          UUID NOT NULL REFERENCES bladder_instance(bladder_id) ON DELETE CASCADE,

    reason_code         TEXT NOT NULL REFERENCES event_reason(reason_code),
    occurred_on         DATE NOT NULL,

    -- Cycles accrued in THIS segment only. Whether it closes the lifecycle
    -- is determined by event_reason.is_terminal — never hardcoded in a query.
    cycles_this_segment INTEGER CHECK (cycles_this_segment IS NULL
                                       OR cycles_this_segment >= 0),

    press_id            TEXT,
    factory_id          TEXT,

    source_system       TEXT NOT NULL,
    source_record_id    TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    data_quality_flag   TEXT,

    CONSTRAINT bladder_event_source_key UNIQUE (source_system, source_record_id)
);

CREATE INDEX idx_bladder_event_bladder ON bladder_event (bladder_id, occurred_on);
CREATE INDEX idx_bladder_event_reason  ON bladder_event (reason_code, occurred_on);


-- =====================================================================
-- §5  LAB RESULTS  —  unified across MDR / Mooney / GOTECH
-- =====================================================================
CREATE TABLE lab_result (
    result_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- The existing 4-part identity model from labcore, kept intact.
    source_id           TEXT NOT NULL,     -- machine/PC, e.g. MDR_PC01
    method_code         TEXT NOT NULL,     -- MDR-195-15 / SCORCH / MOONEY
    native_id           TEXT NOT NULL,     -- record ID inside the machine DB
    unique_key          TEXT GENERATED ALWAYS AS
                          (source_id || ':' || method_code || ':' || native_id) STORED,

    material_lot_id     UUID REFERENCES material_lot(lot_id) ON DELETE SET NULL,

    tested_at           TIMESTAMPTZ,
    -- JSONB, not one column per metric: GOTECH's schema is still unknown
    -- (site visit pending). Adding a metric must not require a migration.
    metrics             JSONB NOT NULL DEFAULT '{}'::jsonb,

    content_hash        TEXT NOT NULL,     -- SHA256, meaningful fields only
    revision            INTEGER NOT NULL DEFAULT 1,

    source_system       TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT lab_result_identity UNIQUE (source_id, method_code, native_id, revision)
);

CREATE INDEX idx_lab_result_key     ON lab_result (unique_key);
CREATE INDEX idx_lab_result_lot     ON lab_result (material_lot_id);
CREATE INDEX idx_lab_result_tested  ON lab_result (tested_at DESC);
CREATE INDEX idx_lab_result_metrics ON lab_result USING GIN (metrics);


-- =====================================================================
-- §6  BANBURY  —  mixer batches and process readings
-- =====================================================================
CREATE TABLE banbury_batch (
    batch_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    machine_id          TEXT NOT NULL,

    -- Production day boundary is 08:00, NOT midnight. Computed by the
    -- pipeline and stored — never re-derived ad hoc in a dashboard.
    production_day      DATE NOT NULL,
    batch_of_day        INTEGER NOT NULL,
    raw_batch_counter   INTEGER,   -- 当前批次: unreliable, resets at shifts. Reference only.

    material_lot_id     UUID REFERENCES material_lot(lot_id) ON DELETE SET NULL,
    formula_code        TEXT,

    started_at          TIMESTAMPTZ,
    ended_at            TIMESTAMPTZ,     -- BHWork.时间 = discharge end
    cycle_time_s        NUMERIC(8,2) CHECK (cycle_time_s IS NULL OR cycle_time_s >= 0),
    set_mix_time_s      NUMERIC(8,2),
    actual_mix_time_s   NUMERIC(8,2),
    discharge_temp_c    NUMERIC(6,2),

    -- Known data anomalies as first-class booleans, not free text
    is_phantom          BOOLEAN NOT NULL DEFAULT FALSE,
    overlaps_previous   BOOLEAN NOT NULL DEFAULT FALSE,
    boundary_derived    BOOLEAN NOT NULL DEFAULT FALSE,  -- inferred, no BHWork row

    source_system       TEXT NOT NULL,
    source_record_id    TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT banbury_batch_source_key UNIQUE (source_system, source_record_id),
    CONSTRAINT banbury_batch_day_key    UNIQUE (machine_id, production_day, batch_of_day)
);

CREATE INDEX idx_banbury_batch_day     ON banbury_batch (production_day, machine_id);
CREATE INDEX idx_banbury_batch_formula ON banbury_batch (formula_code, production_day);
CREATE INDEX idx_banbury_batch_lot     ON banbury_batch (material_lot_id);

-- ~5-second interval sensor readings. High volume: ~253k rows per USB pull.
-- No UUID PK — time-series tables are keyed by (time, series) for locality.
CREATE TABLE banbury_reading (
    reading_time        TIMESTAMPTZ NOT NULL,
    machine_id          TEXT NOT NULL,
    batch_id            UUID REFERENCES banbury_batch(batch_id) ON DELETE CASCADE,

    -- Units for the first three are UNCONFIRMED — deliberately unlabelled.
    main_current        NUMERIC(10,3),   -- 主机电流
    main_speed          NUMERIC(10,3),   -- 主机转速
    ram_pressure        NUMERIC(10,3),   -- 上顶栓压力
    compound_temp_c     NUMERIC(10,3),   -- 胶料温度 (°C by inference)

    source_system       TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT banbury_reading_key PRIMARY KEY (machine_id, reading_time)
);

CREATE INDEX idx_banbury_reading_batch ON banbury_reading (batch_id, reading_time);


-- =====================================================================
-- §7  TIMESCALEDB  —  OPTIONAL. Skip entirely if not installed.
-- =====================================================================
-- Plain Postgres handles a few million rows fine. Convert when
-- banbury_reading exceeds roughly 50M rows or queries slow noticeably.
--
--   CREATE EXTENSION IF NOT EXISTS timescaledb;
--   SELECT create_hypertable('banbury_reading', 'reading_time',
--                            migrate_data => TRUE, if_not_exists => TRUE);
--   SELECT add_retention_policy('banbury_reading', INTERVAL '5 years');
--
-- Nothing above depends on this. It is a performance change, not a
-- schema change — which is why it can be deferred safely.


-- =====================================================================
-- §8  PROCESS CONTEXT  —  currently-unlogged variables with known
--     correlation to defect rates
-- =====================================================================
CREATE TABLE process_context (
    context_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Attaches to either a lot or a stage/date window; both nullable.
    material_lot_id     UUID REFERENCES material_lot(lot_id) ON DELETE CASCADE,
    stage               TEXT CHECK (stage IS NULL OR stage IN ('A','Q1','Q3')),
    effective_on        DATE NOT NULL,

    release_agent       TEXT,            -- CTS vs LNS-GZ01 — different chemistry
    water_softener_ok   BOOLEAN,
    vulc_temp_c         NUMERIC(5,1) CHECK (vulc_temp_c IS NULL
                                            OR vulc_temp_c BETWEEN 100 AND 250),

    source_system       TEXT NOT NULL,
    source_record_id    TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT process_context_source_key UNIQUE (source_system, source_record_id)
);

CREATE INDEX idx_process_context_lot ON process_context (material_lot_id);


-- =====================================================================
-- §9  INGEST AUDIT + QUARANTINE
-- =====================================================================
-- Every adapter run is recorded. Debuggability is a stated principle.
CREATE TABLE ingest_run (
    run_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_system       TEXT NOT NULL,
    adapter_version     TEXT,
    started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at         TIMESTAMPTZ,
    rows_read           INTEGER,
    rows_written        INTEGER,
    rows_quarantined    INTEGER,
    status              TEXT NOT NULL DEFAULT 'RUNNING'
                          CHECK (status IN ('RUNNING','SUCCESS','FAILED')),
    error_text          TEXT
);

-- Rejected rows are KEPT, never silently dropped. This is how you find out
-- that 34% of Q3 lot numbers are blank, instead of quietly analysing 66%
-- of the data and believing it is 100%.
CREATE TABLE ingest_quarantine (
    quarantine_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id              UUID REFERENCES ingest_run(run_id) ON DELETE SET NULL,
    source_system       TEXT NOT NULL,
    source_record_id    TEXT,
    target_table        TEXT NOT NULL,
    reject_reason       TEXT NOT NULL,
    raw_payload         JSONB NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved            BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_quarantine_unresolved ON ingest_quarantine (source_system, resolved)
    WHERE resolved = FALSE;


-- =====================================================================
-- §10  VIEWS  —  the questions the platform exists to answer
-- =====================================================================

-- Correct bladder lifetime. Sums ALL segments under one instance.
-- Fixes the documented understatement: 200 + 300 reports as 500, not 300.
CREATE VIEW v_bladder_lifetime AS
SELECT
    b.bladder_id,
    b.spec_code,
    b.compound_code,
    b.press_id,
    b.factory_id,
    b.q3_lot_id,
    q3.lot_code                                   AS q3_lot_code,
    b.produced_on,
    SUM(COALESCE(e.cycles_this_segment, 0))       AS total_cycles,
    COUNT(e.event_id)                             AS segment_count,
    MAX(e.occurred_on) FILTER (WHERE r.is_terminal) AS retired_on,
    MAX(e.reason_code) FILTER (WHERE r.is_terminal) AS retirement_reason,
    bool_or(r.is_terminal)                        AS is_retired
FROM bladder_instance b
LEFT JOIN bladder_event e  ON e.bladder_id  = b.bladder_id
LEFT JOIN event_reason  r  ON r.reason_code = e.reason_code
LEFT JOIN material_lot  q3 ON q3.lot_id     = b.q3_lot_id
GROUP BY b.bladder_id, b.spec_code, b.compound_code, b.press_id,
         b.factory_id, b.q3_lot_id, q3.lot_code, b.produced_on;

COMMENT ON VIEW v_bladder_lifetime IS
  'total_cycles is only a true LIFETIME where is_retired = TRUE. '
  'For in-service bladders it is cycles-to-date. Filter accordingly.';

-- Full upstream lineage of any lot: Q3 -> its Q1 parents -> their A parents.
-- Recursive CTE walks the lot_consumption edges to arbitrary depth.
CREATE VIEW v_lot_ancestry AS
WITH RECURSIVE ancestry AS (
    SELECT
        l.lot_id        AS descendant_lot_id,
        l.lot_id        AS ancestor_lot_id,
        l.stage         AS ancestor_stage,
        l.lot_code      AS ancestor_lot_code,
        0               AS depth
    FROM material_lot l
  UNION ALL
    SELECT
        a.descendant_lot_id,
        p.lot_id,
        p.stage,
        p.lot_code,
        a.depth + 1
    FROM ancestry a
    JOIN lot_consumption c ON c.child_lot_id  = a.ancestor_lot_id
    JOIN material_lot    p ON p.lot_id        = c.parent_lot_id
    WHERE a.depth < 10          -- cycle guard
)
SELECT * FROM ancestry WHERE depth > 0;

-- Data completeness, per source. Run this weekly — it is your KPI for
-- whether the data is trustworthy enough to draw conclusions from.
CREATE VIEW v_data_completeness AS
SELECT 'bladder_instance' AS table_name, 'q3_lot_id'     AS column_name,
       COUNT(*) AS total,
       COUNT(*) FILTER (WHERE q3_lot_id IS NULL)     AS missing,
       ROUND(100.0 * COUNT(*) FILTER (WHERE q3_lot_id IS NULL)
             / NULLIF(COUNT(*),0), 1)                AS pct_missing
FROM bladder_instance
UNION ALL
SELECT 'bladder_instance', 'tray_position',
       COUNT(*), COUNT(*) FILTER (WHERE tray_position IS NULL),
       ROUND(100.0 * COUNT(*) FILTER (WHERE tray_position IS NULL)
             / NULLIF(COUNT(*),0), 1)
FROM bladder_instance
UNION ALL
SELECT 'bladder_instance', 'press_id',
       COUNT(*), COUNT(*) FILTER (WHERE press_id IS NULL),
       ROUND(100.0 * COUNT(*) FILTER (WHERE press_id IS NULL)
             / NULLIF(COUNT(*),0), 1)
FROM bladder_instance
UNION ALL
SELECT 'bladder_event', 'cycles_this_segment',
       COUNT(*), COUNT(*) FILTER (WHERE cycles_this_segment IS NULL),
       ROUND(100.0 * COUNT(*) FILTER (WHERE cycles_this_segment IS NULL)
             / NULLIF(COUNT(*),0), 1)
FROM bladder_event
UNION ALL
SELECT 'material_lot', 'compound_code',
       COUNT(*), COUNT(*) FILTER (WHERE compound_code IS NULL),
       ROUND(100.0 * COUNT(*) FILTER (WHERE compound_code IS NULL)
             / NULLIF(COUNT(*),0), 1)
FROM material_lot;
