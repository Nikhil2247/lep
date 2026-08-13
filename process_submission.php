<?php
/**
 * Handle LEP Form Submission (v1.1)
 * Creates teacher_submissions + task_responses + submission_evidence
 */
define('LEP_APP', true);
require_once __DIR__ . '/config/config.php';
require_once __DIR__ . '/includes/db.php';
require_once __DIR__ . '/includes/functions.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: index.php');
    exit;
}

$errors = [];
$pdo    = getPDO();

// ── Collect & validate Section A ──
$teacher_name = trim($_POST['teacher_name'] ?? '');
$designation  = trim($_POST['designation'] ?? '');
$district_id  = filter_input(INPUT_POST, 'district_id', FILTER_VALIDATE_INT);
$block_id     = filter_input(INPUT_POST, 'block_id', FILTER_VALIDATE_INT);
$school_id    = filter_input(INPUT_POST, 'school_id', FILTER_VALIDATE_INT);

if ($teacher_name === '') $errors[] = 'Teacher Name is required.';
if ($designation === '')  $errors[] = 'Designation is required.';
if (!$district_id)        $errors[] = 'District is required.';
if (!$block_id)           $errors[] = 'Block is required.';
if (!$school_id)          $errors[] = 'School is required.';

// ── Section B ──
$grade_id   = filter_input(INPUT_POST, 'grade_id', FILTER_VALIDATE_INT);
$subject_id = filter_input(INPUT_POST, 'subject_id', FILTER_VALIDATE_INT);
$cycle_id   = filter_input(INPUT_POST, 'cycle_id', FILTER_VALIDATE_INT);
$project_id = filter_input(INPUT_POST, 'project_id', FILTER_VALIDATE_INT);

if (!$grade_id)   $errors[] = 'Grade is required.';
if (!$cycle_id)   $errors[] = 'Cycle is required.';
if (!$project_id) $errors[] = 'Project could not be determined. Please re-select Grade / Subject / Cycle.';

// Determine if School Leader
$isSchoolLeader = false;
if ($grade_id) {
    $gstmt = $pdo->prepare("SELECT is_school_leader FROM grades WHERE id = ?");
    $gstmt->execute([$grade_id]);
    $isSchoolLeader = (int)$gstmt->fetchColumn() === 1;
}

if (!$isSchoolLeader && !$subject_id) {
    $errors[] = 'Subject is required for the selected Grade.';
}
if ($isSchoolLeader) {
    $subject_id = null;
}

// ── Tasks (Yes/No only) ──
$taskCompleted = $_POST['task_completed'] ?? [];

if (empty($taskCompleted)) {
    $errors[] = 'No task responses received. Please complete the Project Tasks section.';
}

if ($project_id && empty($errors)) {
    $tstmt = $pdo->prepare(
        "SELECT id FROM project_tasks WHERE project_id = ? AND is_active = 1"
    );
    $tstmt->execute([$project_id]);
    $expectedTaskIds = $tstmt->fetchAll(PDO::FETCH_COLUMN);

    foreach ($expectedTaskIds as $tid) {
        if (!isset($taskCompleted[$tid]) || !in_array($taskCompleted[$tid], ['Yes', 'No'], true)) {
            $errors[] = "Please select Yes or No for all tasks.";
            break;
        }
    }
}

// ── Project-level Video Link (optional) ──
$videoLink = trim($_POST['project_video_link'] ?? '');
if ($videoLink !== '' && !filter_var($videoLink, FILTER_VALIDATE_URL)) {
    $errors[] = 'Video Link must be a valid URL.';
}

// ── Multiple Evidence Files (mandatory ≥1, max 5, combined ≤ 5 MB) ──
$evidenceFiles = $_FILES['project_evidence'] ?? null;
$validatedFiles = [];
$fileCount = 0;

if ($evidenceFiles && is_array($evidenceFiles['name'])) {
    $fileCount = count(array_filter(
        $evidenceFiles['name'],
        static fn($n) => is_string($n) && $n !== ''
    ));
}

