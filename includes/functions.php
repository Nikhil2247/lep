<?php
/**
 * Shared helper functions
 * LEP Application
 */

declare(strict_types=1);

if (!defined('LEP_APP')) {
    require_once dirname(__DIR__) . '/config/config.php';
}

/**
 * Sanitize string input
 */
function sanitize(string $value): string
{
    return htmlspecialchars(trim($value), ENT_QUOTES | ENT_HTML5, 'UTF-8');
}

/**
 * Generate next Submission ID: LEP-YYYY-000001
 */
function generateSubmissionId(PDO $pdo): string
{
    $prefix = SUBMISSION_PREFIX; // e.g. LEP-2026-
    $year   = date('Y');

    $stmt = $pdo->prepare(
        "SELECT submission_id FROM teacher_submissions
         WHERE submission_id LIKE :prefix
         ORDER BY id DESC LIMIT 1"
    );
    $stmt->execute(['prefix' => $prefix . '%']);
    $last = $stmt->fetchColumn();

    if ($last) {
        $num = (int) substr($last, strlen($prefix));
        $next = $num + 1;
    } else {
        $next = 1;
    }

    return $prefix . str_pad((string) $next, 6, '0', STR_PAD_LEFT);
}

/**
 * Validate a single uploaded evidence file (v1.1)
 * Returns ['ok' => true, 'ext' => ..., 'tmp' => ..., 'name' => ...] or ['ok' => false, 'error' => ...]
 */
function validateEvidenceFile(array $file): array
{
    if ($file['error'] === UPLOAD_ERR_NO_FILE) {
        return ['ok' => true, 'empty' => true];
    }

    if ($file['error'] !== UPLOAD_ERR_OK) {
        return ['ok' => false, 'error' => 'Upload error code: ' . $file['error']];
    }

    // Single file must not exceed the total budget of 5 MB
    if ($file['size'] > MAX_EVIDENCE_TOTAL_SIZE) {
        return ['ok' => false, 'error' => 'File exceeds the maximum allowed size of 5 MB.'];
    }

    $ext = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
    if (!in_array($ext, ALLOWED_EVIDENCE_EXT, true)) {
        return ['ok' => false, 'error' => 'Invalid file type. Allowed: ' . implode(', ', ALLOWED_EVIDENCE_EXT)];
    }

    $finfo = finfo_open(FILEINFO_MIME_TYPE);
    $mime  = finfo_file($finfo, $file['tmp_name']);
    finfo_close($finfo);

    $allowedMimes = [
        'application/pdf',
        'image/jpeg',
        'image/png',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ];
    if (!in_array($mime, $allowedMimes, true)) {
        return ['ok' => false, 'error' => 'Invalid file content type.'];
    }

    return [
        'ok'    => true,
        'empty' => false,
        'ext'   => $ext,
        'tmp'   => $file['tmp_name'],
        'name'  => $file['name']
    ];
}

/**
 * Save a single evidence file under uploads/evidence/{SubmissionID}/
 * Returns relative path string or null on failure.
 * Physical filename is randomized; original name is stored in DB separately.
 */
function saveEvidenceFile(array $validated, string $submissionCode, int $index = 0): ?string
{
    if (!empty($validated['empty'])) {
        return null;
    }

    // Trusted Submission ID folder name (e.g. LEP-2026-000001)
    $folder = preg_replace('/[^A-Za-z0-9\-]/', '', $submissionCode);
    if ($folder === '') {
        return null;
    }

    if (!is_dir(EVIDENCE_PATH)) {
        if (!mkdir(EVIDENCE_PATH, 0755, true) && !is_dir(EVIDENCE_PATH)) {
            return null;
        }
    }

    $dir = EVIDENCE_PATH . DIRECTORY_SEPARATOR . $folder;
    if (!is_dir($dir)) {
        if (!mkdir($dir, 0755, true) && !is_dir($dir)) {
            return null;
        }
    }

    $safeName = 'evidence_' . ($index + 1) . '_' . bin2hex(random_bytes(4)) . '.' . $validated['ext'];
    $dest     = $dir . DIRECTORY_SEPARATOR . $safeName;

    if (!move_uploaded_file($validated['tmp'], $dest)) {
        return null;
    }

    return 'uploads/evidence/' . $folder . '/' . $safeName;
}

/**
 * JSON response helper for AJAX
 */
function jsonResponse(array $data, int $code = 200): void
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

/**
 * Fetch all active grades ordered
 */
function getGrades(PDO $pdo): array
{
    $stmt = $pdo->query(
        "SELECT id, name, is_school_leader
         FROM grades
         WHERE is_active = 1
         ORDER BY sort_order, name"
    );
    return $stmt->fetchAll();
}

/**
 * Fetch all active cycles
 */
function getCycles(PDO $pdo): array
{
    $stmt = $pdo->query(
        "SELECT id, name FROM cycles WHERE is_active = 1 ORDER BY sort_order, name"
    );
    return $stmt->fetchAll();
}

/**
 * Fetch districts
 */
function getDistricts(PDO $pdo): array
{
    $stmt = $pdo->query(
        "SELECT id, name FROM districts WHERE is_active = 1 ORDER BY name"
    );
    return $stmt->fetchAll();
}
