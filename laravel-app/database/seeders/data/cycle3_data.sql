-- Cycle 3 catalog import (cycles/projects/project_tasks), run by
-- Cycle3DataSeeder. Extracted from lep_cycle3_import_FINAL_PRODUCTION_CANDIDATE.sql,
-- executable body only (STEP 1-4: preflight, baseline, INSERTs, verify-then-
-- commit-or-rollback gate). The original file's doc header and post-commit
-- cosmetic report (STEP 5, plus a status line with a semicolon inside a
-- string literal) are intentionally omitted - Cycle3DataSeeder reproduces
-- the commit/rollback status itself via DB::select() on @import_ok /
-- @finish_sql after running this script. See the original .sql for the
-- full runbook and safety rationale. Idempotent: safe to re-run.
SET NAMES utf8mb4;

-- MariaDB 10.3 default group_concat_max_len is 1024 bytes. The Cycle 1/2/3
-- fingerprints below far exceed that; an unexpanded GROUP_CONCAT would
-- silently truncate and make the MD5 comparisons unreliable.
SET SESSION group_concat_max_len = 16777216;

-- --- STEP 1: pre-flight (read-only). IDs on the left must match the names. -
SELECT id, name FROM grades ORDER BY id;
SELECT id, name FROM subjects ORDER BY id;
SELECT id, name, is_active FROM cycles ORDER BY id;   -- expect Cycle 1 + Cycle 2
SELECT COUNT(*) AS cycle1_projects FROM projects WHERE cycle_id = 1;   -- expect 27
SELECT COUNT(*) AS cycle1_tasks FROM project_tasks t
  JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1;         -- expect 165
SELECT COUNT(*) AS cycle2_projects FROM projects p JOIN cycles c ON c.id = p.cycle_id
 WHERE c.name = 'Cycle 2';                                            -- expect 27
SELECT COUNT(*) AS cycle2_tasks FROM project_tasks t JOIN projects p ON p.id = t.project_id
  JOIN cycles c ON c.id = p.cycle_id WHERE c.name = 'Cycle 2';        -- expect 146

-- Any Cycle 3 project already present? On a clean import this returns 0 rows.
-- If it returns rows, stop and reconcile: rows that differ from this file are
-- skipped by the guards below, which will make STEP 4 fail and roll back.
SELECT p.id, g.name AS grade, COALESCE(s.name,'School Leaders') AS subject,
       p.project_title, p.project_file
FROM projects p JOIN cycles c ON c.id = p.cycle_id
JOIN grades g ON g.id = p.grade_id LEFT JOIN subjects s ON s.id = p.subject_id
WHERE c.name = 'Cycle 3' ORDER BY p.id;

-- --- STEP 2: capture the baseline (read-only, before any write) -----------
SET @b_cycles       = (SELECT COUNT(*) FROM cycles);
SET @b_grades       = (SELECT COUNT(*) FROM grades);
SET @b_subjects     = (SELECT COUNT(*) FROM subjects);
SET @b_gsmap        = (SELECT COUNT(*) FROM grade_subject_map);
SET @b_c3_cycles    = (SELECT COUNT(*) FROM cycles WHERE name = 'Cycle 3');
SET @b_c3_projects  = (SELECT COUNT(*) FROM projects p JOIN cycles c ON c.id = p.cycle_id
                       WHERE c.name = 'Cycle 3');
SET @b_c3_tasks     = (SELECT COUNT(*) FROM project_tasks t JOIN projects p ON p.id = t.project_id
                       JOIN cycles c ON c.id = p.cycle_id WHERE c.name = 'Cycle 3');
SET @b_c3_active    = (SELECT IFNULL((SELECT is_active FROM cycles WHERE name = 'Cycle 3'), 0));
SET @b_c1_active    = (SELECT is_active FROM cycles WHERE id = 1);
SET @b_c2_active    = (SELECT IFNULL((SELECT is_active FROM cycles WHERE name = 'Cycle 2'), 0));

-- Cycle 1 identity
SET @b_c1_projects  = (SELECT COUNT(*) FROM projects WHERE cycle_id = 1);
SET @b_c1_tasks     = (SELECT COUNT(*) FROM project_tasks t
                       JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1);
SET @b_c1_md5       = (SELECT MD5(GROUP_CONCAT(CONCAT_WS('|', id, grade_id,
                         IFNULL(subject_id,'N'), project_title, IFNULL(duration,''),
                         IFNULL(objective,''), IFNULL(project_file,''), is_active)
                         ORDER BY id SEPARATOR '#')) FROM projects WHERE cycle_id = 1);
SET @b_c1_task_md5  = (SELECT MD5(GROUP_CONCAT(CONCAT_WS('|', t.id, t.project_id,
                         t.task_number, t.task_type, t.task_description)
                         ORDER BY t.id SEPARATOR '#')) FROM project_tasks t
                       JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1);
SET @b_c1_id_sum    = (SELECT SUM(id) FROM projects WHERE cycle_id = 1);
SET @b_c1_t_id_sum  = (SELECT SUM(t.id) FROM project_tasks t JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1);

-- Cycle 2 identity - Cycle 3 must not disturb it either
SET @b_c2_projects  = (SELECT COUNT(*) FROM projects p JOIN cycles c ON c.id = p.cycle_id
                       WHERE c.name = 'Cycle 2');
SET @b_c2_tasks     = (SELECT COUNT(*) FROM project_tasks t JOIN projects p ON p.id = t.project_id
                       JOIN cycles c ON c.id = p.cycle_id WHERE c.name = 'Cycle 2');
SET @b_c2_md5       = (SELECT MD5(GROUP_CONCAT(CONCAT_WS('|', p.id, p.grade_id,
                         IFNULL(p.subject_id,'N'), p.project_title, IFNULL(p.duration,''),
                         IFNULL(p.objective,''), IFNULL(p.project_file,''), p.is_active)
                         ORDER BY p.id SEPARATOR '#')) FROM projects p
                       JOIN cycles c ON c.id = p.cycle_id WHERE c.name = 'Cycle 2');
SET @b_c2_task_md5  = (SELECT MD5(GROUP_CONCAT(CONCAT_WS('|', t.id, t.project_id,
                         t.task_number, t.task_type, t.task_description)
                         ORDER BY t.id SEPARATOR '#')) FROM project_tasks t
                       JOIN projects p ON p.id = t.project_id JOIN cycles c ON c.id = p.cycle_id
                       WHERE c.name = 'Cycle 2');
SET @b_c2_id_sum    = (SELECT SUM(p.id) FROM projects p JOIN cycles c ON c.id = p.cycle_id WHERE c.name = 'Cycle 2');
SET @b_c2_t_id_sum  = (SELECT SUM(t.id) FROM project_tasks t JOIN projects p ON p.id = t.project_id
                       JOIN cycles c ON c.id = p.cycle_id WHERE c.name = 'Cycle 2');

SET @b_submissions  = (SELECT COUNT(*) FROM teacher_submissions);
SET @b_responses    = (SELECT COUNT(*) FROM task_responses);
SET @b_evidence     = (SELECT COUNT(*) FROM submission_evidence);

SELECT @b_c1_projects AS c1_projects, @b_c1_tasks AS c1_tasks,
       @b_c2_projects AS c2_projects, @b_c2_tasks AS c2_tasks,
       @b_submissions AS submissions,
       @b_c1_md5 AS c1_fingerprint, @b_c2_md5 AS c2_fingerprint;

-- --- STEP 3: import -------------------------------------------------------
START TRANSACTION;

INSERT INTO cycles (name, sort_order, is_active)
SELECT 'Cycle 3', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM cycles WHERE name = 'Cycle 3');

SET @cycle3 = (SELECT id FROM cycles WHERE name = 'Cycle 3');

