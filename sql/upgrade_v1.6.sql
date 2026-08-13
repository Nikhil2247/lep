-- ============================================================
-- LEP Version 1.6 – Full Cycle 1 Subject/Project/Task Master
-- Source: LEP_Cycle1_Final_Master_Projects_Tasks.xlsx
-- ============================================================

USE lep_nagaland;

-- ------------------------------------------------------------
-- 0. One-time cleanup of development test submissions
--    (only runs if total submissions <= 10 to avoid wiping real data)
-- ------------------------------------------------------------
SET @sub_count = (SELECT COUNT(*) FROM teacher_submissions);
-- Delete dependent rows first
DELETE FROM submission_evidence WHERE @sub_count > 0 AND @sub_count <= 10;
DELETE FROM task_responses WHERE @sub_count > 0 AND @sub_count <= 10;
DELETE FROM teacher_submissions WHERE @sub_count > 0 AND @sub_count <= 10;

-- ------------------------------------------------------------
-- 1. Schema: task_type on project_tasks; duration/objective if missing
-- ------------------------------------------------------------
SET @c = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME='project_tasks' AND COLUMN_NAME='task_type');
SET @sql = IF(@c=0,
  'ALTER TABLE project_tasks ADD COLUMN task_type VARCHAR(20) NOT NULL DEFAULT ''Task'' AFTER task_number',
  'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

SET @c = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME='projects' AND COLUMN_NAME='duration');
SET @sql = IF(@c=0,
  'ALTER TABLE projects ADD COLUMN duration VARCHAR(50) DEFAULT NULL AFTER project_title',
  'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

SET @c = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME='projects' AND COLUMN_NAME='objective');
SET @sql = IF(@c=0,
  'ALTER TABLE projects ADD COLUMN objective TEXT DEFAULT NULL AFTER duration',
  'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ------------------------------------------------------------
-- 2. Subjects: rename, create grade-specific, deactivate broad
-- ------------------------------------------------------------

-- Rename Art Education → Arts Teacher (Grade 6-8) if exists
UPDATE subjects SET name = 'Arts Teacher (Grade 6-8)'
WHERE name = 'Art Education (Grade 6-8)';

-- Ensure grouped subjects exist
INSERT INTO subjects (name, sort_order, is_active)
SELECT v.name, v.ord, 1 FROM (
  SELECT 'Pre-Primary Teacher (Grade A & B)' AS name, 1 AS ord UNION ALL
  SELECT 'Arts Teacher (A & B)', 2 UNION ALL
  SELECT 'Literacy Teacher (Grade 1, 2 & 3)', 3 UNION ALL
  SELECT 'Numeracy Teacher (Grade 1, 2 & 3)', 4 UNION ALL
  SELECT 'Arts Teacher (Grade 1-5)', 5 UNION ALL
  SELECT 'Arts Teacher (Grade 6-8)', 10
) v
WHERE NOT EXISTS (SELECT 1 FROM subjects s WHERE s.name = v.name);

-- Create grade-specific subjects
INSERT INTO subjects (name, sort_order, is_active)
SELECT v.name, v.ord, 1 FROM (
  SELECT 'Math (Grade 4)' AS name, 20 AS ord UNION ALL
  SELECT 'English (Grade 4)', 21 UNION ALL
  SELECT 'Math (Grade 5)', 22 UNION ALL
  SELECT 'English (Grade 5)', 23 UNION ALL
  SELECT 'Math (Grade 6)', 24 UNION ALL
  SELECT 'Science (Grade 6)', 25 UNION ALL
  SELECT 'Math (Grade 7)', 26 UNION ALL
  SELECT 'Science (Grade 7)', 27 UNION ALL
  SELECT 'Math (Grade 8)', 28 UNION ALL
  SELECT 'Science (Grade 8)', 29
) v
WHERE NOT EXISTS (SELECT 1 FROM subjects s WHERE s.name = v.name);

-- Deactivate old broad subjects (preserve rows for history)
UPDATE subjects SET is_active = 0
WHERE name IN ('Math (4,5)', 'English (4,5)', 'Math (6,7,8)', 'Science (6,7,8)',
               'Mathematics', 'English', 'Science', 'Environmental Studies (EVS)',
               'Social Science', 'Language (Mother Tongue)');

-- ------------------------------------------------------------
-- 3. Rebuild grade_subject_map for Cycle 1 structure
-- ------------------------------------------------------------
DELETE FROM grade_subject_map;

INSERT INTO grade_subject_map (grade_id, subject_id)
SELECT g.id, s.id FROM grades g, subjects s WHERE g.name='Pre-Primary (A-B)' AND s.name='Pre-Primary Teacher (Grade A & B)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name='Pre-Primary (A-B)' AND s.name='Arts Teacher (A & B)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name IN ('Grade 1','Grade 2','Grade 3') AND s.name='Literacy Teacher (Grade 1, 2 & 3)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name IN ('Grade 1','Grade 2','Grade 3') AND s.name='Numeracy Teacher (Grade 1, 2 & 3)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name IN ('Grade 1','Grade 2','Grade 3','Grade 4','Grade 5') AND s.name='Arts Teacher (Grade 1-5)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name='Grade 4' AND s.name='Math (Grade 4)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name='Grade 4' AND s.name='English (Grade 4)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name='Grade 5' AND s.name='Math (Grade 5)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name='Grade 5' AND s.name='English (Grade 5)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name='Grade 6' AND s.name='Math (Grade 6)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name='Grade 6' AND s.name='Science (Grade 6)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name='Grade 7' AND s.name='Math (Grade 7)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name='Grade 7' AND s.name='Science (Grade 7)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name='Grade 8' AND s.name='Math (Grade 8)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name='Grade 8' AND s.name='Science (Grade 8)'
UNION ALL SELECT g.id, s.id FROM grades g, subjects s WHERE g.name IN ('Grade 6','Grade 7','Grade 8') AND s.name='Arts Teacher (Grade 6-8)';

-- ------------------------------------------------------------
-- 4. Clear existing Cycle 1 projects/tasks (replaced by official master)
--    Does not touch submissions (already cleaned if test-only)
-- ------------------------------------------------------------
DELETE pt FROM project_tasks pt
INNER JOIN projects p ON p.id = pt.project_id
INNER JOIN cycles c ON c.id = p.cycle_id
WHERE c.name = 'Cycle 1';

DELETE p FROM projects p
INNER JOIN cycles c ON c.id = p.cycle_id
WHERE c.name = 'Cycle 1';



SET @cycle1 = (SELECT id FROM cycles WHERE name = 'Cycle 1' LIMIT 1);


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, NULL, @cycle1, 'Setting Direction – School Vision & Priority Goals', '1 Month', 'To establish clear, shared school priorities that guide teaching, learning, and improvement efforts.',
       'uploads/projects/Revised_LNF_4.0_Cycle-1_School_Leader.pdf', 1
FROM grades g
WHERE g.name = 'School Leaders'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id IS NULL AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  WHERE g.name = 'School Leaders' AND p.subject_id IS NULL AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Conduct a staff reflection meeting on current school status (learning levels, attendance, engagement).', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Identify 2–3 priority areas (e.g., reading, math, student participation, etc.).', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Co-create simple, measurable school goals for the academic year.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Break goals into term-wise focus areas.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Display goals visibly (staff room/classrooms) for constant reference.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Communicate priorities to students and parents (assembly/PTM).', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 7, 'Task', 'Review progress once every month in staff meetings.', 7, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 7
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Classroom Arrangement: Building a Supportive Learning Space', '1 month', 'Teachers will enhance the quality of early learning experiences, identifying improvement areas, organizing learning spaces effectively, implementing developmentally appropriate activities, and observing and reflecting on children’s play and learning.',
       'uploads/projects/Pre_Primary_Teacher_Grade_A_B_Cycle_1.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Pre-Primary (A-B)' AND s.name = 'Pre-Primary Teacher (Grade A & B)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Pre-Primary (A-B)' AND s.name = 'Pre-Primary Teacher (Grade A & B)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Enagage with the ideal ECCE strategy document.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Plan and conduct a classroom diagnostic using the checklist and identify three areas for improvement.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Organise your classroom using the IDEAL ECCE classroom arrangement.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Conduct activities using the classroom setup and upload photos of children participating.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Observe classroom play and share moments and stories of children.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Sensory Exploration for Fine Motor Development', '1 month', 'Strengthen development of fine motor skills - hand strength, finger movement, and hand-eye coordination - in learners by engaging them in movement-based art activities using yarn and clay.',
       'uploads/projects/Arts_Teacher_A_B_Cycle_1.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Pre-Primary (A-B)' AND s.name = 'Arts Teacher (A & B)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Pre-Primary (A-B)' AND s.name = 'Arts Teacher (A & B)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Conduct Activity 1: Yarn Stick — Students play with yarn and explore different ways to wrap, twist, and weave it around sticks.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Conduct Activity 2: Clay Molding — Students play with clay and experiment with different molding techniques.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Observe & Track Student Progress', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ fine motor skills.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Listening and Speaking: Opportunitites for All', '1 month', 'Teacher will be able to provide daily opportunities for all students to listen, speak, and express ideas confidently during regular classroom teaching.',
       'uploads/projects/Revised_LNF_4.0_Cycle-1_Literacy_Teacher.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 1' AND s.name = 'Literacy Teacher (Grade 1, 2 & 3)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 1' AND s.name = 'Literacy Teacher (Grade 1, 2 & 3)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Observe how students listen and speak during regular classroom interactions.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Plan a fixed daily 10–15 minute time for listening and speaking using textbook stories and poems.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Arrange the classroom space and set simple listening–speaking rules to encourage participation.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Conduct daily read-alouds, recitations, and guided classroom talk with all students.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Assess student participation and speaking progress through simple oral observation.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Reflect on what worked well and what can be improved for better engagement.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Listening and Speaking: Opportunitites for All', '1 month', 'Teacher will be able to provide daily opportunities for all students to listen, speak, and express ideas confidently during regular classroom teaching.',
       'uploads/projects/Revised_LNF_4.0_Cycle-1_Literacy_Teacher.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 2' AND s.name = 'Literacy Teacher (Grade 1, 2 & 3)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 2' AND s.name = 'Literacy Teacher (Grade 1, 2 & 3)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Observe how students listen and speak during regular classroom interactions.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Plan a fixed daily 10–15 minute time for listening and speaking using textbook stories and poems.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Arrange the classroom space and set simple listening–speaking rules to encourage participation.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Conduct daily read-alouds, recitations, and guided classroom talk with all students.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Assess student participation and speaking progress through simple oral observation.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Reflect on what worked well and what can be improved for better engagement.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Listening and Speaking: Opportunitites for All', '1 month', 'Teacher will be able to provide daily opportunities for all students to listen, speak, and express ideas confidently during regular classroom teaching.',
       'uploads/projects/Revised_LNF_4.0_Cycle-1_Literacy_Teacher.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 3' AND s.name = 'Literacy Teacher (Grade 1, 2 & 3)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 3' AND s.name = 'Literacy Teacher (Grade 1, 2 & 3)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Observe how students listen and speak during regular classroom interactions.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Plan a fixed daily 10–15 minute time for listening and speaking using textbook stories and poems.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Arrange the classroom space and set simple listening–speaking rules to encourage participation.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Conduct daily read-alouds, recitations, and guided classroom talk with all students.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Assess student participation and speaking progress through simple oral observation.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Reflect on what worked well and what can be improved for better engagement.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Building Number Sense', '1 month', 'Teacher will be able to build number sense through concrete experiences and real-life contexts, helping children connect numbers with quantities and everyday situations.',
       'uploads/projects/Revised_LNF_4.0_Cycle-1_Numeracy_Teacher.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 1' AND s.name = 'Numeracy Teacher (Grade 1, 2 & 3)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 1' AND s.name = 'Numeracy Teacher (Grade 1, 2 & 3)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Observe how students count, recognise numbers, and compare quantities during daily activities.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Plan daily number-sense routines using objects, stories, and real-life examples.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Arrange materials like seeds, stones, sticks, and classroom objects for counting and grouping.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Conduct daily oral number talks and activities using real objects.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Reflect on students’ understanding of number quantities and their ability to compare.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Building Number Sense', '1 month', 'Teacher will be able to build number sense through concrete experiences and real-life contexts, helping children connect numbers with quantities and everyday situations.',
       'uploads/projects/Revised_LNF_4.0_Cycle-1_Numeracy_Teacher.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 2' AND s.name = 'Numeracy Teacher (Grade 1, 2 & 3)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 2' AND s.name = 'Numeracy Teacher (Grade 1, 2 & 3)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Observe how students count, recognise numbers, and compare quantities during daily activities.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Plan daily number-sense routines using objects, stories, and real-life examples.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Arrange materials like seeds, stones, sticks, and classroom objects for counting and grouping.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Conduct daily oral number talks and activities using real objects.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Reflect on students’ understanding of number quantities and their ability to compare.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Building Number Sense', '1 month', 'Teacher will be able to build number sense through concrete experiences and real-life contexts, helping children connect numbers with quantities and everyday situations.',
       'uploads/projects/Revised_LNF_4.0_Cycle-1_Numeracy_Teacher.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 3' AND s.name = 'Numeracy Teacher (Grade 1, 2 & 3)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 3' AND s.name = 'Numeracy Teacher (Grade 1, 2 & 3)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Observe how students count, recognise numbers, and compare quantities during daily activities.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Plan daily number-sense routines using objects, stories, and real-life examples.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Arrange materials like seeds, stones, sticks, and classroom objects for counting and grouping.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Conduct daily oral number talks and activities using real objects.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Reflect on students’ understanding of number quantities and their ability to compare.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Building Self-Awareness Using Visual Art', '1 month', 'Support the development of self-awareness by enabling learners to recognize and express their feelings, ideas, and identity through portrait drawing, food/culture, and symbolic art-making.',
       'uploads/projects/Arts_Teacher_Grade_1_5_Cycle_1.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 1' AND s.name = 'Arts Teacher (Grade 1-5)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 1' AND s.name = 'Arts Teacher (Grade 1-5)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Conduct Activity 1: Self-Portrait — Students create a self-portrait to express what makes them special. Students create a head to toe self-portrait to express what makes them special.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Conduct Activity 2: Favourite food — Students create a paper collage of your favourite fruit or vegetable. Students create a plate of their favourite food items to show what they enjoy eating.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Observe & Track Student Progress', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ self-awareness.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Building Self-Awareness Using Visual Art', '1 month', 'Support the development of self-awareness by enabling learners to recognize and express their feelings, ideas, and identity through portrait drawing, food/culture, and symbolic art-making.',
       'uploads/projects/Arts_Teacher_Grade_1_5_Cycle_1.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 2' AND s.name = 'Arts Teacher (Grade 1-5)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 2' AND s.name = 'Arts Teacher (Grade 1-5)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Conduct Activity 1: Self-Portrait — Students create a self-portrait to express what makes them special. Students create a head to toe self-portrait to express what makes them special.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Conduct Activity 2: Favourite food — Students create a paper collage of your favourite fruit or vegetable. Students create a plate of their favourite food items to show what they enjoy eating.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Observe & Track Student Progress', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ self-awareness.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Building Self-Awareness Using Visual Art', '1 month', 'Support the development of self-awareness by enabling learners to recognize and express their feelings, ideas, and identity through portrait drawing, food/culture, and symbolic art-making.',
       'uploads/projects/Arts_Teacher_Grade_1_5_Cycle_1.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 3' AND s.name = 'Arts Teacher (Grade 1-5)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 3' AND s.name = 'Arts Teacher (Grade 1-5)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Conduct Activity 1: Self-Portrait — Students create a self-portrait to express what makes them special. Students create a head to toe self-portrait to express what makes them special.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Conduct Activity 2: Favourite food — Students create a paper collage of your favourite fruit or vegetable. Students create a plate of their favourite food items to show what they enjoy eating.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Observe & Track Student Progress', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ self-awareness.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Building Self-Awareness Using Visual Art', '1 month', 'Support the development of self-awareness by enabling learners to recognize and express their feelings, ideas, and identity through portrait drawing, food/culture, and symbolic art-making.',
       'uploads/projects/Arts_Teacher_Grade_1_5_Cycle_1.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 4' AND s.name = 'Arts Teacher (Grade 1-5)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 4' AND s.name = 'Arts Teacher (Grade 1-5)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Conduct Activity 1: Self-Portrait — Students create a self-portrait to express what makes them special. Students create a head to toe self-portrait to express what makes them special.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Conduct Activity 2: Favourite food — Students create a paper collage of your favourite fruit or vegetable. Students create a plate of their favourite food items to show what they enjoy eating.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Observe & Track Student Progress', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ self-awareness.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Building Self-Awareness Using Visual Art', '1 month', 'Support the development of self-awareness by enabling learners to recognize and express their feelings, ideas, and identity through portrait drawing, food/culture, and symbolic art-making.',
       'uploads/projects/Arts_Teacher_Grade_1_5_Cycle_1.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 5' AND s.name = 'Arts Teacher (Grade 1-5)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 5' AND s.name = 'Arts Teacher (Grade 1-5)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Conduct Activity 1: Self-Portrait — Students create a self-portrait to express what makes them special. Students create a head to toe self-portrait to express what makes them special.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Conduct Activity 2: Favourite food — Students create a paper collage of your favourite fruit or vegetable. Students create a plate of their favourite food items to show what they enjoy eating.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Observe & Track Student Progress', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ self-awareness.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Animal Shelters (Class 4)', '1 week', 'Teacher will guide learners in designing and building models of animal shelters by applying simple fractions to divide land into sections, and planning features that support animal well-being.',
       'uploads/projects/Animal_Shelters_MIP_Nagaland_Grade4.docx.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 4' AND s.name = 'Math (Grade 4)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 4' AND s.name = 'Math (Grade 4)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Read the attached learning resource. Introduce the project to students and set classroom norms for group work and participation.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Day 1 Guide students begin planning their animal shelters and explore fractions as a way to divide the shelter plot into different areas.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Day 2 Help learners apply fractions to divide the shelter plot into different areas and plan the spaces for their animal shelters.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Day 3 Support students in finalising their shelter designs based on peer feedback and check if any key areas in their shelter plots represent common fractions.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Day 4 Guide students to work in groups and design model shelters.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Day 5 Facilitate group presentation and reflection excerise in the classroom.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 7, 'Task', 'Assess the students'' work and presentation based on the assessment criteria.', 7, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 7
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Shawls of Identity (Class 5)', '1 week', 'Teachers will introduce students to traditional Naga shawls and guide them to apply concepts of fractions and decimals to design shawls.',
       'uploads/projects/Shawls_of_Identity_MIP_Nagaland_Grade5 (1).pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 5' AND s.name = 'Math (Grade 5)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 5' AND s.name = 'Math (Grade 5)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Read the attached learning resource. Introduce the project to students and set classroom norms for group work and participation.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Day 1 Guide students to explore shawl designs from different Naga tribes and fill observation tables.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Day 2 Support students to design shawls on a 20×5 grid and calculate the space occupied by each colour using fractions.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Day 3 Teach conversion of fractions into decimals. Guide groups to compare colour usage using decimal numbers and give peer feedback.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Day 4 Guide students to revise shawl designs based on peer feedback and plan for the art gallery presentation.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Day 5 Help students present their designs at the art gallery and reflect on what they learned. Upload the picutres or video of the activities and presentation.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 7, 'Task', 'Assess the students'' work and presentation based on the assessment criteria.', 7, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 7
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Write Your Own Poem (Class 4)', '1 week', 'Teachers will guide learners to write and perform original poems inspired by their culture, land, or history, while building an understanding of rhyme, rhythm, and poetic expression.',
       'uploads/projects/Write_Your_Own_Poem_MIP_Nagaland_Grade4.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 4' AND s.name = 'English (Grade 4)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 4' AND s.name = 'English (Grade 4)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Introduce the project, read the poem “My Land” with the class, and guide students to explore key elements of a poem.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Guide students to finalise their poem’s elements and support them in using homophones.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Guide students to exlpore adjectives, antonyms, and synonyms, and assist learners in drafting their poems.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Organise peer-feedback, help learners revise and write final version, and prepare them for presentations.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Facilitate the poetry presentation session and lead a reflection discussion.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Assess the students'' work and presentation based on the assessment criteria.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Voices for the Voiceless (Class 5)', '1 week', 'Teachers will help students reflect on themes of empathy and support them in collaboratively creating comic strips that combine storytelling with dialogue and visuals.',
       'uploads/projects/Voices_For_The_Voiceless_MIP_Nagaland_Grade5 (1).pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 5' AND s.name = 'English (Grade 5)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 5' AND s.name = 'English (Grade 5)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Read the attached learning resource. Introduce the project to students and set classroom norms for group work and participation.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Day-1 Explain the purpose of the project and instruct students to start reading the chapter ‘The Hunt’.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Day-2 Ensure that students complete the reading of the chapter and guide groups to brainstorm a comic message and main character.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Day-3 Help learners write a short 5–6 line story idea and create a rough comic layout with 9–10 frames.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Day-4 Support peer feedback between groups and guide them in finalising the comic strip using visuals, narration, and dialogues.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Day-5 Organise a classroom comic showcase and reflection activity. Display final comics and discuss key takeaways from the project. Upload the picutres or video of the activities and presentation.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 7, 'Task', 'Assess the students'' work and presentation based on the assessment criteria.', 7, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 7
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Perimeter and Area', '1 Week', 'Learners explore the concepts of perimeter and area through familiar spaces and objects. They measure boundaries, compare shapes, calculate the perimeter and area of rectangles and squares, derive formulas through patterns, and apply their learning to design meaningful spaces from their community.',
       'uploads/projects/NLNF_MIP_Perimeter_and_Area.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 6' AND s.name = 'Math (Grade 6)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 6' AND s.name = 'Math (Grade 6)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Read the attached learning resource. Introduce the project and discuss the key question: How can perimeter and area help us design and understand spaces around us? Form groups and set norms for collaboration.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Day 1: Guide learners to understand perimeter as the distance around a shape by walking, measuring, or using string around familiar spaces such as the classroom, playground, or garden. Let them create different shapes with the same length of string and compare them.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Day 2: Introduce area as the space covered inside a shape. Guide learners to use grids or locally available materials to find the area of rectangles and squares. Help them compare perimeter and area and identify common misconceptions.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Day 3: Guide learners to discover the formulas for the perimeter and area of rectangles and squares through patterns and examples rather than giving the formulas directly. Let them practise using measurements from real objects and spaces.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Day 4: Ask learners to choose a familiar community space such as a kitchen garden, playground, paddy field, classroom, or festival stall. In groups, guide them to measure or decide dimensions and begin creating a drawing/model showing perimeter and area calculations.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Day 5: Guide groups to present their “Nagaland Space Design”, explaining the shapes used, perimeter and area calculations, and how their design could be useful in real life. Encourage peer feedback, reflection, and discussion on what they discovered.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Chapter 7: Working with Fractions', '1 Week', 'Students move from splitting a shared orange by eye to confidently multiplying and dividing fractions, discovering the rules for themselves through folding, sharing and pattern recognition, and applying fractions as operators and quantities to real Nagaland sharing and scaling situations.',
       'uploads/projects/NLNF_MIP_Fractions_Grade7_.docx.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 7' AND s.name = 'Math (Grade 7)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 7' AND s.name = 'Math (Grade 7)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Sharing the Orange - Fractions as Parts of a Whole. Students share a real orange (or paper circle) equally among 4, then 2, 3 and 6 friends, label each part, and learn the vocabulary of numerator and denominator, refreshing fractions as equal parts of one whole.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Scaling the Recipe - Multiplying a Fraction by a Whole Number. Using a 1-plate recipe (e.g. 1/2 cup rice), students first solve 1/2+1/2+1/2 by repeated addition, then learn the shortcut 1/2 x 3 = 3/2, and scale a second ingredient for 5 and 8 plates.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Fraction of a Fraction - Multiplying Two Fractions. Through paper folding (half of half, half of a third), students discover 1/2 of 1/2 = 1/4 and 1/2 of 1/3 = 1/6, generalise the rule (multiply numerators, multiply denominators), and solve ''fraction of'' word problems with local items.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Busting the Myths - Does Multiplying Always Make Numbers Bigger? Students compare 1/2x6 vs 1/2x1/2 to discover multiplying by a fraction less than one shrinks the result, then write a Myth and a Fact with counter-examples for the class ''Myth or Fact?'' chart.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'The Flip Trick - Cracking the Code for Dividing Fractions. Using stones to physically share a half-kilo of rice among 4 people, students record results in a pattern table, discover that dividing by 4 equals multiplying by 1/4, and formalise the reciprocal rule for dividing fractions.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Measure My Kitchen. As homework, students record a real fractional ingredient quantity from a home-cooked dish, use multiplication to scale it for more guests, use division to work out a fair individual share, and share their calculations in class the next day.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 7, 'Showcase', 'Nagaland Feast Planners - Final Project. Groups choose a feast or sharing occasion (village feast, church lunch, Hornbill stall), scale a recipe using multiplication of fractions for a chosen number of guests, use division to work out fair shares for a different guest count, and present their plan.', 7, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 7
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Chapter 8: We Distribute, Yet Things Multiply', '1 week', 'Building on Grade 6''s Perimeter and Area pattern-generalisation work, students extend the same instinct to algebra: the distributive property, expanding expressions, multiplying binomials, and discovering identities, using bamboo weaving, kitchen gardens, paddy terraces, Naga shawl motifs and the local market.',
       'uploads/projects/NLNF_MIP_Grade8_Chapter6_.docx.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 8' AND s.name = 'Math (Grade 8)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 8' AND s.name = 'Math (Grade 8)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Observe how learners already share and distribute quantities in daily classroom routines, then set up the three-week plan and a low-cost ''algebra kit'' (bamboo strips, string, chalk, paper). Fix the six-period routine around familiar Nagaland contexts and introduce key vocabulary: distribute, expand, term, product, factor, identity.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Guide learners to physically distribute bundled bamboo strips (e.g. 5 baskets of 3 long + 2 short strips) into groups to discover a(b+c) = ab+ac and a(b−c) = ab−ac. Correct the common a(b+c) = ab+c error by pointing back to the physical groups.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Take learners outdoors (or use grid paper) to build and verify 2x(x+3) = 2x² + 6x by representing a garden plot''s width and depth with string or hand-spans. Then use an area model of two paddy terraces to multiply binomials such as (x+2)(x+5), labelling the four regions ac, ad, bc, bd.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Guide learners to design coloured Naga shawl block patterns to discover the identities (a+b)² = a²+2ab+b², (a−b)², and a²−b², naming designs after their village''s shawl motif. Then role-play a market stall where learners use these identities for quick mental calculations, such as 102×98 = (100+2)(100−2).', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Ask learners to spot the rule in a repeating woven pattern, then solve one synthesis problem using distribution, expansion, and an identity through different valid strategies. Close with reflection on learners'' reasoning and a gallery-walk showcase, ''Algebra in Nagaland Life'', combining shawl-block, garden-plot, and market-shortcut work.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Showcase', 'Ask learners to spot the rule in a repeating woven pattern, then solve one synthesis problem using distribution, expansion, and an identity through different valid strategies. Close with reflection on learners'' reasoning and a gallery-walk showcase, ''Algebra in Nagaland Life'', combining shawl-block, garden-plot, and market-shortcut work.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Chapter 6: Materials Around Us', '1 Week', 'Students look closely at everyday Nagaland objects and sort them the way a scientist would - by lustre, hardness, solubility, sink/float and transparency - culminating in a comparison of plastic objects with natural alternatives for the environment.',
       'uploads/projects/NLNF_MIP_Materials_Grade6_.docx.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 6' AND s.name = 'Science (Grade 6)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 6' AND s.name = 'Science (Grade 6)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'What Is It Made Of? - Objects Around Us. Students look around the classroom/school and list 8-10 objects with the material each is made of, discuss objects made of more than one material, and are introduced to the term ''material''.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Sorting Shelf - Planning an Investigation to Classify Materials. Students sort the same set of 8-10 objects by different properties (hard/soft, shiny/dull) and discover that the same objects can be grouped differently depending on the property tested, setting up the week''s plan.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Shine or Dull? - Lustre and Appearance. Comparing a shiny steel spoon with dull chalk, students learn the term lustre and test each object from their list, recording whether it is shiny or dull in their properties table.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Squeeze and Scratch - Hard or Soft. Students press or scratch each object to classify it as hard or soft, then test a small steel nail against a large cotton pillow to bust the myth that bigger or heavier always means harder.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Sink, Float, or Dissolve? - Density and Solubility. Students test objects for sinking/floating and materials (salt, sand, sugar) for solubility, recording patterns in a table and predicting/testing a banana leaf and plastic bead before checking.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'See-Through Search. As homework, students classify 5 objects at home as opaque, transparent or translucent, ask a family member why windows are made of glass, and share findings the next day to add to the class''s master properties table.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 7, 'Showcase', 'Nagaland Material Detectives - Choosing Better Alternatives. Groups compare 5 plastic objects with natural alternatives across all five properties tested during the week, decide which is better for the environment, correct a misconception, and present a comparison chart in a class exhibition.', 7, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 7
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Chapter 7: Heat Transfer', '1 Week', 'Students move from judging hotness/coldness by touch to reliably measuring temperature, and explain conduction, convection and radiation through everyday Nagaland contexts (tin roofs, thermos flasks, shawls), culminating in a locally-grounded investigation or design showcase.',
       'uploads/projects/NLNF_MIP_Heat_Transfer_.docx.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 7' AND s.name = 'Science (Grade 7)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 7' AND s.name = 'Science (Grade 7)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Hot or Cold? Trusting a Real Measure. Students test the same room-temperature water with a hand that was in cold water and one that was in warm water, discover touch is unreliable, and are introduced to the thermometer as a reliable numerical measure.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Meet the Thermometers - Clinical and Laboratory. Students compare a clinical and a laboratory thermometer for range, least count, unit and use, understand the role of the kink, and list precautions for safe, accurate use.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Feel the Heat - Conduction, Conductors and Insulators. Students place a metal spoon, wooden stick and plastic spoon in hot water, rank which heats fastest, and learn conduction and the difference between conductors and insulators, linking to why tin roofs get hot.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Rising Smoke, Sinking Cool - Convection and Land-Sea Breeze. Teacher-led candle/incense demonstration (or a hot/cold water with food colour alternative) shows how heat moves through rising and sinking currents, applied to explain land and river breezes.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Catching the Sun - Radiation and the Colour of Clothes. Students compare water heated in black- vs white-wrapped bottles in sunlight to learn radiation and how dark surfaces absorb more heat, connecting this to Naga shawl colours and clothing choices.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'The Flask That Keeps Its Cool - Why a Thermos Stays the Same Temperature. Students compare cooling of hot water in an ordinary cup vs a thermos, then connect the vacuum, silvered surface and stopper to how a thermos blocks conduction, convection and radiation.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 7, 'Task', 'Dressing for the Weather - Heat Transfer and Our Clothes. As homework, students examine clothing worn in different seasons at home, connect colour/thickness/material to conduction, convection and radiation, and ask a family elder about clothing in very cold or hot places.', 7, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 7
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 8, 'Showcase', 'Nagaland Heat Detectives - Final Project. In groups, students choose a real home/village problem related to heat (keeping a house cool, keeping tea warm, roof colour, etc.), design and test a model or investigation using at least two heat-transfer ideas, and present it in a class exhibition.', 8, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 8
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Chapter 9: The Magic of Science - Solutes, Solvents & Solutions', '1 Week, 40 minutes a day for 5 days', 'Learners turn into science magicians, using hands-on tricks to reveal the ideas of solutes, solvents, solutions, saturation, temperature effects and density. Each group builds and explains a trick, culminating in a village-style Science Magic Show for a real audience.',
       'uploads/projects/NLNF_MIP_Grade8_.docx.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 8' AND s.name = 'Science (Grade 8)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 8' AND s.name = 'Science (Grade 8)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'The Bending Pencil - What Are Solute, Solvent and Solution? Using the pencil-in-water refraction demo as a hook, learners identify solutes, solvents and solutions in everyday mixtures (ORS, salt water, lemon juice, coffee), form groups, and agree on the leading question and project criteria.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'The Disappearing Salt - Saturation and the Effect of Temperature. Learners dissolve salt spoon by spoon in cold and hot water to distinguish saturated from unsaturated solutions, discover how temperature affects solubility, and begin planning their magic trick.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Float or Sink? - Discovering Density. Learners predict and test which objects float or sink (including an egg in plain vs. salt water), explain results using density (Mass ÷ Volume), and use the idea to improve their magic trick.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Testing, Feedback and the Poster. Groups test their trick, exchange peer feedback using the Peer Feedback Form, revise their trick based on feedback, and design a poster with a catchy title and diagrams explaining the science.', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Showcase', 'The Science Magic Show - Final Presentation. Groups set up stalls like the Hornbill Festival and perform their tricks for classmates, teachers and visitors, explain the science behind each trick, gather audience feedback, and reflect individually on their learning.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Expressing Self Through Visual Art', '1 month', 'These activities help students explore and express emotions through art, using masks and drawings inspired by cultural and contemporary styles. They support communication skills by encouraging self-expression and understanding of feelings in themselves and others.',
       'uploads/projects/Arts_Teacher_Grade_6_8_Cycle_1.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 6' AND s.name = 'Arts Teacher (Grade 6-8)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 6' AND s.name = 'Arts Teacher (Grade 6-8)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Conduct Activity 1: Mask — Make masks inspired by Indian Tribal Art to express emotions using lines and shapes.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Conduct Activity 2: Expressing Emotions — Explore emotions and actions by creating drawings inspired by Keith Haring.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Observe & Track Student Progress', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ communication skills.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Expressing Self Through Visual Art', '1 month', 'These activities help students explore and express emotions through art, using masks and drawings inspired by cultural and contemporary styles. They support communication skills by encouraging self-expression and understanding of feelings in themselves and others.',
       'uploads/projects/Arts_Teacher_Grade_6_8_Cycle_1.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 7' AND s.name = 'Arts Teacher (Grade 6-8)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 7' AND s.name = 'Arts Teacher (Grade 6-8)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Conduct Activity 1: Mask — Make masks inspired by Indian Tribal Art to express emotions using lines and shapes.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Conduct Activity 2: Expressing Emotions — Explore emotions and actions by creating drawings inspired by Keith Haring.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Observe & Track Student Progress', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ communication skills.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT g.id, s.id, @cycle1, 'Expressing Self Through Visual Art', '1 month', 'These activities help students explore and express emotions through art, using masks and drawings inspired by cultural and contemporary styles. They support communication skills by encouraging self-expression and understanding of feelings in themselves and others.',
       'uploads/projects/Arts_Teacher_Grade_6_8_Cycle_1.pdf', 1
FROM grades g
CROSS JOIN subjects s
WHERE g.name = 'Grade 8' AND s.name = 'Arts Teacher (Grade 6-8)'
  AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM projects px
    WHERE px.grade_id = g.id AND px.subject_id = s.id AND px.cycle_id = @cycle1
  );