if ($fileCount < 1) {
    $errors[] = 'Please upload at least one evidence file before submitting your response.';
} elseif ($fileCount > MAX_EVIDENCE_FILES) {
    $errors[] = 'You may upload a maximum of ' . MAX_EVIDENCE_FILES . ' evidence files.';
} else {
    $totalSize = 0;
    for ($i = 0; $i < count($evidenceFiles['name']); $i++) {
        if (
            !isset($evidenceFiles['error'][$i])
            || $evidenceFiles['error'][$i] === UPLOAD_ERR_NO_FILE
            || ($evidenceFiles['name'][$i] ?? '') === ''
        ) {
            continue;
        }
        $fileArr = [
            'name'     => $evidenceFiles['name'][$i],
            'type'     => $evidenceFiles['type'][$i] ?? '',
            'tmp_name' => $evidenceFiles['tmp_name'][$i] ?? '',
            'error'    => $evidenceFiles['error'][$i],
            'size'     => $evidenceFiles['size'][$i] ?? 0,
        ];
        $validated = validateEvidenceFile($fileArr);
        if (!$validated['ok']) {
            $errors[] = 'Evidence file "' . sanitize($fileArr['name']) . '": ' . $validated['error'];
        } elseif (empty($validated['empty'])) {
            $totalSize += (int) $fileArr['size'];
            $validatedFiles[] = $validated;
        }
    }

    if (count($validatedFiles) < 1) {
        // All files failed validation, or none usable
        if (empty(array_filter($errors, static fn($e) => str_contains($e, 'Evidence file')))) {
            $errors[] = 'Please upload at least one evidence file before submitting your response.';
        }
    } elseif ($totalSize > MAX_EVIDENCE_TOTAL_SIZE) {
        $errors[] = 'The total combined size of all uploaded evidence files cannot exceed 5 MB. Please remove one or more files and try again.';
        $validatedFiles = [];
    }
}

// ── Early exit on validation errors ──
if (!empty($errors)) {
    session_start();
    $_SESSION['lep_errors'] = $errors;
    $_SESSION['lep_old']    = $_POST;
    header('Location: index.php');
    exit;
}

// ── Begin transaction ──
try {
    $pdo->beginTransaction();

    $submissionCode = generateSubmissionId($pdo);

    $stmt = $pdo->prepare(
        "INSERT INTO teacher_submissions
            (submission_id, teacher_name, designation, district_id, block_id, school_id,
             grade_id, subject_id, cycle_id, project_id, video_link, ip_address)
         VALUES
            (:sid, :tname, :desig, :did, :bid, :schid, :gid, :subid, :cid, :pid, :vlink, :ip)"
    );

    $stmt->execute([
        'sid'   => $submissionCode,
        'tname' => $teacher_name,
        'desig' => $designation,
        'did'   => $district_id,
        'bid'   => $block_id,
        'schid' => $school_id,
        'gid'   => $grade_id,
        'subid' => $subject_id,
        'cid'   => $cycle_id,
        'pid'   => $project_id,
        'vlink' => $videoLink !== '' ? $videoLink : null,
        'ip'    => $_SERVER['REMOTE_ADDR'] ?? null
    ]);

    $submissionDbId = (int)$pdo->lastInsertId();

    // Insert task responses (Yes/No only)
    $insertResp = $pdo->prepare(
        "INSERT INTO task_responses (submission_id, task_id, completed)
         VALUES (:sid, :tid, :comp)"
    );

    foreach ($taskCompleted as $taskId => $completed) {
        $insertResp->execute([
            'sid'  => $submissionDbId,
            'tid'  => (int)$taskId,
            'comp' => $completed
        ]);
    }

    // Save multiple evidence files
    if (!empty($validatedFiles)) {
        $insertEv = $pdo->prepare(
            "INSERT INTO submission_evidence (submission_id, file_path, original_name)
             VALUES (:sid, :path, :oname)"
        );

        foreach ($validatedFiles as $idx => $validated) {
            $path = saveEvidenceFile($validated, $submissionCode, $idx);
            if ($path === null) {
                throw new Exception('Failed to save evidence file: ' . ($validated['name'] ?? 'unknown'));
            }
            $insertEv->execute([
                'sid'   => $submissionDbId,
                'path'  => $path,
                'oname' => $validated['name'] ?? null
            ]);
        }
    }


    $pdo->commit();

    session_start();
    $_SESSION['lep_success'] = $submissionCode;
    header('Location: index.php?success=1');
    exit;

} catch (Exception $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollback();
    }
    error_log('LEP Submission Error: ' . $e->getMessage());
    session_start();
    $_SESSION['lep_errors'] = ['Submission failed: ' . $e->getMessage()];
    $_SESSION['lep_old']    = $_POST;
    header('Location: index.php');
    exit;
}
