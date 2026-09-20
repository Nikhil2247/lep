-- ===========================================================================
-- LEP Cycle 2 import  -  PRODUCTION
--
-- Adds Cycle 2: 1 cycle row, 27 projects, 146 tasks.
-- Target: MariaDB 10.3+ (uses only INSERT ... SELECT ... FROM DUAL, user
-- variables and scalar subqueries - no 10.4+ syntax, no stored routines,
-- no temporary tables).
--
-- SAFETY PROPERTIES
--   * The only executable statements are INSERT, SELECT, SET, START
--     TRANSACTION, PREPARE/EXECUTE of COMMIT or ROLLBACK, and DEALLOCATE.
--     There is no UPDATE, DELETE, DROP, ALTER, TRUNCATE or REPLACE.
--     There is no unconditional COMMIT.
--   * Nothing can reach a Cycle 1 row: every INSERT targets @cycle2, and
--     Cycle 1 is only ever read by COUNT/MD5 verification queries.
--   * Idempotent: every INSERT is guarded by NOT EXISTS on its natural key
--     (cycles.name / grade+subject+cycle / project+task_number), so a
--     second run inserts nothing.
--   * COMMIT is conditional. See HOW THE COMMIT WORKS below.
--
-- HOW COMMIT / ROLLBACK WORKS
--   Baseline catalog values are captured into user variables BEFORE any
--   write. After the inserts, STEP 4 re-measures Cycle 1 identity and the
--   full Cycle 2 workbook contents (grade, subject, title, duration,
--   objective, file key, per-project task counts, and MD5 of all Cycle 2
--   project/task text).
--   SET @import_ok = 1 only when every catalog check passes.
--   The script then PREPARE/EXECUTE either COMMIT or ROLLBACK.
--   There is no later unconditional COMMIT, so a GUI or --force client
--   that continues after an error still cannot persist a failed import.
--   NEVER pass --force. Prefer the official mysql CLI.
--
-- EXECUTION (non-interactive batch client ONLY - do not use a GUI)
--   Supported client: the official mysql/mariadb CLI reading this file
--   from stdin or via SOURCE with --abort-source-on-error.
--
--   Commit safety does not depend on the client aborting. STEP 4
--   PREPARE/EXECUTE COMMIT or ROLLBACK. GUI clients that continue after
--   an error still cannot hit an unconditional COMMIT because there is
--   none. Still prefer the official mysql CLI; do not use --force.
--
--   Exact command:
--     mysql --default-character-set=utf8mb4 --abort-source-on-error \
--       -u <user> -p <db> < lep_cycle2_import_FINAL_PRODUCTION_CANDIDATE.sql
--     NEVER pass --force. NEVER paste this file into a GUI query window.
--
--   1. Take a FRESH dump immediately before running - do not rely on any
--      older backup:
--        mysqldump --single-transaction --routines --triggers \
--          --default-character-set=utf8mb4 <db> > lep_pre_cycle2_<ts>.sql
--      Restore that dump into a scratch database to prove it is readable.
--   2. Run the command above.
--   3. Read the output. STEP 4 prints every check with a PASS/FAIL column.
--      Success ends with commit_gate_must_be_null = NULL, the line
--      "Cycle 2 import committed.", and exit status 0.
--      Failure ends with status "Cycle 2 import rolled back; no catalog
--      changes kept." and action_taken = ROLLBACK.
--
-- ROLLBACK
--   Before COMMIT: nothing to undo. An aborted run leaves no trace.
--   After COMMIT, to take Cycle 2 out of the form without losing data, set
--   cycles.is_active to 0 for the row whose name is Cycle 2 (single-row,
--   unique index on name; Cycle 1 unaffected). That statement is
--   deliberately NOT in this file.
--   Full restore is the last resort and uses the fresh dump from step 1.
-- ===========================================================================

-- The file is UTF-8. This line is required: without it the client may
-- connect as latin1 and double-encode apostrophes and dashes.
SET NAMES utf8mb4;

-- MariaDB 10.3 default group_concat_max_len is 1024 bytes. Cycle 1
-- objectives + 165 task texts exceed that; an unexpanded GROUP_CONCAT
-- would silently truncate and make the MD5 fingerprints unreliable.
SET SESSION group_concat_max_len = 16777216;

-- --- STEP 1: pre-flight (read-only). IDs on the left must match the names. -
SELECT id, name FROM grades ORDER BY id;
SELECT id, name FROM subjects ORDER BY id;
SELECT id, name, is_active FROM cycles ORDER BY id;   -- expect only Cycle 1
SELECT COUNT(*) AS cycle1_projects FROM projects WHERE cycle_id = 1;   -- expect 27
SELECT COUNT(*) AS cycle1_tasks FROM project_tasks t
  JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1;         -- expect 165

-- Any Cycle 2 project already present? On a clean import this returns 0 rows.
-- If it returns rows, stop and reconcile: rows that differ from this file are
-- skipped by the guards below, which will make STEP 4 fail and abort the run.
SELECT p.id, g.name AS grade, COALESCE(s.name,'School Leaders') AS subject,
       p.project_title, p.project_file
FROM projects p JOIN cycles c ON c.id = p.cycle_id
JOIN grades g ON g.id = p.grade_id LEFT JOIN subjects s ON s.id = p.subject_id
WHERE c.name = 'Cycle 2' ORDER BY p.id;

-- --- STEP 2: capture the baseline (read-only, before any write) -----------
SET @b_cycles       = (SELECT COUNT(*) FROM cycles);
SET @b_grades       = (SELECT COUNT(*) FROM grades);
SET @b_subjects     = (SELECT COUNT(*) FROM subjects);
SET @b_gsmap        = (SELECT COUNT(*) FROM grade_subject_map);
SET @b_c2_cycles    = (SELECT COUNT(*) FROM cycles WHERE name = 'Cycle 2');
SET @b_c2_projects  = (SELECT COUNT(*) FROM projects p JOIN cycles c ON c.id = p.cycle_id
                       WHERE c.name = 'Cycle 2');
SET @b_c2_tasks     = (SELECT COUNT(*) FROM project_tasks t JOIN projects p ON p.id = t.project_id
                       JOIN cycles c ON c.id = p.cycle_id WHERE c.name = 'Cycle 2');
SET @b_c1_active    = (SELECT is_active FROM cycles WHERE id = 1);
SET @b_c2_active    = (SELECT IFNULL((SELECT is_active FROM cycles WHERE name = 'Cycle 2'), 0));
-- A clean import starts from 0/0/0. An exact re-run starts from 1/27/146 and
-- inserts nothing. Anything else is a partial or conflicting Cycle 2 and the
-- gate in STEP 4 will refuse to commit.
SET @b_c1_projects  = (SELECT COUNT(*) FROM projects WHERE cycle_id = 1);
SET @b_c1_tasks     = (SELECT COUNT(*) FROM project_tasks t
                       JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1);
SET @b_submissions  = (SELECT COUNT(*) FROM teacher_submissions);
SET @b_responses    = (SELECT COUNT(*) FROM task_responses);
SET @b_evidence     = (SELECT COUNT(*) FROM submission_evidence);
SET @b_c1_md5       = (SELECT MD5(GROUP_CONCAT(CONCAT_WS('|', id, grade_id,
                         IFNULL(subject_id,'N'), project_title, IFNULL(duration,''),
                         IFNULL(objective,''), IFNULL(project_file,''), is_active)
                         ORDER BY id SEPARATOR '#')) FROM projects WHERE cycle_id = 1);
SET @b_c1_task_md5  = (SELECT MD5(GROUP_CONCAT(CONCAT_WS('|', t.id, t.project_id,
                         t.task_number, t.task_type, t.task_description)
                         ORDER BY t.id SEPARATOR '#')) FROM project_tasks t
                       JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1);
-- Extra Cycle 1 identity checks that do not depend on GROUP_CONCAT.
SET @b_c1_id_min    = (SELECT MIN(id) FROM projects WHERE cycle_id = 1);
SET @b_c1_id_max    = (SELECT MAX(id) FROM projects WHERE cycle_id = 1);
SET @b_c1_id_sum    = (SELECT SUM(id) FROM projects WHERE cycle_id = 1);
SET @b_c1_t_id_min  = (SELECT MIN(t.id) FROM project_tasks t JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1);
SET @b_c1_t_id_max  = (SELECT MAX(t.id) FROM project_tasks t JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1);
SET @b_c1_t_id_sum  = (SELECT SUM(t.id) FROM project_tasks t JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1);

