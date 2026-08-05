-- =====================================================================
-- ss-platform — 006: Ingest Audit & Quarantine
-- =====================================================================
-- Debuggability is a stated project principle. Every adapter run is
-- recorded, and every rejected row is KEPT.
-- =====================================================================

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

-- Rejected rows are never silently dropped. This is how you FIND OUT
-- that 34% of Q3 lot numbers are blank, instead of quietly analysing
-- 66% of the data while believing it is 100%.
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
