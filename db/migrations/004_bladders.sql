-- =====================================================================
-- ss-platform — 004: Bladder Instance & Service Events
-- =====================================================================
-- Source: MANUFACTURING_SYSTEM_DEV_CONTEXT.md §3, §4, §5  (2026-08-05)
--
-- THE CONTRADICTION THIS FILE RESOLVES:
--   §3 says (production_date, curing_machine_id, 胶囊LOT) uniquely
--       identifies a bladder.
--   §5 says 胶囊LOT is ~48% missing and production date ~20% missing
--       in legacy data.
--
-- Both are true, about different things: the triple is unique WHEN
-- PRESENT, and frequently ABSENT historically. So:
--
--   UUID primary key            -> every row loads, including the ~48%
--   UNIQUE on the triple        -> new records cannot duplicate
--
-- Postgres allows multiple NULL rows under a unique constraint, so
-- incomplete legacy records coexist with enforced uniqueness on
-- complete ones. Using the triple AS the PK would make roughly half
-- your history unloadable.
-- =====================================================================


-- =====================================================================
-- §1  EVENT REASON  —  lookup table, not a CHECK constraint
-- =====================================================================
-- is_terminal is a PROPERTY of the reason, so it lives with the reason.
-- No query anywhere hardcodes which reasons end a bladder's life — and
-- that distinction is precisely WHY legacy cycle counts understate
-- lifetime. Add a reason next year with one INSERT; every existing
-- query handles it correctly.
CREATE TABLE event_reason (
    reason_code     TEXT PRIMARY KEY,
    label_zh        TEXT NOT NULL,
    label_en        TEXT NOT NULL,
    is_terminal     BOOLEAN NOT NULL,
    notes           TEXT
);

COMMENT ON COLUMN event_reason.is_terminal IS
  'TRUE  = bladder retired; cycles_this_segment closes the lifecycle. '
  'FALSE = bladder returns to service; cycles_this_segment is PARTIAL. '
  'Ignoring this distinction is the documented understatement bug (§4).';

INSERT INTO event_reason (reason_code, label_zh, label_en, is_terminal, notes) VALUES
  ('AGING',           '老化',      'Aging / normal wear',      TRUE,  'Baseline expected end-of-life'),
  ('CRACK_UPPER',     '上部裂开',   'Upper crack (EAR crack)',  TRUE,
   'Bead/clamp-ring zone. Mechanistically DISTINCT from RB — not a subtype (§6)'),
  ('CRACK_INTERNAL',  '内部裂开',   'Internal crack',           TRUE,  NULL),
  ('CRACK_SURFACE',   '表面裂开',   'Surface crack',            TRUE,  NULL),
  ('CRACK_LOWER',     '下部裂开',   'Lower crack',              TRUE,  NULL),
  ('CRACK_MIDDLE',    '中部裂开',   'Middle crack',             TRUE,  NULL),
  ('CRACK_GROOVE',    '花纹槽裂开', 'Tread groove crack',       TRUE,  NULL),
  ('DELAMINATION',    '分层',      'Delamination',             TRUE,  NULL),
  ('PEELING',         '脱皮',      'Peeling',                  TRUE,  NULL),
  ('RB',              'RB',       'Rough Bladder',            TRUE,
   'Sulfur-migration microcrack. NOT safety-critical, NOT rubber burst — '
   'do not alert as high severity (§6). Onset <300 cycles is itself a signal.'),
  ('LEB',             'LEB',      'Low-cycle early failure',  TRUE,  NULL),
  ('MOLD_CHANGE',     '模具交替',   'Mold change',              FALSE, 'Continues in service — PARTIAL count'),
  ('MOLD_CLEANING',   '模具清扫',   'Mold cleaning',            FALSE, 'Continues in service — PARTIAL count'),
  ('EQUIPMENT_FAULT', '故障',      'Equipment fault',          FALSE, 'Continues in service — PARTIAL count'),
  ('DEPLOY',          '新装',      'New deployment',           FALSE, 'No cycle data yet'),
  ('TRIAL',           '试验',      'Trial unit',               FALSE, 'EXCLUDE from lifecycle statistics'),
  ('OTHER',           '其他',      'Unspecified',              FALSE, NULL);