SELECT @b_c1_projects AS c1_projects, @b_c1_tasks AS c1_tasks,
       @b_submissions AS submissions, @b_c1_md5 AS c1_fingerprint,
       @b_c1_id_sum AS c1_id_sum, @b_c1_t_id_sum AS c1_task_id_sum;

-- --- STEP 3: import -------------------------------------------------------
START TRANSACTION;

INSERT INTO cycles (name, sort_order, is_active)
SELECT 'Cycle 2', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM cycles WHERE name = 'Cycle 2');

SET @cycle2 = (SELECT id FROM cycles WHERE name = 'Cycle 2');

-- 1/27  Pre-Primary (A-B)  /  Pre-Primary Teacher (Grade A & B)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 1, 1, @cycle2, 'Observe Your Child: Using Observation to Improve Classroom Instruction', '1 month', 'Teachers will strengthen classroom instruction by observing children during daily activities, identifying their learning needs, and making small instructional changes to better support their development.', 'uploads/projects/Cycle2/Pre-Primary Teacher (Grade A & B)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 1 AND p.subject_id = 1 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 1 AND subject_id = 1 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Engage with the resource on observation-based assessment in ECCE.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Observe 2–3 children during different classroom activities.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Record key observations using a simple format.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Try one small instructional change based on the observations.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Share a reflection or example from the classroom.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 2/27  Grade 1  /  Literacy Teacher (Grade 1, 2 & 3)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 2, 3, @cycle2, 'Building writing skills', '1 month', 'To introduce the topic of games through pictures, and build vocabulary for the names of common games played at home and school.', 'uploads/projects/Cycle2/Literacy Teacher (Grade 1, 2 & 3)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 2 AND p.subject_id = 3 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 2 AND subject_id = 3 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Guide students and introduce the topic of games through pictures, and build vocabulary for the names of common games played at home and school.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide students to associate written words with the pictures they represent.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide students to display and share the words and pictures learned, and for each child to name their favourite game aloud.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide students to recite a poem aloud with proper rhythm, stress, and intonation, identify the sequence of events or ideas in the poem.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Assess the students'' work and presentation based on the assessment criteria.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 3/27  Grade 2  /  Literacy Teacher (Grade 1, 2 & 3)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 3, 3, @cycle2, 'Building writing skills', '1 month', 'To introduce the topic of games through pictures, and build vocabulary for the names of common games played at home and school.', 'uploads/projects/Cycle2/Literacy Teacher (Grade 1, 2 & 3)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 3 AND p.subject_id = 3 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 3 AND subject_id = 3 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Guide students and introduce the topic of games through pictures, and build vocabulary for the names of common games played at home and school.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide students to associate written words with the pictures they represent.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide students to display and share the words and pictures learned, and for each child to name their favourite game aloud.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide students to recite a poem aloud with proper rhythm, stress, and intonation, identify the sequence of events or ideas in the poem.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Assess the students'' work and presentation based on the assessment criteria.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 4/27  Grade 3  /  Literacy Teacher (Grade 1, 2 & 3)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 4, 3, @cycle2, 'Building writing skills', '1 month', 'To introduce the topic of games through pictures, and build vocabulary for the names of common games played at home and school.', 'uploads/projects/Cycle2/Literacy Teacher (Grade 1, 2 & 3)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 4 AND p.subject_id = 3 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 4 AND subject_id = 3 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Guide students and introduce the topic of games through pictures, and build vocabulary for the names of common games played at home and school.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide students to associate written words with the pictures they represent.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide students to display and share the words and pictures learned, and for each child to name their favourite game aloud.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide students to recite a poem aloud with proper rhythm, stress, and intonation, identify the sequence of events or ideas in the poem.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Assess the students'' work and presentation based on the assessment criteria.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 5/27  Grade 1  /  Numeracy Teacher (Grade 1, 2 & 3)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 2, 4, @cycle2, 'Number system,Measurement &Geometry', '1 month', 'Teachers will strengthen classroom instruction by observing children during daily activities, identifying their learning needs, and making small instructional changes to support , includes helping children arrange numbers up to 99 in ascending and descending order, recognise days, months, and the sequence of seasons, and explore shapes through paper folding, cutting, and describing their sides, corners, and diagonals', 'uploads/projects/Cycle2/Numeracy (Grade 1, 2 & 3)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 2 AND p.subject_id = 4 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 2 AND subject_id = 4 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Support students to read and write numerals and their matching number names up to 99.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Help students to arrange real objects from bigger to smaller and smaller to bigger, building an intuitive sense of order before applying it to numbers.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide students to recognise, identify, and sequence the 7 days of the week, and to distinguish school days from vacation days.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide students to get a feel for the sequence of seasons, and the events and activities that happen in each.To identify and count the diagonals of a shape, adding one more way to describe and compare shapes.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Organize & bring Grades 1, 2, and 3 together to share what each has built ordered numbers, a calendar of days/months/seasons, and described 2D shapes with the whole school.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 6/27  Grade 2  /  Numeracy Teacher (Grade 1, 2 & 3)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 3, 4, @cycle2, 'Number system,Measurement &Geometry', '1 month', 'Teachers will strengthen classroom instruction by observing children during daily activities, identifying their learning needs, and making small instructional changes to support , includes helping children arrange numbers up to 99 in ascending and descending order, recognise days, months, and the sequence of seasons, and explore shapes through paper folding, cutting, and describing their sides, corners, and diagonals', 'uploads/projects/Cycle2/Numeracy (Grade 1, 2 & 3)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 3 AND p.subject_id = 4 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 3 AND subject_id = 4 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Support students to read and write numerals and their matching number names up to 99.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Help students to arrange real objects from bigger to smaller and smaller to bigger, building an intuitive sense of order before applying it to numbers.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide students to recognise, identify, and sequence the 7 days of the week, and to distinguish school days from vacation days.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide students to get a feel for the sequence of seasons, and the events and activities that happen in each.To identify and count the diagonals of a shape, adding one more way to describe and compare shapes.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Organize & bring Grades 1, 2, and 3 together to share what each has built ordered numbers, a calendar of days/months/seasons, and described 2D shapes with the whole school.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 7/27  Grade 3  /  Numeracy Teacher (Grade 1, 2 & 3)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 4, 4, @cycle2, 'Number system,Measurement &Geometry', '1 month', 'Teachers will strengthen classroom instruction by observing children during daily activities, identifying their learning needs, and making small instructional changes to support , includes helping children arrange numbers up to 99 in ascending and descending order, recognise days, months, and the sequence of seasons, and explore shapes through paper folding, cutting, and describing their sides, corners, and diagonals', 'uploads/projects/Cycle2/Numeracy (Grade 1, 2 & 3)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 4 AND p.subject_id = 4 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 4 AND subject_id = 4 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Support students to read and write numerals and their matching number names up to 99.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Help students to arrange real objects from bigger to smaller and smaller to bigger, building an intuitive sense of order before applying it to numbers.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide students to recognise, identify, and sequence the 7 days of the week, and to distinguish school days from vacation days.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide students to get a feel for the sequence of seasons, and the events and activities that happen in each.To identify and count the diagonals of a shape, adding one more way to describe and compare shapes.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Organize & bring Grades 1, 2, and 3 together to share what each has built ordered numbers, a calendar of days/months/seasons, and described 2D shapes with the whole school.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 8/27  Grade 4  /  English (Grade 4)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 5, 8, @cycle2, 'A trip to Dzukuo', '1 month', 'Teachers will help children respond verbally in English to questions and discussions, follow simple instructions and announcements made in English in class, and write short paragraphs with growing confidence and accuracy.', 'uploads/projects/Cycle2/English (Grade 4)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 5 AND p.subject_id = 8 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 5 AND subject_id = 8 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce the project, read the opening of ‘A Trip to Dzükou’ with comprehension, and build vocabulary from the glossary.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Ensure students read the climb and the waterfall scene (Pg. 42) with comprehension, and use inference, prediction, and visualisation to picture the journey.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Help students to read the remaining details about life in Dzükou Valley, recall key facts, and check comprehension using a true/false exercise.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Help students to write a short, grammatically correct paragraph about a real or imagined journey, using peer feedback to improve it.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Organize and support students to share the finished paragraph aloud in a class storytelling circle, respond to questions from classmates, and reflect on the project.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 9/27  Grade 4  /  Math (Grade 4)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 5, 7, @cycle2, 'Planning a day trip', '1 month', 'Teachers will help children convert rupees to paise and vice versa, apply number operations to find totals, change, multiple costs, and unit cost, and estimate totals and total cost with reasonable accuracy.', 'uploads/projects/Cycle2/Math (Grade 4)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 5 AND p.subject_id = 7 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 5 AND subject_id = 7 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce the project and leading question, choose a day trip destination, and learn to convert rupees to paise and back.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide students to list all expenses for the day trip and use addition and subtraction of money to find the cost per person.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Support students to estimate the group’s total cost roughly before calculating it exactly using multiplication and division of money, and to check whether the plan fits the ₹500 budget.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide to improve the day trip plan using peer feedback, and to organise all costs into a simple rate chart and bill.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Organize and ensure students present the finished day trip plan and bill to a real audience, and to reflect on the project', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 10/27  Grade 5  /  English (Grade 5)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 6, 10, @cycle2, 'Laugh out Loud weel', '1 month', 'Teachers will help children recite English poems with expression and share them with peers and family members, write and speak their personal views and responses clearly, and use meaningful, grammatically correct sentences to describe and narrate incidents.', 'uploads/projects/Cycle2/English (Grade 5)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 6 AND p.subject_id = 10 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 6 AND subject_id = 10 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce the project through a fun warm-up, read ‘Daddy Fell Into the Pond’ aloud with rhythm and expression, and build comprehension and new vocabulary from the poem.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide students to explore how playful sounds and rhyme create humour, and to teach students to identify a poem’s rhyme scheme.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Support students to explore how playful sounds and rhyme create humour, and to teach students to identify a poem’s rhyme scheme.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Facilitate and ensure students revise the group’s performance using peer feedback, rehearse it aloud, and prepare simple props.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Organize and ensure students perform the group’s original comedy act for the class, and to reflect on what was learned about humour, language, and teamwork.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 11/27  Grade 5  /  Math (Grade 5)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 6, 9, @cycle2, 'Paper Furniture', '1 month', 'Teachers will help children identify solid shapes such as cubes, cuboids, cylinders, and cones and describe their features, identify the fractional part of a collection, compare fractions, and use decimal fractions in the context of units of length and money.', 'uploads/projects/Cycle2/Math (Grade 5)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 6 AND p.subject_id = 9 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 6 AND subject_id = 9 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce the project and leading question, recognise that furniture is built from solid shapes joined together, identify a real need in the school, and find the fractional part of a collection of project materials.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide students to explore the features of cubes and cuboids by making paper models, compare and find equivalent fractions while dividing paper into equal parts, and begin designing furniture using these shapes', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Support students to explore the features of cylinders and cones by making paper models, use decimal fractions to measure furniture dimensions in centimetres, and complete the furniture design.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Facilitate and ensure students to improve the furniture design using peer feedback, calculate the cost of materials using decimal fractions in money, and begin building the paper model.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Organise and ensure students assemble the finished paper furniture model, present it to the class explaining the shapes and measurements used, and reflect on the project.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 12/27  Grade 6  /  Math (Grade 6)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 7, 11, @cycle2, 'Shelter for Animals', '1 month', 'Learners move from splitting a shared roti or plot of land by eye to confidently marking, comparing, adding and subtracting fractions, culminating in a locally-grounded animal-shelter design presented to their own Village Council.', 'uploads/projects/Cycle2/Math (Grade 6)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 7 AND p.subject_id = 11 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 7 AND subject_id = 11 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce the project through animals roaming without shelter in the village, then guide learners to divide a shelter plot into fractional areas and mark fractions on a number line. Form groups and share the Day-5 presentation criteria for the shelter design.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide learners to record each shelter area as a fraction, compare fractions with the same or different denominators using > and <, and order their areas from biggest to smallest. Have groups add their like fractions to check that their plot''s areas total the whole (400/400).', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Exchange shelter plots between groups for quick peer feedback on whether every animal''s needs are met and the fraction calculations are correct. Guide learners to add unlike fractions by first converting to a common denominator, then calculate the daily food needed for their own animals.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide learners to convert mixed numbers to improper fractions and subtract like fractions to compare how long different shelter jobs take. Have groups begin building their shelter model using free, locally available materials, dividing tasks among their group roles.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Each group presents its shelter model as if to the Village Council, explaining why the shelter is needed and how much food and work time it requires. Learners discuss what it would take to make their shelter real and what they learned during the project.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 13/27  Grade 7  /  Math (Grade 7)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 8, 13, @cycle2, 'Village Football Integer League', '1 month', 'Learners move from following someone else''s game rules to writing trustworthy integer rules of their own, discovering the sign rules for multiplication and division, and building a complete football scoring game that another group can play from their Rule Book alone.', 'uploads/projects/Cycle2/Math (Grade 7)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 8 AND p.subject_id = 13 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 8 AND subject_id = 13 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce integers through the Terhuchu board game and football events, then guide learners to agree on the Game Kit''s product criteria as a class. Divide learners into groups to choose a game name, list rough football events, and note ''need to know'' questions.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide learners to add and subtract integers using a number line and a token (zero-pair) model, discovering that subtracting an integer is the same as adding its additive inverse. Have groups build a three-column event table and a four-column Score Sheet, allowing the running total to legitimately fall below zero.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide learners to multiply and divide integers using a token model and pattern recognition, connecting the sign rules to Brahmagupta''s ancient rule of fortune and debt. Have groups add one multiplication rule and one division rule to their Rule Book, each with a worked example labelled in red pen.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Have each group test another group''s game using only its Rule Book, then give and receive written peer feedback on clarity and correctness. Groups apply two chosen revisions and check that a multi-operation expression from their Rule Book matches the distributive property.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Each group hosts a live match using their own event table, announcing the running total and the winner''s score using integer operations. Learners individually reflect on where a negative number changed their game''s result and where a running total might legitimately go below zero', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 14/27  Grade 8  /  Math (Grade 8)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 9, 15, @cycle2, 'Designing our Village structure', '1 month', 'Learners move from admiring fractal patterns and structures to designing one of their own — building a measured fractal decoration, folding an accurate net into a working 3D model, and drawing the front, top, side and isometric views a real builder would need.', 'uploads/projects/Cycle2/Math (Grade 8)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 9 AND p.subject_id = 15 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 9 AND subject_id = 15 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce fractal patterns already visible in nature and Naga craft, then guide learners to form groups, choose a village structure, and agree on the Final Product Criteria. Have each group name a fractal-like pattern from their own village life and note where it could decorate their structure.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide learners to construct Steps 0-2 of a chosen fractal (Sierpinski Carpet, Sierpinski Gasket, or Koch Snowflake) to measurement, using the appropriate formula. Have groups fill their number-pattern table up to Step 3 and decide which step to use as their decoration.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Introduce face, edge, and vertex using a cuboid, then guide learners to fix a scale, draw a labelled to-scale net for each solid their structure needs, and cut and score it. Have groups fold every crease, build their model, and attach their Day-2 decoration, checking for gaps.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide learners to draw the front, top, and side views of their model, then set up isometric axes and draw their model edge by edge on the grid. Have groups assemble their Village Design Board and take part in a silent gallery walk for peer feedback.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Each group presents its structure, fractal decoration, net and model, and technical drawings to a real audience, ending with a geometry-backed building suggestion. Learners individually reflect on whether someone could build their structure from their drawings alone.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 15/27  Grade 6  /  Science (Grade 6)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 7, 12, @cycle2, 'Solar water purifier', '1 month', 'Learners move from noticing that wet clothes dry faster in strong sun toward understanding evaporation and condensation as a real water cycle, and toward designing a working solar water purifier that copies this cycle to clean dirty water using only sunlight and free, everyday materials.', 'uploads/projects/Cycle2/Science (Grade 6)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 7 AND p.subject_id = 12 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 7 AND subject_id = 12 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce the project through a village story about a girl who walks far for water and falls ill from drinking it, then guide learners to test whether sunlight evaporates dirt along with water using an overnight soil-and-water cup test. Form groups and share the leading question and Final Product Criteria for their solar water purifier.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide learners to conclude that only water evaporates while dirt stays behind, then design a labelled solar water purifier showing evaporation, condensation, and separate collection. Have groups swap designs with another group for quick feedback before finalising their plan.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide learners to build their purifier using free materials, dividing tasks by role, then fill it with a measured amount of dirty water. Place the purifier in strong sunlight to begin evaporating, with a reminder to wash hands and never taste or drink the collected water.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide learners to compare how much clean water each purifier collected and discuss what needs to happen for more water to be collected. Have groups apply at least one evidence-based improvement — sealing joints, using black paper, or widening the water surface — and retest in sunlight.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Each group presents its purifier to a real audience, explaining how evaporation and condensation clean the water and what changed between their first and final design. Learners individually reflect on what they discovered about water changing state and whether their purifier could really help a family get clean water.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 16/27  Grade 7  /  Science (Grade 7)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 8, 14, @cycle2, 'Who is the fastest?', '1 month', 'Learners move from knowing a race has a winner to building a handmade timing device, discovering what makes a pendulum''s swing dependable, and using their own measured data to calculate speed and distinguish uniform from non-uniform motion.', 'uploads/projects/Cycle2/Science (Grade 7)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 8 AND p.subject_id = 14 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 8 AND subject_id = 14 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce the project through how people once told time without clocks, then guide learners to build a working sand-clock time device in groups. Form groups and test how consistently their sand clock measures 30 seconds against a class clock.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide learners to build a simple pendulum, measure its time period across three tries, and discover that the time period depends on length and not the mass of the bob. Introduce the second as the SI unit of time and have each group calibrate their pendulum as close to one second as possible.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide learners onto a marked 20-metre track to time each member using their pendulum ''second counter'' and calculate speed as distance divided by time. Have groups begin planning their own race event — its name, written rules, and scoring — for the Sports Meet.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide learners to record distance covered in equal time intervals for two runners, concluding whether their motion is uniform or non-uniform. Have groups exchange their time device and event plan for peer feedback, then prepare their Speed Record Card.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Each group hosts its own race event using only its handmade time device, announcing the speed of the top three finishers in m/s. Learners individually reflect on what they learned from building and trusting a device of their own.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 17/27  Grade 8  /  Science (Grade 8)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 9, 16, @cycle2, 'Optics Fun Mela', '1 month', 'Learners move from noticing everyday tricks of light to explaining them — classifying concave and convex mirrors, proving the laws of reflection, and distinguishing converging from diverging lenses — before performing their own optics ''magic tricks'' and revealing the science behind each.', 'uploads/projects/Cycle2/Science (Grade 8)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 9 AND p.subject_id = 16 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 9 AND subject_id = 16 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce the project through a familiar steel spoon, then guide learners to predict and test how their face looks on its concave (inner) and convex (outer) sides. Form groups and start an ''Optics Fun Mela ideas'' page with the magic spoon as their first trick idea.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide learners to shine a torch beam onto a plane mirror, measure the angle of incidence and angle of reflection with a protractor, and confirm the first law of reflection. Demonstrate the second law using a ''same-plane check'' and add ''the bouncing beam'' to their Mela ideas page.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide learners to test parallel beams on a plane mirror and the spoon''s concave and convex sides to discover that concave mirrors converge light and convex mirrors diverge it. Outdoors, safely demonstrate a concave mirror focusing sunlight, connecting both effects to real village uses like solar cookers and road-safety mirrors.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide learners to use a water drop as a convex (converging) lens to make letters look bigger, then compare it with a concave (diverging) spectacle lens. Have each group choose its Mela tricks and receive peer feedback on clarity and correctness from another group.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Each group performs its chosen mirror and lens ''magic tricks'' for a real audience, then reveals the science behind each and names real village objects that use them. Learners individually reflect on what surprised them about mirrors and lenses this week.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 18/27  School Leaders  /  School Leaders (no subject)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 10, NULL, @cycle2, 'Building Teacher Collaboration & Practice Culture', '1 month', 'To create a consistent structure for teacher collaboration, enabling sharing, reflection, and improvement of classroom practices.', 'uploads/projects/Cycle2/School Leader Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 10 AND p.subject_id IS NULL AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 10 AND subject_id IS NULL AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Schedule a bi-weekly teacher sharing space (30–45 mins).', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Create a simple structure:What did I try? What worked? What didn’t?', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Identify one common teaching focus (e.g., reading strategy, questioning)', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Encourage teachers to share their micro-improvement practices.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Document 2–3 good practices emerging from discussions.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Rotate facilitation among teachers to build ownership.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 7, 'Task', 'Integrate discussions into existing staff meetings (no extra burden).', 7, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 7);

