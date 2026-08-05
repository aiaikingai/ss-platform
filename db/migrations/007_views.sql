-- =====================================================================
-- ss-platform — 007: Views
-- =====================================================================
-- The questions the platform exists to answer.
-- =====================================================================


-- =====================================================================
-- §1  BLADDER LIFETIME  —  the orphaned-segment fix
-- =====================================================================
-- Sums ALL segments under one instance, so 200 + 300 reports as 500.
CREATE VIEW v_bladder_lifetime AS
SELECT
    b.bladder_id,
    b.produced_on,
    b.curing_machine_id,
    b.bladder_sequence_no,
    b.spec_code,
    b.compound_code,
    b.coating_type,
    b.q3_lot_id,
    q3.lot_code                                     AS q3_lot_code,
    q3.stack_position,
    q3.stack_sequence_no,
    -- Where it was USED (client), from its terminal event
    MAX(e.client_factory_id)                        AS client_factory_id,
    SUM(COALESCE(e.cycles_this_segment, 0))         AS total_cycles,
    COUNT(e.event_id)                               AS segment_count,
    MAX(e.occurred_on) FILTER (WHERE r.is_terminal) AS retired_on,
    MAX(e.reason_code) FILTER (WHERE r.is_terminal) AS retirement_reason,
    bool_or(r.is_terminal)                          AS is_retired,
    bool_or(e.reason_code = 'TRIAL')                AS is_trial,
    -- Hankook KPI: 400 target, 300-500 acceptable. NULL (not FALSE) for
    -- in-service units: "hasn't finished yet" is not "failed".
    CASE WHEN bool_or(r.is_terminal)
         THEN SUM(COALESCE(e.cycles_this_segment,0)) BETWEEN 300 AND 500
    END                                             AS meets_spec
FROM bladder_instance b
LEFT JOIN bladder_event e  ON e.bladder_id  = b.bladder_id
LEFT JOIN event_reason  r  ON r.reason_code = e.reason_code
LEFT JOIN material_lot  q3 ON q3.lot_id     = b.q3_lot_id
GROUP BY b.bladder_id, b.produced_on, b.curing_machine_id, b.bladder_sequence_no,
         b.spec_code, b.compound_code, b.coating_type, b.q3_lot_id,
         q3.lot_code, q3.stack_position, q3.stack_sequence_no;

COMMENT ON VIEW v_bladder_lifetime IS
  'total_cycles is a true LIFETIME only where is_retired = TRUE; otherwise it '
  'is cycles-to-date. Always filter on is_retired before computing mean '
  'lifecycle or compliance rate, and exclude is_trial units (doc §4).';


-- =====================================================================
-- §2  PRODUCTION QC SUMMARY  —  grade A derived, never stored
-- =====================================================================
-- A-grade = total - B - C. Computing it means it cannot drift out of
-- agreement with the parts. Rates are computed here at query time from
-- raw counts, never stored pre-aggregated (doc §6: averaging
-- pre-computed rates across unequal batch sizes is invalid).
CREATE VIEW v_production_qc_summary AS
SELECT
    q.qc_record_id,
    q.production_date,
    q.shift,
    q.curing_machine_id,
    q.spec_code,
    q.compound_code,
    q.bladder_sequence_no,
    m.lot_code                                  AS q3_lot_code,
    m.stack_position,
    m.stack_sequence_no,
    q.total_output_ea,
    COALESCE(SUM(d.count_ea) FILTER (WHERE d.grade = 'B'), 0)  AS grade_b_ea,
    COALESCE(SUM(d.count_ea) FILTER (WHERE d.grade = 'C'), 0)  AS grade_c_ea,
    q.total_output_ea
      - COALESCE(SUM(d.count_ea) FILTER (WHERE d.grade = 'B'), 0)
      - COALESCE(SUM(d.count_ea) FILTER (WHERE d.grade = 'C'), 0) AS grade_a_ea,
    COALESCE(SUM(d.count_ea) FILTER (WHERE dt.is_bubble), 0)   AS bubble_defect_ea
