-- =====================================================================
-- ss-platform — 003: SY Production Quality Record
-- =====================================================================
-- Source: MANUFACTURING_SYSTEM_DEV_CONTEXT.md §3a  (2026-08-05)
--
-- This is the PRODUCTION-side record (what SY made and how it graded).
-- It is NOT the client lifecycle record (how bladders failed in service).
-- §3a is explicit that both must exist as separate tables, linked — not
-- merged. They have genuinely different grains:
--
--   production_qc_record : one row per (Q3 lot, spec, date, shift)  -- AGGREGATE
--   bladder_event        : one row per service event per bladder    -- PER-UNIT
--
-- Joining these two is, per §3a, "probably the single highest-value
-- capability the new system should aim for" — it is what lets you ask
-- whether a batch's bubble rate predicted its field crack rate.
-- =====================================================================


-- =====================================================================
-- §1  DEFECT TYPE  —  lookup, not an enum
-- =====================================================================
-- A table rather than a CHECK constraint because 初回's meaning is still
-- unconfirmed with production staff and the list will grow. Adding a row
-- is an INSERT; changing a CHECK is a migration.
CREATE TABLE defect_type (
    defect_code     TEXT PRIMARY KEY,
    label_zh        TEXT NOT NULL,
    label_en        TEXT NOT NULL,
    -- Bubble defects drive ~99% of B-grade outcomes (§3a item 2,
    -- resolved 2026-08-04). Flagged so queries can isolate the real
    -- driver without hardcoding two defect codes.
    is_bubble       BOOLEAN NOT NULL DEFAULT FALSE,
    notes           TEXT
);

INSERT INTO defect_type (defect_code, label_zh, label_en, is_bubble, notes) VALUES
  ('BUBBLE_INTERNAL', '内部汽包', 'Internal bubble',        TRUE,
   'Primary B/C grading driver'),
  ('BUBBLE_EXTERNAL', '外部汽包', 'External bubble',        TRUE,
   'Primary B/C grading driver'),
  ('SHORT_SHOT',      '缺料',    'Short shot / shortage',  FALSE, NULL),
  ('INJECTION',       '注射不良', 'Injection defect',       FALSE, NULL),
  ('SCORCH',          '焦烧',    'Scorch',                 FALSE, NULL),
  ('CRACK',           '裂开',    'Crack',                  FALSE,
   'Rare in B grade — tail case, not a driver (§3a, resolved 2026-08-04)'),
  ('EQUIPMENT',       '设备',    'Equipment-caused',       FALSE, 'Observed in C only'),
  ('FM',              'FM',      'Foreign matter',         FALSE, 'Observed in C only'),
  ('FIRST_CURE',      '初回',    'First cure',             FALSE,
   'MEANING UNCONFIRMED — verify with production staff (§3a open item)');


