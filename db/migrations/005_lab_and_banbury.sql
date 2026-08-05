-- =====================================================================
-- ss-platform — 005: Lab Results & Banbury Process Data
-- =====================================================================
-- Both are JX-side (production) data. Neither has any client dimension:
-- a lab test and a mixer reading happen at OUR plant, before the product
-- ever reaches a customer. This is exactly why production_site and
-- client_factory are separate tables.
-- =====================================================================

CREATE TABLE lab_result (
    result_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- The existing 4-part identity from labcore, kept intact.
    source_id           TEXT NOT NULL,     -- machine/PC, e.g. MDR_PC01
    method_code         TEXT NOT NULL,     -- MDR-195-15 / SCORCH / MOONEY
    native_id           TEXT NOT NULL,     -- record ID inside the machine DB
    unique_key          TEXT GENERATED ALWAYS AS
                          (source_id || ':' || method_code || ':' || native_id) STORED,

    material_lot_id     UUID REFERENCES material_lot(lot_id) ON DELETE SET NULL,
    production_site_id  TEXT REFERENCES production_site(site_id),

    tested_at           TIMESTAMPTZ,
    -- JSONB rather than a column per metric: the GOTECH schema is still
    -- being confirmed, and adding a metric must not require a migration.
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


CREATE TABLE banbury_batch (
    batch_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    machine_id          TEXT NOT NULL,
    production_site_id  TEXT REFERENCES production_site(site_id),

    -- 08:00 boundary, same rule as 胶囊LOT and shift. Computed by the
    -- pipeline using production_day() and STORED — never re-derived ad
    -- hoc in a dashboard, where a different boundary would silently
    -- produce different answers to the same question.
    production_day      DATE NOT NULL,
    batch_of_day        INTEGER NOT NULL,
    raw_batch_counter   INTEGER,   -- 当前批次: unreliable, resets at shifts

    material_lot_id     UUID REFERENCES material_lot(lot_id) ON DELETE SET NULL,
    formula_code        TEXT,

    started_at          TIMESTAMPTZ,
    ended_at            TIMESTAMPTZ,
    cycle_time_s        NUMERIC(8,2) CHECK (cycle_time_s IS NULL OR cycle_time_s >= 0),
    set_mix_time_s      NUMERIC(8,2),
    actual_mix_time_s   NUMERIC(8,2),
    discharge_temp_c    NUMERIC(6,2),

    -- Known data anomalies as first-class booleans, not free text
    is_phantom          BOOLEAN NOT NULL DEFAULT FALSE,
    overlaps_previous   BOOLEAN NOT NULL DEFAULT FALSE,
    boundary_derived    BOOLEAN NOT NULL DEFAULT FALSE,

    source_system       TEXT NOT NULL,
    source_record_id    TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT banbury_batch_source_key UNIQUE (source_system, source_record_id),
    CONSTRAINT banbury_batch_day_key    UNIQUE (machine_id, production_day, batch_of_day)
);

CREATE INDEX idx_banbury_batch_day     ON banbury_batch (production_day, machine_id);
CREATE INDEX idx_banbury_batch_formula ON banbury_batch (formula_code, production_day);
CREATE INDEX idx_banbury_batch_lot     ON banbury_batch (material_lot_id);


-- ~5-second interval sensor readings. High volume. No UUID PK —
-- time-series tables are keyed by (series, time) for storage locality.
CREATE TABLE banbury_reading (
    reading_time        TIMESTAMPTZ NOT NULL,
    machine_id          TEXT NOT NULL,
    batch_id            UUID REFERENCES banbury_batch(batch_id) ON DELETE CASCADE,

    -- Units for the first three are UNCONFIRMED — deliberately unlabelled
    -- rather than guessed. A wrong unit label is worse than none.
    main_current        NUMERIC(10,3),   -- 主机电流
    main_speed          NUMERIC(10,3),   -- 主机转速
    ram_pressure        NUMERIC(10,3),   -- 上顶栓压力
    compound_temp_c     NUMERIC(10,3),   -- 胶料温度 (degC by inference)

    source_system       TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT banbury_reading_key PRIMARY KEY (machine_id, reading_time)
);

CREATE INDEX idx_banbury_reading_batch ON banbury_reading (batch_id, reading_time);

-- TIMESCALEDB — OPTIONAL, deferred deliberately.
-- Plain Postgres handles several million rows fine. Convert only when
-- banbury_reading gets large or queries slow noticeably:
--   CREATE EXTENSION IF NOT EXISTS timescaledb;
--   SELECT create_hypertable('banbury_reading','reading_time',
--                            migrate_data => TRUE, if_not_exists => TRUE);
-- Nothing above depends on it. It is a performance change, not a schema
-- change, which is exactly why it can wait.
