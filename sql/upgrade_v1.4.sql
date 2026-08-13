-- ============================================================
-- LEP Version 1.4 – Official Cycle 1 Grade → Subject Mapping
-- Replaces sample grades / subjects / mappings with official data.
-- Safe to run on an existing v1.3 database (no teacher submissions assumed
-- for grade/subject ID changes; sample projects are adjusted).
-- ============================================================

USE lep_nagaland;

SET FOREIGN_KEY_CHECKS = 0;

-- ------------------------------------------------------------
-- 1. Clear dependent mapping + sample project data that uses old IDs
-- ------------------------------------------------------------
DELETE FROM grade_subject_map;
DELETE FROM project_tasks;
DELETE FROM projects;
DELETE FROM subjects;
DELETE FROM grades;

-- ------------------------------------------------------------
-- 2. Official Grades (Cycle 1)
-- ------------------------------------------------------------
INSERT INTO grades (id, name, is_school_leader, sort_order, is_active) VALUES
(1,  'Pre-Primary (A-B)', 0, 1,  1),
(2,  'Grade 1',           0, 2,  1),
(3,  'Grade 2',           0, 3,  1),
(4,  'Grade 3',           0, 4,  1),
(5,  'Grade 4',           0, 5,  1),
(6,  'Grade 5',           0, 6,  1),
(7,  'Grade 6',           0, 7,  1),
(8,  'Grade 7',           0, 8,  1),
(9,  'Grade 8',           0, 9,  1),
(10, 'School Leaders',    1, 99, 1);

-- Reset AUTO_INCREMENT
ALTER TABLE grades AUTO_INCREMENT = 11;

-- ------------------------------------------------------------
-- 3. Official Subjects (display names exactly as specified)
-- ------------------------------------------------------------
INSERT INTO subjects (id, name, sort_order, is_active) VALUES
(1,  'Pre-Primary Teacher (Grade A & B)', 1,  1),
(2,  'Arts Teacher (A & B)',              2,  1),
(3,  'Literacy Teacher (Grade 1, 2 & 3)', 3,  1),
(4,  'Numeracy Teacher (Grade 1, 2 & 3)', 4,  1),
(5,  'Arts Teacher (Grade 1-5)',          5,  1),
(6,  'Math (4,5)',                        6,  1),
(7,  'English (4,5)',                     7,  1),
(8,  'Math (6,7,8)',                      8,  1),
(9,  'Science (6,7,8)',                   9,  1),
(10, 'Art Education (Grade 6-8)',         10, 1);

ALTER TABLE subjects AUTO_INCREMENT = 11;

-- ------------------------------------------------------------
-- 4. Official Grade → Subject mapping (Cycle 1 scope)
--    School Leaders: NO subject mapping (subject dropdown hidden)
-- ------------------------------------------------------------
INSERT INTO grade_subject_map (grade_id, subject_id) VALUES
-- Pre-Primary (A-B)
(1, 1), (1, 2),
-- Grade 1
(2, 3), (2, 4), (2, 5),
-- Grade 2
(3, 3), (3, 4), (3, 5),
-- Grade 3
(4, 3), (4, 4), (4, 5),
-- Grade 4
(5, 6), (5, 7), (5, 5),
-- Grade 5
(6, 6), (6, 7), (6, 5),
-- Grade 6
(7, 8), (7, 9), (7, 10),
-- Grade 7
(8, 8), (8, 9), (8, 10),
-- Grade 8
(9, 8), (9, 9), (9, 10);
-- School Leaders (id=10): no rows

-- ------------------------------------------------------------
-- 5. Ensure Cycle 1 exists (keep other cycles if present)
-- ------------------------------------------------------------
INSERT INTO cycles (name, sort_order, is_active)
SELECT 'Cycle 1', 1, 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM cycles WHERE name = 'Cycle 1');

UPDATE cycles SET is_active = 1, sort_order = 1 WHERE name = 'Cycle 1';

-- ------------------------------------------------------------
-- 6. Placeholder School Leaders project for Cycle 1 only
--    (subject_id IS NULL – matches existing app logic)
--    Real project titles/files will be provided later.
-- ------------------------------------------------------------
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, project_file, is_active)
SELECT 10, NULL, c.id,
       'School Leadership for Learning Enhancement (Cycle 1)',
       'uploads/projects/school_leaders_cycle1.pdf',
       1
FROM cycles c
WHERE c.name = 'Cycle 1'
  AND NOT EXISTS (
      SELECT 1 FROM projects p
      WHERE p.grade_id = 10 AND p.subject_id IS NULL AND p.cycle_id = c.id
  );

SET FOREIGN_KEY_CHECKS = 1;

-- ------------------------------------------------------------
-- Verification queries (optional – run manually)
-- ------------------------------------------------------------
-- SELECT g.name AS grade, COUNT(m.id) AS subject_count
-- FROM grades g
-- LEFT JOIN grade_subject_map m ON m.grade_id = g.id
-- WHERE g.is_active = 1
-- GROUP BY g.id, g.name
-- ORDER BY g.sort_order;
