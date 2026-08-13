-- ============================================================
-- LEP Version 1.5 – Cycle 1 Project & Task Master Data
-- Source: LEP_Cycle1_First_3_Subjects.xlsx
-- Adds duration/objective columns and imports 3 projects + 18 tasks.
-- Does NOT touch districts, blocks, schools, grades, subjects, mappings.
-- ============================================================

USE lep_nagaland;

-- ------------------------------------------------------------
-- 1. Add duration + objective columns if missing
-- ------------------------------------------------------------
SET @col_dur = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'projects' AND COLUMN_NAME = 'duration'
);
SET @sql = IF(@col_dur = 0,
    'ALTER TABLE projects ADD COLUMN duration VARCHAR(50) DEFAULT NULL COMMENT ''e.g. 1 Month'' AFTER project_title',
    'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

SET @col_obj = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'projects' AND COLUMN_NAME = 'objective'
);
SET @sql = IF(@col_obj = 0,
    'ALTER TABLE projects ADD COLUMN objective TEXT DEFAULT NULL AFTER duration',
    'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ------------------------------------------------------------
-- 2. Resolve IDs for grades / subjects / cycle
-- ------------------------------------------------------------
-- Grades (from v1.4):
--   Pre-Primary (A-B)=1, Grade 1=2 ... Grade 8=9, School Leaders=10
-- Subjects:
--   Pre-Primary Teacher=1, Arts Teacher (A & B)=2, ...

SET @cycle1 = (SELECT id FROM cycles WHERE name = 'Cycle 1' LIMIT 1);
SET @g_sl   = (SELECT id FROM grades WHERE name = 'School Leaders' LIMIT 1);
SET @g_pp   = (SELECT id FROM grades WHERE name = 'Pre-Primary (A-B)' LIMIT 1);
SET @s_pp   = (SELECT id FROM subjects WHERE name = 'Pre-Primary Teacher (Grade A & B)' LIMIT 1);
SET @s_art  = (SELECT id FROM subjects WHERE name = 'Arts Teacher (A & B)' LIMIT 1);

-- ------------------------------------------------------------
-- 3. Remove old placeholder School Leaders project (v1.4) if present
--    so we can insert the official title without unique-key conflict
-- ------------------------------------------------------------
DELETE pt FROM project_tasks pt
INNER JOIN projects p ON p.id = pt.project_id
WHERE p.grade_id = @g_sl AND p.subject_id IS NULL AND p.cycle_id = @cycle1
  AND p.project_title LIKE 'School Leadership for Learning Enhancement%';

DELETE FROM projects
WHERE grade_id = @g_sl AND subject_id IS NULL AND cycle_id = @cycle1
  AND project_title LIKE 'School Leadership for Learning Enhancement%';

-- ------------------------------------------------------------
-- 4. Upsert the 3 official projects
-- ------------------------------------------------------------

-- 4a. School Leaders + Cycle 1 (subject_id IS NULL)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT @g_sl, NULL, @cycle1,
       'Setting Direction – School Vision & Priority Goals',
       '1 Month',
       'To establish clear, shared school priorities that guide teaching, learning, and improvement efforts.',
       'uploads/projects/Revised_LNF_4.0_Cycle-1_School_Leader.pdf',
       1
FROM DUAL
WHERE @g_sl IS NOT NULL AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM projects
      WHERE grade_id = @g_sl AND subject_id IS NULL AND cycle_id = @cycle1
  );

UPDATE projects SET
    project_title = 'Setting Direction – School Vision & Priority Goals',
    duration      = '1 Month',
    objective     = 'To establish clear, shared school priorities that guide teaching, learning, and improvement efforts.',
    project_file  = 'uploads/projects/Revised_LNF_4.0_Cycle-1_School_Leader.pdf',
    is_active     = 1
WHERE grade_id = @g_sl AND subject_id IS NULL AND cycle_id = @cycle1;

-- 4b. Pre-Primary + Pre-Primary Teacher
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT @g_pp, @s_pp, @cycle1,
       'Classroom Arrangement: Building a Supportive Learning Space',
       '1 Month',
       'Teachers will enhance the quality of early learning experiences, identifying improvement areas, organizing learning spaces effectively, implementing developmentally appropriate activities, and observing and reflecting on children''s play and learning.',
       'uploads/projects/Pre_Primary_Teacher_Grade_A_B_Cycle_1.pdf',
       1
FROM DUAL
WHERE @g_pp IS NOT NULL AND @s_pp IS NOT NULL AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM projects
      WHERE grade_id = @g_pp AND subject_id = @s_pp AND cycle_id = @cycle1
  );

UPDATE projects SET
    project_title = 'Classroom Arrangement: Building a Supportive Learning Space',
    duration      = '1 Month',
    objective     = 'Teachers will enhance the quality of early learning experiences, identifying improvement areas, organizing learning spaces effectively, implementing developmentally appropriate activities, and observing and reflecting on children''s play and learning.',
    project_file  = 'uploads/projects/Pre_Primary_Teacher_Grade_A_B_Cycle_1.pdf',
    is_active     = 1
WHERE grade_id = @g_pp AND subject_id = @s_pp AND cycle_id = @cycle1;

-- 4c. Pre-Primary + Arts Teacher (A & B)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file, is_active)
SELECT @g_pp, @s_art, @cycle1,
       'Sensory Exploration for Fine Motor Development',
       '1 Month',
       'Strengthen development of fine motor skills - hand strength, finger movement, and hand-eye coordination - in learners by engaging them in movement-based art activities using yarn and clay.',
       'uploads/projects/Arts_Teacher_A_B_Cycle_1.pdf',
       1