-- 19/27  Pre-Primary (A-B)  /  Arts Teacher (A & B)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 1, 2, @cycle2, 'Developing Fine and Gross Motor Skills Using Different Art Materials', '1 month', 'To build creativity and confidence while developing gross and fine motor skills, hand–eye coordination, and control over different art materials through movement-based and large-scale art activitie', 'uploads/projects/Cycle2/Arts Teacher (A & B)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 1 AND p.subject_id = 2 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 1 AND subject_id = 2 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Conduct Activity 1: Body Movements and Scribbles Students explore and learn through body movements.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Activity 2: Large-Scale Artwork Students paint using everyday objects to create different marks and designs.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Observe & Track Student Progress', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ gross motor skills', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);

-- 20/27  Grade 1  /  Arts Teacher (Grade 1-5)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 2, 5, @cycle2, 'Expressing Emotions Using Visual Art', '1 month', 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.', 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 2 AND p.subject_id = 5 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 2 AND subject_id = 5 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Conduct Activity 1: Origami house and Family portrait Students make an origami house and draw a family portrait.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Activity 2: Emotion Monster Puppet Students create Emotion Monster puppet using colours and shapes to communicate different emotions.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Observe & Track Student Progress', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ emotional awareness.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);

-- 21/27  Grade 2  /  Arts Teacher (Grade 1-5)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 3, 5, @cycle2, 'Expressing Emotions Using Visual Art', '1 month', 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.', 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 3 AND p.subject_id = 5 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 3 AND subject_id = 5 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Conduct Activity 1: Origami house and Family portrait Students make an origami house and draw a family portrait.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Activity 2: Emotion Monster Puppet Students create Emotion Monster puppet using colours and shapes to communicate different emotions.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Observe & Track Student Progress', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ emotional awareness.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);

