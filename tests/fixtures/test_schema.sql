\set ON_ERROR_STOP on
\pset border 2

-- ====== T1: Q3 lot uniqueness — SAME DATE, DIFFERENT STACK must be allowed
\echo ''
\echo '=== T1: two Q3 batches same date, different stacks ==='
INSERT INTO material_lot (stage,lot_code,stack_position,stack_sequence_no,compound_code,produced_on,filtered,production_site_id,source_system,source_record_id) VALUES
 ('A' ,'260101',NULL,NULL,'H39','2026-01-01',TRUE ,'JX','excel','A-260101'),
 ('Q1','260103',NULL,NULL,'H39','2026-01-03',FALSE,'JX','excel','Q1-260103'),
 ('Q3','260105','A',1,'H39','2026-01-05',TRUE,'JX','excel','Q3-260105-A1'),
 ('Q3','260105','B',1,'H39','2026-01-05',TRUE,'JX','excel','Q3-260105-B1');
SELECT lot_code, stack_position, stack_sequence_no FROM material_lot WHERE stage='Q3' ORDER BY stack_position;
DO $$ BEGIN
  IF (SELECT COUNT(*) FROM material_lot WHERE stage='Q3' AND lot_code='260105')=2
  THEN RAISE NOTICE 'PASS: same YYMMDD on different stacks accepted';
  ELSE RAISE EXCEPTION 'FAIL'; END IF;
  -- but a true duplicate must be rejected
  BEGIN
    INSERT INTO material_lot (stage,lot_code,stack_position,stack_sequence_no,source_system,source_record_id)
    VALUES ('Q3','260105','A',1,'excel','dup');
    RAISE EXCEPTION 'FAIL: exact duplicate accepted';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PASS: exact duplicate (Q3,260105,A,1) rejected';
  END;
END $$;

-- genealogy edges
INSERT INTO lot_consumption (parent_lot_id,child_lot_id,source_system,source_record_id)
SELECT p.lot_id,c.lot_id,'excel','e1' FROM material_lot p, material_lot c
WHERE p.lot_code='260101' AND c.lot_code='260103';
INSERT INTO lot_consumption (parent_lot_id,child_lot_id,source_system,source_record_id)
SELECT p.lot_id,c.lot_id,'excel','e2' FROM material_lot p, material_lot c
WHERE p.lot_code='260103' AND c.lot_code='260105' AND c.stack_position='A';

-- ====== T2: orphaned segment 200+300 = 500
\echo ''
\echo '=== T2: bladder lifetime, multi-segment ==='
INSERT INTO bladder_instance (produced_on,curing_machine_id,bladder_sequence_no,q3_lot_id,spec_code,compound_code,coating_type,produced_at_site_id,source_system,source_record_id)
SELECT '2026-01-06','M07',42,lot_id,'BG36BP','H39','WATER_BASED','SY','excel_bladder','BL-1'
FROM material_lot WHERE lot_code='260105' AND stack_position='A';

INSERT INTO bladder_event (bladder_id,reason_code,occurred_on,cycles_this_segment,client_factory_id,client_press_id,source_system,source_record_id)
SELECT b.bladder_id,v.r,v.d,v.c,'HANKOOK-JX-F1','HK-PRESS-88','excel_ev',v.s
FROM bladder_instance b,(VALUES
  ('DEPLOY'     ,DATE '2026-01-06',NULL::int,'EV-1'),
  ('MOLD_CHANGE',DATE '2026-02-10',200      ,'EV-2'),
  ('AGING'      ,DATE '2026-04-22',300      ,'EV-3')) AS v(r,d,c,s)
WHERE b.source_record_id='BL-1';

SELECT spec_code,coating_type,client_factory_id,total_cycles,segment_count,retirement_reason,meets_spec
FROM v_bladder_lifetime;
DO $$ DECLARE t INT; BEGIN
  SELECT total_cycles INTO t FROM v_bladder_lifetime;
  IF t=500 THEN RAISE NOTICE 'PASS: 200+300 = 500 (orphaned-segment bug fixed)';
  ELSE RAISE EXCEPTION 'FAIL: got %',t; END IF;
