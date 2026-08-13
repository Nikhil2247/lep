-- ============================================================
-- LEP Version 1.1 Upgrade Script
-- Adds support for multiple project-level evidence files
-- and a single video link per submission.
-- Safe to run on an existing v1.0 database.
-- ============================================================

USE lep_nagaland;

-- 1. Add video_link column to teacher_submissions (if not exists)
SET @col_exists = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'lep_nagaland'
      AND TABLE_NAME   = 'teacher_submissions'
      AND COLUMN_NAME  = 'video_link'
);

SET @sql = IF(@col_exists = 0,
    'ALTER TABLE teacher_submissions ADD COLUMN video_link VARCHAR(500) DEFAULT NULL AFTER project_id',
    'SELECT "video_link column already exists" AS info'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 2. Create submission_evidence table for multiple files
CREATE TABLE IF NOT EXISTS submission_evidence (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    submission_id   INT UNSIGNED NOT NULL COMMENT 'FK to teacher_submissions.id',
    file_path       VARCHAR(255) NOT NULL,
    original_name   VARCHAR(255) DEFAULT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (submission_id) REFERENCES teacher_submissions(id) ON DELETE CASCADE ON UPDATE CASCADE,
    INDEX idx_evidence_submission (submission_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Note: The old columns evidence_file and video_link on task_responses
-- are left in place for backward compatibility but are no longer written to.
-- They may be dropped in a future major version if desired.