-- 22/27  Grade 3  /  Arts Teacher (Grade 1-5)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 4, 5, @cycle2, 'Expressing Emotions Using Visual Art', '1 month', 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.', 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 4 AND p.subject_id = 5 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 4 AND subject_id = 5 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Conduct Activity 1: Origami house and Family portrait Students make an origami house and draw a family portrait.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Activity 2: Emotion Monster Puppet Students create Emotion Monster puppet using colours and shapes to communicate different emotions.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Observe & Track Student Progress', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ emotional awareness.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);

-- 23/27  Grade 4  /  Arts Teacher (Grade 1-5)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 5, 5, @cycle2, 'Expressing Emotions Using Visual Art', '1 month', 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.', 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 5 AND p.subject_id = 5 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 5 AND subject_id = 5 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Conduct Activity 1: Origami house and Family portrait Students make an origami house and draw a family portrait.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Activity 2: Emotion Monster Puppet Students create Emotion Monster puppet using colours and shapes to communicate different emotions.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Observe & Track Student Progress', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ emotional awareness.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);

-- 24/27  Grade 5  /  Arts Teacher (Grade 1-5)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 6, 5, @cycle2, 'Expressing Emotions Using Visual Art', '1 month', 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.', 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 6 AND p.subject_id = 5 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 6 AND subject_id = 5 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Conduct Activity 1: Origami house and Family portrait Students make an origami house and draw a family portrait.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Activity 2: Emotion Monster Puppet Students create Emotion Monster puppet using colours and shapes to communicate different emotions.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Observe & Track Student Progress', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ emotional awareness.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);

-- 25/27  Grade 6  /  Arts Teacher (Grade 6-8)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 7, 6, @cycle2, 'Building Relationships Through Shared Artmaking', '1 month', 'These activities promote communication and collaboration by engaging students in creating mosaic and line-and-shape artworks together, building teamwork and creative expression.', 'uploads/projects/Cycle2/Arts Teacher (Grade 6-8)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 7 AND p.subject_id = 6 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 7 AND subject_id = 6 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Conduct Activity 1: Mosaic Art Draw an object and fill it by pasting pieces of paper to create a mosaic art.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Activity 2: Lines and Shapes Art Create unique drawings using lines and shapes.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Observe & Track Student Progress', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ collaboration skills.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);