-- 1/27  Pre-Primary (A-B)  /  Pre-Primary Teacher (Grade A & B)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 1, 1, @cycle3, 'Story Telling with children', '1 month', 'Learners move from understanding storytelling as a daily classroom practice to confidently using voice, expressions, questions, and simple props to engage children, while observing how stories nurture language, imagination, participation, and expression.', 'uploads/projects/Cycle3/Pre-Primary Teacher (Grade A & B)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 1 AND p.subject_id = 1 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 1 AND subject_id = 1 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Explore the importance of storytelling and how it helps children move from listening to
expressing, thinking, and connecting with the world around them.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Practice storytelling ,narrate a story in your own words during circle time or a
language activity.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Narrate a story using a story book. Ask questions after the narration to  help them recall and think', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Have a reflection session post the story telling narration', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Capture the story telling session ', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 2/27  Grade 1  /  Literacy Teacher (Grade 1, 2 & 3)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 2, 3, @cycle3, 'Building speaking skills', '1 month', 'Learners move from listening to short lessons, instructions, and poems to confidently answering comprehension questions, following spoken directions, identifying rhyming words, and expanding their vocabulary through collaborative activities.', 'uploads/projects/Cycle3/Literacy Teacher (Grade 1, 2 & 3)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 2 AND p.subject_id = 3 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 2 AND subject_id = 3 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', ' Guide learners to move from listening to new words supported by gestures, objects, and picture cards to confidently recognising, repeating, and using the words through guided practice and repetition.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Start with 1-step instructions before building up to 2–3 steps. Keep it playful, like a game, rather than a test.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Read the poem aloud with expression first, so students enjoy it before analysing it. Support early writers with a simple word bank on the board.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Divide the class into groups and assign each group a stanza, so every group has a manageable task. Celebrate creative rhyming attempts, even imperfect ones.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Coordinate timing across the three grades so each has a short, clear turn. Encourage older students (Grade 3) to cheer for and encourage the younger grades, building a sense of shared speaking confidence across the school.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 3/27  Grade 2  /  Literacy Teacher (Grade 1, 2 & 3)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 3, 3, @cycle3, 'Building speaking skills', '1 month', 'Learners move from listening to short lessons, instructions, and poems to confidently answering comprehension questions, following spoken directions, identifying rhyming words, and expanding their vocabulary through collaborative activities.', 'uploads/projects/Cycle3/Literacy Teacher (Grade 1, 2 & 3)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 3 AND p.subject_id = 3 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 3 AND subject_id = 3 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', ' Guide learners to move from listening to new words supported by gestures, objects, and picture cards to confidently recognising, repeating, and using the words through guided practice and repetition.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Start with 1-step instructions before building up to 2–3 steps. Keep it playful, like a game, rather than a test.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Read the poem aloud with expression first, so students enjoy it before analysing it. Support early writers with a simple word bank on the board.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Divide the class into groups and assign each group a stanza, so every group has a manageable task. Celebrate creative rhyming attempts, even imperfect ones.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Coordinate timing across the three grades so each has a short, clear turn. Encourage older students (Grade 3) to cheer for and encourage the younger grades, building a sense of shared speaking confidence across the school.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 4/27  Grade 3  /  Literacy Teacher (Grade 1, 2 & 3)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 4, 3, @cycle3, 'Building speaking skills', '1 month', 'Learners move from listening to short lessons, instructions, and poems to confidently answering comprehension questions, following spoken directions, identifying rhyming words, and expanding their vocabulary through collaborative activities.', 'uploads/projects/Cycle3/Literacy Teacher (Grade 1, 2 & 3)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 4 AND p.subject_id = 3 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 4 AND subject_id = 3 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', ' Guide learners to move from listening to new words supported by gestures, objects, and picture cards to confidently recognising, repeating, and using the words through guided practice and repetition.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Start with 1-step instructions before building up to 2–3 steps. Keep it playful, like a game, rather than a test.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Read the poem aloud with expression first, so students enjoy it before analysing it. Support early writers with a simple word bank on the board.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Divide the class into groups and assign each group a stanza, so every group has a manageable task. Celebrate creative rhyming attempts, even imperfect ones.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Coordinate timing across the three grades so each has a short, clear turn. Encourage older students (Grade 3) to cheer for and encourage the younger grades, building a sense of shared speaking confidence across the school.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 5/27  Grade 1  /  Numeracy Teacher (Grade 1, 2 & 3)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 2, 4, @cycle3, 'Building numerical skills, shapes,lines & data', '1 month', 'Learners move from exploring everyday objects and identifying basic shapes to investigating how objects roll or slide, recognising shapes in their surroundings, and using tally marks, repeated addition, and equal sharing to interpret data and explain their findings.', 'uploads/projects/Cycle3/Numeracy (Grade 1, 2 & 3)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 2 AND p.subject_id = 4 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 2 AND subject_id = 4 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', ' Guide learners to use safe objects from the surroundings. Let every child handle the objects  discovery by touching and pushing is the point of this task. Use a slightly tilted board or plank as a slope.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Introduce one shape at a time with a cut-out and a real object before showing all four together. Take children outdoors for the shape hunt if possible.

', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Support the learners to discover that a folded edge and a stretched string are always straight. Keep sample curved objects (a bangle, a bent twig) nearby for comparison.

', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Link each line to a body or surroundings cue: horizontal lines lie down like the horizon, vertical lines stand up like a bamboo pole, and slant lines lean like a hillside path.

', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Choose a survey topic children care about, such as favourite fruit. Teach the bundle of five (four lines and one slash) carefully, since it is the key to fast counting.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Guide the discussion with questions rather than answers, so children reach their own conclusions. Connect each bundle of five to ‘5 + 5 + 5’ to show multiplication as repeated addition.

', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 7, 'Task', 'Coordinate timing so each grade has a short, clear turn. Encourage older students to cheer on the younger grades, building shared numeracy pride across the school.

', 7, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 7);

-- 6/27  Grade 2  /  Numeracy Teacher (Grade 1, 2 & 3)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 3, 4, @cycle3, 'Building numerical skills, shapes,lines & data', '1 month', 'Learners move from exploring everyday objects and identifying basic shapes to investigating how objects roll or slide, recognising shapes in their surroundings, and using tally marks, repeated addition, and equal sharing to interpret data and explain their findings.', 'uploads/projects/Cycle3/Numeracy (Grade 1, 2 & 3)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 3 AND p.subject_id = 4 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 3 AND subject_id = 4 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', ' Guide learners to use safe objects from the surroundings. Let every child handle the objects  discovery by touching and pushing is the point of this task. Use a slightly tilted board or plank as a slope.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Introduce one shape at a time with a cut-out and a real object before showing all four together. Take children outdoors for the shape hunt if possible.

', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Support the learners to discover that a folded edge and a stretched string are always straight. Keep sample curved objects (a bangle, a bent twig) nearby for comparison.

', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Link each line to a body or surroundings cue: horizontal lines lie down like the horizon, vertical lines stand up like a bamboo pole, and slant lines lean like a hillside path.

', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Choose a survey topic children care about, such as favourite fruit. Teach the bundle of five (four lines and one slash) carefully, since it is the key to fast counting.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Guide the discussion with questions rather than answers, so children reach their own conclusions. Connect each bundle of five to ‘5 + 5 + 5’ to show multiplication as repeated addition.

', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 7, 'Task', 'Coordinate timing so each grade has a short, clear turn. Encourage older students to cheer on the younger grades, building shared numeracy pride across the school.

', 7, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 7);

-- 7/27  Grade 3  /  Numeracy Teacher (Grade 1, 2 & 3)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 4, 4, @cycle3, 'Building numerical skills, shapes,lines & data', '1 month', 'Learners move from exploring everyday objects and identifying basic shapes to investigating how objects roll or slide, recognising shapes in their surroundings, and using tally marks, repeated addition, and equal sharing to interpret data and explain their findings.', 'uploads/projects/Cycle3/Numeracy (Grade 1, 2 & 3)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 4 AND p.subject_id = 4 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 4 AND subject_id = 4 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', ' Guide learners to use safe objects from the surroundings. Let every child handle the objects  discovery by touching and pushing is the point of this task. Use a slightly tilted board or plank as a slope.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Introduce one shape at a time with a cut-out and a real object before showing all four together. Take children outdoors for the shape hunt if possible.

', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Support the learners to discover that a folded edge and a stretched string are always straight. Keep sample curved objects (a bangle, a bent twig) nearby for comparison.

', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Link each line to a body or surroundings cue: horizontal lines lie down like the horizon, vertical lines stand up like a bamboo pole, and slant lines lean like a hillside path.

', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Choose a survey topic children care about, such as favourite fruit. Teach the bundle of five (four lines and one slash) carefully, since it is the key to fast counting.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Guide the discussion with questions rather than answers, so children reach their own conclusions. Connect each bundle of five to ‘5 + 5 + 5’ to show multiplication as repeated addition.

', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 7, 'Task', 'Coordinate timing so each grade has a short, clear turn. Encourage older students to cheer on the younger grades, building shared numeracy pride across the school.

', 7, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 7);

-- 8/27  Grade 4  /  English (Grade 4)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 5, 8, @cycle3, 'Our Festival Fun Fair', '1 month', 'Learners move from reading and understanding the chapter Christmas to exploring a local festival, writing about its significance and traditions, creating related stories and activities, and collaboratively developing and presenting an engaging festival experience corner for visitors.', 'uploads/projects/Cycle3/English (Grade 4)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 5 AND p.subject_id = 8 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 5 AND subject_id = 8 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Divide students into fixed, mixed-ability groups of 5–6 for the whole project. Encourage students to guess the meaning of new words (like merrymaking, carols) from the sentence around them before checking together.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Offer the sentence-starter structure (e.g., ‘The Festival is celebrated in ) for groups that need support. Circulate during the jumbled-sentence puzzle to help students self-correct', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Circulate to check that stories connect clearly to the festival, use meaningful and correct sentences, and that every group member contributes.

', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Facilitate model constructive feedback language (e.g., ‘Maybe you should try to…’ instead of ‘This is wrong’). Ensure every group member has a clear, active role in the final corner.

', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Arrange the room (or an open space) so each group has a separate area, with enough room for visitors to move between corners. Invite other classes, teachers, or parents as visitors. Give clear spoken instructions for setup and remind students to listen for announcements as the fair begins and ends.

', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 9/27  Grade 4  /  Math (Grade 4)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 5, 7, @cycle3, 'Fitness challenge', '1 month', 'Learners move from exploring fitness through simple body-part tests to collecting and representing data using pictographs and bar graphs, interpreting results, and applying mental maths, estimation, or written calculations to draw meaningful conclusions.', 'uploads/projects/Cycle3/Math (Grade 4)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 5 AND p.subject_id = 7 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 5 AND subject_id = 7 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Start with the 1-minute jog to make the topic real and personal. Divide students into fixed groups of 3–4 for the whole project.

', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Emphasise kindness  no comments on anyone’s results, and anonymous recording using ‘Student #’ rather than names.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Use the sit-up data table from Task-2 and ask questions that show why a visual is easier to read than a plain table, especially as the data set grows.

', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'For groups with larger numbers (e.g., 40, 60, 75), show how to use intervals of 10 on the vertical axis rather than marking every single unit.

', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Model the inference discussion first as a whole class (highest/lowest/most common score) before groups do the same for their own data, so ‘drawing inferences by discussing with the teacher’ is genuinely guided, not just independent.

', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 10/27  Grade 5  /  English (Grade 5)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 6, 10, @cycle3, 'Act it Out', '1 month', 'Learners move from reading and understanding The Farmer and the Well to exploring dialogue, rewriting story endings, and creating original plays, culminating in a collaborative performance that communicates a meaningful message about fairness and reflects on their learning journey.', 'uploads/projects/Cycle3/English (Grade 5)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 6 AND p.subject_id = 10 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 6 AND subject_id = 10 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Divide students into fixed, mixed-ability groups of 4–5 for the whole project. Prompt the opening discussion with everyday examples of unfairness if students are stuck (someone cutting the line, being blamed unfairly, not being listened to).', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Circulate to support groups with vocabulary, sentence structure, and clarifying ideas. Remind students that dialogue should sound like real people talking.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Remind groups this is a big-picture planning step — short points are enough, not full sentences yet. Circulate to help groups stay on task and keep their story focused on the message of fairness.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Pair two groups together for feedback; model sentence starters such as ‘One thing we really liked was…’ and ‘It might be even better if…’. Circulate during rehearsal to support stage presence, language, and creative use of materials.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Give each group 2 minutes to set up with props. Remind the audience to watch attentively and note something positive to share afterward. The class votes for the best play based on creativity, acting, message, and dialogue; the winning group can perform at the school assembly or a special event.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 11/27  Grade 5  /  Math (Grade 5)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 6, 9, @cycle3, 'Naga Stadium', '1 month', 'Learners move from exploring traditional Naga games and designing a stadium using fractions to calculating perimeter, area, and construction costs, applying measurement and the four operations to estimate materials and develop a practical stadium plan.', 'uploads/projects/Cycle3/Math (Grade 5)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 6 AND p.subject_id = 9 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 6 AND subject_id = 9 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Divide students into fixed groups of 3–4 for the whole project, ensuring each group chooses a different game if possible. Use the classroom’s approximate dimensions (e.g., 6 m x 4 m) to help groups estimate realistic playing-field sizes.

', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Use the handkerchief demonstration (where would lace go around its border?) to introduce perimeter concretely before moving to formulas.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Use the handkerchief again (dyeing its entire surface) to introduce the area concretely. For groups using combined shapes, guide them to add the areas of each part.

', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Bring a small weighing scale, a measuring cup/jug, and a ruler if available, so groups can physically verify what 1 kg or 1 litre feels or looks like before estimating larger quantities. Keep the peer-feedback round brief and focused.

', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', '
If stadium sketches are too small to show clearly, let groups redraw key parts on the board during their presentation.

', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 12/27  Grade 6  /  Math (Grade 6)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 7, 11, @cycle3, 'The Integer Board Game', '1 month', 'Learners move from the everyday feeling of climbing up a hill and coming back down to the village to confidently placing, comparing, adding and subtracting integers, culminating in an original integer board game that each group teaches to an audience beyond the teacher.', 'uploads/projects/Cycle3/Math (Grade 6)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 7 AND p.subject_id = 11 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 7 AND subject_id = 11 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce the project and leading question through the experience of climbing up and coming down a hill, then guide learners to build a human number line from −10 to +10 and classify real-life situations as above, below, or at zero.
 Form groups, fix roles and share the Final Product Criteria (number-line track, clear rules, 4–6 challenge cards) for the board game.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide learners to compare integers using < and >, and to add and subtract integers by moving right or left along a number line.
 Have learners discover the zero pair (a number and its negative add to zero) and use it to solve sums quickly.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide learners to create 4–6 challenge cards that use integer operations correctly, with every answer checked by the group.
 Have groups write clear game rules that a new player could follow without any extra explanation.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Pair groups for structured peer feedback on whether the rules are clear and the challenge cards use integers correctly.
 Guide groups to make one agreed improvement and build their playable board game (number-line track, tokens, dice or number chits).', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Each group plays and explains its board game to a real audience, showing how the track, challenge cards and rules use integers.
 Learners individually reflect on what became clearer about integers by building a game and what they would improve.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 13/27  Grade 7  /  Math (Grade 7)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 8, 13, @cycle3, 'Smart Bazaar: Our Village Best Buy Report', '1 month', 'Learners move from guessing which packet ''looks'' cheaper at the village bazaar to proving the true best buy with decimal multiplication and division, culminating in a Best Buy Report Board with real prices, shown working and a calculated recommendation presented to the village.', 'uploads/projects/Cycle3/Math (Grade 7)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 8 AND p.subject_id = 13 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 8 AND subject_id = 13 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce the project and leading question through a real bazaar dilemma (a 200 g packet of dal for ₹28 versus a 1 kg packet for ₹122), then guide learners to form groups and set up their Best Buy Report Board.
 Have groups copy the market data table, write a prediction and plan a market price survey.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide learners to multiply decimals by removing the decimal points, multiplying as whole numbers and placing the point back using the total decimal places.
 Have groups use their collected prices to calculate a family''s weekly and monthly market bill.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide learners to divide decimals by whole numbers and by 10, 100 and 1000 to find the true price per 100 g of each packet size.
 Have groups decide and justify the Best Buy for each item, solve a ₹500 budget problem and write a first-draft conclusion using numbers.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide learners through a gallery walk to review other groups'' boards using a structured Peer Feedback Form, checking decimal placement, units and calculations.
 Have groups revise their board, write a final conclusion with at least two calculated values and add a ''What Surprised Us'' box.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Each group presents its Best Buy Report Board to a community audience, covering its data, monthly cost, price per 100 g and Best Buy recommendation, and answers a question that any member may be asked.
 Learners individually reflect on how decimals can help their family spend market money wisely.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 14/27  Grade 8  /  Math (Grade 8)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 9, 15, @cycle3, 'The Village Data Story', '1 month', 'Learners move from sensing that the village market is ''busy'' or ''quiet'' to tracking real numbers over several days, finding the mean and median by hand, and turning the data into a hand-drawn line graph that tells a genuine story about their own village.', 'uploads/projects/Cycle3/Math (Grade 8)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 9 AND p.subject_id = 15 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 9 AND subject_id = 15 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce the project and leading question through a village-market puzzle, then guide learners to find the mean and median of real classroom numbers by hand and feel the mean as a ''balancing centre'' on a human number line.
 Form groups, share the Final Product Criteria and have each group choose one part of village life to track.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide learners to predict and check how the mean and median change when a very high (''festival day'') or very low (''rainy day'') value is added to their own tracked data.
 Have groups conclude that one extreme value pulls the mean while the median barely moves, and note early patterns in their numbers.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide learners to plot their daily tracked data as dots on a labelled grid with a sensible vertical scale, one dot per day.
 Have groups join the dots in order to form a line graph and discuss where the line climbs and drops.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide learners to mark the mean as a reference line on their graph, name the highest and lowest points and write a 3–4 sentence tale describing the trend.
 Have groups swap graphs for peer feedback using a Peer Feedback Form and make one improvement to their data story.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Each group presents its Village Data Story to a real audience, showing its line graph, stating the mean and median and telling its tale, then answers a guest''s question using the actual numbers.
 Learners individually reflect on what their dots and lines revealed about village life.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 15/27  Grade 6  /  Science (Grade 6)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 7, 12, @cycle3, 'Building Our Village Separation Station', '1 month', 'Learners move from watching families clean rice, dal and muddy water at home to naming the method behind each task (handpicking, winnowing, sieving, sedimentation, decantation, filtration, evaporation and magnetic separation), culminating in a live Separation Station with a working water filter run for the village.', 'uploads/projects/Cycle3/Science (Grade 6)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 7 AND p.subject_id = 12 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 7 AND subject_id = 12 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce the project and leading question through the everyday task of cleaning rice or dal, then guide learners to observe real mixtures, try separating one by hand (handpicking) and sort mixtures by why they are separated.
 Form groups, fix roles, share the Final Product Criteria and start a Station Log.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide learners to separate solid-solid mixtures using winnowing (by weight, with wind) and sieving (by size, with a sieve).
 Have groups add the method that worked best and the property used to their Station Log.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide learners to separate solids from liquids using sedimentation and decantation on muddy water.
 Have groups design and build a water filter from local materials (cloth, sand, charcoal, gravel), test it, and be reminded never to taste the filtered water.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Guide learners to recover dissolved salt using evaporation and to pull out iron nails using a magnet, and discuss using more than one method in sequence for a mixture with several components.
 Have groups prepare their stations with label cards, give and receive peer feedback and make one improvement.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Each group runs its Separation Station for a real audience, demonstrating at least two methods and a working water filter live, and explaining the property used and why each method is the best choice.
 Learners individually reflect on which method surprised them most and how they would now answer the leading question.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 16/27  Grade 7  /  Science (Grade 7)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 8, 14, @cycle3, 'The Bright Room Challenge', '1 month', 'Learners move from noticing that a bamboo home or morung stays dark on a bright afternoon to understanding that light travels in straight lines and reflects off a plane mirror, culminating in a model Bright Room with one light-entry hole and two mirrors lighting two dark corners, presented to a real audience.', 'uploads/projects/Cycle3/Science (Grade 7)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 8 AND p.subject_id = 14 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 8 AND subject_id = 14 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce the project and leading question through a familiar dark storeroom or morung, then guide learners to sort objects as luminous or non-luminous and show with a straight and a bent tube that light travels in a straight line.
 Form groups, share the Final Product Criteria and have each group build a dark model room with a single light-entry hole.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide learners to predict and test materials as transparent, translucent or opaque, and to see that a shadow needs a light source, an opaque object and a screen.
 Have groups decide what the walls and window of their model room should be made of.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide learners to shine a torch on a mirror, tilt it to see how the reflected spot moves, and describe the mirror image (same size, erect, laterally inverted).
 Have groups place a mirror in their model room so the beam bounces onto a dark corner and adjust it until the corner lights up.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Pair groups for structured peer feedback on how clearly light enters and reaches the dark corner.
 Have groups place a second mirror to light a second corner, test the room against all criteria and prepare who will demonstrate and explain.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Each group presents its Bright Room to a real audience, demonstrating how the corners are lit and explaining why light travels straight and how the mirrors change its direction.
 Learners individually reflect on what surprised them about the way light behaves.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 17/27  Grade 8  /  Science (Grade 8)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 9, 16, @cycle3, 'Preserve and Protect', '1 month', 'Learners move from noticing a cleared hillside or a drying stream to explaining the web of life behind it (biotic and abiotic components, food chains, interdependence), culminating in a Conservation Action Plan for their own village presented to a real audience.', 'uploads/projects/Cycle3/Science (Grade 8)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 9 AND p.subject_id = 16 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 9 AND subject_id = 16 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Introduce the project and leading question through a vivid local scenario of the hill behind the village losing its trees, then guide learners on a nature walk (or an imagined walk) to observe living and non-living things.
 Form groups, share the Final Product Criteria and have learners sort what they saw as biotic and abiotic and connect it to the idea of an ecosystem.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide learners to distinguish a population from a community, and to act out and label a local food chain naming producers, consumers and decomposers.
 Have learners explore how removing one link affects the balance, and learn about local conservation areas and species, including the Pangti village story of the Amur falcon.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Guide learners to see how one small ecological change can spread through a whole web of life, using the two-pond story.
 Have groups complete a Cause, Effect and Solution table for local issues and brainstorm realistic solutions through reforestation, recycling and waste management.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Pair groups for structured peer feedback on their chosen problems and solutions.
 Have each group build its Conservation Action Plan on chart paper, showing the problem, web of life, at least two solutions and 2–3 action steps with a timeline.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Each group presents its Conservation Action Plan to a real audience through a gallery walk and collects names of people willing to help with its actions.
 Learners individually reflect on how living and non-living things are connected and one action they will take in daily life.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);

