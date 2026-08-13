<?php
/**
 * AJAX: Load Project + its Tasks for given Grade + Subject (optional) + Cycle
 */
define('LEP_APP', true);
require_once dirname(__DIR__) . '/config/config.php';
require_once dirname(__DIR__) . '/includes/db.php';
require_once dirname(__DIR__) . '/includes/functions.php';

header('Content-Type: application/json; charset=utf-8');

$gradeId   = filter_input(INPUT_GET, 'grade_id', FILTER_VALIDATE_INT);
$subjectId = filter_input(INPUT_GET, 'subject_id', FILTER_VALIDATE_INT);
$cycleId   = filter_input(INPUT_GET, 'cycle_id', FILTER_VALIDATE_INT);

if (!$gradeId || !$cycleId) {
    jsonResponse(['success' => false, 'message' => 'Grade and Cycle are required'], 400);
}

// Treat 0 or empty subject as NULL (School Leaders)
if ($subjectId === false || $subjectId === 0) {
    $subjectId = null;
}

try {
    $pdo = getPDO();

    if ($subjectId === null) {
        $sql = "SELECT p.id, p.project_title, p.duration, p.objective, p.project_file, g.is_school_leader
                FROM projects p
                INNER JOIN grades g ON g.id = p.grade_id
                WHERE p.grade_id = :gid
                  AND p.subject_id IS NULL
                  AND p.cycle_id = :cid
                  AND p.is_active = 1
                LIMIT 1";
        $params = ['gid' => $gradeId, 'cid' => $cycleId];
    } else {
        $sql = "SELECT p.id, p.project_title, p.duration, p.objective, p.project_file, g.is_school_leader
                FROM projects p
                INNER JOIN grades g ON g.id = p.grade_id
                WHERE p.grade_id = :gid
                  AND p.subject_id = :sid
                  AND p.cycle_id = :cid
                  AND p.is_active = 1
                LIMIT 1";
        $params = ['gid' => $gradeId, 'sid' => $subjectId, 'cid' => $cycleId];
    }

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $project = $stmt->fetch();

    if (!$project) {
        jsonResponse([
            'success' => false,
            'message' => 'No project found for the selected Grade / Subject / Cycle combination.'
        ]);
    }

    $tstmt = $pdo->prepare(
        "SELECT id, task_number, task_type, task_description
         FROM project_tasks
         WHERE project_id = :pid AND is_active = 1
         ORDER BY sort_order, task_number"
    );
    $tstmt->execute(['pid' => $project['id']]);
    $tasks = $tstmt->fetchAll();

    jsonResponse([
        'success' => true,
        'project' => [
            'id'           => (int)$project['id'],
            'title'        => $project['project_title'],
            'duration'     => $project['duration'] ?: '—',
            'objective'    => $project['objective'] ?? '',
            'file'         => $project['project_file'],
            'has_download' => !empty($project['project_file'])
        ],
        'tasks' => $tasks
    ]);
} catch (Exception $e) {
    error_log('get_project: ' . $e->getMessage());
    jsonResponse(['success' => false, 'message' => 'Server error'], 500);
}