-- 26/27  Grade 7  /  Arts Teacher (Grade 6-8)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 8, 6, @cycle2, 'Building Relationships Through Shared Artmaking', '1 month', 'These activities promote communication and collaboration by engaging students in creating mosaic and line-and-shape artworks together, building teamwork and creative expression.', 'uploads/projects/Cycle2/Arts Teacher (Grade 6-8)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 8 AND p.subject_id = 6 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 8 AND subject_id = 6 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Conduct Activity 1: Mosaic Art Draw an object and fill it by pasting pieces of paper to create a mosaic art.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Activity 2: Lines and Shapes Art Create unique drawings using lines and shapes.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Observe & Track Student Progress', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ collaboration skills.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);

-- 27/27  Grade 8  /  Arts Teacher (Grade 6-8)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 9, 6, @cycle2, 'Building Relationships Through Shared Artmaking', '1 month', 'These activities promote communication and collaboration by engaging students in creating mosaic and line-and-shape artworks together, building teamwork and creative expression.', 'uploads/projects/Cycle2/Arts Teacher (Grade 6-8)Cycle2.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 9 AND p.subject_id = 6 AND p.cycle_id = @cycle2);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 9 AND subject_id = 6 AND cycle_id = @cycle2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Conduct Activity 1: Mosaic Art Draw an object and fill it by pasting pieces of paper to create a mosaic art.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Activity 2: Lines and Shapes Art Create unique drawings using lines and shapes.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Observe & Track Student Progress', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ collaboration skills.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);

-- --- STEP 4: verify contents, then COMMIT or ROLLBACK in-session ----------
SET @a_c2_projects  = (SELECT COUNT(*) FROM projects WHERE cycle_id = @cycle2);
SET @a_c2_tasks     = (SELECT COUNT(*) FROM project_tasks t
                       JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = @cycle2);
SET @a_c2_files     = (SELECT COUNT(*) FROM projects WHERE cycle_id = @cycle2
                       AND project_file LIKE BINARY 'uploads/projects/Cycle2/%');
SET @a_c2_notasks   = (SELECT COUNT(*) FROM projects p WHERE p.cycle_id = @cycle2
                       AND (SELECT COUNT(*) FROM project_tasks t
                            WHERE t.project_id = p.id) = 0);
SET @a_c2_cycles    = (SELECT COUNT(*) FROM cycles WHERE name = 'Cycle 2');
SET @a_c2_active    = (SELECT is_active FROM cycles WHERE name = 'Cycle 2');
SET @a_c1_active    = (SELECT is_active FROM cycles WHERE id = 1);
SET @a_cycles       = (SELECT COUNT(*) FROM cycles);
SET @a_grades       = (SELECT COUNT(*) FROM grades);
SET @a_subjects     = (SELECT COUNT(*) FROM subjects);
SET @a_gsmap        = (SELECT COUNT(*) FROM grade_subject_map);
SET @a_c1_projects  = (SELECT COUNT(*) FROM projects WHERE cycle_id = 1);
SET @a_c1_tasks     = (SELECT COUNT(*) FROM project_tasks t
                       JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1);
SET @a_c1_md5       = (SELECT MD5(GROUP_CONCAT(CONCAT_WS('|', id, grade_id,
                         IFNULL(subject_id,'N'), project_title, IFNULL(duration,''),
                         IFNULL(objective,''), IFNULL(project_file,''), is_active)
                         ORDER BY id SEPARATOR '#')) FROM projects WHERE cycle_id = 1);
SET @a_c1_task_md5  = (SELECT MD5(GROUP_CONCAT(CONCAT_WS('|', t.id, t.project_id,
                         t.task_number, t.task_type, t.task_description)
                         ORDER BY t.id SEPARATOR '#')) FROM project_tasks t
                       JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1);
SET @a_c1_id_min    = (SELECT MIN(id) FROM projects WHERE cycle_id = 1);
SET @a_c1_id_max    = (SELECT MAX(id) FROM projects WHERE cycle_id = 1);
SET @a_c1_id_sum    = (SELECT SUM(id) FROM projects WHERE cycle_id = 1);
SET @a_c1_t_id_min  = (SELECT MIN(t.id) FROM project_tasks t JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1);
SET @a_c1_t_id_max  = (SELECT MAX(t.id) FROM project_tasks t JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1);
SET @a_c1_t_id_sum  = (SELECT SUM(t.id) FROM project_tasks t JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1);