-- =====================================================================
-- §2  SOURCE REASON MAP  —  multi-vocabulary translation
-- =====================================================================
-- A Korean or European plant will not write 老化. Without this table,
-- every adapter carries its own translation dict — the same rule in N
-- files, silently diverging. With it, adapters LOOK UP, never translate,
-- and the mapping is data you can inspect and fix with an UPDATE.
CREATE TABLE source_reason_map (
    map_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_system   TEXT NOT NULL,
    -- Stored EXACTLY as it appears in the source. Do not trim or
    -- normalise case here — the adapter must match byte for byte or the
    -- lookup silently misses.
    raw_reason      TEXT NOT NULL,
    reason_code     TEXT NOT NULL REFERENCES event_reason(reason_code),

    -- CONFIRMED = a human at that site verified the meaning.
    -- ASSUMED   = inferred by translation, NOT verified.
    -- Analysis resting on ASSUMED mappings must say so.
    confidence      TEXT NOT NULL DEFAULT 'ASSUMED'
                      CHECK (confidence IN ('CONFIRMED','ASSUMED')),
    mapped_by       TEXT,
    mapped_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    notes           TEXT,

    CONSTRAINT source_reason_map_key UNIQUE (source_system, raw_reason)
);

INSERT INTO source_reason_map (source_system, raw_reason, reason_code, confidence) VALUES
  ('feishu_lifecycle_hankook_jx', '老化',      'AGING',           'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', '上部裂开',   'CRACK_UPPER',     'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', '内部裂开',   'CRACK_INTERNAL',  'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', '表面裂开',   'CRACK_SURFACE',   'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', '下部裂开',   'CRACK_LOWER',     'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', '中部裂开',   'CRACK_MIDDLE',    'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', '花纹槽裂开', 'CRACK_GROOVE',    'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', '分层',      'DELAMINATION',    'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', '脱皮',      'PEELING',         'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', 'RB',       'RB',              'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', 'LEB',      'LEB',             'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', '模具交替',   'MOLD_CHANGE',     'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', '模具清扫',   'MOLD_CLEANING',   'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', '故障',      'EQUIPMENT_FAULT', 'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', '新装',      'DEPLOY',          'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', '试验',      'TRIAL',           'CONFIRMED'),
  ('feishu_lifecycle_hankook_jx', '其他',      'OTHER',           'CONFIRMED');

-- Returns NULL for an unknown term. The adapter MUST treat NULL as
-- "quarantine this row", never as "default to OTHER".
-- Silently bucketing an unrecognised defect term into OTHER destroys
-- the signal the platform exists to find. A new site's unknown term
-- should stop and ask a human once, then be mapped forever.
CREATE FUNCTION resolve_reason(p_source TEXT, p_raw TEXT)
RETURNS TEXT
LANGUAGE sql STABLE AS $$
    SELECT reason_code FROM source_reason_map
    WHERE source_system = p_source AND raw_reason = p_raw;
$$;