FROM production_qc_record q
LEFT JOIN material_lot     m  ON m.lot_id      = q.material_lot_id
LEFT JOIN production_defect d ON d.qc_record_id = q.qc_record_id
LEFT JOIN defect_type      dt ON dt.defect_code = d.defect_code
GROUP BY q.qc_record_id, q.production_date, q.shift, q.curing_machine_id,
         q.spec_code, q.compound_code, q.bladder_sequence_no,
         m.lot_code, m.stack_position, m.stack_sequence_no, q.total_output_ea;


-- =====================================================================
-- §3  PRODUCTION QC  <->  FIELD PERFORMANCE
-- =====================================================================
-- Per doc §3a this is "probably the single highest-value capability the
-- new system should aim for" — impossible today because the two live in
-- separate, unlinked spreadsheets.
--
-- Joined on the §3 identity triple: (production_date, curing_machine_id,
-- 胶囊LOT). Confirmed same value on both sides for Hankook JX.
-- UNVERIFIED for Korea plants — hence client_factory_id is exposed so
-- every query can and should scope by client site.
CREATE VIEW v_qc_field_performance AS
SELECT
    s.production_date,
    s.curing_machine_id,
    s.bladder_sequence_no,
    s.q3_lot_code,
    s.spec_code,
    s.shift,
    s.total_output_ea,
    s.grade_a_ea,
    s.grade_b_ea,
    s.grade_c_ea,
    s.bubble_defect_ea,
    l.bladder_id,
    l.client_factory_id,
    l.coating_type,
    l.total_cycles,
    l.retirement_reason,
    l.is_retired,
    l.meets_spec
FROM v_production_qc_summary s
JOIN v_bladder_lifetime l
  ON  l.produced_on          = s.production_date
  AND l.curing_machine_id    = s.curing_machine_id
  AND l.bladder_sequence_no  = s.bladder_sequence_no;

COMMENT ON VIEW v_qc_field_performance IS
  'Joins SY production QC to client field outcomes on the §3 identity triple. '
  'Triple semantics CONFIRMED for Hankook JX only — filter by client_factory_id '
  'before drawing conclusions, and re-verify before including Korea data.';


-- =====================================================================
-- §4  CLIENT FACTORY PERFORMANCE  —  client side only
-- =====================================================================
-- Retired, non-trial units only. Mixing in-service bladders into a mean
-- lifetime understates it — the same class of error as the
-- orphaned-segment bug, so the filter lives in the view, not in the
-- memory of whoever writes the query.
CREATE VIEW v_client_factory_performance AS
SELECT
    cf.client_factory_id,
    cl.name                                     AS client_name,
    loc.name                                    AS location_name,
    loc.country_code,
    l.compound_code,
    l.spec_code,
    l.coating_type,
    COUNT(*)                                    AS retired_units,
    ROUND(AVG(l.total_cycles), 1)               AS mean_cycles,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY l.total_cycles) AS median_cycles,
    MIN(l.total_cycles)                         AS min_cycles,
    MAX(l.total_cycles)                         AS max_cycles,
    ROUND(100.0 * COUNT(*) FILTER (WHERE l.meets_spec) / NULLIF(COUNT(*),0), 1)
                                                AS pct_meets_spec,
    ROUND(100.0 * COUNT(*) FILTER (WHERE l.retirement_reason LIKE 'CRACK%')
          / NULLIF(COUNT(*),0), 1)              AS pct_crack_failure
FROM v_bladder_lifetime l
JOIN client_factory  cf  ON cf.client_factory_id = l.client_factory_id
JOIN client_location loc ON loc.location_id      = cf.location_id
JOIN client          cl  ON cl.client_id         = loc.client_id
WHERE l.is_retired AND NOT l.is_trial
GROUP BY cf.client_factory_id, cl.name, loc.name, loc.country_code,
         l.compound_code, l.spec_code, l.coating_type;


