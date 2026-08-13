<?php
/**
 * AJAX: Return subjects mapped to a grade
 * If grade is School Leaders → return empty (UI will hide dropdown)
 */
define('LEP_APP', true);
require_once dirname(__DIR__) . '/config/config.php';
require_once dirname(__DIR__) . '/includes/db.php';
require_once dirname(__DIR__) . '/includes/functions.php';

header('Content-Type: application/json; charset=utf-8');

$gradeId = filter_input(INPUT_GET, 'grade_id', FILTER_VALIDATE_INT);

if (!$gradeId) {
    jsonResponse(['success' => false, 'message' => 'Invalid grade'], 400);
}

try {
    $pdo = getPDO();

    // Check if School Leaders
    $stmt = $pdo->prepare("SELECT is_school_leader FROM grades WHERE id = :gid AND is_active = 1");
    $stmt->execute(['gid' => $gradeId]);
    $grade = $stmt->fetch();

    if (!$grade) {
        jsonResponse(['success' => false, 'message' => 'Grade not found'], 404);
    }

    if ((int)$grade['is_school_leader'] === 1) {
        jsonResponse([
            'success'           => true,
            'is_school_leader'  => true,
            'data'              => []
        ]);
    }

    $stmt = $pdo->prepare(
        "SELECT s.id, s.name
         FROM subjects s
         INNER JOIN grade_subject_map m ON m.subject_id = s.id
         WHERE m.grade_id = :gid AND s.is_active = 1
         ORDER BY s.sort_order, s.name"
    );
    $stmt->execute(['gid' => $gradeId]);
    $subjects = $stmt->fetchAll();

    jsonResponse([
        'success'          => true,
        'is_school_leader' => false,
        'data'             => $subjects
    ]);
} catch (Exception $e) {
    error_log('get_subjects: ' . $e->getMessage());
    jsonResponse(['success' => false, 'message' => 'Server error'], 500);
}
