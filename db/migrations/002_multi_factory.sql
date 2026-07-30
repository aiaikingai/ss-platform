-- =====================================================================
-- ss-lab-platform — migration 002
-- Multi-factory / multi-country support
-- =====================================================================
-- Driver: cycle data will arrive from factories in other countries with
-- different formats and, critically, a DIFFERENT DEFECT VOCABULARY.
--
-- Two additions:
--   §1  factory        — factories become a real entity, not a TEXT label
--   §2  source_reason_map — canonical reason codes decoupled from the
--                           words each source actually writes
--
-- Both are cheap now and expensive to retrofit after data is loaded.
-- =====================================================================


-- =====================================================================
-- §1  FACTORY
-- =====================================================================
-- DELIBERATE EXCEPTION to the UUID-primary-key rule.
--
-- Why: there will be under ~20 factories, ever. The codes are stable,
-- human-readable, and appear in nearly every query and dashboard filter.
-- A UUID here would force a join on every ad-hoc question you ask.
-- UUIDs exist to prevent collisions in high-volume, machine-generated,
-- multi-source data — that risk does not apply to a hand-maintained
-- list of factories.
--
-- Knowing WHY a rule exists is what tells you when not to apply it.
CREATE TABLE factory (
    factory_id      TEXT PRIMARY KEY
                      CHECK (factory_id ~ '^[A-Z0-9_-]{2,20}$'),
    name            TEXT NOT NULL,
    country_code    CHAR(2) NOT NULL,   -- ISO 3166-1 alpha-2: CN, KR, HU ...
    timezone        TEXT NOT NULL,      -- IANA: 'Asia/Shanghai', 'Asia/Seoul'
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    notes           TEXT
);

COMMENT ON COLUMN factory.timezone IS
  'All *_on DATE columns store the LOCAL calendar date at the factory. '
  'This column exists to convert them when comparing across countries. '
  'Never store event dates in UTC — a mold change on 2026-03-12 in Korea '
  'is 2026-03-12, regardless of what UTC says.';

INSERT INTO factory (factory_id, name, country_code, timezone, notes) VALUES
  ('JIAXING', '嘉兴新盛橡塑模具有限公司', 'CN', 'Asia/Shanghai',
   'Home factory. Source of all data as of 2026-07.'),
  ('UNKNOWN', 'Unattributed / legacy records', 'CN', 'Asia/Shanghai',
   'Placeholder for historical rows with no factory recorded. '
   'Treat as a data-quality bucket, not a real site.');


-- Attach existing tables to it.
-- Nullable, because historical rows may genuinely not say which factory.
ALTER TABLE bladder_instance
    ADD CONSTRAINT bladder_instance_factory_fk
    FOREIGN KEY (factory_id) REFERENCES factory(factory_id) ON DELETE RESTRICT;

ALTER TABLE bladder_event
    ADD CONSTRAINT bladder_event_factory_fk
    FOREIGN KEY (factory_id) REFERENCES factory(factory_id) ON DELETE RESTRICT;

ALTER TABLE material_lot
    ADD COLUMN factory_id TEXT REFERENCES factory(factory_id) ON DELETE RESTRICT;

CREATE INDEX idx_bladder_instance_factory ON bladder_instance (factory_id);
CREATE INDEX idx_bladder_event_factory    ON bladder_event (factory_id);
CREATE INDEX idx_material_lot_factory     ON material_lot (factory_id);


