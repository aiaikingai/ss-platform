-- =====================================================================
-- ss-platform — 002: Material Lots, Genealogy, Transport
-- =====================================================================
-- Source: MANUFACTURING_SYSTEM_DEV_CONTEXT.md §2, §3  (2026-08-05)
--
-- CORRECTION APPLIED HERE (confirmed 2026-08-05):
--   An earlier draft had UNIQUE (stage, lot_code).
--   That asserts ONE Q3 batch per calendar day, because Q3胶Lot is a
--   YYMMDD date. FALSE: multiple stacks (A/B/C/D) each produce Q3
--   batches on the same date.
--
--   Confirmed rule: Q3胶Lot + 托盘号 together define a unique Q3 rubber.
--   So 托盘号 is IDENTITY-BEARING for Q3 lots, not merely descriptive
--   as doc §3b currently states. The doc should be corrected.
-- =====================================================================


-- =====================================================================
-- §1  MATERIAL LOT  —  A / Q1 / Q3 compound batches
-- =====================================================================
CREATE TABLE material_lot (
    lot_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    stage               TEXT NOT NULL CHECK (stage IN ('A','Q1','Q3')),

    -- What humans write. Q3 uses YYMMDD. TEXT, never numeric — storing
    -- it as a number is what produced '260105.0' vs '260105' in the
    -- legacy data (§5).
    lot_code            TEXT NOT NULL
                          CHECK (lot_code <> ''
                                 AND lot_code !~* '^(error|repeated|n/?a|#n/?a)$'),

    -- 托盘号, split into its two real components (§3c).
    -- Stack letter A/B/C/D, plus a running count of Q3 batches completed
    -- at that stack (A1 -> A2 -> A3). Q3 only; NULL for A/Q1 stages.
    stack_position      TEXT CHECK (stack_position IS NULL
                                    OR stack_position ~ '^[A-D]$'),
    stack_sequence_no   INTEGER CHECK (stack_sequence_no IS NULL
                                       OR stack_sequence_no > 0),

    compound_code       TEXT,          -- H39, H01, TC16, TC45, LC02
    produced_on         DATE,
    production_site_id  TEXT REFERENCES production_site(site_id),

    -- The filtration asymmetry (§2) stored as DATA, not as an IF in code.
    -- A = filtered, Q1 = NOT filtered, Q3 = filtered (过滤头).
    -- Q1-origin agglomerates survive to Q3; this makes that queryable.
    filtered            BOOLEAN,

    quantity_kg         NUMERIC(10,2) CHECK (quantity_kg IS NULL OR quantity_kg >= 0),

    -- Provenance on every ingested row. Enables re-ingest, dedupe, and
    -- running Excel + a future ERP in parallel during cutover.
    source_system       TEXT NOT NULL,
    source_record_id    TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    data_quality_flag   TEXT,          -- NULL = clean, else why suspect
    notes               TEXT,

    -- CORRECTED natural key. Includes the stack components, because
    -- (stage='Q3', lot_code='260105') is NOT unique on its own.
    -- NULLs in stack_* mean A/Q1 lots are keyed on (stage, lot_code)
    -- effectively, since Postgres treats NULLs as distinct — acceptable,
    -- as A/Q1 have no stack concept.
    CONSTRAINT material_lot_natural_key
        UNIQUE (stage, lot_code, stack_position, stack_sequence_no),

    -- Idempotency: re-running an adapter updates, never duplicates.
    CONSTRAINT material_lot_source_key UNIQUE (source_system, source_record_id),

    -- Stack components are all-or-nothing.
    CONSTRAINT material_lot_stack_complete
        CHECK ((stack_position IS NULL) = (stack_sequence_no IS NULL))
);

COMMENT ON COLUMN material_lot.stack_position IS
  '托盘号 letter A-D. IDENTITY-BEARING for Q3 lots, not descriptive: '
  'Q3胶Lot + 托盘号 together define a unique Q3 rubber (confirmed 2026-08-05).';

CREATE INDEX idx_material_lot_compound ON material_lot (compound_code, produced_on);
CREATE INDEX idx_material_lot_produced ON material_lot (produced_on);
CREATE INDEX idx_material_lot_site     ON material_lot (production_site_id);
CREATE INDEX idx_material_lot_q3       ON material_lot (lot_code)
    WHERE stage = 'Q3';


-- =====================================================================
-- §2  LOT CONSUMPTION  —  the genealogy edge table
-- =====================================================================
-- This one table turns "which Q1 batch caused this defect?" from an
-- investigation into a query. Many-to-many: a Q3 lot may consume several
-- Q1 lots; a Q1 lot may feed several Q3 lots.
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
-- §3  LOT SHIPMENT  —  the JX -> SY transport leg
-- =====================================================================
-- §2 is explicit that this is "a real production stage, not just
-- logistics overhead" and should be first-class if tracking in-transit
-- time or temperature exposure. Modeled now even though the data is not
-- collected yet: adding the table later is easy, but retrofitting the
-- FK onto rows that already exist is not.
CREATE TABLE lot_shipment (
    shipment_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lot_id              UUID NOT NULL REFERENCES material_lot(lot_id) ON DELETE RESTRICT,

    from_site_id        TEXT NOT NULL REFERENCES production_site(site_id),
    to_site_id          TEXT NOT NULL REFERENCES production_site(site_id),

    departed_at         TIMESTAMPTZ,
    arrived_at          TIMESTAMPTZ,
    ambient_temp_c      NUMERIC(5,1),
    vehicle_id          TEXT,
    notes               TEXT,

    source_system       TEXT NOT NULL,
    source_record_id    TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT lot_shipment_source_key UNIQUE (source_system, source_record_id),
    CONSTRAINT lot_shipment_sites      CHECK (from_site_id <> to_site_id),
    CONSTRAINT lot_shipment_timing     CHECK (arrived_at IS NULL
                                              OR departed_at IS NULL
                                              OR arrived_at >= departed_at)
);

CREATE INDEX idx_lot_shipment_lot ON lot_shipment (lot_id);


-- =====================================================================
-- §4  PROCESS CONTEXT  —  variables with known defect correlation (§8)
-- =====================================================================
CREATE TABLE process_context (
    context_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    material_lot_id     UUID REFERENCES material_lot(lot_id) ON DELETE CASCADE,
    stage               TEXT CHECK (stage IS NULL OR stage IN ('A','Q1','Q3')),
    effective_on        DATE NOT NULL,

    release_agent       TEXT,   -- CTS vs LNS-GZ01 — materially different chemistry
    water_softener_ok   BOOLEAN,
    vulc_temp_c         NUMERIC(5,1) CHECK (vulc_temp_c IS NULL
                                            OR vulc_temp_c BETWEEN 100 AND 250),

    source_system       TEXT NOT NULL,
    source_record_id    TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT process_context_source_key UNIQUE (source_system, source_record_id)
);

CREATE INDEX idx_process_context_lot ON process_context (material_lot_id);
