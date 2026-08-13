<?php
/**
 * LEP – Learning Enhancement Program
 * Application Configuration
 * Government of Nagaland | Samagra Shiksha Nagaland
 */

declare(strict_types=1);

// Prevent direct access
if (!defined('LEP_APP')) {
    define('LEP_APP', true);
}

// ------------------------------------------------------------
// Environment
// ------------------------------------------------------------
define('APP_NAME', 'Learning Enhancement Program (LEP)');
define('APP_VERSION', '2.0');
define('APP_YEAR', '2026');

// Base path (adjust if installed in a subdirectory)
define('BASE_PATH', dirname(__DIR__));
define('BASE_URL', ''); // e.g. '/lep' if in subfolder; leave empty for root

// ------------------------------------------------------------
// Database credentials – UPDATE THESE FOR YOUR ENVIRONMENT
// ------------------------------------------------------------
define('DB_HOST', 'localhost');
define('DB_NAME', 'lep_nagaland');
define('DB_USER', 'lep_user');
define('DB_PASS', 'CHANGE_THIS');
define('DB_CHARSET', 'utf8mb4');

// ------------------------------------------------------------
// Paths
// ------------------------------------------------------------
define('UPLOADS_PATH', BASE_PATH . '/uploads');
define('EVIDENCE_PATH', UPLOADS_PATH . '/evidence');
define('PROJECTS_PATH', UPLOADS_PATH . '/projects');

// Logo – replace the file at this path without touching code
define('LOGO_PATH', 'assets/images/logo.png');
define('LOGO_ALT', 'Samagra Shiksha Nagaland – LEP');

// ------------------------------------------------------------
// Upload limits (v1.2.2 – Project Completion Evidence)
// ------------------------------------------------------------
define('MAX_EVIDENCE_TOTAL_SIZE', 5 * 1024 * 1024); // combined size of ALL files ≤ 5 MB
define('MAX_EVIDENCE_FILES', 5);                      // maximum 5 files per submission
define('ALLOWED_EVIDENCE_EXT', ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx']);

// Backward-compatible alias (used by validateEvidenceFile for a single-file sanity check)
define('MAX_EVIDENCE_SIZE', MAX_EVIDENCE_TOTAL_SIZE);

// ------------------------------------------------------------
// Submission ID prefix
// ------------------------------------------------------------
define('SUBMISSION_PREFIX', 'LEP-' . date('Y') . '-');

// ------------------------------------------------------------
// Error reporting (turn off display in production)
// ------------------------------------------------------------
error_reporting(E_ALL);
ini_set('display_errors', '0'); // set to '1' only during development
ini_set('log_errors', '1');

// Timezone
date_default_timezone_set('Asia/Kolkata');
