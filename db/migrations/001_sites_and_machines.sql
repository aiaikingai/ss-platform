-- =====================================================================
-- ss-platform — 001: Sites, Machines, Client Hierarchy
-- =====================================================================
-- Source: MANUFACTURING_SYSTEM_DEV_CONTEXT.md §2, §2a  (2026-08-05)
--
-- THE CENTRAL DISTINCTION IN THIS FILE:
--   production_site = OUR plants (JX mixing, SY molding/curing)
--   client_*        = CUSTOMER sites where bladders are USED and FAIL
--
-- These were one table in an earlier draft. That was wrong: a bladder is
-- MADE at SY and USED at a Hankook factory. One column cannot hold both,
-- and any "performance by factory" query over a merged table is
-- meaningless because it averages two unrelated things.
--
-- Note the trap: this company has a JX plant (rubber mixing) AND Hankook
-- has a JX plant (tire manufacturing). Different companies, same city.
-- Never join on the string 'JX'.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()


-- =====================================================================
-- §1  PRODUCTION SITES  —  our own plants
-- =====================================================================
-- TEXT primary key, not UUID. Deliberate exception to the UUID rule:
-- there will be ~2-5 of these ever, the codes are stable and
-- human-readable, and they appear in nearly every query. A UUID here
-- would force a join to answer "how did JX do last month".
CREATE TABLE production_site (
    site_id         TEXT PRIMARY KEY CHECK (site_id ~ '^[A-Z0-9_-]{2,20}$'),
    name            TEXT NOT NULL,
    legal_name      TEXT,
    function        TEXT NOT NULL CHECK (function IN ('MIXING','MOLDING','BOTH')),
    country_code    CHAR(2) NOT NULL,
    timezone        TEXT NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    notes           TEXT
);

COMMENT ON TABLE production_site IS
  'OUR plants. Not customer sites — see client_factory for those.';

INSERT INTO production_site (site_id, name, legal_name, function, country_code, timezone, notes) VALUES
  ('JX', '嘉兴新盛橡塑模具有限公司', '嘉兴新盛橡塑模具有限公司', 'MIXING', 'CN', 'Asia/Shanghai',
   'Rubber mixing: A/Q1/Q3 compound stages through release-agent application. Q3 output ships to SY.'),
  ('SY', '昶安橡胶科技', '昶安橡胶科技 (CA Rubber-Tech)', 'MOLDING', 'CN', 'Asia/Shanghai',
   'Injection molding + vulcanization on 19 curing machines, post-cure coating, ships to clients. '
   'CA Rubber-Tech IS this plant — not a separate supplier (doc §7 correction 2026-08-04).');


-- =====================================================================
-- §2  CURING MACHINES  —  the 19 vulcanization machines at SY
-- =====================================================================
-- First-class entity because 硫化机号 is (a) part of bladder identity
-- per §3 and (b) independently correlates with crack-rate outcomes.
CREATE TABLE curing_machine (
    machine_id      TEXT PRIMARY KEY,
    site_id         TEXT NOT NULL REFERENCES production_site(site_id),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    notes           TEXT
);

-- Seeded as M01..M19. Rename to the real shop-floor labels when known —
-- one UPDATE, cascades nowhere, because everything references machine_id.
INSERT INTO curing_machine (machine_id, site_id, notes)
SELECT 'M' || LPAD(n::TEXT, 2, '0'), 'SY', 'Seeded placeholder — rename to real machine label'
FROM generate_series(1, 19) AS n;

INSERT INTO curing_machine (machine_id, site_id, notes) VALUES
  ('UNKNOWN', 'SY', 'Historical records with no machine recorded. Data-quality bucket, not a real machine.');


-- =====================================================================
-- §3  CLIENT HIERARCHY  —  three levels, per §2a
-- =====================================================================
--   Client (Hankook, Sailun)
--     └── Location (Hankook JX, Hankook Cambodia)
--           └── Factory number (Factory 1, 2, 3)
--
-- Why three levels now rather than a flat field: the legacy 工厂别 field
-- stores only the bottom level. That works ONLY because nearly all
-- current volume is Hankook JX. The moment Sailun is onboarded,
-- Sailun's "Factory 1" collides with Hankook's "Factory 1" and every
-- historical comparison silently corrupts. Retrofitting a hierarchy
-- after data exists is far more expensive than building it now.

