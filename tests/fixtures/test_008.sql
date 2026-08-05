\set ON_ERROR_STOP on
\pset border 2

\echo ''
\echo '=== T1: ingredient batches + BLENDING (multiple A -> Q1, multiple Q1 -> Q3) ==='
-- two carbon black deliveries + one resin delivery
INSERT INTO material_lot (stage,lot_code,ingredient_code,supplier,produced_on,quantity_kg,production_site_id,source_system,source_record_id) VALUES
 ('RAW','CB-2601','CARBON_BLACK','Cabot','2026-01-02',1000,'JX','excel_ing','ING-1'),
 ('RAW','RES-2601','HITANOL_M40','Hitanol','2026-01-02',200,'JX','excel_ing','ING-2');

-- TWO A lots, both using the same carbon black delivery
INSERT INTO material_lot (stage,lot_code,compound_code,produced_on,filtered,production_site_id,source_system,source_record_id) VALUES
 ('A','A-2601a','H39','2026-01-03',TRUE,'JX','excel_cmp','A-a'),
 ('A','A-2601b','H39','2026-01-03',TRUE,'JX','excel_cmp','A-b');

-- ONE Q1 lot blended from BOTH A lots + the resin
INSERT INTO material_lot (stage,lot_code,compound_code,produced_on,filtered,production_site_id,source_system,source_record_id) VALUES
 ('Q1','Q1-2604','H39','2026-01-04',FALSE,'JX','excel_cmp','Q1-a');

-- ONE Q3 lot from that Q1
INSERT INTO material_lot (stage,lot_code,stack_position,stack_sequence_no,compound_code,produced_on,filtered,production_site_id,source_system,source_record_id) VALUES
 ('Q3','260106','C',1,'H39','2026-01-06',TRUE,'JX','excel_cmp','Q3-c1');

-- edges: CB -> both A lots ; resin -> Q1 ; both A -> Q1 (BLENDING) ; Q1 -> Q3
INSERT INTO lot_consumption (parent_lot_id,child_lot_id,source_system,source_record_id)
SELECT p.lot_id,c.lot_id,'excel_cmp',v.s FROM (VALUES
 ('CB-2601','A-2601a','x1'),('CB-2601','A-2601b','x2'),
 ('RES-2601','Q1-2604','x3'),
 ('A-2601a','Q1-2604','x4'),('A-2601b','Q1-2604','x5'),
 ('Q1-2604','260106','x6')) AS v(pl,cl,s)
JOIN material_lot p ON p.lot_code=v.pl
JOIN material_lot c ON c.lot_code=v.cl;

SELECT stage,lot_code,ingredient_code,supplier,compound_code
FROM material_lot WHERE stage='RAW' ORDER BY lot_code;

DO $$ DECLARE n INT; BEGIN
  SELECT COUNT(*) INTO n FROM lot_consumption c
  JOIN material_lot ch ON ch.lot_id=c.child_lot_id WHERE ch.lot_code='Q1-2604';
  IF n=3 THEN RAISE NOTICE 'PASS: Q1 blended from 3 parents (2 A lots + 1 resin)';
  ELSE RAISE EXCEPTION 'FAIL: % parents',n; END IF;
END $$;

\echo ''
\echo '=== T2: full ancestry of the Q3 lot — ingredient level reached ==='
SELECT a.depth,a.ancestor_stage,a.ancestor_lot_code
FROM material_lot q3 JOIN v_lot_ancestry a ON a.descendant_lot_id=q3.lot_id
WHERE q3.lot_code='260106' ORDER BY a.depth,a.ancestor_lot_code;

DO $$ DECLARE n INT; BEGIN
  SELECT COUNT(*) INTO n FROM material_lot q3
  JOIN v_lot_ancestry a ON a.descendant_lot_id=q3.lot_id
  JOIN material_lot anc ON anc.lot_id=a.ancestor_lot_id
  WHERE q3.lot_code='260106' AND anc.stage='RAW';
  IF n=2 THEN RAISE NOTICE 'PASS: Q3 traced back to 2 RAW ingredient batches';
  ELSE RAISE EXCEPTION 'FAIL: % raw ancestors',n; END IF;
END $$;

\echo ''
\echo '=== T3: BLAST RADIUS — which lots contain the bad resin delivery? ==='
SELECT ingredient_name,supplier,ingredient_lot_code,descendant_stage,descendant_lot_code
FROM v_ingredient_usage WHERE ingredient_lot_code='RES-2601'
ORDER BY descendant_stage,descendant_lot_code;