-- 18/27  School Leaders  /  School Leaders (no subject)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 10, NULL, @cycle3, 'Purposeful Community Engagement', '1 month', 'Schools move from routine Parent-Teacher Meetings focused on attendance and discipline to meaningful, learning-focused conversations where parents understand their child’s progress, explore ways to support learning at home, and build stronger partnerships with teachers to improve student outcomes.', 'uploads/projects/Cycle3/School Leader Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 10 AND p.subject_id IS NULL AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 10 AND subject_id IS NULL AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Prepare a structured PTM planning sheet outlining learning goals, discussion points, parent engagement activities, roles, and follow-up actions to make PTMs more meaningful and focused on student learning.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Create a clear, learning-focused PTM agenda that guides discussions on student progress, parent participation, home-based learning support, and actionable next steps.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Share each student’s learning progress, strengths, and areas for improvement with parents, along with practical suggestions to support their child’s learning at home.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Demonstrate simple, engaging home-based learning activities that parents can easily practise with their children to strengthen foundational literacy and numeracy skills.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Collect parent feedback on the PTM experience, their understanding of the child’s learning progress, and the support needed to strengthen learning at home.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Track parent attendance, participation, and engagement during PTMs to identify gaps and plan follow-up support for stronger school–home partnerships.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 7, 'Task', 'Display key learning messages and simple home-support tips to help parents understand their role in strengthening their child’s learning.', 7, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 7);

-- 19/27  Pre-Primary (A-B)  /  Arts Teacher (A & B)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 1, 2, @cycle3, 'Collaborative Art Making
Using Textured Materials', '1 month', 'To help learners develop collaboration, share space and materials, adapt to challenges, contribute ideas, and build a sense of belonging through shared art activities.', 'uploads/projects/Cycle3/Arts Teacher (A & B)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 1 AND p.subject_id = 2 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 1 AND subject_id = 2 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Prepare the art space, organise shared materials, and plan simple collaborative activities that encourage students to share resources, exchange ideas, and create artwork together.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Conduct Art Activity 1, where students creatively explore different types of paper, experiment with materials, share ideas, and collaborate to create artwork together.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Art Activity 2, where students explore everyday objects to discover and experiment with different textures, sharing materials and ideas while creating collaborative artwork.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Observe and track students’ participation, creativity, collaboration, sharing of materials, and confidence in expressing ideas during art activities to identify progress and areas for support.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Prepare a sample progress tracker to record students’ creativity, participation, collaboration, sharing of materials, and confidence in expressing ideas during art activities.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Reflect on students’ engagement, collaboration, creativity, and challenges during art activities to identify successes, lessons learned, and areas for improvement in future sessions.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);

-- 20/27  Grade 1  /  Arts Teacher (Grade 1-5)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 2, 5, @cycle3, 'Exploring Identity and Emotions
Through Colour and Art', '1 month', 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.', 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 2 AND p.subject_id = 5 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 2 AND subject_id = 5 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Prepare the art space, organise shared materials, and plan simple collaborative activities that encourage students to share resources, exchange ideas, and create artwork together.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide students to create an artwork representing a word that best describes them, using colours, shapes, and images to express their identity, feelings, and personal experiences.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Art Activity 1, where students creatively explore different types of paper, experiment with materials, share ideas, and collaborate to create artwork together.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Encourage students to draw a landscape and use colours that express their feelings and imagination rather than realistic colours, helping them communicate emotions through art.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Observe and track students’ ability to express feelings and personal experiences through art, use colours creatively, communicate meaning through images, and interpret and appreciate others’ artwork.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Observe students during both art activities and record their names under Small Steps (🌱), Growing (🌿), or Strong & Steady (🌳) for each skill, based on their participation, creativity, and ability to express feelings and ideas through art.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 7, 'Task', 'Please tick (✔) the responses that best describes
your experience during the art activities.', 7, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 7);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 8, 'Task', 'Collect Student Artworks, Create an Art Wall in the Classroom, Take Photos and Upload', 8, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 8);

-- 21/27  Grade 2  /  Arts Teacher (Grade 1-5)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 3, 5, @cycle3, 'Exploring Identity and Emotions
Through Colour and Art', '1 month', 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.', 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 3 AND p.subject_id = 5 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 3 AND subject_id = 5 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Prepare the art space, organise shared materials, and plan simple collaborative activities that encourage students to share resources, exchange ideas, and create artwork together.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide students to create an artwork representing a word that best describes them, using colours, shapes, and images to express their identity, feelings, and personal experiences.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Art Activity 1, where students creatively explore different types of paper, experiment with materials, share ideas, and collaborate to create artwork together.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Encourage students to draw a landscape and use colours that express their feelings and imagination rather than realistic colours, helping them communicate emotions through art.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Observe and track students’ ability to express feelings and personal experiences through art, use colours creatively, communicate meaning through images, and interpret and appreciate others’ artwork.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Observe students during both art activities and record their names under Small Steps (🌱), Growing (🌿), or Strong & Steady (🌳) for each skill, based on their participation, creativity, and ability to express feelings and ideas through art.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 7, 'Task', 'Please tick (✔) the responses that best describes
your experience during the art activities.', 7, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 7);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 8, 'Task', 'Collect Student Artworks, Create an Art Wall in the Classroom, Take Photos and Upload', 8, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 8);

-- 22/27  Grade 3  /  Arts Teacher (Grade 1-5)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 4, 5, @cycle3, 'Exploring Identity and Emotions
Through Colour and Art', '1 month', 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.', 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 4 AND p.subject_id = 5 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 4 AND subject_id = 5 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Prepare the art space, organise shared materials, and plan simple collaborative activities that encourage students to share resources, exchange ideas, and create artwork together.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide students to create an artwork representing a word that best describes them, using colours, shapes, and images to express their identity, feelings, and personal experiences.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Art Activity 1, where students creatively explore different types of paper, experiment with materials, share ideas, and collaborate to create artwork together.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Encourage students to draw a landscape and use colours that express their feelings and imagination rather than realistic colours, helping them communicate emotions through art.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Observe and track students’ ability to express feelings and personal experiences through art, use colours creatively, communicate meaning through images, and interpret and appreciate others’ artwork.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Observe students during both art activities and record their names under Small Steps (🌱), Growing (🌿), or Strong & Steady (🌳) for each skill, based on their participation, creativity, and ability to express feelings and ideas through art.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 7, 'Task', 'Please tick (✔) the responses that best describes
your experience during the art activities.', 7, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 7);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 8, 'Task', 'Collect Student Artworks, Create an Art Wall in the Classroom, Take Photos and Upload', 8, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 8);

-- 23/27  Grade 4  /  Arts Teacher (Grade 1-5)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 5, 5, @cycle3, 'Exploring Identity and Emotions
Through Colour and Art', '1 month', 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.', 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 5 AND p.subject_id = 5 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 5 AND subject_id = 5 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Prepare the art space, organise shared materials, and plan simple collaborative activities that encourage students to share resources, exchange ideas, and create artwork together.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide students to create an artwork representing a word that best describes them, using colours, shapes, and images to express their identity, feelings, and personal experiences.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Art Activity 1, where students creatively explore different types of paper, experiment with materials, share ideas, and collaborate to create artwork together.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Encourage students to draw a landscape and use colours that express their feelings and imagination rather than realistic colours, helping them communicate emotions through art.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Observe and track students’ ability to express feelings and personal experiences through art, use colours creatively, communicate meaning through images, and interpret and appreciate others’ artwork.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Observe students during both art activities and record their names under Small Steps (🌱), Growing (🌿), or Strong & Steady (🌳) for each skill, based on their participation, creativity, and ability to express feelings and ideas through art.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 7, 'Task', 'Please tick (✔) the responses that best describes
your experience during the art activities.', 7, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 7);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 8, 'Task', 'Collect Student Artworks, Create an Art Wall in the Classroom, Take Photos and Upload', 8, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 8);

-- 24/27  Grade 5  /  Arts Teacher (Grade 1-5)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 6, 5, @cycle3, 'Exploring Identity and Emotions
Through Colour and Art', '1 month', 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.', 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 6 AND p.subject_id = 5 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 6 AND subject_id = 5 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Prepare the art space, organise shared materials, and plan simple collaborative activities that encourage students to share resources, exchange ideas, and create artwork together.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide students to create an artwork representing a word that best describes them, using colours, shapes, and images to express their identity, feelings, and personal experiences.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Art Activity 1, where students creatively explore different types of paper, experiment with materials, share ideas, and collaborate to create artwork together.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Encourage students to draw a landscape and use colours that express their feelings and imagination rather than realistic colours, helping them communicate emotions through art.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Observe and track students’ ability to express feelings and personal experiences through art, use colours creatively, communicate meaning through images, and interpret and appreciate others’ artwork.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Observe students during both art activities and record their names under Small Steps (🌱), Growing (🌿), or Strong & Steady (🌳) for each skill, based on their participation, creativity, and ability to express feelings and ideas through art.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 7, 'Task', 'Please tick (✔) the responses that best describes
your experience during the art activities.', 7, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 7);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 8, 'Task', 'Collect Student Artworks, Create an Art Wall in the Classroom, Take Photos and Upload', 8, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 8);

