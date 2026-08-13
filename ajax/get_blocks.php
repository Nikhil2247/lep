<?php
/**
 * AJAX: Return blocks for a given district
 */
define('LEP_APP', true);
require_once dirname(__DIR__) . '/config/config.php';
require_once dirname(__DIR__) . '/includes/db.php';
require_once dirname(__DIR__) . '/includes/functions.php';

header('Content-Type: application/json; charset=utf-8');

$districtId = filter_input(INPUT_GET, 'district_id', FILTER_VALIDATE_INT);

if (!$districtId) {
    jsonResponse(['success' => false, 'message' => 'Invalid district'], 400);
}

try {
    $pdo  = getPDO();
    $stmt = $pdo->prepare(
        "SELECT id, name FROM blocks
         WHERE district_id = :did AND is_active = 1
         ORDER BY name"
    );
    $stmt->execute(['did' => $districtId]);
    $blocks = $stmt->fetchAll();

    jsonResponse(['success' => true, 'data' => $blocks]);
} catch (Exception $e) {
    error_log('get_blocks: ' . $e->getMessage());
    jsonResponse(['success' => false, 'message' => 'Server error'], 500);
}
