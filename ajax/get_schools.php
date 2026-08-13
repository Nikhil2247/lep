<?php
/**
 * AJAX: Return schools for a given block
 */
define('LEP_APP', true);
require_once dirname(__DIR__) . '/config/config.php';
require_once dirname(__DIR__) . '/includes/db.php';
require_once dirname(__DIR__) . '/includes/functions.php';

header('Content-Type: application/json; charset=utf-8');

$blockId = filter_input(INPUT_GET, 'block_id', FILTER_VALIDATE_INT);

if (!$blockId) {
    jsonResponse(['success' => false, 'message' => 'Invalid block'], 400);
}

try {
    $pdo  = getPDO();
    $stmt = $pdo->prepare(
        "SELECT id, school_name, udise_code
         FROM schools
         WHERE block_id = :bid AND is_active = 1
         ORDER BY school_name"
    );
    $stmt->execute(['bid' => $blockId]);
    $schools = $stmt->fetchAll();

    jsonResponse(['success' => true, 'data' => $schools]);
} catch (Exception $e) {
    error_log('get_schools: ' . $e->getMessage());
    jsonResponse(['success' => false, 'message' => 'Server error'], 500);
}