-- 25/27  Grade 6  /  Arts Teacher (Grade 6-8)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 7, 6, @cycle3, 'Exploring Emotions and Ideas through art', '1 month', 'Help learners explore and express ideas through art by experimenting with materials, colours, and forms, reflecting on real-world experiences, revising their work, and creating imaginative artworks beyond realistic representations.', 'uploads/projects/Cycle3/Arts Teacher (Grade 6-8)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 7 AND p.subject_id = 6 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 7 AND subject_id = 6 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Prepare the art space, organise shared materials, and plan simple collaborative activities that encourage students to share resources, exchange ideas, and create artwork together.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide students to create an artwork representing a word that best describes them, using colours, shapes, and images to express their identity, feelings, and personal experiences.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Art Activity 1, where students creatively explore different types of paper, experiment with materials, share ideas, and collaborate to create artwork together.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Encourage students to draw a landscape and use colours that express their feelings and imagination rather than realistic colours, helping them communicate emotions through art.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Observe and track students’ ability to express feelings and personal experiences through art, use colours creatively, communicate meaning through images, and interpret and appreciate others’ artwork.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Observe students during both art activities and record their names under Small Steps (🌱), Growing (🌿), or Strong & Steady (🌳) for each skill, based on their participation, creativity, and ability to express feelings and ideas through art.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 7, 'Task', 'Please tick (✔) the responses that best describes
your experience during the art activities.', 7, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 7);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 8, 'Task', 'Collect Student Artworks, Create an Art Wall in the Classroom, Take Photos and Upload', 8, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 8);

-- 26/27  Grade 7  /  Arts Teacher (Grade 6-8)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 8, 6, @cycle3, 'Exploring Emotions and Ideas through art', '1 month', 'Help learners explore and express ideas through art by experimenting with materials, colours, and forms, reflecting on real-world experiences, revising their work, and creating imaginative artworks beyond realistic representations.', 'uploads/projects/Cycle3/Arts Teacher (Grade 6-8)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 8 AND p.subject_id = 6 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 8 AND subject_id = 6 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Prepare the art space, organise shared materials, and plan simple collaborative activities that encourage students to share resources, exchange ideas, and create artwork together.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide students to create an artwork representing a word that best describes them, using colours, shapes, and images to express their identity, feelings, and personal experiences.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Art Activity 1, where students creatively explore different types of paper, experiment with materials, share ideas, and collaborate to create artwork together.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Encourage students to draw a landscape and use colours that express their feelings and imagination rather than realistic colours, helping them communicate emotions through art.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Observe and track students’ ability to express feelings and personal experiences through art, use colours creatively, communicate meaning through images, and interpret and appreciate others’ artwork.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Observe students during both art activities and record their names under Small Steps (🌱), Growing (🌿), or Strong & Steady (🌳) for each skill, based on their participation, creativity, and ability to express feelings and ideas through art.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 7, 'Task', 'Please tick (✔) the responses that best describes
your experience during the art activities.', 7, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 7);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 8, 'Task', 'Collect Student Artworks, Create an Art Wall in the Classroom, Take Photos and Upload', 8, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 8);

-- 27/27  Grade 8  /  Arts Teacher (Grade 6-8)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT 9, 6, @cycle3, 'Exploring Emotions and Ideas through art', '1 month', 'Help learners explore and express ideas through art by experimenting with materials, colours, and forms, reflecting on real-world experiences, revising their work, and creating imaginative artworks beyond realistic representations.', 'uploads/projects/Cycle3/Arts Teacher (Grade 6-8)Cycle3.pdf', 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM projects p
  WHERE p.grade_id = 9 AND p.subject_id = 6 AND p.cycle_id = @cycle3);
SET @p = (SELECT id FROM projects
  WHERE grade_id = 9 AND subject_id = 6 AND cycle_id = @cycle3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 1, 'Task', 'Prepare the art space, organise shared materials, and plan simple collaborative activities that encourage students to share resources, exchange ideas, and create artwork together.', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 1);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 2, 'Task', 'Guide students to create an artwork representing a word that best describes them, using colours, shapes, and images to express their identity, feelings, and personal experiences.', 2, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 2);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 3, 'Task', 'Conduct Art Activity 1, where students creatively explore different types of paper, experiment with materials, share ideas, and collaborate to create artwork together.', 3, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 3);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 4, 'Task', 'Encourage students to draw a landscape and use colours that express their feelings and imagination rather than realistic colours, helping them communicate emotions through art.', 4, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 4);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 5, 'Task', 'Observe and track students’ ability to express feelings and personal experiences through art, use colours creatively, communicate meaning through images, and interpret and appreciate others’ artwork.', 5, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 5);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 6, 'Task', 'Observe students during both art activities and record their names under Small Steps (🌱), Growing (🌿), or Strong & Steady (🌳) for each skill, based on their participation, creativity, and ability to express feelings and ideas through art.', 6, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 6);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 7, 'Task', 'Please tick (✔) the responses that best describes
your experience during the art activities.', 7, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 7);
INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @p, 8, 'Task', 'Collect Student Artworks, Create an Art Wall in the Classroom, Take Photos and Upload', 8, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = @p AND x.task_number = 8);

-- --- STEP 4: verify contents, then COMMIT or ROLLBACK in-session ----------
SET @a_c3_projects  = (SELECT COUNT(*) FROM projects WHERE cycle_id = @cycle3);
SET @a_c3_tasks     = (SELECT COUNT(*) FROM project_tasks t
                       JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = @cycle3);
SET @a_c3_files     = (SELECT COUNT(*) FROM projects WHERE cycle_id = @cycle3
                       AND project_file LIKE BINARY 'uploads/projects/Cycle3/%');
SET @a_c3_notasks   = (SELECT COUNT(*) FROM projects p WHERE p.cycle_id = @cycle3
                       AND (SELECT COUNT(*) FROM project_tasks t
                            WHERE t.project_id = p.id) = 0);
SET @a_c3_cycles    = (SELECT COUNT(*) FROM cycles WHERE name = 'Cycle 3');
SET @a_c3_active    = (SELECT is_active FROM cycles WHERE name = 'Cycle 3');
SET @a_c1_active    = (SELECT is_active FROM cycles WHERE id = 1);
SET @a_c2_active    = (SELECT IFNULL((SELECT is_active FROM cycles WHERE name = 'Cycle 2'), 0));
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
SET @a_c1_id_sum    = (SELECT SUM(id) FROM projects WHERE cycle_id = 1);
SET @a_c1_t_id_sum  = (SELECT SUM(t.id) FROM project_tasks t JOIN projects p ON p.id = t.project_id WHERE p.cycle_id = 1);
SET @a_c2_projects  = (SELECT COUNT(*) FROM projects p JOIN cycles c ON c.id = p.cycle_id
                       WHERE c.name = 'Cycle 2');
SET @a_c2_tasks     = (SELECT COUNT(*) FROM project_tasks t JOIN projects p ON p.id = t.project_id
                       JOIN cycles c ON c.id = p.cycle_id WHERE c.name = 'Cycle 2');
SET @a_c2_md5       = (SELECT MD5(GROUP_CONCAT(CONCAT_WS('|', p.id, p.grade_id,
                         IFNULL(p.subject_id,'N'), p.project_title, IFNULL(p.duration,''),
                         IFNULL(p.objective,''), IFNULL(p.project_file,''), p.is_active)
                         ORDER BY p.id SEPARATOR '#')) FROM projects p
                       JOIN cycles c ON c.id = p.cycle_id WHERE c.name = 'Cycle 2');
SET @a_c2_task_md5  = (SELECT MD5(GROUP_CONCAT(CONCAT_WS('|', t.id, t.project_id,
                         t.task_number, t.task_type, t.task_description)
                         ORDER BY t.id SEPARATOR '#')) FROM project_tasks t
                       JOIN projects p ON p.id = t.project_id JOIN cycles c ON c.id = p.cycle_id
                       WHERE c.name = 'Cycle 2');
SET @a_c2_id_sum    = (SELECT SUM(p.id) FROM projects p JOIN cycles c ON c.id = p.cycle_id WHERE c.name = 'Cycle 2');
SET @a_c2_t_id_sum  = (SELECT SUM(t.id) FROM project_tasks t JOIN projects p ON p.id = t.project_id
                       JOIN cycles c ON c.id = p.cycle_id WHERE c.name = 'Cycle 2');