-- Content of Cycle 2 after inserts (includes any pre-existing Cycle 2 rows
-- that NOT EXISTS refused to replace). Must match the workbook-derived set.
SET @a_c2_exact = (SELECT COUNT(*) FROM projects p WHERE p.cycle_id = @cycle2 AND (
    (p.grade_id = 1 AND p.subject_id = 1 AND p.project_title = 'Observe Your Child: Using Observation to Improve Classroom Instruction' AND p.duration = '1 month' AND p.objective = 'Teachers will strengthen classroom instruction by observing children during daily activities, identifying their learning needs, and making small instructional changes to better support their development.' AND p.project_file = 'uploads/projects/Cycle2/Pre-Primary Teacher (Grade A & B)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 2 AND p.subject_id = 3 AND p.project_title = 'Building writing skills' AND p.duration = '1 month' AND p.objective = 'To introduce the topic of games through pictures, and build vocabulary for the names of common games played at home and school.' AND p.project_file = 'uploads/projects/Cycle2/Literacy Teacher (Grade 1, 2 & 3)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 3 AND p.subject_id = 3 AND p.project_title = 'Building writing skills' AND p.duration = '1 month' AND p.objective = 'To introduce the topic of games through pictures, and build vocabulary for the names of common games played at home and school.' AND p.project_file = 'uploads/projects/Cycle2/Literacy Teacher (Grade 1, 2 & 3)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 4 AND p.subject_id = 3 AND p.project_title = 'Building writing skills' AND p.duration = '1 month' AND p.objective = 'To introduce the topic of games through pictures, and build vocabulary for the names of common games played at home and school.' AND p.project_file = 'uploads/projects/Cycle2/Literacy Teacher (Grade 1, 2 & 3)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 2 AND p.subject_id = 4 AND p.project_title = 'Number system,Measurement &Geometry' AND p.duration = '1 month' AND p.objective = 'Teachers will strengthen classroom instruction by observing children during daily activities, identifying their learning needs, and making small instructional changes to support , includes helping children arrange numbers up to 99 in ascending and descending order, recognise days, months, and the sequence of seasons, and explore shapes through paper folding, cutting, and describing their sides, corners, and diagonals' AND p.project_file = 'uploads/projects/Cycle2/Numeracy (Grade 1, 2 & 3)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 3 AND p.subject_id = 4 AND p.project_title = 'Number system,Measurement &Geometry' AND p.duration = '1 month' AND p.objective = 'Teachers will strengthen classroom instruction by observing children during daily activities, identifying their learning needs, and making small instructional changes to support , includes helping children arrange numbers up to 99 in ascending and descending order, recognise days, months, and the sequence of seasons, and explore shapes through paper folding, cutting, and describing their sides, corners, and diagonals' AND p.project_file = 'uploads/projects/Cycle2/Numeracy (Grade 1, 2 & 3)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 4 AND p.subject_id = 4 AND p.project_title = 'Number system,Measurement &Geometry' AND p.duration = '1 month' AND p.objective = 'Teachers will strengthen classroom instruction by observing children during daily activities, identifying their learning needs, and making small instructional changes to support , includes helping children arrange numbers up to 99 in ascending and descending order, recognise days, months, and the sequence of seasons, and explore shapes through paper folding, cutting, and describing their sides, corners, and diagonals' AND p.project_file = 'uploads/projects/Cycle2/Numeracy (Grade 1, 2 & 3)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 5 AND p.subject_id = 8 AND p.project_title = 'A trip to Dzukuo' AND p.duration = '1 month' AND p.objective = 'Teachers will help children respond verbally in English to questions and discussions, follow simple instructions and announcements made in English in class, and write short paragraphs with growing confidence and accuracy.' AND p.project_file = 'uploads/projects/Cycle2/English (Grade 4)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 5 AND p.subject_id = 7 AND p.project_title = 'Planning a day trip' AND p.duration = '1 month' AND p.objective = 'Teachers will help children convert rupees to paise and vice versa, apply number operations to find totals, change, multiple costs, and unit cost, and estimate totals and total cost with reasonable accuracy.' AND p.project_file = 'uploads/projects/Cycle2/Math (Grade 4)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 6 AND p.subject_id = 10 AND p.project_title = 'Laugh out Loud weel' AND p.duration = '1 month' AND p.objective = 'Teachers will help children recite English poems with expression and share them with peers and family members, write and speak their personal views and responses clearly, and use meaningful, grammatically correct sentences to describe and narrate incidents.' AND p.project_file = 'uploads/projects/Cycle2/English (Grade 5)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 6 AND p.subject_id = 9 AND p.project_title = 'Paper Furniture' AND p.duration = '1 month' AND p.objective = 'Teachers will help children identify solid shapes such as cubes, cuboids, cylinders, and cones and describe their features, identify the fractional part of a collection, compare fractions, and use decimal fractions in the context of units of length and money.' AND p.project_file = 'uploads/projects/Cycle2/Math (Grade 5)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 7 AND p.subject_id = 11 AND p.project_title = 'Shelter for Animals' AND p.duration = '1 month' AND p.objective = 'Learners move from splitting a shared roti or plot of land by eye to confidently marking, comparing, adding and subtracting fractions, culminating in a locally-grounded animal-shelter design presented to their own Village Council.' AND p.project_file = 'uploads/projects/Cycle2/Math (Grade 6)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 8 AND p.subject_id = 13 AND p.project_title = 'Village Football Integer League' AND p.duration = '1 month' AND p.objective = 'Learners move from following someone else''s game rules to writing trustworthy integer rules of their own, discovering the sign rules for multiplication and division, and building a complete football scoring game that another group can play from their Rule Book alone.' AND p.project_file = 'uploads/projects/Cycle2/Math (Grade 7)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 9 AND p.subject_id = 15 AND p.project_title = 'Designing our Village structure' AND p.duration = '1 month' AND p.objective = 'Learners move from admiring fractal patterns and structures to designing one of their own — building a measured fractal decoration, folding an accurate net into a working 3D model, and drawing the front, top, side and isometric views a real builder would need.' AND p.project_file = 'uploads/projects/Cycle2/Math (Grade 8)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 7 AND p.subject_id = 12 AND p.project_title = 'Solar water purifier' AND p.duration = '1 month' AND p.objective = 'Learners move from noticing that wet clothes dry faster in strong sun toward understanding evaporation and condensation as a real water cycle, and toward designing a working solar water purifier that copies this cycle to clean dirty water using only sunlight and free, everyday materials.' AND p.project_file = 'uploads/projects/Cycle2/Science (Grade 6)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 8 AND p.subject_id = 14 AND p.project_title = 'Who is the fastest?' AND p.duration = '1 month' AND p.objective = 'Learners move from knowing a race has a winner to building a handmade timing device, discovering what makes a pendulum''s swing dependable, and using their own measured data to calculate speed and distinguish uniform from non-uniform motion.' AND p.project_file = 'uploads/projects/Cycle2/Science (Grade 7)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 9 AND p.subject_id = 16 AND p.project_title = 'Optics Fun Mela' AND p.duration = '1 month' AND p.objective = 'Learners move from noticing everyday tricks of light to explaining them — classifying concave and convex mirrors, proving the laws of reflection, and distinguishing converging from diverging lenses — before performing their own optics ''magic tricks'' and revealing the science behind each.' AND p.project_file = 'uploads/projects/Cycle2/Science (Grade 8)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 10 AND p.subject_id IS NULL AND p.project_title = 'Building Teacher Collaboration & Practice Culture' AND p.duration = '1 month' AND p.objective = 'To create a consistent structure for teacher collaboration, enabling sharing, reflection, and improvement of classroom practices.' AND p.project_file = 'uploads/projects/Cycle2/School Leader Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 1 AND p.subject_id = 2 AND p.project_title = 'Developing Fine and Gross Motor Skills Using Different Art Materials' AND p.duration = '1 month' AND p.objective = 'To build creativity and confidence while developing gross and fine motor skills, hand–eye coordination, and control over different art materials through movement-based and large-scale art activitie' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (A & B)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 2 AND p.subject_id = 5 AND p.project_title = 'Expressing Emotions Using Visual Art' AND p.duration = '1 month' AND p.objective = 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 3 AND p.subject_id = 5 AND p.project_title = 'Expressing Emotions Using Visual Art' AND p.duration = '1 month' AND p.objective = 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 4 AND p.subject_id = 5 AND p.project_title = 'Expressing Emotions Using Visual Art' AND p.duration = '1 month' AND p.objective = 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 5 AND p.subject_id = 5 AND p.project_title = 'Expressing Emotions Using Visual Art' AND p.duration = '1 month' AND p.objective = 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 6 AND p.subject_id = 5 AND p.project_title = 'Expressing Emotions Using Visual Art' AND p.duration = '1 month' AND p.objective = 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 7 AND p.subject_id = 6 AND p.project_title = 'Building Relationships Through Shared Artmaking' AND p.duration = '1 month' AND p.objective = 'These activities promote communication and collaboration by engaging students in creating mosaic and line-and-shape artworks together, building teamwork and creative expression.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 6-8)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 8 AND p.subject_id = 6 AND p.project_title = 'Building Relationships Through Shared Artmaking' AND p.duration = '1 month' AND p.objective = 'These activities promote communication and collaboration by engaging students in creating mosaic and line-and-shape artworks together, building teamwork and creative expression.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 6-8)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 9 AND p.subject_id = 6 AND p.project_title = 'Building Relationships Through Shared Artmaking' AND p.duration = '1 month' AND p.objective = 'These activities promote communication and collaboration by engaging students in creating mosaic and line-and-shape artworks together, building teamwork and creative expression.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 6-8)Cycle2.pdf' AND p.is_active = 1)
));
SET @a_c2_unexpected = (SELECT COUNT(*) FROM projects p WHERE p.cycle_id = @cycle2 AND NOT (
    (p.grade_id = 1 AND p.subject_id = 1 AND p.project_title = 'Observe Your Child: Using Observation to Improve Classroom Instruction' AND p.duration = '1 month' AND p.objective = 'Teachers will strengthen classroom instruction by observing children during daily activities, identifying their learning needs, and making small instructional changes to better support their development.' AND p.project_file = 'uploads/projects/Cycle2/Pre-Primary Teacher (Grade A & B)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 2 AND p.subject_id = 3 AND p.project_title = 'Building writing skills' AND p.duration = '1 month' AND p.objective = 'To introduce the topic of games through pictures, and build vocabulary for the names of common games played at home and school.' AND p.project_file = 'uploads/projects/Cycle2/Literacy Teacher (Grade 1, 2 & 3)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 3 AND p.subject_id = 3 AND p.project_title = 'Building writing skills' AND p.duration = '1 month' AND p.objective = 'To introduce the topic of games through pictures, and build vocabulary for the names of common games played at home and school.' AND p.project_file = 'uploads/projects/Cycle2/Literacy Teacher (Grade 1, 2 & 3)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 4 AND p.subject_id = 3 AND p.project_title = 'Building writing skills' AND p.duration = '1 month' AND p.objective = 'To introduce the topic of games through pictures, and build vocabulary for the names of common games played at home and school.' AND p.project_file = 'uploads/projects/Cycle2/Literacy Teacher (Grade 1, 2 & 3)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 2 AND p.subject_id = 4 AND p.project_title = 'Number system,Measurement &Geometry' AND p.duration = '1 month' AND p.objective = 'Teachers will strengthen classroom instruction by observing children during daily activities, identifying their learning needs, and making small instructional changes to support , includes helping children arrange numbers up to 99 in ascending and descending order, recognise days, months, and the sequence of seasons, and explore shapes through paper folding, cutting, and describing their sides, corners, and diagonals' AND p.project_file = 'uploads/projects/Cycle2/Numeracy (Grade 1, 2 & 3)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 3 AND p.subject_id = 4 AND p.project_title = 'Number system,Measurement &Geometry' AND p.duration = '1 month' AND p.objective = 'Teachers will strengthen classroom instruction by observing children during daily activities, identifying their learning needs, and making small instructional changes to support , includes helping children arrange numbers up to 99 in ascending and descending order, recognise days, months, and the sequence of seasons, and explore shapes through paper folding, cutting, and describing their sides, corners, and diagonals' AND p.project_file = 'uploads/projects/Cycle2/Numeracy (Grade 1, 2 & 3)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 4 AND p.subject_id = 4 AND p.project_title = 'Number system,Measurement &Geometry' AND p.duration = '1 month' AND p.objective = 'Teachers will strengthen classroom instruction by observing children during daily activities, identifying their learning needs, and making small instructional changes to support , includes helping children arrange numbers up to 99 in ascending and descending order, recognise days, months, and the sequence of seasons, and explore shapes through paper folding, cutting, and describing their sides, corners, and diagonals' AND p.project_file = 'uploads/projects/Cycle2/Numeracy (Grade 1, 2 & 3)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 5 AND p.subject_id = 8 AND p.project_title = 'A trip to Dzukuo' AND p.duration = '1 month' AND p.objective = 'Teachers will help children respond verbally in English to questions and discussions, follow simple instructions and announcements made in English in class, and write short paragraphs with growing confidence and accuracy.' AND p.project_file = 'uploads/projects/Cycle2/English (Grade 4)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 5 AND p.subject_id = 7 AND p.project_title = 'Planning a day trip' AND p.duration = '1 month' AND p.objective = 'Teachers will help children convert rupees to paise and vice versa, apply number operations to find totals, change, multiple costs, and unit cost, and estimate totals and total cost with reasonable accuracy.' AND p.project_file = 'uploads/projects/Cycle2/Math (Grade 4)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 6 AND p.subject_id = 10 AND p.project_title = 'Laugh out Loud weel' AND p.duration = '1 month' AND p.objective = 'Teachers will help children recite English poems with expression and share them with peers and family members, write and speak their personal views and responses clearly, and use meaningful, grammatically correct sentences to describe and narrate incidents.' AND p.project_file = 'uploads/projects/Cycle2/English (Grade 5)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 6 AND p.subject_id = 9 AND p.project_title = 'Paper Furniture' AND p.duration = '1 month' AND p.objective = 'Teachers will help children identify solid shapes such as cubes, cuboids, cylinders, and cones and describe their features, identify the fractional part of a collection, compare fractions, and use decimal fractions in the context of units of length and money.' AND p.project_file = 'uploads/projects/Cycle2/Math (Grade 5)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 7 AND p.subject_id = 11 AND p.project_title = 'Shelter for Animals' AND p.duration = '1 month' AND p.objective = 'Learners move from splitting a shared roti or plot of land by eye to confidently marking, comparing, adding and subtracting fractions, culminating in a locally-grounded animal-shelter design presented to their own Village Council.' AND p.project_file = 'uploads/projects/Cycle2/Math (Grade 6)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 8 AND p.subject_id = 13 AND p.project_title = 'Village Football Integer League' AND p.duration = '1 month' AND p.objective = 'Learners move from following someone else''s game rules to writing trustworthy integer rules of their own, discovering the sign rules for multiplication and division, and building a complete football scoring game that another group can play from their Rule Book alone.' AND p.project_file = 'uploads/projects/Cycle2/Math (Grade 7)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 9 AND p.subject_id = 15 AND p.project_title = 'Designing our Village structure' AND p.duration = '1 month' AND p.objective = 'Learners move from admiring fractal patterns and structures to designing one of their own — building a measured fractal decoration, folding an accurate net into a working 3D model, and drawing the front, top, side and isometric views a real builder would need.' AND p.project_file = 'uploads/projects/Cycle2/Math (Grade 8)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 7 AND p.subject_id = 12 AND p.project_title = 'Solar water purifier' AND p.duration = '1 month' AND p.objective = 'Learners move from noticing that wet clothes dry faster in strong sun toward understanding evaporation and condensation as a real water cycle, and toward designing a working solar water purifier that copies this cycle to clean dirty water using only sunlight and free, everyday materials.' AND p.project_file = 'uploads/projects/Cycle2/Science (Grade 6)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 8 AND p.subject_id = 14 AND p.project_title = 'Who is the fastest?' AND p.duration = '1 month' AND p.objective = 'Learners move from knowing a race has a winner to building a handmade timing device, discovering what makes a pendulum''s swing dependable, and using their own measured data to calculate speed and distinguish uniform from non-uniform motion.' AND p.project_file = 'uploads/projects/Cycle2/Science (Grade 7)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 9 AND p.subject_id = 16 AND p.project_title = 'Optics Fun Mela' AND p.duration = '1 month' AND p.objective = 'Learners move from noticing everyday tricks of light to explaining them — classifying concave and convex mirrors, proving the laws of reflection, and distinguishing converging from diverging lenses — before performing their own optics ''magic tricks'' and revealing the science behind each.' AND p.project_file = 'uploads/projects/Cycle2/Science (Grade 8)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 10 AND p.subject_id IS NULL AND p.project_title = 'Building Teacher Collaboration & Practice Culture' AND p.duration = '1 month' AND p.objective = 'To create a consistent structure for teacher collaboration, enabling sharing, reflection, and improvement of classroom practices.' AND p.project_file = 'uploads/projects/Cycle2/School Leader Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 1 AND p.subject_id = 2 AND p.project_title = 'Developing Fine and Gross Motor Skills Using Different Art Materials' AND p.duration = '1 month' AND p.objective = 'To build creativity and confidence while developing gross and fine motor skills, hand–eye coordination, and control over different art materials through movement-based and large-scale art activitie' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (A & B)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 2 AND p.subject_id = 5 AND p.project_title = 'Expressing Emotions Using Visual Art' AND p.duration = '1 month' AND p.objective = 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 3 AND p.subject_id = 5 AND p.project_title = 'Expressing Emotions Using Visual Art' AND p.duration = '1 month' AND p.objective = 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 4 AND p.subject_id = 5 AND p.project_title = 'Expressing Emotions Using Visual Art' AND p.duration = '1 month' AND p.objective = 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 5 AND p.subject_id = 5 AND p.project_title = 'Expressing Emotions Using Visual Art' AND p.duration = '1 month' AND p.objective = 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 6 AND p.subject_id = 5 AND p.project_title = 'Expressing Emotions Using Visual Art' AND p.duration = '1 month' AND p.objective = 'Support the development of self and emotional awareness by encouraging learners to express feelings, make personal choices, and share stories through art-making and peer interaction.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 1-5)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 7 AND p.subject_id = 6 AND p.project_title = 'Building Relationships Through Shared Artmaking' AND p.duration = '1 month' AND p.objective = 'These activities promote communication and collaboration by engaging students in creating mosaic and line-and-shape artworks together, building teamwork and creative expression.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 6-8)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 8 AND p.subject_id = 6 AND p.project_title = 'Building Relationships Through Shared Artmaking' AND p.duration = '1 month' AND p.objective = 'These activities promote communication and collaboration by engaging students in creating mosaic and line-and-shape artworks together, building teamwork and creative expression.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 6-8)Cycle2.pdf' AND p.is_active = 1)
    OR (p.grade_id = 9 AND p.subject_id = 6 AND p.project_title = 'Building Relationships Through Shared Artmaking' AND p.duration = '1 month' AND p.objective = 'These activities promote communication and collaboration by engaging students in creating mosaic and line-and-shape artworks together, building teamwork and creative expression.' AND p.project_file = 'uploads/projects/Cycle2/Arts Teacher (Grade 6-8)Cycle2.pdf' AND p.is_active = 1)
));
SET @a_c2_task_dev = (SELECT COALESCE(SUM(ABS(delta)),0) FROM (
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 1 AND p.subject_id = 1
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 2 AND p.subject_id = 3
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 3 AND p.subject_id = 3
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 4 AND p.subject_id = 3
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 2 AND p.subject_id = 4
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 3 AND p.subject_id = 4
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 4 AND p.subject_id = 4
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 5 AND p.subject_id = 8
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 5 AND p.subject_id = 7
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 6 AND p.subject_id = 10
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 6 AND p.subject_id = 9
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 7 AND p.subject_id = 11
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 8 AND p.subject_id = 13
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 9 AND p.subject_id = 15
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 7 AND p.subject_id = 12
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 8 AND p.subject_id = 14
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 9 AND p.subject_id = 16
UNION ALL
SELECT 7 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 10 AND p.subject_id IS NULL
UNION ALL
SELECT 6 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 1 AND p.subject_id = 2
UNION ALL
SELECT 6 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 2 AND p.subject_id = 5
UNION ALL
SELECT 6 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 3 AND p.subject_id = 5
UNION ALL
SELECT 6 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 4 AND p.subject_id = 5
UNION ALL
SELECT 6 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 5 AND p.subject_id = 5
UNION ALL
SELECT 6 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 6 AND p.subject_id = 5
UNION ALL
SELECT 6 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 7 AND p.subject_id = 6
UNION ALL
SELECT 6 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 8 AND p.subject_id = 6
UNION ALL
SELECT 6 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle2 AND p.grade_id = 9 AND p.subject_id = 6
) AS task_dev);

