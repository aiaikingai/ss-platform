-- =====================================================================
-- ss-platform — 008: Ingredient Batches & SY Lab
-- =====================================================================
-- Two gaps identified 2026-08-05:
--
--   1. INGREDIENT BATCHES had nowhere to live. material_lot only allowed
--      stage IN ('A','Q1','Q3'), so the carbon black lot, the Hitanol
--      resin lot, the IIR delivery had no home. Consequence: a defect
--      traced back to a bad resin batch stopped at the Q1 lot — you
--      could not ask "which other Q1 lots used that same resin?", which
--      is the central question in any supplier-quality investigation.
--
--   2. SY LAB could re-test Q3 samples (lab_result already carries
--      production_site_id) but had nowhere to record FINAL PRODUCT
--      tests, because lab_result links only to material_lot and a
--      finished bladder is not a material lot.
--
-- DESIGN NOTE — why ingredients are NOT a separate table:
--   A raw material batch has the same shape as a compound batch: a code,
--   a date, a quantity, a supplier, and it is consumed by something
--   downstream. lot_consumption already models exactly that edge.
--   A separate ingredient_lot table would mean a second genealogy
--   mechanism, a second ancestry view, and two places to fix when the
--   rules change — the duplicated-logic failure mode this schema exists
--   to prevent. One table, one edge table, one recursive view.
--
-- Result: the chain extends one level upstream, unchanged machinery.
--   ingredient -> A -> Q1 -> Q3 -> bladder
-- Blending is already handled: lot_consumption is many-to-many, so
-- several A lots feeding one Q1 lot (or several Q1 into one Q3) needs
-- no schema change at all.
-- =====================================================================


-- =====================================================================
-- §1  ALLOW RAW INGREDIENT LOTS
-- =====================================================================
ALTER TABLE material_lot DROP CONSTRAINT material_lot_stage_check;

ALTER TABLE material_lot
    ADD CONSTRAINT material_lot_stage_check
    CHECK (stage IN ('RAW','A','Q1','Q3'));

COMMENT ON COLUMN material_lot.stage IS
  'RAW = purchased ingredient batch (carbon black, resin, ZnO, IIR...). '
  'A/Q1/Q3 = in-house compound stages. RAW sits upstream of A in the same '
  'genealogy chain, so v_lot_ancestry traces ingredient -> bladder with no '
  'query changes.';

-- Supplier identity, only meaningful for RAW lots.
ALTER TABLE material_lot
    ADD COLUMN supplier        TEXT,
    ADD COLUMN ingredient_code TEXT;

COMMENT ON COLUMN material_lot.ingredient_code IS
  'FK-by-convention to ingredient_type.ingredient_code for RAW lots. '
  'NULL for A/Q1/Q3 — those are identified by compound_code instead.';

-- filtered has no meaning for a purchased ingredient — it describes an
-- in-house process step. Enforce that rather than leaving ambiguous NULLs
-- that later get misread as "not filtered".
ALTER TABLE material_lot
    ADD CONSTRAINT material_lot_raw_not_filtered
    CHECK (stage <> 'RAW' OR filtered IS NULL);


-- =====================================================================
-- §2  INGREDIENT TYPE  —  lookup, not an enum
-- =====================================================================
-- A table because the ingredient list will grow, and because
-- feeds_stage is a PROPERTY of the ingredient that queries should read
-- rather than hardcode. Doc §2: A-stage takes IIR/BIIR/CIIR + carbon
-- black + acetylene black + ZnO + castor oil; Q1 adds M-40 phenolic
-- resin (Hitanol) + stearic acid.
CREATE TABLE ingredient_type (
    ingredient_code TEXT PRIMARY KEY,
    label_zh        TEXT,
    label_en        TEXT NOT NULL,
    category        TEXT NOT NULL
                      CHECK (category IN ('POLYMER','FILLER','RESIN','OIL',
                                          'ACTIVATOR','ACID','RELEASE_AGENT','OTHER')),
    -- Which compound stage normally consumes it. Descriptive, not
    -- enforced — a constraint here would break the first time an
    -- ingredient is legitimately used at an unexpected stage.
    feeds_stage     TEXT CHECK (feeds_stage IS NULL OR feeds_stage IN ('A','Q1','Q3')),
    notes           TEXT
);