END $$;

-- ====== T3: production QC + long-format defects
\echo ''
\echo '=== T3: production QC, grade A derived ==='
INSERT INTO production_qc_record (material_lot_id,curing_machine_id,spec_code,compound_code,production_date,shift,bladder_sequence_no,total_output_ea,source_system,source_record_id)
SELECT lot_id,'M07','BG36BP','H39','2026-01-06','A',42,100,'excel_qc','QC-1'
FROM material_lot WHERE lot_code='260105' AND stack_position='A';

INSERT INTO production_defect (qc_record_id,grade,defect_code,count_ea)
SELECT qc_record_id,g,d,c FROM production_qc_record,(VALUES
  ('B','BUBBLE_INTERNAL',5),('B','BUBBLE_EXTERNAL',3),
  ('C','BUBBLE_INTERNAL',2),('C','FM',1)) AS v(g,d,c)
WHERE source_record_id='QC-1';

SELECT total_output_ea,grade_a_ea,grade_b_ea,grade_c_ea,bubble_defect_ea
FROM v_production_qc_summary;
DO $$ DECLARE a INT; bub INT; BEGIN
  SELECT grade_a_ea,bubble_defect_ea INTO a,bub FROM v_production_qc_summary;
  IF a=89 THEN RAISE NOTICE 'PASS: grade A derived = 100-8-3 = 89';
  ELSE RAISE EXCEPTION 'FAIL: grade A = %',a; END IF;
  IF bub=10 THEN RAISE NOTICE 'PASS: bubble defects = 10 (across B and C)';
  ELSE RAISE EXCEPTION 'FAIL: bubbles = %',bub; END IF;
END $$;

-- ====== T4: THE KEY CAPABILITY — QC joined to field performance
\echo ''
\echo '=== T4: production QC <-> field outcome join ==='
SELECT production_date,curing_machine_id,bladder_sequence_no,q3_lot_code,
       total_output_ea,grade_b_ea,grade_c_ea,total_cycles,retirement_reason,client_factory_id
FROM v_qc_field_performance;
DO $$ DECLARE n INT; BEGIN
  SELECT COUNT(*) INTO n FROM v_qc_field_performance;
  IF n=1 THEN RAISE NOTICE 'PASS: QC record joined to field outcome on the identity triple';
  ELSE RAISE EXCEPTION 'FAIL: % rows',n; END IF;
END $$;

-- ====== T5: legacy rows with NULL 胶囊LOT must still load
\echo ''
\echo '=== T5: incomplete legacy records (48% missing seq no) ==='
INSERT INTO bladder_instance (produced_on,curing_machine_id,bladder_sequence_no,spec_code,source_system,source_record_id,data_quality_flag) VALUES
 ('2026-01-07','M09',NULL,'BE26AN','excel_bladder','BL-2','no 胶囊LOT in source'),
 ('2026-01-07','M09',NULL,'BE26AN','excel_bladder','BL-3','no 胶囊LOT in source'),
 (NULL,NULL,NULL,'BD0150','excel_bladder','BL-4','date+machine+seq all missing');
DO $$ BEGIN
  RAISE NOTICE 'PASS: 3 incomplete legacy rows loaded (NULLs coexist under unique constraint)';
END $$;
-- but a complete duplicate is still blocked
DO $$ BEGIN
  INSERT INTO bladder_instance (produced_on,curing_machine_id,bladder_sequence_no,source_system,source_record_id)
  VALUES ('2026-01-06','M07',42,'excel_bladder','BL-DUP');
  RAISE EXCEPTION 'FAIL: duplicate triple accepted';
EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'PASS: duplicate (2026-01-06,M07,42) rejected';
END $$;

