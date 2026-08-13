-- ============================================================
-- Learning Enhancement Program (LEP) - Version 1.0
-- Database Schema + Sample Master Data
-- Government of Nagaland | Samagra Shiksha Nagaland
-- ============================================================

CREATE DATABASE IF NOT EXISTS lep_nagaland
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE lep_nagaland;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ------------------------------------------------------------
-- Drop existing tables (for clean install)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS submission_evidence;
DROP TABLE IF EXISTS task_responses;
DROP TABLE IF EXISTS teacher_submissions;
DROP TABLE IF EXISTS project_tasks;
DROP TABLE IF EXISTS projects;
DROP TABLE IF EXISTS grade_subject_map;
DROP TABLE IF EXISTS cycles;
DROP TABLE IF EXISTS subjects;
DROP TABLE IF EXISTS grades;
DROP TABLE IF EXISTS schools;
DROP TABLE IF EXISTS blocks;
DROP TABLE IF EXISTS districts;

-- ------------------------------------------------------------
-- MASTER: Districts
-- ------------------------------------------------------------
CREATE TABLE districts (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    is_active   TINYINT(1) NOT NULL DEFAULT 1,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_district_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- MASTER: Blocks
-- ------------------------------------------------------------
CREATE TABLE blocks (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    district_id INT UNSIGNED NOT NULL,
    name        VARCHAR(100) NOT NULL,
    is_active   TINYINT(1) NOT NULL DEFAULT 1,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (district_id) REFERENCES districts(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    UNIQUE KEY uq_block_district (district_id, name),
    INDEX idx_blocks_district (district_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- MASTER: Schools
-- ------------------------------------------------------------
CREATE TABLE schools (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    block_id    INT UNSIGNED NOT NULL,
    school_name VARCHAR(255) NOT NULL,
    udise_code  VARCHAR(20)  NOT NULL,
    is_active   TINYINT(1) NOT NULL DEFAULT 1,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (block_id) REFERENCES blocks(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    UNIQUE KEY uq_udise (udise_code),
    INDEX idx_schools_block (block_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- MASTER: Grades
-- ------------------------------------------------------------
CREATE TABLE grades (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name             VARCHAR(100) NOT NULL,
    is_school_leader TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1 = School Leaders (no subject required)',
    sort_order       SMALLINT NOT NULL DEFAULT 0,
    is_active        TINYINT(1) NOT NULL DEFAULT 1,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_grade_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- MASTER: Subjects
-- ------------------------------------------------------------
CREATE TABLE subjects (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    sort_order  SMALLINT NOT NULL DEFAULT 0,
    is_active   TINYINT(1) NOT NULL DEFAULT 1,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_subject_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- MASTER: Grade ↔ Subject mapping (many-to-many)
-- ------------------------------------------------------------
CREATE TABLE grade_subject_map (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    grade_id    INT UNSIGNED NOT NULL,
    subject_id  INT UNSIGNED NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (grade_id)   REFERENCES grades(id)   ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE ON UPDATE CASCADE,
    UNIQUE KEY uq_grade_subject (grade_id, subject_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- MASTER: Cycles
-- ------------------------------------------------------------
CREATE TABLE cycles (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(50) NOT NULL,
    sort_order  SMALLINT NOT NULL DEFAULT 0,
    is_active   TINYINT(1) NOT NULL DEFAULT 1,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_cycle_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- MASTER: Projects
-- subject_id is NULL when grade is School Leaders
-- ------------------------------------------------------------
CREATE TABLE projects (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    grade_id      INT UNSIGNED NOT NULL,
    subject_id    INT UNSIGNED NULL DEFAULT NULL,
    cycle_id      INT UNSIGNED NOT NULL,
    project_title VARCHAR(255) NOT NULL,
    duration      VARCHAR(50)  DEFAULT NULL COMMENT 'e.g. 1 Month',
    objective     TEXT         DEFAULT NULL,
    project_file  VARCHAR(255) DEFAULT NULL COMMENT 'Relative path under uploads/projects/',
    is_active     TINYINT(1) NOT NULL DEFAULT 1,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (grade_id)   REFERENCES grades(id)   ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (cycle_id)   REFERENCES cycles(id)   ON DELETE RESTRICT ON UPDATE CASCADE,
    UNIQUE KEY uq_project (grade_id, subject_id, cycle_id),
    INDEX idx_projects_lookup (grade_id, subject_id, cycle_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- MASTER: Project Tasks (variable number per project)
-- ------------------------------------------------------------
CREATE TABLE project_tasks (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    project_id       INT UNSIGNED NOT NULL,
    task_number      SMALLINT UNSIGNED NOT NULL,
    task_type        VARCHAR(20) NOT NULL DEFAULT 'Task' COMMENT 'Task or Showcase',
    task_description TEXT NOT NULL,
    sort_order       SMALLINT NOT NULL DEFAULT 0,
    is_active        TINYINT(1) NOT NULL DEFAULT 1,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE ON UPDATE CASCADE,
    UNIQUE KEY uq_project_task (project_id, task_number),
    INDEX idx_tasks_project (project_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- TRANSACTION: Teacher Submissions
-- ------------------------------------------------------------
CREATE TABLE teacher_submissions (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    submission_id   VARCHAR(20) NOT NULL COMMENT 'e.g. LEP-2026-000001',
    teacher_name    VARCHAR(150) NOT NULL,
    designation     VARCHAR(100) NOT NULL,
    district_id     INT UNSIGNED NOT NULL,
    block_id        INT UNSIGNED NOT NULL,
    school_id       INT UNSIGNED NOT NULL,
    grade_id        INT UNSIGNED NOT NULL,
    subject_id      INT UNSIGNED NULL DEFAULT NULL,
    cycle_id        INT UNSIGNED NOT NULL,
    project_id      INT UNSIGNED NOT NULL,
    video_link      VARCHAR(500) DEFAULT NULL COMMENT 'Optional project video link (v1.1)',
    submitted_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ip_address      VARCHAR(45) DEFAULT NULL,
    FOREIGN KEY (district_id) REFERENCES districts(id) ON DELETE RESTRICT,
    FOREIGN KEY (block_id)    REFERENCES blocks(id)    ON DELETE RESTRICT,
    FOREIGN KEY (school_id)   REFERENCES schools(id)   ON DELETE RESTRICT,
    FOREIGN KEY (grade_id)    REFERENCES grades(id)    ON DELETE RESTRICT,
    FOREIGN KEY (subject_id)  REFERENCES subjects(id)  ON DELETE RESTRICT,
    FOREIGN KEY (cycle_id)    REFERENCES cycles(id)    ON DELETE RESTRICT,
    FOREIGN KEY (project_id)  REFERENCES projects(id)  ON DELETE RESTRICT,
    UNIQUE KEY uq_submission_id (submission_id),
    INDEX idx_submissions_date (submitted_at),
    INDEX idx_submissions_school (school_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- TRANSACTION: Task Responses (one row per task per submission)
-- Evidence & video moved to project level in v1.1
-- ------------------------------------------------------------
CREATE TABLE task_responses (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    submission_id   INT UNSIGNED NOT NULL COMMENT 'FK to teacher_submissions.id',
    task_id         INT UNSIGNED NOT NULL,
    completed       ENUM('Yes','No') NOT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (submission_id) REFERENCES teacher_submissions(id) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (task_id)       REFERENCES project_tasks(id)       ON DELETE RESTRICT ON UPDATE CASCADE,
    UNIQUE KEY uq_submission_task (submission_id, task_id),
    INDEX idx_responses_submission (submission_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- TRANSACTION: Submission Evidence (multiple files per submission – v1.1)
-- ------------------------------------------------------------
CREATE TABLE submission_evidence (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    submission_id   INT UNSIGNED NOT NULL COMMENT 'FK to teacher_submissions.id',
    file_path       VARCHAR(255) NOT NULL,
    original_name   VARCHAR(255) DEFAULT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (submission_id) REFERENCES teacher_submissions(id) ON DELETE CASCADE ON UPDATE CASCADE,
    INDEX idx_evidence_submission (submission_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- SAMPLE MASTER DATA
-- ============================================================

-- Districts (sample Nagaland districts)
INSERT INTO districts (name) VALUES
('Kohima'),
('Dimapur'),
('Mokokchung'),
('Tuensang'),
('Mon'),
('Phek'),
('Wokha'),
('Zunheboto');

-- Blocks
INSERT INTO blocks (district_id, name) VALUES
(1, 'Kohima Sadar'),
(1, 'Jakhama'),
(1, 'Chiephobozou'),
(2, 'Dimapur Sadar'),
(2, 'Chumukedima'),
(2, 'Medziphema'),
(3, 'Mokokchung Sadar'),
(3, 'Changtongya'),
(4, 'Tuensang Sadar'),
(5, 'Mon Sadar');

-- Schools (sample)
INSERT INTO schools (block_id, school_name, udise_code) VALUES
(1, 'Government High School Kohima', '13010100101'),
(1, 'Baptist High School Kohima', '13010100102'),
(1, 'Rüzhükhrie Government Higher Secondary School', '13010100103'),
(2, 'Jakhama Government Middle School', '13010100201'),
(3, 'Chiephobozou Government School', '13010100301'),
(4, 'Government Higher Secondary School Dimapur', '13020100101'),
(4, 'Christian Higher Secondary School Dimapur', '13020100102'),
(5, 'Chumukedima Government High School', '13020100201'),
(6, 'Medziphema Government School', '13020100301'),
(7, 'Government High School Mokokchung', '13030100101'),
(8, 'Changtongya Government Middle School', '13030100201'),
(9, 'Tuensang Government High School', '13040100101'),
(10, 'Mon Government Higher Secondary School', '13050100101');

-- Grades (official Cycle 1 list – v1.4)
INSERT INTO grades (name, is_school_leader, sort_order) VALUES
('Pre-Primary (A-B)', 0, 1),
('Grade 1',           0, 2),
('Grade 2',           0, 3),
('Grade 3',           0, 4),
('Grade 4',           0, 5),
('Grade 5',           0, 6),
('Grade 6',           0, 7),
('Grade 7',           0, 8),
('Grade 8',           0, 9),
('School Leaders',    1, 99);

-- Subjects (official Cycle 1 display names – v1.4)
INSERT INTO subjects (name, sort_order) VALUES
('Pre-Primary Teacher (Grade A & B)', 1),
('Arts Teacher (A & B)',              2),
('Literacy Teacher (Grade 1, 2 & 3)', 3),
('Numeracy Teacher (Grade 1, 2 & 3)', 4),
('Arts Teacher (Grade 1-5)',          5),
('Math (4,5)',                        6),
('English (4,5)',                     7),
('Math (6,7,8)',                      8),
('Science (6,7,8)',                   9),
('Art Education (Grade 6-8)',         10);

-- Official Grade → Subject mapping (Cycle 1)
-- School Leaders: no subject mapping (dropdown hidden)
INSERT INTO grade_subject_map (grade_id, subject_id) VALUES
-- Pre-Primary (A-B)  → subjects 1, 2
(1, 1), (1, 2),
-- Grade 1            → Literacy, Numeracy, Arts (1-5)
(2, 3), (2, 4), (2, 5),
-- Grade 2
(3, 3), (3, 4), (3, 5),
-- Grade 3
(4, 3), (4, 4), (4, 5),
-- Grade 4            → Math (4,5), English (4,5), Arts (1-5)
(5, 6), (5, 7), (5, 5),
-- Grade 5
(6, 6), (6, 7), (6, 5),
-- Grade 6            → Math (6-8), Science (6-8), Art Education (6-8)
(7, 8), (7, 9), (7, 10),
-- Grade 7
(8, 8), (8, 9), (8, 10),
-- Grade 8
(9, 8), (9, 9), (9, 10);

-- Cycles (Cycle 1 is the active reporting cycle)
INSERT INTO cycles (name, sort_order) VALUES
('Cycle 1', 1),
('Cycle 2', 2),
('Cycle 3', 3);

-- Projects (Cycle 1 – first 3 subjects from official workbook)
-- grade_id: 1=Pre-Primary, 10=School Leaders | subject: 1=PP Teacher, 2=Arts (A&B)
INSERT INTO projects (grade_id, subject_id, cycle_id, project_title, duration, objective, project_file) VALUES
(10, NULL, 1,
 'Setting Direction – School Vision & Priority Goals',
 '1 Month',
 'To establish clear, shared school priorities that guide teaching, learning, and improvement efforts.',
 'uploads/projects/Revised_LNF_4.0_Cycle-1_School_Leader.pdf'),
(1, 1, 1,
 'Classroom Arrangement: Building a Supportive Learning Space',
 '1 Month',
 'Teachers will enhance the quality of early learning experiences, identifying improvement areas, organizing learning spaces effectively, implementing developmentally appropriate activities, and observing and reflecting on children''s play and learning.',
 'uploads/projects/Pre_Primary_Teacher_Grade_A_B_Cycle_1.pdf'),
(1, 2, 1,
 'Sensory Exploration for Fine Motor Development',
 '1 Month',
 'Strengthen development of fine motor skills - hand strength, finger movement, and hand-eye coordination - in learners by engaging them in movement-based art activities using yarn and clay.',
 'uploads/projects/Arts_Teacher_A_B_Cycle_1.pdf');

-- Tasks: School Leaders (project_id = 1) – 7 tasks
INSERT INTO project_tasks (project_id, task_number, task_description, sort_order) VALUES
(1, 1, 'Conduct a staff reflection meeting on current school status (learning levels, attendance, engagement).', 1),
(1, 2, 'Identify 2–3 priority areas (e.g., reading, math, student participation, etc.).', 2),
(1, 3, 'Co-create simple, measurable school goals for the academic year.', 3),
(1, 4, 'Break goals into term-wise focus areas.', 4),
(1, 5, 'Display goals visibly (staff room/classrooms) for constant reference.', 5),
(1, 6, 'Communicate priorities to students and parents (assembly/PTM).', 6),
(1, 7, 'Review progress once every month in staff meetings.', 7);

-- Tasks: Pre-Primary Teacher (project_id = 2) – 5 tasks
INSERT INTO project_tasks (project_id, task_number, task_description, sort_order) VALUES
(2, 1, 'Engage with the ideal ECCE strategy document.', 1),
(2, 2, 'Plan and conduct a classroom diagnostic using the checklist and identify three areas for improvement.', 2),
(2, 3, 'Organise your classroom using the IDEAL ECCE classroom arrangement.', 3),
(2, 4, 'Conduct activities using the classroom setup and upload photos of children participating.', 4),
(2, 5, 'Observe classroom play and share moments and stories of children.', 5);

-- Tasks: Arts Teacher A & B (project_id = 3) – 6 tasks
INSERT INTO project_tasks (project_id, task_number, task_description, sort_order) VALUES
(3, 1, 'Refer to the learning resource and plan for the session with materials and resources.', 1),
(3, 2, 'Conduct Activity 1: Yarn Stick – Students play with yarn and explore different ways to wrap, twist, and weave it around sticks.', 2),
(3, 3, 'Conduct Activity 2: Clay Molding – Students play with clay and experiment with different molding techniques.', 3),
(3, 4, 'Observe & Track Student Progress', 4),
(3, 5, 'Reflection: Teachers to reflect & (✔) the response that best reflects how the art activities supported learners'' fine motor skills.', 5),
(3, 6, 'Create an art wall in the classroom and collect student artworks, and share a picture of the artworks.', 6);

-- ============================================================
-- END OF SCHEMA + SAMPLE DATA
-- ============================================================