INSERT INTO ingredient_type (ingredient_code, label_zh, label_en, category, feeds_stage, notes) VALUES
  ('IIR',            '丁基橡胶',   'IIR butyl rubber',          'POLYMER',   'A',  NULL),
  ('BIIR',           '溴化丁基',   'BIIR brominated butyl',     'POLYMER',   'A',  NULL),
  ('CIIR',           '氯化丁基',   'CIIR chlorinated butyl',    'POLYMER',   'A',  NULL),
  ('CARBON_BLACK',   '炭黑',      'Carbon black',              'FILLER',    'A',  NULL),
  ('ACETYLENE_BLACK','乙炔炭黑',   'Acetylene black',           'FILLER',    'A',  NULL),
  ('ZNO',            '氧化锌',     'Zinc oxide',                'ACTIVATOR', 'A',  NULL),
  ('CASTOR_OIL',     '蓖麻油',     'Castor oil',                'OIL',       'A',  NULL),
  ('HITANOL_M40',    'M-40树脂',  'M-40 phenolic resin',       'RESIN',     'Q1',
   'Poor dispersion here forms agglomerates. Q1 has NO filtration, so they '
   'survive to Q3 (doc §2 filtration asymmetry). Prime suspect ingredient.'),
  ('STEARIC_ACID',   '硬脂酸',     'Stearic acid',              'ACID',      'Q1', NULL),
  ('RELEASE_CTS',    NULL,        'CTS release agent',         'RELEASE_AGENT', NULL,
   'Korean supplier. Materially different chemistry from LNS-GZ01 — do not '
   'treat the two as interchangeable in analysis.'),
  ('RELEASE_LNS',    NULL,        'LNS-GZ01 release agent',    'RELEASE_AGENT', NULL,
   'Qingdao Lainisi.');

CREATE INDEX idx_material_lot_ingredient ON material_lot (ingredient_code, produced_on)
    WHERE stage = 'RAW';
CREATE INDEX idx_material_lot_supplier   ON material_lot (supplier)
    WHERE stage = 'RAW';


-- =====================================================================
-- §3  SY LAB  —  final product testing
-- =====================================================================
-- SY re-tests Q3 samples that JX supplies (already works: lab_result has
-- material_lot_id + production_site_id). What was missing is testing a
-- FINISHED BLADDER. Nullable because most lab results are material tests.
ALTER TABLE lab_result
    ADD COLUMN bladder_id UUID REFERENCES bladder_instance(bladder_id) ON DELETE SET NULL,
    ADD COLUMN sample_type TEXT
        CHECK (sample_type IS NULL OR sample_type IN ('MATERIAL','FINISHED_PRODUCT'));

COMMENT ON COLUMN lab_result.bladder_id IS
  'Set only for finished-product tests at SY. Material tests use '
  'material_lot_id instead. A row should not carry both.';

-- Exactly one subject per result. A row pointing at both a lot and a
-- bladder is ambiguous — is it testing the rubber or the product?
ALTER TABLE lab_result
    ADD CONSTRAINT lab_result_one_subject
    CHECK (NOT (material_lot_id IS NOT NULL AND bladder_id IS NOT NULL));

CREATE INDEX idx_lab_result_bladder ON lab_result (bladder_id)
    WHERE bladder_id IS NOT NULL;
CREATE INDEX idx_lab_result_site    ON lab_result (production_site_id, tested_at DESC);


-- =====================================================================
-- §4  VIEWS
-- =====================================================================

-- Which finished lots contain a given ingredient batch — the supplier
-- quality question that was unanswerable before this migration.
CREATE VIEW v_ingredient_usage AS
SELECT
    raw.lot_id                AS ingredient_lot_id,
    raw.ingredient_code,
    it.label_en               AS ingredient_name,
    it.category,
    raw.supplier,
    raw.lot_code              AS ingredient_lot_code,
    raw.produced_on           AS received_on,
    d.descendant_lot_id,
    down.stage                AS descendant_stage,
    down.lot_code             AS descendant_lot_code,
    down.compound_code
FROM material_lot raw
JOIN v_lot_ancestry  d    ON d.ancestor_lot_id   = raw.lot_id
JOIN material_lot    down ON down.lot_id         = d.descendant_lot_id
LEFT JOIN ingredient_type it ON it.ingredient_code = raw.ingredient_code
WHERE raw.stage = 'RAW';