FROM DUAL
WHERE @g_pp IS NOT NULL AND @s_art IS NOT NULL AND @cycle1 IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM projects
      WHERE grade_id = @g_pp AND subject_id = @s_art AND cycle_id = @cycle1
  );

UPDATE projects SET
    project_title = 'Sensory Exploration for Fine Motor Development',
    duration      = '1 Month',
    objective     = 'Strengthen development of fine motor skills - hand strength, finger movement, and hand-eye coordination - in learners by engaging them in movement-based art activities using yarn and clay.',
    project_file  = 'uploads/projects/Arts_Teacher_A_B_Cycle_1.pdf',
    is_active     = 1
WHERE grade_id = @g_pp AND subject_id = @s_art AND cycle_id = @cycle1;

-- ------------------------------------------------------------
-- 5. Import tasks (skip if task_number already exists for project)
-- ------------------------------------------------------------

-- Helper: project IDs
SET @p_sl  = (SELECT id FROM projects WHERE grade_id = @g_sl AND subject_id IS NULL AND cycle_id = @cycle1 LIMIT 1);
SET @p_pp  = (SELECT id FROM projects WHERE grade_id = @g_pp AND subject_id = @s_pp AND cycle_id = @cycle1 LIMIT 1);
SET @p_art = (SELECT id FROM projects WHERE grade_id = @g_pp AND subject_id = @s_art AND cycle_id = @cycle1 LIMIT 1);

-- School Leaders – 7 tasks
INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_sl, 1, 'Conduct a staff reflection meeting on current school status (learning levels, attendance, engagement).', 1, 1
FROM DUAL WHERE @p_sl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_sl AND task_number = 1);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_sl, 2, 'Identify 2–3 priority areas (e.g., reading, math, student participation, etc.).', 2, 1
FROM DUAL WHERE @p_sl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_sl AND task_number = 2);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_sl, 3, 'Co-create simple, measurable school goals for the academic year.', 3, 1
FROM DUAL WHERE @p_sl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_sl AND task_number = 3);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_sl, 4, 'Break goals into term-wise focus areas.', 4, 1
FROM DUAL WHERE @p_sl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_sl AND task_number = 4);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_sl, 5, 'Display goals visibly (staff room/classrooms) for constant reference.', 5, 1
FROM DUAL WHERE @p_sl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_sl AND task_number = 5);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_sl, 6, 'Communicate priorities to students and parents (assembly/PTM).', 6, 1
FROM DUAL WHERE @p_sl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_sl AND task_number = 6);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_sl, 7, 'Review progress once every month in staff meetings.', 7, 1
FROM DUAL WHERE @p_sl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_sl AND task_number = 7);

-- Pre-Primary Teacher – 5 tasks
INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_pp, 1, 'Engage with the ideal ECCE strategy document.', 1, 1
FROM DUAL WHERE @p_pp IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_pp AND task_number = 1);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_pp, 2, 'Plan and conduct a classroom diagnostic using the checklist and identify three areas for improvement.', 2, 1
FROM DUAL WHERE @p_pp IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_pp AND task_number = 2);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_pp, 3, 'Organise your classroom using the IDEAL ECCE classroom arrangement.', 3, 1
FROM DUAL WHERE @p_pp IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_pp AND task_number = 3);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_pp, 4, 'Conduct activities using the classroom setup and upload photos of children participating.', 4, 1
FROM DUAL WHERE @p_pp IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_pp AND task_number = 4);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_pp, 5, 'Observe classroom play and share moments and stories of children.', 5, 1
FROM DUAL WHERE @p_pp IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_pp AND task_number = 5);

-- Arts Teacher (A & B) – 6 tasks
INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_art, 1, 'Refer to the learning resource and plan for the session with materials and resources.', 1, 1
FROM DUAL WHERE @p_art IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_art AND task_number = 1);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_art, 2, 'Conduct Activity 1: Yarn Stick – Students play with yarn and explore different ways to wrap, twist, and weave it around sticks.', 2, 1
FROM DUAL WHERE @p_art IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_art AND task_number = 2);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_art, 3, 'Conduct Activity 2: Clay Molding – Students play with clay and experiment with different molding techniques.', 3, 1
FROM DUAL WHERE @p_art IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_art AND task_number = 3);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_art, 4, 'Observe & Track Student Progress', 4, 1
FROM DUAL WHERE @p_art IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_art AND task_number = 4);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_art, 5, 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners'' fine motor skills.', 5, 1
FROM DUAL WHERE @p_art IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_art AND task_number = 5);

INSERT INTO project_tasks (project_id, task_number, task_description, sort_order, is_active)
SELECT @p_art, 6, 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6, 1
FROM DUAL WHERE @p_art IS NOT NULL AND NOT EXISTS (SELECT 1 FROM project_tasks WHERE project_id = @p_art AND task_number = 6);

-- ------------------------------------------------------------
-- 6. Verification summary
-- ------------------------------------------------------------
SELECT
    g.name AS grade,
    COALESCE(s.name, '(no subject)') AS subject,
    p.project_title,
    p.duration,
    (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id = p.id AND t.is_active = 1) AS task_count
FROM projects p
INNER JOIN grades g ON g.id = p.grade_id
LEFT JOIN subjects s ON s.id = p.subject_id
WHERE p.is_active = 1
ORDER BY g.sort_order, s.sort_order;