-- =====================================================================
-- §3  BLADDER INSTANCE  —  one row per physical bladder, ever
-- =====================================================================
CREATE TABLE bladder_instance (
    bladder_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- ---- the natural key triple (§3), all nullable for legacy load ----
    produced_on         DATE,
    curing_machine_id   TEXT REFERENCES curing_machine(machine_id),
    bladder_sequence_no INTEGER CHECK (bladder_sequence_no IS NULL
                                       OR bladder_sequence_no > 0),

    -- ---- descriptive attributes (NOT identity, per §3/§3b) ----
    q3_lot_id           UUID REFERENCES material_lot(lot_id) ON DELETE SET NULL,
    spec_code           TEXT,        -- 规格
    compound_code       TEXT,        -- 橡胶
    stack_position      TEXT CHECK (stack_position IS NULL OR stack_position ~ '^[A-D]$'),
    stack_sequence_no   INTEGER CHECK (stack_sequence_no IS NULL OR stack_sequence_no > 0),

    produced_at_site_id TEXT REFERENCES production_site(site_id),

    -- Post-cure coating (§2). Three mutually exclusive states.
    -- Oil-based has documented adhesion failure near the clamp-ring/bead
    -- zone at ~50 cycles vs ~400 normal — an 8x lifetime reduction, so
    -- this is not optional. Water-based has NO equivalent documented
    -- failure history: do NOT assume shared failure modes in alerting.
    coating_type        TEXT CHECK (coating_type IS NULL
                                    OR coating_type IN ('NONE','OIL_BASED','WATER_BASED')),

    source_system       TEXT NOT NULL,
    source_record_id    TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    data_quality_flag   TEXT,

    CONSTRAINT bladder_instance_source_key UNIQUE (source_system, source_record_id),

    -- The §3 triple. Enforced when present; NULLs coexist freely so the
    -- ~48% of legacy rows missing 胶囊LOT still load.
    CONSTRAINT bladder_instance_natural_key
        UNIQUE (produced_on, curing_machine_id, bladder_sequence_no)
);

COMMENT ON COLUMN bladder_instance.bladder_sequence_no IS
  '胶囊LOT — sequence within (produced_on, curing_machine_id), 08:00->08:00 window. '
  'NOT a tray position (superseded v1 definition). NOT derived from rubber type '
  'or Q3 lot — both can change mid-window while this keeps counting.';

CREATE INDEX idx_bladder_q3_lot  ON bladder_instance (q3_lot_id);
CREATE INDEX idx_bladder_spec    ON bladder_instance (spec_code, produced_on);
CREATE INDEX idx_bladder_machine ON bladder_instance (curing_machine_id, produced_on);
CREATE INDEX idx_bladder_coating ON bladder_instance (coating_type);


-- =====================================================================
-- §4  BLADDER EVENT  —  the orphaned-segment fix
-- =====================================================================
-- Each service segment is a CHILD row under a persistent instance.
-- Lifetime = SUM(cycles_this_segment). The documented
-- 200 + 300 = 500 case becomes correct BY CONSTRUCTION rather than by
-- someone remembering to write the query correctly.
CREATE TABLE bladder_event (
    event_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bladder_id          UUID NOT NULL REFERENCES bladder_instance(bladder_id) ON DELETE CASCADE,

    reason_code         TEXT NOT NULL REFERENCES event_reason(reason_code),
    occurred_on         DATE NOT NULL,

    -- Cycles accrued in THIS segment only. Whether it closes the
    -- lifecycle is decided by event_reason.is_terminal — never
    -- hardcoded in a query.
    cycles_this_segment INTEGER CHECK (cycles_this_segment IS NULL
                                       OR cycles_this_segment >= 0),

    -- WHERE IT WAS USED — the client's site. Distinct from
    -- bladder_instance.produced_at_site_id (where it was MADE).
    client_factory_id   TEXT REFERENCES client_factory(client_factory_id),
    -- The customer's own tire press. Free text: their equipment, their
    -- numbering. NOT the same thing as curing_machine_id.
    client_press_id     TEXT,

    source_system       TEXT NOT NULL,
    source_record_id    TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    data_quality_flag   TEXT,

    CONSTRAINT bladder_event_source_key UNIQUE (source_system, source_record_id)
);

COMMENT ON COLUMN bladder_event.client_press_id IS
  'The CLIENT tire press where the bladder was in service. Never confuse with '
  'bladder_instance.curing_machine_id, which is OUR SY machine that made it.';

CREATE INDEX idx_bladder_event_bladder ON bladder_event (bladder_id, occurred_on);
CREATE INDEX idx_bladder_event_reason  ON bladder_event (reason_code, occurred_on);
CREATE INDEX idx_bladder_event_factory ON bladder_event (client_factory_id, occurred_on);