CREATE TABLE client (
    client_id       TEXT PRIMARY KEY CHECK (client_id ~ '^[A-Z0-9_-]{2,20}$'),
    name            TEXT NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE client_location (
    location_id     TEXT PRIMARY KEY CHECK (location_id ~ '^[A-Z0-9_-]{2,30}$'),
    client_id       TEXT NOT NULL REFERENCES client(client_id) ON DELETE RESTRICT,
    name            TEXT NOT NULL,
    country_code    CHAR(2) NOT NULL,
    -- Event dates are stored as the LOCAL calendar date at the site.
    -- This column exists to convert when comparing across countries.
    -- Never store event dates in UTC: a mold change on 2026-03-12 in
    -- Korea is 2026-03-12, whatever UTC says.
    timezone        TEXT NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE client_factory (
    client_factory_id  TEXT PRIMARY KEY CHECK (client_factory_id ~ '^[A-Z0-9_-]{2,40}$'),
    location_id        TEXT NOT NULL REFERENCES client_location(location_id) ON DELETE RESTRICT,
    -- The raw value as written in the legacy 工厂别 column ('1','2','3').
    -- Kept so historical import can map without guessing.
    legacy_factory_no  TEXT,
    name               TEXT NOT NULL,
    is_active          BOOLEAN NOT NULL DEFAULT TRUE
);

COMMENT ON COLUMN client_factory.legacy_factory_no IS
  '工厂别 as recorded in legacy data. Meaningful ONLY within a location — '
  'Hankook JX Factory 1 is unrelated to Sailun Factory 1.';

INSERT INTO client (client_id, name) VALUES
  ('HANKOOK', 'Hankook Tire'),
  ('UNKNOWN', 'Unattributed / legacy records');

INSERT INTO client_location (location_id, client_id, name, country_code, timezone) VALUES
  ('HANKOOK-JX', 'HANKOOK', 'Hankook Jiaxing plant', 'CN', 'Asia/Shanghai'),
  ('UNKNOWN',    'UNKNOWN', 'Unknown location',      'CN', 'Asia/Shanghai');

INSERT INTO client_factory (client_factory_id, location_id, legacy_factory_no, name) VALUES
  ('HANKOOK-JX-F1', 'HANKOOK-JX', '1', 'Hankook Jiaxing Factory 1'),
  ('HANKOOK-JX-F2', 'HANKOOK-JX', '2', 'Hankook Jiaxing Factory 2'),
  ('HANKOOK-JX-F3', 'HANKOOK-JX', '3', 'Hankook Jiaxing Factory 3'),
  ('UNKNOWN',       'UNKNOWN',    NULL, 'Unknown factory');

CREATE INDEX idx_client_location_client  ON client_location (client_id);
CREATE INDEX idx_client_factory_location ON client_factory (location_id);


-- =====================================================================
-- §4  SHARED DOMAIN CONSTANT  —  the 08:00 production-day boundary
-- =====================================================================
-- Three separate things use an 08:00 day boundary:
--   1. 胶囊LOT counting window   (§3)
--   2. Shift A/B split           (§3a: A = 08:00-20:00, B = 20:00-08:00)
--   3. Banbury production day
--
-- Implementing that three times is three chances to get it wrong.
-- One function here; the Python side gets ONE matching helper in
-- labcore/. Never a third copy.
CREATE FUNCTION production_day(ts TIMESTAMPTZ, tz TEXT DEFAULT 'Asia/Shanghai')
RETURNS DATE
LANGUAGE sql IMMUTABLE AS $$
    SELECT (ts AT TIME ZONE tz - INTERVAL '8 hours')::DATE;
$$;

COMMENT ON FUNCTION production_day IS
  'Production day runs 08:00 -> 08:00 next day. A reading at 2026-03-12 07:30 '
  'belongs to production day 2026-03-11.';

CREATE FUNCTION production_shift(ts TIMESTAMPTZ, tz TEXT DEFAULT 'Asia/Shanghai')
RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN EXTRACT(HOUR FROM ts AT TIME ZONE tz) >= 8
         AND EXTRACT(HOUR FROM ts AT TIME ZONE tz) < 20
        THEN 'A' ELSE 'B' END;
$$;

COMMENT ON FUNCTION production_shift IS
  'A = 早班 08:00-20:00, B = 晚班 20:00-08:00. Shift tracks which inspection '
  'team was on duty; it is descriptive, never part of any identity key.';