-- =====================================================================
-- §2  PRODUCTION QC RECORD  —  one row per (Q3 lot, spec, date, shift)
-- =====================================================================
-- Grain confirmed 2026-08-05:
--   Q3胶Lot + 托盘号 identifies the rubber (-> material_lot_id)
--   规格 varies within one rubber batch per the manufacturing plan
--   shift is DESCRIPTIVE (which inspection team), never identity
--
-- So one Q3 rubber batch produces MULTIPLE qc rows, one per spec made
-- from it. That is correct and useful: it lets you ask whether a single
-- rubber batch performed differently across bladder sizes.
CREATE TABLE production_qc_record (
    qc_record_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- The Q3 rubber. Nullable because legacy records have ~34% missing
    -- Q3 lot (§5) — NULL means genuinely unknown, never a sentinel.
    material_lot_id     UUID REFERENCES material_lot(lot_id) ON DELETE SET NULL,

    site_id             TEXT NOT NULL DEFAULT 'SY' REFERENCES production_site(site_id),
    curing_machine_id   TEXT REFERENCES curing_machine(machine_id),

    spec_code           TEXT,        -- 规格: BG36BP, BE26AN, ...
    compound_code       TEXT,        -- 橡胶
    production_date     DATE NOT NULL,
    shift               TEXT CHECK (shift IS NULL OR shift IN ('A','B')),

    -- 胶囊LOT. The join key to the client lifecycle record.
    -- Per §3: a sequence scoped to (production_date, curing_machine_id),
    -- counting window 08:00 -> 08:00. NOT a tray position (that was the
    -- superseded v1 definition), NOT derived from rubber or Q3 lot.
    bladder_sequence_no INTEGER CHECK (bladder_sequence_no IS NULL
                                       OR bladder_sequence_no > 0),

    -- 总生产量(EA). A-grade count is total minus B minus C — never
    -- stored, always derived, so it cannot drift out of agreement.
    total_output_ea     INTEGER CHECK (total_output_ea IS NULL
                                       OR total_output_ea >= 0),

    remarks             TEXT,        -- 备注

    source_system       TEXT NOT NULL,
    source_record_id    TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    data_quality_flag   TEXT,

    CONSTRAINT production_qc_source_key UNIQUE (source_system, source_record_id),
    CONSTRAINT production_qc_grain
        UNIQUE (material_lot_id, spec_code, production_date, shift)
);

COMMENT ON COLUMN production_qc_record.bladder_sequence_no IS
  '胶囊LOT — sequence within (production_date, curing_machine_id), 08:00 window. '
  'Joins to the client lifecycle record. Confirmed same value on both sides for '
  'Hankook JX; UNVERIFIED for Korea plants — scope joins by client site.';

CREATE INDEX idx_qc_lot     ON production_qc_record (material_lot_id);
CREATE INDEX idx_qc_date    ON production_qc_record (production_date, shift);
CREATE INDEX idx_qc_spec    ON production_qc_record (spec_code, production_date);
CREATE INDEX idx_qc_machine ON production_qc_record (curing_machine_id, production_date);
CREATE INDEX idx_qc_join    ON production_qc_record
    (production_date, curing_machine_id, bladder_sequence_no);


-- =====================================================================
-- §3  PRODUCTION DEFECT  —  long format, per §3a design guidance
-- =====================================================================
-- §3a explicitly warns against flat columns per defect type:
--   "a fact table with grade (A/B/C) and defect-type as dimensions,
--    not flat columns per defect type if you want it queryable
--    (e.g. 'total FM defects by month' without hardcoding column names)"
--
-- With 9 defect types x 2 grades, the flat version would be 18 columns
-- and every new defect type would need an ALTER TABLE. Long format:
-- one row per (record, grade, defect_type, count). Adding a type is an
-- INSERT into defect_type.
--
-- Grade A gets no rows here at all. A is not a defect; it is the
-- remainder: total_output_ea - SUM(count_ea).
CREATE TABLE production_defect (
    defect_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    qc_record_id    UUID NOT NULL REFERENCES production_qc_record(qc_record_id) ON DELETE CASCADE,

    grade           TEXT NOT NULL CHECK (grade IN ('B','C')),
    defect_code     TEXT NOT NULL REFERENCES defect_type(defect_code),
    count_ea        INTEGER NOT NULL CHECK (count_ea >= 0),

    CONSTRAINT production_defect_key UNIQUE (qc_record_id, grade, defect_code)
);

COMMENT ON TABLE production_defect IS
  'Grade B = minor (small/few bubbles), C = reject. The exact B-vs-C bubble '
  'threshold is UNDEFINED (§3a open item 1) — grade is stored AS RECORDED by '
  'the inspector, never computed. Note the schema does NOT restrict which '
  'defect types may be grade B: 设备/FM/初回 appear only in C in the legacy '
  'sheet, but whether that is structural or incidental is unconfirmed (§3a '
  'open item 3). Let the data show it rather than constraining prematurely.';

CREATE INDEX idx_production_defect_record ON production_defect (qc_record_id);
CREATE INDEX idx_production_defect_type   ON production_defect (defect_code, grade);