SET @proj = (SELECT p.id FROM projects p
  INNER JOIN grades g ON g.id = p.grade_id
  INNER JOIN subjects s ON s.id = p.subject_id
  WHERE g.name = 'Grade 8' AND s.name = 'Arts Teacher (Grade 6-8)' AND p.cycle_id = @cycle1 LIMIT 1);


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 1, 'Task', 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 1
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 2, 'Task', 'Conduct Activity 1: Mask — Make masks inspired by Indian Tribal Art to express emotions using lines and shapes.', 2, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 2
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 3, 'Task', 'Conduct Activity 2: Expressing Emotions — Explore emotions and actions by creating drawings inspired by Keith Haring.', 3, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 3
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 4, 'Task', 'Observe & Track Student Progress', 4, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 4
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 5, 'Task', 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners’ communication skills.', 5, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 5
  );


INSERT INTO project_tasks (project_id, task_number, task_type, task_description, sort_order, is_active)
SELECT @proj, 6, 'Task', 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1
FROM DUAL
WHERE @proj IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM project_tasks WHERE project_id = @proj AND task_number = 6
  );


-- ============================================================
-- Verification
-- ============================================================
SELECT 'projects_cycle1' AS metric, COUNT(*) AS cnt FROM projects p
  INNER JOIN cycles c ON c.id = p.cycle_id WHERE c.name='Cycle 1' AND p.is_active=1
UNION ALL
SELECT 'tasks_cycle1', COUNT(*) FROM project_tasks pt
  INNER JOIN projects p ON p.id = pt.project_id
  INNER JOIN cycles c ON c.id = p.cycle_id WHERE c.name='Cycle 1' AND pt.is_active=1
UNION ALL
SELECT 'showcase', COUNT(*) FROM project_tasks WHERE task_type='Showcase' AND is_active=1
UNION ALL
SELECT 'submissions_remaining', COUNT(*) FROM teacher_submissions;

-- Expected expanded project rows: 27
-- Expected task inserts (across expansions): 165
-- Showcase rows: 5