-- Cycle 3 content after inserts (includes any pre-existing Cycle 3 rows that
-- NOT EXISTS refused to replace). Must match the workbook-derived set exactly.
SET @a_c3_exact = (SELECT COUNT(*) FROM projects p WHERE p.cycle_id = @cycle3 AND (
    (p.grade_id = 1 AND p.subject_id = 1 AND p.project_title = 'Story Telling with children' AND p.duration = '1 month' AND p.objective = 'Learners move from understanding storytelling as a daily classroom practice to confidently using voice, expressions, questions, and simple props to engage children, while observing how stories nurture language, imagination, participation, and expression.' AND p.project_file = 'uploads/projects/Cycle3/Pre-Primary Teacher (Grade A & B)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 2 AND p.subject_id = 3 AND p.project_title = 'Building speaking skills' AND p.duration = '1 month' AND p.objective = 'Learners move from listening to short lessons, instructions, and poems to confidently answering comprehension questions, following spoken directions, identifying rhyming words, and expanding their vocabulary through collaborative activities.' AND p.project_file = 'uploads/projects/Cycle3/Literacy Teacher (Grade 1, 2 & 3)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 3 AND p.subject_id = 3 AND p.project_title = 'Building speaking skills' AND p.duration = '1 month' AND p.objective = 'Learners move from listening to short lessons, instructions, and poems to confidently answering comprehension questions, following spoken directions, identifying rhyming words, and expanding their vocabulary through collaborative activities.' AND p.project_file = 'uploads/projects/Cycle3/Literacy Teacher (Grade 1, 2 & 3)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 4 AND p.subject_id = 3 AND p.project_title = 'Building speaking skills' AND p.duration = '1 month' AND p.objective = 'Learners move from listening to short lessons, instructions, and poems to confidently answering comprehension questions, following spoken directions, identifying rhyming words, and expanding their vocabulary through collaborative activities.' AND p.project_file = 'uploads/projects/Cycle3/Literacy Teacher (Grade 1, 2 & 3)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 2 AND p.subject_id = 4 AND p.project_title = 'Building numerical skills, shapes,lines & data' AND p.duration = '1 month' AND p.objective = 'Learners move from exploring everyday objects and identifying basic shapes to investigating how objects roll or slide, recognising shapes in their surroundings, and using tally marks, repeated addition, and equal sharing to interpret data and explain their findings.' AND p.project_file = 'uploads/projects/Cycle3/Numeracy (Grade 1, 2 & 3)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 3 AND p.subject_id = 4 AND p.project_title = 'Building numerical skills, shapes,lines & data' AND p.duration = '1 month' AND p.objective = 'Learners move from exploring everyday objects and identifying basic shapes to investigating how objects roll or slide, recognising shapes in their surroundings, and using tally marks, repeated addition, and equal sharing to interpret data and explain their findings.' AND p.project_file = 'uploads/projects/Cycle3/Numeracy (Grade 1, 2 & 3)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 4 AND p.subject_id = 4 AND p.project_title = 'Building numerical skills, shapes,lines & data' AND p.duration = '1 month' AND p.objective = 'Learners move from exploring everyday objects and identifying basic shapes to investigating how objects roll or slide, recognising shapes in their surroundings, and using tally marks, repeated addition, and equal sharing to interpret data and explain their findings.' AND p.project_file = 'uploads/projects/Cycle3/Numeracy (Grade 1, 2 & 3)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 5 AND p.subject_id = 8 AND p.project_title = 'Our Festival Fun Fair' AND p.duration = '1 month' AND p.objective = 'Learners move from reading and understanding the chapter Christmas to exploring a local festival, writing about its significance and traditions, creating related stories and activities, and collaboratively developing and presenting an engaging festival experience corner for visitors.' AND p.project_file = 'uploads/projects/Cycle3/English (Grade 4)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 5 AND p.subject_id = 7 AND p.project_title = 'Fitness challenge' AND p.duration = '1 month' AND p.objective = 'Learners move from exploring fitness through simple body-part tests to collecting and representing data using pictographs and bar graphs, interpreting results, and applying mental maths, estimation, or written calculations to draw meaningful conclusions.' AND p.project_file = 'uploads/projects/Cycle3/Math (Grade 4)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 6 AND p.subject_id = 10 AND p.project_title = 'Act it Out' AND p.duration = '1 month' AND p.objective = 'Learners move from reading and understanding The Farmer and the Well to exploring dialogue, rewriting story endings, and creating original plays, culminating in a collaborative performance that communicates a meaningful message about fairness and reflects on their learning journey.' AND p.project_file = 'uploads/projects/Cycle3/English (Grade 5)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 6 AND p.subject_id = 9 AND p.project_title = 'Naga Stadium' AND p.duration = '1 month' AND p.objective = 'Learners move from exploring traditional Naga games and designing a stadium using fractions to calculating perimeter, area, and construction costs, applying measurement and the four operations to estimate materials and develop a practical stadium plan.' AND p.project_file = 'uploads/projects/Cycle3/Math (Grade 5)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 7 AND p.subject_id = 11 AND p.project_title = 'The Integer Board Game' AND p.duration = '1 month' AND p.objective = 'Learners move from the everyday feeling of climbing up a hill and coming back down to the village to confidently placing, comparing, adding and subtracting integers, culminating in an original integer board game that each group teaches to an audience beyond the teacher.' AND p.project_file = 'uploads/projects/Cycle3/Math (Grade 6)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 8 AND p.subject_id = 13 AND p.project_title = 'Smart Bazaar: Our Village Best Buy Report' AND p.duration = '1 month' AND p.objective = 'Learners move from guessing which packet ''looks'' cheaper at the village bazaar to proving the true best buy with decimal multiplication and division, culminating in a Best Buy Report Board with real prices, shown working and a calculated recommendation presented to the village.' AND p.project_file = 'uploads/projects/Cycle3/Math (Grade 7)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 9 AND p.subject_id = 15 AND p.project_title = 'The Village Data Story' AND p.duration = '1 month' AND p.objective = 'Learners move from sensing that the village market is ''busy'' or ''quiet'' to tracking real numbers over several days, finding the mean and median by hand, and turning the data into a hand-drawn line graph that tells a genuine story about their own village.' AND p.project_file = 'uploads/projects/Cycle3/Math (Grade 8)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 7 AND p.subject_id = 12 AND p.project_title = 'Building Our Village Separation Station' AND p.duration = '1 month' AND p.objective = 'Learners move from watching families clean rice, dal and muddy water at home to naming the method behind each task (handpicking, winnowing, sieving, sedimentation, decantation, filtration, evaporation and magnetic separation), culminating in a live Separation Station with a working water filter run for the village.' AND p.project_file = 'uploads/projects/Cycle3/Science (Grade 6)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 8 AND p.subject_id = 14 AND p.project_title = 'The Bright Room Challenge' AND p.duration = '1 month' AND p.objective = 'Learners move from noticing that a bamboo home or morung stays dark on a bright afternoon to understanding that light travels in straight lines and reflects off a plane mirror, culminating in a model Bright Room with one light-entry hole and two mirrors lighting two dark corners, presented to a real audience.' AND p.project_file = 'uploads/projects/Cycle3/Science (Grade 7)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 9 AND p.subject_id = 16 AND p.project_title = 'Preserve and Protect' AND p.duration = '1 month' AND p.objective = 'Learners move from noticing a cleared hillside or a drying stream to explaining the web of life behind it (biotic and abiotic components, food chains, interdependence), culminating in a Conservation Action Plan for their own village presented to a real audience.' AND p.project_file = 'uploads/projects/Cycle3/Science (Grade 8)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 10 AND p.subject_id IS NULL AND p.project_title = 'Purposeful Community Engagement' AND p.duration = '1 month' AND p.objective = 'Schools move from routine Parent-Teacher Meetings focused on attendance and discipline to meaningful, learning-focused conversations where parents understand their child’s progress, explore ways to support learning at home, and build stronger partnerships with teachers to improve student outcomes.' AND p.project_file = 'uploads/projects/Cycle3/School Leader Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 1 AND p.subject_id = 2 AND p.project_title = 'Collaborative Art Making
Using Textured Materials' AND p.duration = '1 month' AND p.objective = 'To help learners develop collaboration, share space and materials, adapt to challenges, contribute ideas, and build a sense of belonging through shared art activities.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (A & B)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 2 AND p.subject_id = 5 AND p.project_title = 'Exploring Identity and Emotions
Through Colour and Art' AND p.duration = '1 month' AND p.objective = 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 3 AND p.subject_id = 5 AND p.project_title = 'Exploring Identity and Emotions
Through Colour and Art' AND p.duration = '1 month' AND p.objective = 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 4 AND p.subject_id = 5 AND p.project_title = 'Exploring Identity and Emotions
Through Colour and Art' AND p.duration = '1 month' AND p.objective = 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 5 AND p.subject_id = 5 AND p.project_title = 'Exploring Identity and Emotions
Through Colour and Art' AND p.duration = '1 month' AND p.objective = 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 6 AND p.subject_id = 5 AND p.project_title = 'Exploring Identity and Emotions
Through Colour and Art' AND p.duration = '1 month' AND p.objective = 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 7 AND p.subject_id = 6 AND p.project_title = 'Exploring Emotions and Ideas through art' AND p.duration = '1 month' AND p.objective = 'Help learners explore and express ideas through art by experimenting with materials, colours, and forms, reflecting on real-world experiences, revising their work, and creating imaginative artworks beyond realistic representations.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 6-8)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 8 AND p.subject_id = 6 AND p.project_title = 'Exploring Emotions and Ideas through art' AND p.duration = '1 month' AND p.objective = 'Help learners explore and express ideas through art by experimenting with materials, colours, and forms, reflecting on real-world experiences, revising their work, and creating imaginative artworks beyond realistic representations.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 6-8)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 9 AND p.subject_id = 6 AND p.project_title = 'Exploring Emotions and Ideas through art' AND p.duration = '1 month' AND p.objective = 'Help learners explore and express ideas through art by experimenting with materials, colours, and forms, reflecting on real-world experiences, revising their work, and creating imaginative artworks beyond realistic representations.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 6-8)Cycle3.pdf' AND p.is_active = 1)
));
SET @a_c3_unexpected = (SELECT COUNT(*) FROM projects p WHERE p.cycle_id = @cycle3 AND NOT (
    (p.grade_id = 1 AND p.subject_id = 1 AND p.project_title = 'Story Telling with children' AND p.duration = '1 month' AND p.objective = 'Learners move from understanding storytelling as a daily classroom practice to confidently using voice, expressions, questions, and simple props to engage children, while observing how stories nurture language, imagination, participation, and expression.' AND p.project_file = 'uploads/projects/Cycle3/Pre-Primary Teacher (Grade A & B)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 2 AND p.subject_id = 3 AND p.project_title = 'Building speaking skills' AND p.duration = '1 month' AND p.objective = 'Learners move from listening to short lessons, instructions, and poems to confidently answering comprehension questions, following spoken directions, identifying rhyming words, and expanding their vocabulary through collaborative activities.' AND p.project_file = 'uploads/projects/Cycle3/Literacy Teacher (Grade 1, 2 & 3)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 3 AND p.subject_id = 3 AND p.project_title = 'Building speaking skills' AND p.duration = '1 month' AND p.objective = 'Learners move from listening to short lessons, instructions, and poems to confidently answering comprehension questions, following spoken directions, identifying rhyming words, and expanding their vocabulary through collaborative activities.' AND p.project_file = 'uploads/projects/Cycle3/Literacy Teacher (Grade 1, 2 & 3)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 4 AND p.subject_id = 3 AND p.project_title = 'Building speaking skills' AND p.duration = '1 month' AND p.objective = 'Learners move from listening to short lessons, instructions, and poems to confidently answering comprehension questions, following spoken directions, identifying rhyming words, and expanding their vocabulary through collaborative activities.' AND p.project_file = 'uploads/projects/Cycle3/Literacy Teacher (Grade 1, 2 & 3)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 2 AND p.subject_id = 4 AND p.project_title = 'Building numerical skills, shapes,lines & data' AND p.duration = '1 month' AND p.objective = 'Learners move from exploring everyday objects and identifying basic shapes to investigating how objects roll or slide, recognising shapes in their surroundings, and using tally marks, repeated addition, and equal sharing to interpret data and explain their findings.' AND p.project_file = 'uploads/projects/Cycle3/Numeracy (Grade 1, 2 & 3)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 3 AND p.subject_id = 4 AND p.project_title = 'Building numerical skills, shapes,lines & data' AND p.duration = '1 month' AND p.objective = 'Learners move from exploring everyday objects and identifying basic shapes to investigating how objects roll or slide, recognising shapes in their surroundings, and using tally marks, repeated addition, and equal sharing to interpret data and explain their findings.' AND p.project_file = 'uploads/projects/Cycle3/Numeracy (Grade 1, 2 & 3)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 4 AND p.subject_id = 4 AND p.project_title = 'Building numerical skills, shapes,lines & data' AND p.duration = '1 month' AND p.objective = 'Learners move from exploring everyday objects and identifying basic shapes to investigating how objects roll or slide, recognising shapes in their surroundings, and using tally marks, repeated addition, and equal sharing to interpret data and explain their findings.' AND p.project_file = 'uploads/projects/Cycle3/Numeracy (Grade 1, 2 & 3)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 5 AND p.subject_id = 8 AND p.project_title = 'Our Festival Fun Fair' AND p.duration = '1 month' AND p.objective = 'Learners move from reading and understanding the chapter Christmas to exploring a local festival, writing about its significance and traditions, creating related stories and activities, and collaboratively developing and presenting an engaging festival experience corner for visitors.' AND p.project_file = 'uploads/projects/Cycle3/English (Grade 4)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 5 AND p.subject_id = 7 AND p.project_title = 'Fitness challenge' AND p.duration = '1 month' AND p.objective = 'Learners move from exploring fitness through simple body-part tests to collecting and representing data using pictographs and bar graphs, interpreting results, and applying mental maths, estimation, or written calculations to draw meaningful conclusions.' AND p.project_file = 'uploads/projects/Cycle3/Math (Grade 4)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 6 AND p.subject_id = 10 AND p.project_title = 'Act it Out' AND p.duration = '1 month' AND p.objective = 'Learners move from reading and understanding The Farmer and the Well to exploring dialogue, rewriting story endings, and creating original plays, culminating in a collaborative performance that communicates a meaningful message about fairness and reflects on their learning journey.' AND p.project_file = 'uploads/projects/Cycle3/English (Grade 5)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 6 AND p.subject_id = 9 AND p.project_title = 'Naga Stadium' AND p.duration = '1 month' AND p.objective = 'Learners move from exploring traditional Naga games and designing a stadium using fractions to calculating perimeter, area, and construction costs, applying measurement and the four operations to estimate materials and develop a practical stadium plan.' AND p.project_file = 'uploads/projects/Cycle3/Math (Grade 5)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 7 AND p.subject_id = 11 AND p.project_title = 'The Integer Board Game' AND p.duration = '1 month' AND p.objective = 'Learners move from the everyday feeling of climbing up a hill and coming back down to the village to confidently placing, comparing, adding and subtracting integers, culminating in an original integer board game that each group teaches to an audience beyond the teacher.' AND p.project_file = 'uploads/projects/Cycle3/Math (Grade 6)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 8 AND p.subject_id = 13 AND p.project_title = 'Smart Bazaar: Our Village Best Buy Report' AND p.duration = '1 month' AND p.objective = 'Learners move from guessing which packet ''looks'' cheaper at the village bazaar to proving the true best buy with decimal multiplication and division, culminating in a Best Buy Report Board with real prices, shown working and a calculated recommendation presented to the village.' AND p.project_file = 'uploads/projects/Cycle3/Math (Grade 7)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 9 AND p.subject_id = 15 AND p.project_title = 'The Village Data Story' AND p.duration = '1 month' AND p.objective = 'Learners move from sensing that the village market is ''busy'' or ''quiet'' to tracking real numbers over several days, finding the mean and median by hand, and turning the data into a hand-drawn line graph that tells a genuine story about their own village.' AND p.project_file = 'uploads/projects/Cycle3/Math (Grade 8)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 7 AND p.subject_id = 12 AND p.project_title = 'Building Our Village Separation Station' AND p.duration = '1 month' AND p.objective = 'Learners move from watching families clean rice, dal and muddy water at home to naming the method behind each task (handpicking, winnowing, sieving, sedimentation, decantation, filtration, evaporation and magnetic separation), culminating in a live Separation Station with a working water filter run for the village.' AND p.project_file = 'uploads/projects/Cycle3/Science (Grade 6)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 8 AND p.subject_id = 14 AND p.project_title = 'The Bright Room Challenge' AND p.duration = '1 month' AND p.objective = 'Learners move from noticing that a bamboo home or morung stays dark on a bright afternoon to understanding that light travels in straight lines and reflects off a plane mirror, culminating in a model Bright Room with one light-entry hole and two mirrors lighting two dark corners, presented to a real audience.' AND p.project_file = 'uploads/projects/Cycle3/Science (Grade 7)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 9 AND p.subject_id = 16 AND p.project_title = 'Preserve and Protect' AND p.duration = '1 month' AND p.objective = 'Learners move from noticing a cleared hillside or a drying stream to explaining the web of life behind it (biotic and abiotic components, food chains, interdependence), culminating in a Conservation Action Plan for their own village presented to a real audience.' AND p.project_file = 'uploads/projects/Cycle3/Science (Grade 8)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 10 AND p.subject_id IS NULL AND p.project_title = 'Purposeful Community Engagement' AND p.duration = '1 month' AND p.objective = 'Schools move from routine Parent-Teacher Meetings focused on attendance and discipline to meaningful, learning-focused conversations where parents understand their child’s progress, explore ways to support learning at home, and build stronger partnerships with teachers to improve student outcomes.' AND p.project_file = 'uploads/projects/Cycle3/School Leader Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 1 AND p.subject_id = 2 AND p.project_title = 'Collaborative Art Making
Using Textured Materials' AND p.duration = '1 month' AND p.objective = 'To help learners develop collaboration, share space and materials, adapt to challenges, contribute ideas, and build a sense of belonging through shared art activities.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (A & B)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 2 AND p.subject_id = 5 AND p.project_title = 'Exploring Identity and Emotions
Through Colour and Art' AND p.duration = '1 month' AND p.objective = 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 3 AND p.subject_id = 5 AND p.project_title = 'Exploring Identity and Emotions
Through Colour and Art' AND p.duration = '1 month' AND p.objective = 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 4 AND p.subject_id = 5 AND p.project_title = 'Exploring Identity and Emotions
Through Colour and Art' AND p.duration = '1 month' AND p.objective = 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 5 AND p.subject_id = 5 AND p.project_title = 'Exploring Identity and Emotions
Through Colour and Art' AND p.duration = '1 month' AND p.objective = 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 6 AND p.subject_id = 5 AND p.project_title = 'Exploring Identity and Emotions
Through Colour and Art' AND p.duration = '1 month' AND p.objective = 'Help learners express feelings and personal experiences through art, explore how colours and images communicate meaning, and develop the ability to observe, interpret, and appreciate the artwork of others.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 1-5)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 7 AND p.subject_id = 6 AND p.project_title = 'Exploring Emotions and Ideas through art' AND p.duration = '1 month' AND p.objective = 'Help learners explore and express ideas through art by experimenting with materials, colours, and forms, reflecting on real-world experiences, revising their work, and creating imaginative artworks beyond realistic representations.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 6-8)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 8 AND p.subject_id = 6 AND p.project_title = 'Exploring Emotions and Ideas through art' AND p.duration = '1 month' AND p.objective = 'Help learners explore and express ideas through art by experimenting with materials, colours, and forms, reflecting on real-world experiences, revising their work, and creating imaginative artworks beyond realistic representations.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 6-8)Cycle3.pdf' AND p.is_active = 1)
    OR (p.grade_id = 9 AND p.subject_id = 6 AND p.project_title = 'Exploring Emotions and Ideas through art' AND p.duration = '1 month' AND p.objective = 'Help learners explore and express ideas through art by experimenting with materials, colours, and forms, reflecting on real-world experiences, revising their work, and creating imaginative artworks beyond realistic representations.' AND p.project_file = 'uploads/projects/Cycle3/Arts Teacher (Grade 6-8)Cycle3.pdf' AND p.is_active = 1)
));
-- Per-project task-count deviation: 0 means every project has exactly the
-- number of tasks the workbook supplies for it.
SET @a_c3_task_dev = (SELECT COALESCE(SUM(ABS(delta)),0) FROM (
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 1 AND p.subject_id = 1
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 2 AND p.subject_id = 3
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 3 AND p.subject_id = 3
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 4 AND p.subject_id = 3
UNION ALL
SELECT 7 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 2 AND p.subject_id = 4
UNION ALL
SELECT 7 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 3 AND p.subject_id = 4
UNION ALL
SELECT 7 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 4 AND p.subject_id = 4
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 5 AND p.subject_id = 8
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 5 AND p.subject_id = 7
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 6 AND p.subject_id = 10
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 6 AND p.subject_id = 9
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 7 AND p.subject_id = 11
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 8 AND p.subject_id = 13
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 9 AND p.subject_id = 15
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 7 AND p.subject_id = 12
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 8 AND p.subject_id = 14
UNION ALL
SELECT 5 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 9 AND p.subject_id = 16
UNION ALL
SELECT 7 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 10 AND p.subject_id IS NULL
UNION ALL
SELECT 6 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 1 AND p.subject_id = 2
UNION ALL
SELECT 8 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 2 AND p.subject_id = 5
UNION ALL
SELECT 8 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 3 AND p.subject_id = 5
UNION ALL
SELECT 8 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 4 AND p.subject_id = 5
UNION ALL
SELECT 8 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 5 AND p.subject_id = 5
UNION ALL
SELECT 8 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 6 AND p.subject_id = 5
UNION ALL
SELECT 8 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 7 AND p.subject_id = 6
UNION ALL
SELECT 8 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 8 AND p.subject_id = 6
UNION ALL
SELECT 8 - (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS delta FROM projects p WHERE p.cycle_id = @cycle3 AND p.grade_id = 9 AND p.subject_id = 6
) AS task_dev);

SET @a_c3_proj_md5 = (SELECT MD5(GROUP_CONCAT(CONCAT_WS('|', grade_id,
                         IFNULL(subject_id,'N'), project_title, IFNULL(duration,''),
                         IFNULL(objective,''), IFNULL(project_file,''), is_active)
                         ORDER BY grade_id, IFNULL(subject_id,0), project_title SEPARATOR '#'))
                      FROM projects WHERE cycle_id = @cycle3);
SET @a_c3_task_md5 = (SELECT MD5(GROUP_CONCAT(CONCAT_WS('|', p.grade_id,
                         IFNULL(p.subject_id,'N'), t.task_number, t.task_type, t.task_description)
                         ORDER BY p.grade_id, IFNULL(p.subject_id,0), t.task_number SEPARATOR '#'))
                      FROM project_tasks t
                      JOIN projects p ON p.id = t.project_id
                      WHERE p.cycle_id = @cycle3);

-- Embedded expected hashes of the 27 projects / 168 tasks in this file.
-- Recomputed from the INSERT literals (utf8). If you edit an INSERT, recompute.
SET @exp_c3_proj_md5 = '446ecb8671ed8034c3155839fa6e418b';
SET @exp_c3_task_md5 = 'c2787fe1b0f6c77b07c07b54edd3e2fa';

SELECT 'Cycle 1 still active'            AS check_name, @a_c1_active, 1, IF(@a_c1_active=1,'PASS','FAIL') AS result
UNION ALL SELECT 'Cycle 2 still active',             @a_c2_active, 1, IF(@a_c2_active=1,'PASS','FAIL')
UNION ALL SELECT 'Cycle 3 cycle row = 1',            @a_c3_cycles, 1, IF(@a_c3_cycles=1,'PASS','FAIL')
UNION ALL SELECT 'Cycle 3 is active',                @a_c3_active, 1, IF(@a_c3_active=1,'PASS','FAIL')
UNION ALL SELECT 'Cycle 3 projects = 27',            @a_c3_projects, 27, IF(@a_c3_projects=27,'PASS','FAIL')
UNION ALL SELECT 'Cycle 3 tasks = 168',              @a_c3_tasks, 168, IF(@a_c3_tasks=168,'PASS','FAIL')
UNION ALL SELECT 'Cycle 3 files under Cycle3/ = 27', @a_c3_files, 27, IF(@a_c3_files=27,'PASS','FAIL')
UNION ALL SELECT 'Cycle 3 projects with no task = 0',@a_c3_notasks, 0, IF(@a_c3_notasks=0,'PASS','FAIL')
UNION ALL SELECT 'Cycle 3 rows matching workbook',   @a_c3_exact, 27, IF(@a_c3_exact=27,'PASS','FAIL')
UNION ALL SELECT 'Cycle 3 unexpected rows = 0',      @a_c3_unexpected, 0, IF(@a_c3_unexpected=0,'PASS','FAIL')
UNION ALL SELECT 'Cycle 3 task-count deviation = 0', @a_c3_task_dev, 0, IF(@a_c3_task_dev=0,'PASS','FAIL')
UNION ALL SELECT 'Cycle 3 project content hash',     0, 0, IF(@a_c3_proj_md5 <=> @exp_c3_proj_md5,'PASS','FAIL')
UNION ALL SELECT 'Cycle 3 task content hash',        0, 0, IF(@a_c3_task_md5 <=> @exp_c3_task_md5,'PASS','FAIL')
UNION ALL SELECT 'cycles row count correct',         @a_cycles, @b_cycles+(1-@b_c3_cycles), IF(@a_cycles=@b_cycles+(1-@b_c3_cycles),'PASS','FAIL')
UNION ALL SELECT 'grades unchanged',                 @a_grades, @b_grades, IF(@a_grades=@b_grades,'PASS','FAIL')
UNION ALL SELECT 'subjects unchanged',               @a_subjects, @b_subjects, IF(@a_subjects=@b_subjects,'PASS','FAIL')
UNION ALL SELECT 'grade_subject_map unchanged',      @a_gsmap, @b_gsmap, IF(@a_gsmap=@b_gsmap,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 projects unchanged',       @a_c1_projects, @b_c1_projects, IF(@a_c1_projects=@b_c1_projects,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 tasks unchanged',          @a_c1_tasks, @b_c1_tasks, IF(@a_c1_tasks=@b_c1_tasks,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 project content hash',     0, 0, IF(@a_c1_md5 <=> @b_c1_md5,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 task content hash',        0, 0, IF(@a_c1_task_md5 <=> @b_c1_task_md5,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 project id sum',           @a_c1_id_sum, @b_c1_id_sum, IF(@a_c1_id_sum <=> @b_c1_id_sum,'PASS','FAIL')
UNION ALL SELECT 'Cycle 1 task id sum',              @a_c1_t_id_sum, @b_c1_t_id_sum, IF(@a_c1_t_id_sum <=> @b_c1_t_id_sum,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 projects unchanged',       @a_c2_projects, @b_c2_projects, IF(@a_c2_projects=@b_c2_projects,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 tasks unchanged',          @a_c2_tasks, @b_c2_tasks, IF(@a_c2_tasks=@b_c2_tasks,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 project content hash',     0, 0, IF(@a_c2_md5 <=> @b_c2_md5,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 task content hash',        0, 0, IF(@a_c2_task_md5 <=> @b_c2_task_md5,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 project id sum',           @a_c2_id_sum, @b_c2_id_sum, IF(@a_c2_id_sum <=> @b_c2_id_sum,'PASS','FAIL')
UNION ALL SELECT 'Cycle 2 task id sum',              @a_c2_t_id_sum, @b_c2_t_id_sum, IF(@a_c2_t_id_sum <=> @b_c2_t_id_sum,'PASS','FAIL');

-- Submission / response / evidence counts are reported but are NOT part of
-- the commit predicate: a teacher submitting during this short transaction
-- must not abort a correct catalog import, and this script never writes
-- to those tables.
SELECT 'submissions delta (info only)' AS check_name,
       (SELECT COUNT(*) FROM teacher_submissions) AS actual,
       @b_submissions AS baseline, 'INFO' AS result
UNION ALL SELECT 'task_responses delta (info only)',
       (SELECT COUNT(*) FROM task_responses), @b_responses, 'INFO'
UNION ALL SELECT 'submission_evidence delta (info only)',
       (SELECT COUNT(*) FROM submission_evidence), @b_evidence, 'INFO';

SET @import_ok = (
        @a_c1_active    = 1
    AND @a_c2_active    = 1
    AND @a_c3_cycles    = 1
    AND @a_c3_active    = 1
    AND @a_c3_projects  = 27
    AND @a_c3_tasks     = 168
    AND @a_c3_files     = 27
    AND @a_c3_notasks   = 0
    AND @a_c3_exact     = 27
    AND @a_c3_unexpected= 0
    AND @a_c3_task_dev  = 0
    AND @a_c3_proj_md5  <=> @exp_c3_proj_md5
    AND @a_c3_task_md5  <=> @exp_c3_task_md5
    AND @a_cycles       = @b_cycles + (1 - @b_c3_cycles)
    AND (@b_c3_projects = 0 OR (@b_c3_projects = 27 AND @b_c3_tasks = 168 AND @b_c3_active = 1))
    AND @a_grades       = @b_grades
    AND @a_subjects     = @b_subjects
    AND @a_gsmap        = @b_gsmap
    AND @a_c1_projects  = @b_c1_projects
    AND @a_c1_tasks     = @b_c1_tasks
    AND @a_c1_md5       <=> @b_c1_md5
    AND @a_c1_task_md5  <=> @b_c1_task_md5
    AND @a_c1_id_sum    <=> @b_c1_id_sum
    AND @a_c1_t_id_sum  <=> @b_c1_t_id_sum
    AND @a_c2_projects  = @b_c2_projects
    AND @a_c2_tasks     = @b_c2_tasks
    AND @a_c2_md5       <=> @b_c2_md5
    AND @a_c2_task_md5  <=> @b_c2_task_md5
    AND @a_c2_id_sum    <=> @b_c2_id_sum
    AND @a_c2_t_id_sum  <=> @b_c2_t_id_sum
);

-- Commit or roll back INSIDE this session. There is no unconditional COMMIT
-- later in the file, so a client that continues after an error cannot
-- accidentally persist a failed import.
SET @finish_sql = IF(@import_ok, 'COMMIT', 'ROLLBACK');
PREPARE cycle3_finish FROM @finish_sql;
EXECUTE cycle3_finish;
DEALLOCATE PREPARE cycle3_finish;