-- =====================================================================
-- §2  SOURCE REASON MAP  —  the multi-country translation layer
-- =====================================================================
-- A Korean or European factory will not write 老化 or 上部裂开. It will
-- write 'AGING', 'Aging', 'Normal wear', 'Bead crack', or something in
-- Hungarian.
--
-- WITHOUT this table, every adapter hardcodes its own translation dict.
-- That is the HASH_FIELDS bug again: the same rule living in four files,
-- silently diverging. With it, adapters do a LOOKUP, never a translation,
-- and the mapping is data you can inspect and correct with a SQL UPDATE.
CREATE TABLE source_reason_map (
    map_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    source_system   TEXT NOT NULL,
    -- Stored EXACTLY as it appears in the source file. Do not trim,
    -- normalise case, or clean it here — the adapter must match byte for
    -- byte, or the lookup silently misses and you lose the record.
    raw_reason      TEXT NOT NULL,

    reason_code     TEXT NOT NULL REFERENCES event_reason(reason_code),

    -- CONFIRMED = a human at that factory verified the meaning.
    -- ASSUMED   = inferred by translation, NOT yet verified.
    -- Analysis that depends on ASSUMED mappings must say so.
    confidence      TEXT NOT NULL DEFAULT 'ASSUMED'
                      CHECK (confidence IN ('CONFIRMED','ASSUMED')),
    mapped_by       TEXT,
    mapped_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    notes           TEXT,

    CONSTRAINT source_reason_map_key UNIQUE (source_system, raw_reason)
);

CREATE INDEX idx_source_reason_map_lookup
    ON source_reason_map (source_system, raw_reason);

-- Seed the known Jiaxing vocabulary.
INSERT INTO source_reason_map (source_system, raw_reason, reason_code, confidence, notes) VALUES
  ('excel_bladder_jiaxing', '老化',      'AGING',           'CONFIRMED', NULL),
  ('excel_bladder_jiaxing', '上部裂开',   'CRACK_UPPER',     'CONFIRMED', 'EAR crack'),
  ('excel_bladder_jiaxing', '内部裂开',   'CRACK_INTERNAL',  'CONFIRMED', NULL),
  ('excel_bladder_jiaxing', '表面裂开',   'CRACK_SURFACE',   'CONFIRMED', NULL),
  ('excel_bladder_jiaxing', '下部裂开',   'CRACK_LOWER',     'CONFIRMED', NULL),
  ('excel_bladder_jiaxing', '中部裂开',   'CRACK_MIDDLE',    'CONFIRMED', NULL),
  ('excel_bladder_jiaxing', '花纹槽裂开', 'CRACK_GROOVE',    'CONFIRMED', NULL),
  ('excel_bladder_jiaxing', '分层',      'DELAMINATION',    'CONFIRMED', NULL),
  ('excel_bladder_jiaxing', '脱皮',      'PEELING',         'CONFIRMED', NULL),
  ('excel_bladder_jiaxing', 'RB',       'RB',              'CONFIRMED', 'Rough Bladder'),
  ('excel_bladder_jiaxing', 'LEB',      'LEB',             'CONFIRMED', NULL),
  ('excel_bladder_jiaxing', '模具交替',   'MOLD_CHANGE',     'CONFIRMED', 'NON-terminal'),
  ('excel_bladder_jiaxing', '模具清扫',   'MOLD_CLEANING',   'CONFIRMED', 'NON-terminal'),
  ('excel_bladder_jiaxing', '故障',      'EQUIPMENT_FAULT', 'CONFIRMED', 'NON-terminal'),
  ('excel_bladder_jiaxing', '新装',      'DEPLOY',          'CONFIRMED', NULL),
  ('excel_bladder_jiaxing', '试验',      'TRIAL',           'CONFIRMED', NULL),
  ('excel_bladder_jiaxing', '其他',      'OTHER',           'CONFIRMED', NULL);


-- Helper. Returns NULL when a term is unknown — the adapter MUST treat
-- NULL as "quarantine this row", never as "default to OTHER".
--
-- Silently defaulting an unrecognised defect term to OTHER is how you
-- lose the signal you built the platform to find. A new factory's unknown
-- term should stop and ask for a human decision exactly once, then be
-- mapped forever.
CREATE FUNCTION resolve_reason(p_source TEXT, p_raw TEXT)
RETURNS TEXT
LANGUAGE sql STABLE AS $$
    SELECT reason_code FROM source_reason_map
    WHERE source_system = p_source AND raw_reason = p_raw;