DO $$ DECLARE n INT; BEGIN
  SELECT COUNT(*) INTO n FROM v_ingredient_usage WHERE ingredient_lot_code='CB-2601';
  IF n=4 THEN RAISE NOTICE 'PASS: carbon black batch traced to 4 downstream lots (2 A, 1 Q1, 1 Q3)';
  ELSE RAISE EXCEPTION 'FAIL: % downstream',n; END IF;
END $$;

\echo ''
\echo '=== T4: SY lab — finished product test ==='
INSERT INTO bladder_instance (produced_on,curing_machine_id,bladder_sequence_no,spec_code,produced_at_site_id,source_system,source_record_id)
VALUES ('2026-01-08','M11',7,'BG36BP','SY','excel_bl','BL-SY-1');

-- JX tests the Q3 material
INSERT INTO lab_result (source_id,method_code,native_id,material_lot_id,production_site_id,sample_type,tested_at,content_hash,source_system)
SELECT 'MDR_PC01','MDR-195-15','9001',lot_id,'JX','MATERIAL','2026-01-06 10:00+08','h1','labtool'
FROM material_lot WHERE lot_code='260106';
-- SY re-tests the same Q3 material
INSERT INTO lab_result (source_id,method_code,native_id,material_lot_id,production_site_id,sample_type,tested_at,content_hash,source_system)
SELECT 'SY_GOTECH','MDR-195-15','5001',lot_id,'SY','MATERIAL','2026-01-07 09:00+08','h2','sy_lab'
FROM material_lot WHERE lot_code='260106';
-- SY tests a FINISHED BLADDER
INSERT INTO lab_result (source_id,method_code,native_id,bladder_id,production_site_id,sample_type,tested_at,content_hash,source_system)
SELECT 'SY_GOTECH','TENSILE','5002',bladder_id,'SY','FINISHED_PRODUCT','2026-01-09 11:00+08','h3','sy_lab'
FROM bladder_instance WHERE source_record_id='BL-SY-1';

SELECT site_id,sample_type,method_code,result_count FROM v_lab_coverage ORDER BY site_id,sample_type,method_code;

DO $$ BEGIN
  IF (SELECT COUNT(*) FROM lab_result WHERE bladder_id IS NOT NULL)=1
  THEN RAISE NOTICE 'PASS: finished-product lab result recorded against a bladder';
  ELSE RAISE EXCEPTION 'FAIL'; END IF;
END $$;

\echo ''
\echo '=== T5: constraints ==='
DO $$ BEGIN
  BEGIN
    INSERT INTO lab_result (source_id,method_code,native_id,material_lot_id,bladder_id,content_hash,source_system)
    SELECT 'X','M','1',(SELECT lot_id FROM material_lot WHERE lot_code='260106'),
           (SELECT bladder_id FROM bladder_instance WHERE source_record_id='BL-SY-1'),'h','x';
    RAISE EXCEPTION 'FAIL: lab_result with BOTH subjects accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: lab_result cannot target a lot AND a bladder at once';
  END;
  BEGIN
    INSERT INTO material_lot (stage,lot_code,filtered,source_system,source_record_id)
    VALUES ('RAW','BAD-1',TRUE,'x','bad1');
    RAISE EXCEPTION 'FAIL: RAW lot with filtered=TRUE accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: filtered is meaningless on a purchased ingredient, rejected';
  END;
  BEGIN
    INSERT INTO material_lot (stage,lot_code,source_system,source_record_id)
    VALUES ('Q2','BAD-2','x','bad2');
    RAISE EXCEPTION 'FAIL: invalid stage accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: stage must be RAW/A/Q1/Q3';
  END;
END $$;

\echo ''
\echo '=== T6: prior tests still pass (regression) ==='
DO $$ DECLARE t INT; BEGIN
  SELECT total_cycles INTO t FROM v_bladder_lifetime
  WHERE bladder_id=(SELECT bladder_id FROM bladder_instance WHERE source_record_id='BL-1');
  IF t=500 THEN RAISE NOTICE 'PASS: 200+300=500 still correct after migration 008';
  ELSE RAISE EXCEPTION 'FAIL: got %',t; END IF;
  IF (SELECT COUNT(*) FROM v_qc_field_performance)=1
  THEN RAISE NOTICE 'PASS: QC <-> field join still works';
  ELSE RAISE EXCEPTION 'FAIL: qc join broken'; END IF;
END $$;

\echo ''
\echo '=== ALL 008 TESTS COMPLETE ==='
