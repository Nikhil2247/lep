-- ============================================================
-- LEP Version 1.6.1 – Map Cycle 1 projects to official PDF filenames
-- Safe to re-run. Does NOT create/delete projects or tasks.
-- Only updates projects.project_file for active Cycle 1 records.
-- ============================================================

USE lep_nagaland;

-- ------------------------------------------------------------
-- Update by Grade + Subject (+ School Leaders special case)
-- Paths are relative to application root: uploads/projects/<exact name>
-- Filenames match the official ZIP exactly (spaces, hyphens, parentheses).
-- ------------------------------------------------------------

-- 1. School Leaders  →  School Leader.pdf
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/School Leader.pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND p.subject_id IS NULL
  AND g.name = 'School Leaders';

-- 2. Pre-Primary Teacher (Grade A & B)
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Pre-Primary Teacher (Grade A & B).pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name = 'Pre-Primary (A-B)'
  AND s.name = 'Pre-Primary Teacher (Grade A & B)';

-- 3. Arts Teacher (A & B)
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Arts Teacher (A & B).pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name = 'Pre-Primary (A-B)'
  AND s.name = 'Arts Teacher (A & B)';

-- 4. Literacy Teacher (Grade 1, 2 & 3)  — Grades 1, 2, 3
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Literacy Teacher (Grade 1, 2 & 3).pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name IN ('Grade 1', 'Grade 2', 'Grade 3')
  AND s.name = 'Literacy Teacher (Grade 1, 2 & 3)';

-- 5. Numeracy Teacher (Grade 1, 2 & 3)  — Grades 1, 2, 3
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Numeracy Teacher (Grade 1, 2 & 3).pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name IN ('Grade 1', 'Grade 2', 'Grade 3')
  AND s.name = 'Numeracy Teacher (Grade 1, 2 & 3)';

-- 6. Arts Teacher (Grade 1-5)  — Grades 1–5
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Arts Teacher (Grade 1-5).pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name IN ('Grade 1', 'Grade 2', 'Grade 3', 'Grade 4', 'Grade 5')
  AND s.name = 'Arts Teacher (Grade 1-5)';

-- 7. Math (Grade 4)
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Cycle 1 Class 4- Maths.pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name = 'Grade 4'
  AND s.name = 'Math (Grade 4)';

-- 8. English (Grade 4)
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Cycle 1 Class 4- English.pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name = 'Grade 4'
  AND s.name = 'English (Grade 4)';

-- 9. Math (Grade 5)
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Cycle -1 Class 5- Maths.pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name = 'Grade 5'
  AND s.name = 'Math (Grade 5)';

-- 10. English (Grade 5)
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Cycle -1 Class 5- English.pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name = 'Grade 5'
  AND s.name = 'English (Grade 5)';

-- 11. Math (Grade 6)
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Class 6 - Mathematics.pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name = 'Grade 6'
  AND s.name = 'Math (Grade 6)';

-- 12. Science (Grade 6)
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Grade 6 - Science.pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name = 'Grade 6'
  AND s.name = 'Science (Grade 6)';

-- 13. Math (Grade 7)
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Grade 7 - Numeracy (Mathematics).pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name = 'Grade 7'
  AND s.name = 'Math (Grade 7)';

-- 14. Science (Grade 7)
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Grade 7 - Science.pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name = 'Grade 7'
  AND s.name = 'Science (Grade 7)';

-- 15. Math (Grade 8)
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Grade 8 - Numeracy (Mathematics).pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name = 'Grade 8'
  AND s.name = 'Math (Grade 8)';

-- 16. Science (Grade 8)
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Grade 8 - Science.pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name = 'Grade 8'
  AND s.name = 'Science (Grade 8)';

-- 17. Arts Teacher (Grade 6-8)  — Grades 6, 7, 8
UPDATE projects p
INNER JOIN grades g ON g.id = p.grade_id
INNER JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
SET p.project_file = 'uploads/projects/Arts Teacher (Grade 6-8).pdf'
WHERE c.name = 'Cycle 1'
  AND p.is_active = 1
  AND g.name IN ('Grade 6', 'Grade 7', 'Grade 8')
  AND s.name = 'Arts Teacher (Grade 6-8)';

-- ============================================================
-- Validation queries (run after import; review results)
-- ============================================================

-- Counts should remain: projects 27, tasks 165, submissions 0
SELECT 'projects_cycle1' AS metric, COUNT(*) AS cnt
FROM projects p
INNER JOIN cycles c ON c.id = p.cycle_id
WHERE c.name = 'Cycle 1' AND p.is_active = 1
UNION ALL
SELECT 'tasks_cycle1', COUNT(*)
FROM project_tasks pt
INNER JOIN projects p ON p.id = pt.project_id
INNER JOIN cycles c ON c.id = p.cycle_id
WHERE c.name = 'Cycle 1' AND pt.is_active = 1
UNION ALL
SELECT 'submissions', COUNT(*) FROM teacher_submissions
UNION ALL
SELECT 'projects_missing_file', COUNT(*)
FROM projects p
INNER JOIN cycles c ON c.id = p.cycle_id
WHERE c.name = 'Cycle 1' AND p.is_active = 1
  AND (p.project_file IS NULL OR p.project_file = '');

-- Distinct filenames in use (should be 17)
SELECT DISTINCT p.project_file
FROM projects p
INNER JOIN cycles c ON c.id = p.cycle_id
WHERE c.name = 'Cycle 1' AND p.is_active = 1
ORDER BY p.project_file;

-- Grouped projects share one PDF (sample check)
SELECT g.name AS grade, COALESCE(s.name, '(School Leaders)') AS subject, p.project_file
FROM projects p
INNER JOIN grades g ON g.id = p.grade_id
LEFT JOIN subjects s ON s.id = p.subject_id
INNER JOIN cycles c ON c.id = p.cycle_id
WHERE c.name = 'Cycle 1' AND p.is_active = 1
ORDER BY g.sort_order, s.sort_order;