SET @a_c2_proj_md5 = (SELECT MD5(GROUP_CONCAT(CONCAT_WS('|', grade_id,
                         IFNULL(subject_id,'N'), project_title, IFNULL(duration,''),
                         IFNULL(objective,''), IFNULL(project_file,''), is_active)
                         ORDER BY grade_id, IFNULL(subject_id,0), project_title SEPARATOR '#'))
                      FROM projects WHERE cycle_id = @cycle2);
SET @a_c2_task_md5 = (SELECT MD5(GROUP_CONCAT(CONCAT_WS('|', p.grade_id,
                         IFNULL(p.subject_id,'N'), t.task_number, t.task_type, t.task_description)
                         ORDER BY p.grade_id, IFNULL(p.subject_id,0), t.task_number SEPARATOR '#'))
                      FROM project_tasks t
                      JOIN projects p ON p.id = t.project_id
                      WHERE p.cycle_id = @cycle2);

-- Embedded expected hashes of the 27 projects / 146 tasks in this file.
-- Recomputed from the INSERT literals (utf8). If you edit an INSERT, recompute.
SET @exp_c2_proj_md5 = 'a2b06dc0a9527209478de6a89335b49d';
SET @exp_c2_task_md5 = 'd9d2a399393eae05b542596a6adc761c';