COMMENT ON VIEW v_ingredient_usage IS
  'Every downstream lot that contains a given raw ingredient batch. '
  'Answers "which Q3 lots used this resin delivery" — the blast-radius '
  'query for a supplier quality incident.';

-- Lab coverage per plant and sample type. Shows at a glance whether SY
-- lab data has started flowing, and whether finished-product testing
-- exists yet.
CREATE VIEW v_lab_coverage AS
SELECT
    COALESCE(production_site_id, 'UNKNOWN') AS site_id,
    COALESCE(sample_type, 'UNSPECIFIED')    AS sample_type,
    method_code,
    COUNT(*)                                AS result_count,
    MIN(tested_at)                          AS first_test,
    MAX(tested_at)                          AS latest_test
FROM lab_result
GROUP BY production_site_id, sample_type, method_code;


-- =====================================================================
-- §5  FIX: de-duplicate ancestry under blending
-- =====================================================================
-- Caught by test 2026-08-05. Blending creates DIAMOND genealogy:
--
--     CB-2601 --> A-2601a --\
--            \                +--> Q1-2604 --> Q3
--             -> A-2601b --/
--
-- The carbon black reaches Q3 by TWO paths, so the recursive CTE emits
-- CB-2601 twice. Any "what is in this lot" query would then show
-- duplicate ingredients, and any COUNT would overstate.
--
-- This is not hypothetical — the user confirmed blending is routine
-- ("multiple A becomes Q1, multiple Q1 become Q3"), so diamonds are the
-- normal case here, not an edge case.
--
-- Fix: keep the SHORTEST path per (descendant, ancestor) pair. Depth
-- stays meaningful (how many stages up) and each ancestor appears once.
-- The raw multi-path detail is still available by querying
-- lot_consumption directly, if anyone ever needs path counts.
DROP VIEW IF EXISTS v_ingredient_usage;
DROP VIEW IF EXISTS v_lot_ancestry;

CREATE VIEW v_lot_ancestry AS
WITH RECURSIVE walk AS (
    SELECT l.lot_id AS descendant_lot_id, l.lot_id AS ancestor_lot_id,
           l.stage AS ancestor_stage, l.lot_code AS ancestor_lot_code, 0 AS depth
    FROM material_lot l
  UNION ALL
    SELECT w.descendant_lot_id, p.lot_id, p.stage, p.lot_code, w.depth + 1
    FROM walk w
    JOIN lot_consumption c ON c.child_lot_id = w.ancestor_lot_id
    JOIN material_lot    p ON p.lot_id       = c.parent_lot_id
    WHERE w.depth < 10          -- cycle guard
)
SELECT DISTINCT ON (descendant_lot_id, ancestor_lot_id)
       descendant_lot_id, ancestor_lot_id, ancestor_stage, ancestor_lot_code, depth
FROM walk
WHERE depth > 0
ORDER BY descendant_lot_id, ancestor_lot_id, depth;

COMMENT ON VIEW v_lot_ancestry IS
  'Every upstream lot for a given lot, one row per distinct ancestor. '
  'Blending means an ancestor can be reachable by several paths; this view '
  'keeps the shortest and de-duplicates, so counts are trustworthy.';

CREATE VIEW v_ingredient_usage AS
SELECT
    raw.lot_id                AS ingredient_lot_id,
    raw.ingredient_code,
    it.label_en               AS ingredient_name,
    it.category,
    raw.supplier,
    raw.lot_code              AS ingredient_lot_code,
    raw.produced_on           AS received_on,
    d.descendant_lot_id,
    down.stage                AS descendant_stage,
    down.lot_code             AS descendant_lot_code,
    down.compound_code
FROM material_lot raw
JOIN v_lot_ancestry  d    ON d.ancestor_lot_id   = raw.lot_id
JOIN material_lot    down ON down.lot_id         = d.descendant_lot_id
LEFT JOIN ingredient_type it ON it.ingredient_code = raw.ingredient_code
WHERE raw.stage = 'RAW';

COMMENT ON VIEW v_ingredient_usage IS
  'Every downstream lot containing a given raw ingredient batch, once each. '
  'Answers "which Q3 lots used this resin delivery" — the blast-radius query '
  'for a supplier quality incident.';