-- ====== T6: production site vs client site are NOT confusable
\echo ''
\echo '=== T6: production/client separation ==='
DO $$ BEGIN
  BEGIN
    INSERT INTO bladder_event (bladder_id,reason_code,occurred_on,client_factory_id,source_system,source_record_id)
    SELECT bladder_id,'AGING','2026-05-01','SY','ev','BAD-1' FROM bladder_instance WHERE source_record_id='BL-2';
    RAISE EXCEPTION 'FAIL: production site SY accepted as a client factory';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'PASS: cannot use production site as client factory';
  END;
  BEGIN
    INSERT INTO bladder_instance (produced_at_site_id,source_system,source_record_id)
    VALUES ('HANKOOK-JX-F1','ev','BAD-2');
    RAISE EXCEPTION 'FAIL: client factory accepted as production site';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'PASS: cannot use client factory as production site';
  END;
END $$;

-- ====== T7: 08:00 production-day boundary
\echo ''
\echo '=== T7: 08:00 day boundary + shift ==='
SELECT ts::text AS timestamp_shanghai,
       production_day(ts) AS prod_day, production_shift(ts) AS shift
FROM (VALUES
 (TIMESTAMPTZ '2026-03-12 07:30+08'),
 (TIMESTAMPTZ '2026-03-12 08:30+08'),
 (TIMESTAMPTZ '2026-03-12 19:30+08'),
 (TIMESTAMPTZ '2026-03-12 20:30+08')) AS v(ts);
DO $$ BEGIN
  IF production_day(TIMESTAMPTZ '2026-03-12 07:30+08')=DATE '2026-03-11'
 AND production_day(TIMESTAMPTZ '2026-03-12 08:30+08')=DATE '2026-03-12'
 AND production_shift(TIMESTAMPTZ '2026-03-12 19:30+08')='A'
 AND production_shift(TIMESTAMPTZ '2026-03-12 20:30+08')='B'
  THEN RAISE NOTICE 'PASS: 07:30 -> previous day; shift A/B split at 08:00/20:00';
  ELSE RAISE EXCEPTION 'FAIL'; END IF;
END $$;

-- ====== T8: sentinel rejection + coating constraint
\echo ''
\echo '=== T8: garbage rejected ==='
DO $$ BEGIN
  BEGIN INSERT INTO material_lot (stage,lot_code,source_system,source_record_id) VALUES ('Q3','ERROR','x','b1');
    RAISE EXCEPTION 'FAIL: ERROR accepted';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: lot_code "ERROR" rejected'; END;
  BEGIN INSERT INTO material_lot (stage,lot_code,source_system,source_record_id) VALUES ('Q3','repeated','x','b2');
    RAISE EXCEPTION 'FAIL: repeated accepted';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: lot_code "repeated" rejected'; END;
  BEGIN INSERT INTO bladder_instance (coating_type,source_system,source_record_id) VALUES ('spray','x','b3');
    RAISE EXCEPTION 'FAIL: bad coating accepted';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: invalid coating_type rejected'; END;
  BEGIN INSERT INTO material_lot (stage,lot_code,stack_position,source_system,source_record_id) VALUES ('Q3','260201','A','x','b4');
    RAISE EXCEPTION 'FAIL: half a 托盘号 accepted';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: stack_position without sequence_no rejected'; END;
END $$;

-- ====== T9: ancestry + completeness
\echo ''
\echo '=== T9: genealogy trace ==='
SELECT a.depth,a.ancestor_stage,a.ancestor_lot_code
FROM bladder_instance b JOIN v_lot_ancestry a ON a.descendant_lot_id=b.q3_lot_id
WHERE b.source_record_id='BL-1' ORDER BY a.depth;
DO $$ DECLARE n INT; BEGIN
  SELECT COUNT(*) INTO n FROM bladder_instance b JOIN v_lot_ancestry a ON a.descendant_lot_id=b.q3_lot_id WHERE b.source_record_id='BL-1';
  IF n=2 THEN RAISE NOTICE 'PASS: bladder traced back through Q1 to A stage';
  ELSE RAISE EXCEPTION 'FAIL: % ancestors',n; END IF;
END $$;

\echo ''
\echo '=== T10: data completeness view ==='
SELECT table_name,column_name,total,missing,pct_missing FROM v_data_completeness
WHERE table_name='bladder_instance' ORDER BY column_name;

\echo ''
\echo '=== ALL TESTS COMPLETE ==='