$$;


-- =====================================================================
-- §3  VIEWS  —  updated for cross-factory analysis
-- =====================================================================
DROP VIEW IF EXISTS v_bladder_lifetime;

CREATE VIEW v_bladder_lifetime AS
SELECT
    b.bladder_id,
    b.factory_id,
    f.name                                          AS factory_name,
    f.country_code,
    b.spec_code,
    b.compound_code,
    b.press_id,
    b.q3_lot_id,
    q3.lot_code                                     AS q3_lot_code,
    b.produced_on,
    SUM(COALESCE(e.cycles_this_segment, 0))         AS total_cycles,
    COUNT(e.event_id)                               AS segment_count,
    MAX(e.occurred_on) FILTER (WHERE r.is_terminal) AS retired_on,
    MAX(e.reason_code) FILTER (WHERE r.is_terminal) AS retirement_reason,
    bool_or(r.is_terminal)                          AS is_retired,
    -- Hankook KPI: 400 target, 300-500 acceptable. Only meaningful
    -- once retired — an in-service bladder has not finished accruing.
    CASE WHEN bool_or(r.is_terminal)
         THEN SUM(COALESCE(e.cycles_this_segment,0)) BETWEEN 300 AND 500
    END                                             AS meets_spec
FROM bladder_instance b
LEFT JOIN bladder_event e  ON e.bladder_id  = b.bladder_id
LEFT JOIN event_reason  r  ON r.reason_code = e.reason_code
LEFT JOIN material_lot  q3 ON q3.lot_id     = b.q3_lot_id
LEFT JOIN factory       f  ON f.factory_id  = b.factory_id
GROUP BY b.bladder_id, b.factory_id, f.name, f.country_code, b.spec_code,
         b.compound_code, b.press_id, b.q3_lot_id, q3.lot_code, b.produced_on;

COMMENT ON VIEW v_bladder_lifetime IS
  'total_cycles is a true LIFETIME only where is_retired = TRUE. '
  'For in-service bladders it is cycles-to-date. Always filter on '
  'is_retired before computing mean lifecycle or compliance rate.';


-- Cross-factory comparison. Retired units only — mixing in-service
-- bladders into a mean lifetime understates it, which is the same
-- class of error as the orphaned-segment bug.
CREATE VIEW v_factory_performance AS
SELECT
    factory_id,
    factory_name,
    country_code,
    compound_code,
    COUNT(*)                                        AS retired_units,
    ROUND(AVG(total_cycles), 1)                     AS mean_cycles,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_cycles) AS median_cycles,
    MIN(total_cycles)                               AS min_cycles,
    MAX(total_cycles)                               AS max_cycles,
    ROUND(100.0 * COUNT(*) FILTER (WHERE meets_spec) / NULLIF(COUNT(*),0), 1)
                                                    AS pct_meets_spec,
    ROUND(100.0 * COUNT(*) FILTER (WHERE retirement_reason LIKE 'CRACK%')
          / NULLIF(COUNT(*),0), 1)                  AS pct_crack_failure
FROM v_bladder_lifetime
WHERE is_retired
GROUP BY factory_id, factory_name, country_code, compound_code;


-- Mapping coverage. Run after every new-factory ingest: any ASSUMED rows
-- are unverified translations that weaken every conclusion drawn from them.
CREATE VIEW v_reason_map_health AS
SELECT
    source_system,
    COUNT(*)                                            AS mapped_terms,
    COUNT(*) FILTER (WHERE confidence = 'ASSUMED')      AS unverified_terms,
    ROUND(100.0 * COUNT(*) FILTER (WHERE confidence='ASSUMED')
          / NULLIF(COUNT(*),0), 1)                      AS pct_unverified
FROM source_reason_map
GROUP BY source_system;