SELECT 'Cycle 1 still active'            AS check_name, @a_c1_active, 1, IF(@a_c1_active=1,'PASS','FAIL') AS result
UNION ALL SELECT 'Cycle 2 cycle row = 1',            @a_c2_cycles, 1, IF(@a_c2_cycles=1,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 is active',                @a_c2_active, 1, IF(@a_c2_active=1,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 projects = 27',            @a_c2_projects, 27, IF(@a_c2_projects=27,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 tasks = 146',              @a_c2_tasks, 146, IF(@a_c2_tasks=146,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 files under Cycle2/ = 27', @a_c2_files, 27, IF(@a_c2_files=27,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 projects with no task = 0',@a_c2_notasks, 0, IF(@a_c2_notasks=0,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 rows match workbook',      @a_c2_exact, 27, IF(@a_c2_exact=27,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 unexpected projects = 0',  @a_c2_unexpected, 0, IF(@a_c2_unexpected=0,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 per-project task counts',  @a_c2_task_dev, 0, IF(@a_c2_task_dev=0,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 project content hash',     0, 0, IF(@a_c2_proj_md5 <=> @exp_c2_proj_md5,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 task content hash',        0, 0, IF(@a_c2_task_md5 <=> @exp_c2_task_md5,'PASS','FAIL')
UNION ALL SELECT 'total cycles correct',             @a_cycles, @b_cycles+(1-@b_c2_cycles), IF(@a_cycles=@b_cycles+(1-@b_c2_cycles),'PASS','FAIL')
UNION ALL SELECT 'starting state clean or exact content re-run', @b_c2_projects, 0,
          IF(@b_c2_projects=0 OR (@b_c2_projects=27 AND @b_c2_tasks=146 AND @b_c2_active=1),'PASS','FAIL')
UNION ALL SELECT 'grades unchanged',                 @a_grades, @b_grades, IF(@a_grades=@b_grades,'PASS','FAIL')
UNION ALL SELECT 'subjects unchanged',               @a_subjects, @b_subjects, IF(@a_subjects=@b_subjects,'PASS','FAIL')
UNION ALL SELECT 'grade_subject_map unchanged',      @a_gsmap, @b_gsmap, IF(@a_gsmap=@b_gsmap,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 projects unchanged',       @a_c1_projects, @b_c1_projects, IF(@a_c1_projects=@b_c1_projects,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 tasks unchanged',          @a_c1_tasks, @b_c1_tasks, IF(@a_c1_tasks=@b_c1_tasks,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 project fingerprint',      0, 0, IF(@a_c1_md5 <=> @b_c1_md5,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 task fingerprint',         0, 0, IF(@a_c1_task_md5 <=> @b_c1_task_md5,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 project id min',           @a_c1_id_min, @b_c1_id_min, IF(@a_c1_id_min <=> @b_c1_id_min,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 project id max',           @a_c1_id_max, @b_c1_id_max, IF(@a_c1_id_max <=> @b_c1_id_max,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 project id sum',           @a_c1_id_sum, @b_c1_id_sum, IF(@a_c1_id_sum <=> @b_c1_id_sum,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 task id min',              @a_c1_t_id_min, @b_c1_t_id_min, IF(@a_c1_t_id_min <=> @b_c1_t_id_min,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 task id max',              @a_c1_t_id_max, @b_c1_t_id_max, IF(@a_c1_t_id_max <=> @b_c1_t_id_max,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 task id sum',              @a_c1_t_id_sum, @b_c1_t_id_sum, IF(@a_c1_t_id_sum <=> @b_c1_t_id_sum,'PASS','FAIL');

-- Submission / response / evidence counts are reported but are NOT part of
-- the commit predicate. A teacher submitting Cycle 1 during this short
-- transaction must not abort a correct Cycle 2 catalog import, and those
-- tables are not written by this script.
SELECT 'submissions delta (info only)' AS check_name,
       (SELECT COUNT(*) FROM teacher_submissions) AS actual,
       @b_submissions AS baseline,
       'INFO' AS result
UNION ALL SELECT 'task_responses delta (info only)',
       (SELECT COUNT(*) FROM task_responses), @b_responses, 'INFO'
UNION ALL SELECT 'submission_evidence delta (info only)',
       (SELECT COUNT(*) FROM submission_evidence), @b_evidence, 'INFO';

SET @import_ok = (
        @a_c1_active    = 1
    AND @a_c2_cycles    = 1
    AND @a_c2_active    = 1
    AND @a_c2_projects  = 27
    AND @a_c2_tasks     = 146
    AND @a_c2_files     = 27
    AND @a_c2_notasks   = 0
    AND @a_c2_exact     = 27
    AND @a_c2_unexpected= 0
    AND @a_c2_task_dev  = 0
    AND @a_c2_proj_md5  <=> @exp_c2_proj_md5
    AND @a_c2_task_md5  <=> @exp_c2_task_md5
    AND @a_cycles       = @b_cycles + (1 - @b_c2_cycles)
    AND (@b_c2_projects = 0 OR (@b_c2_projects = 27 AND @b_c2_tasks = 146 AND @b_c2_active = 1))
    AND @a_grades       = @b_grades
    AND @a_subjects     = @b_subjects
    AND @a_gsmap        = @b_gsmap
    AND @a_c1_projects  = @b_c1_projects
    AND @a_c1_tasks     = @b_c1_tasks
    AND @a_c1_md5       <=> @b_c1_md5
    AND @a_c1_task_md5  <=> @b_c1_task_md5
    AND @a_c1_id_min    <=> @b_c1_id_min
    AND @a_c1_id_max    <=> @b_c1_id_max
    AND @a_c1_id_sum    <=> @b_c1_id_sum
    AND @a_c1_t_id_min  <=> @b_c1_t_id_min
    AND @a_c1_t_id_max  <=> @b_c1_t_id_max
    AND @a_c1_t_id_sum  <=> @b_c1_t_id_sum
);

-- Commit or roll back INSIDE this session. There is no unconditional COMMIT
-- later in the file. If the client continues after an error, it cannot
-- accidentally persist a failed import.
SET @finish_sql = IF(@import_ok, 'COMMIT', 'ROLLBACK');
PREPARE cycle2_finish FROM @finish_sql;
EXECUTE cycle2_finish;
DEALLOCATE PREPARE cycle2_finish;

SELECT IF(@import_ok,
          'Cycle 2 import committed.',
          'Cycle 2 import rolled back; no catalog changes kept.') AS status,
       @finish_sql AS action_taken,
       @a_c2_proj_md5 AS cycle2_project_hash,
       @a_c2_task_md5 AS cycle2_task_hash;

-- After COMMIT/ROLLBACK has already run. On failure raise ERROR 1242 so
-- the official mysql CLI returns a non-zero exit status. This statement
-- cannot persist data: the transaction is already closed.
SELECT IF(@import_ok, 'ok',
          (SELECT 1 FROM (SELECT 1 UNION ALL SELECT 2) fail_exit
           WHERE @import_ok = 0)
       ) AS fail_exit_gate;