-- =====================================================================
-- §5  LOT ANCESTRY  —  trace any lot back to its A-stage origin
-- =====================================================================
CREATE VIEW v_lot_ancestry AS
WITH RECURSIVE ancestry AS (
    SELECT l.lot_id AS descendant_lot_id, l.lot_id AS ancestor_lot_id,
           l.stage AS ancestor_stage, l.lot_code AS ancestor_lot_code, 0 AS depth
    FROM material_lot l
  UNION ALL
    SELECT a.descendant_lot_id, p.lot_id, p.stage, p.lot_code, a.depth + 1
    FROM ancestry a
    JOIN lot_consumption c ON c.child_lot_id = a.ancestor_lot_id
    JOIN material_lot    p ON p.lot_id       = c.parent_lot_id
    WHERE a.depth < 10          -- cycle guard
)
SELECT * FROM ancestry WHERE depth > 0;


-- =====================================================================
-- §6  DATA COMPLETENESS  —  your trustworthiness KPI
-- =====================================================================
-- Run weekly. Doc §5 records the legacy baselines: 胶囊LOT ~48% missing,
-- production date ~20%, Q3 lot ~34%. If the new system is not beating
-- those, it is not yet solving the problem.
CREATE VIEW v_data_completeness AS
SELECT 'bladder_instance' AS table_name, 'bladder_sequence_no' AS column_name,
       COUNT(*) AS total,
       COUNT(*) FILTER (WHERE bladder_sequence_no IS NULL) AS missing,
       ROUND(100.0 * COUNT(*) FILTER (WHERE bladder_sequence_no IS NULL)
             / NULLIF(COUNT(*),0), 1) AS pct_missing
FROM bladder_instance
UNION ALL
SELECT 'bladder_instance', 'produced_on', COUNT(*),
       COUNT(*) FILTER (WHERE produced_on IS NULL),
       ROUND(100.0 * COUNT(*) FILTER (WHERE produced_on IS NULL) / NULLIF(COUNT(*),0), 1)
FROM bladder_instance
UNION ALL
SELECT 'bladder_instance', 'q3_lot_id', COUNT(*),
       COUNT(*) FILTER (WHERE q3_lot_id IS NULL),
       ROUND(100.0 * COUNT(*) FILTER (WHERE q3_lot_id IS NULL) / NULLIF(COUNT(*),0), 1)
FROM bladder_instance
UNION ALL
SELECT 'bladder_instance', 'curing_machine_id', COUNT(*),
       COUNT(*) FILTER (WHERE curing_machine_id IS NULL),
       ROUND(100.0 * COUNT(*) FILTER (WHERE curing_machine_id IS NULL) / NULLIF(COUNT(*),0), 1)
FROM bladder_instance
UNION ALL
SELECT 'bladder_instance', 'coating_type', COUNT(*),
       COUNT(*) FILTER (WHERE coating_type IS NULL),
       ROUND(100.0 * COUNT(*) FILTER (WHERE coating_type IS NULL) / NULLIF(COUNT(*),0), 1)
FROM bladder_instance
UNION ALL
SELECT 'bladder_event', 'cycles_this_segment', COUNT(*),
       COUNT(*) FILTER (WHERE cycles_this_segment IS NULL),
       ROUND(100.0 * COUNT(*) FILTER (WHERE cycles_this_segment IS NULL) / NULLIF(COUNT(*),0), 1)
FROM bladder_event
UNION ALL
SELECT 'production_qc_record', 'material_lot_id', COUNT(*),
       COUNT(*) FILTER (WHERE material_lot_id IS NULL),
       ROUND(100.0 * COUNT(*) FILTER (WHERE material_lot_id IS NULL) / NULLIF(COUNT(*),0), 1)
FROM production_qc_record;


-- =====================================================================
-- §7  REASON MAP HEALTH  —  how much of the taxonomy is guesswork
-- =====================================================================
CREATE VIEW v_reason_map_health AS
SELECT source_system,
       COUNT(*)                                       AS mapped_terms,
       COUNT(*) FILTER (WHERE confidence = 'ASSUMED') AS unverified_terms,
       ROUND(100.0 * COUNT(*) FILTER (WHERE confidence='ASSUMED')
             / NULLIF(COUNT(*),0), 1)                 AS pct_unverified
FROM source_reason_map
GROUP BY source_system;
