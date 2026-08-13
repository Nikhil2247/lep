<?php
/**
 * Secure Project Document Download
 * Validates project exists and serves the file
 */
define('LEP_APP', true);
require_once __DIR__ . '/config/config.php';
require_once __DIR__ . '/includes/db.php';
require_once __DIR__ . '/includes/functions.php';

$projectId = filter_input(INPUT_GET, 'id', FILTER_VALIDATE_INT);

if (!$projectId) {
    http_response_code(400);
    die('Invalid request.');
}

try {
    $pdo  = getPDO();
    $stmt = $pdo->prepare(
        "SELECT project_title, project_file
         FROM projects
         WHERE id = :id AND is_active = 1"
    );
    $stmt->execute(['id' => $projectId]);
    $project = $stmt->fetch();

    if (!$project || empty($project['project_file'])) {
        http_response_code(404);
        die('Project document not found.');
    }

    $filePath = BASE_PATH . '/' . $project['project_file'];

    if (!is_file($filePath) || !is_readable($filePath)) {
        http_response_code(404);
        die('File is missing on the server. Please contact the administrator.');
    }

    // Security: path must stay under PROJECTS_PATH
    $realFile = realpath($filePath);
    $realRoot = realpath(PROJECTS_PATH);
    if ($realFile === false || $realRoot === false || strpos($realFile, $realRoot) !== 0) {
        http_response_code(404);
        die('File is missing on the server. Please contact the administrator.');
    }

    $filename = basename($realFile);
    $mime     = function_exists('mime_content_type') ? (mime_content_type($realFile) ?: 'application/octet-stream') : 'application/octet-stream';
    $size     = filesize($realFile);

    // Stream large project PDFs without loading entire file into memory
    @set_time_limit(0);
    if (function_exists('apache_setenv')) {
        @apache_setenv('no-gzip', '1');
    }
    @ini_set('zlib.output_compression', '0');

    header('Content-Type: ' . $mime);
    header('Content-Disposition: attachment; filename="' . str_replace('"', '', $filename) . '"');
    header('Content-Length: ' . (string) $size);
    header('Cache-Control: private, max-age=0, must-revalidate');
    header('Pragma: public');
    header('X-Content-Type-Options: nosniff');

    $fp = fopen($realFile, 'rb');
    if ($fp === false) {
        http_response_code(500);
        die('Download failed.');
    }
    while (!feof($fp)) {
        echo fread($fp, 8192);
        flush();
    }
    fclose($fp);
    exit;
} catch (Exception $e) {
    error_log('download_project: ' . $e->getMessage());
    http_response_code(500);
    die('Download failed.');
}
