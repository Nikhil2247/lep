<?php
/**
 * LEP – Export teacher submissions to CSV (UTF-8 with BOM)
 * Developer / programme utility – not linked from the main teacher form.
 *
 * Rule: ONE submission = ONE row
 * Tasks expand as columns (Question + Response pairs)
 * Evidence filenames share a single cell (separated by "; ")
 * Video Link is one column
 */
define('LEP_APP', true);
require_once __DIR__ . '/config/config.php';
require_once __DIR__ . '/includes/db.php';
require_once __DIR__ . '/includes/functions.php';

$pdo = getPDO();
$error = null;
$count = 0;

try {
    $count = (int)$pdo->query('SELECT COUNT(*) FROM teacher_submissions')->fetchColumn();
} catch (Throwable $e) {
    $error = $e->getMessage();
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['export_csv'])) {
    try {
        exportSubmissionsCsv($pdo);
        // exits on success
    } catch (Throwable $e) {
        $error = $e->getMessage();
        error_log('LEP export CSV: ' . $e->getMessage());
    }
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['export_evidence_zip'])) {
    try {
        exportAllEvidenceZip($pdo);
        // exits on success
    } catch (Throwable $e) {
        $error = $e->getMessage();
        error_log('LEP export evidence ZIP: ' . $e->getMessage());
    }
}

/**
 * Stream a UTF-8 BOM CSV download (Excel-compatible).
 */
function exportSubmissionsCsv(PDO $pdo): void
{
    $sql = "SELECT
                ts.id AS db_id,
                ts.submission_id,
                ts.submitted_at,
                ts.teacher_name,
                ts.designation,
                ts.video_link,
                d.name  AS district_name,
                b.name  AS block_name,
                sc.school_name,
                sc.udise_code,
                g.name  AS grade_name,
                s.name  AS subject_name,
                c.name  AS cycle_name,
                p.project_title,
                p.duration,
                p.objective
            FROM teacher_submissions ts
            INNER JOIN districts d  ON d.id  = ts.district_id
            INNER JOIN blocks    b  ON b.id  = ts.block_id
            INNER JOIN schools   sc ON sc.id = ts.school_id
            INNER JOIN grades    g  ON g.id  = ts.grade_id
            INNER JOIN cycles    c  ON c.id  = ts.cycle_id
            INNER JOIN projects  p  ON p.id  = ts.project_id
            LEFT  JOIN subjects  s  ON s.id  = ts.subject_id
            ORDER BY ts.submitted_at ASC, ts.id ASC";

    $submissions = $pdo->query($sql)->fetchAll();
    if (!$submissions) {
        throw new RuntimeException('No submissions found to export.');
    }

    $taskStmt = $pdo->prepare(
        "SELECT pt.task_number, pt.task_type, pt.task_description, tr.completed
         FROM task_responses tr
         INNER JOIN project_tasks pt ON pt.id = tr.task_id
         WHERE tr.submission_id = :sid
         ORDER BY pt.sort_order ASC, pt.task_number ASC, pt.id ASC"
    );

    $evStmt = $pdo->prepare(
        "SELECT original_name
         FROM submission_evidence
         WHERE submission_id = :sid
         ORDER BY id ASC"
    );

    $rowsData = [];
    $maxTasks = 0;

    foreach ($submissions as $sub) {
        $taskStmt->execute(['sid' => $sub['db_id']]);
        $tasks = $taskStmt->fetchAll();
        $maxTasks = max($maxTasks, count($tasks));

        $evStmt->execute(['sid' => $sub['db_id']]);
        $files = [];
        foreach ($evStmt->fetchAll() as $ev) {
            $name = trim((string)($ev['original_name'] ?? ''));
            if ($name !== '') {
                $files[] = $name;
            }
        }

        $rowsData[] = [
            'sub'   => $sub,
            'tasks' => $tasks,
            'files' => $files,
        ];
    }

    $taskHeaders = [];
    for ($i = 0; $i < $maxTasks; $i++) {
        $label = 'Task ' . ($i + 1);
        foreach ($rowsData as $rd) {
            if (!isset($rd['tasks'][$i])) {
                continue;
            }
            $tt = $rd['tasks'][$i]['task_type'] ?? 'Task';
            if ($tt === 'Showcase') {
                $label = 'Showcase';
                break;
            }
            $num = (int)($rd['tasks'][$i]['task_number'] ?? ($i + 1));
            $label = 'Task ' . $num;
        }
        $taskHeaders[] = $label;
    }

    $header = [
        'Submission ID',
        'Submission Date',
        'Name',
        'Designation',
        'District',
        'Block',
        'School',
        'UDISE Code',
        'Grade',
        'Subject',
        'Cycle',
        'Project Title',
        'Duration',
        'Objective',
    ];
    foreach ($taskHeaders as $label) {
        $header[] = $label . ' – Question';
        $header[] = $label . ' – Response';
    }
    $header[] = 'Evidence Files';
    $header[] = 'Video Link';

    $filename = 'LEP_Submissions_' . date('Y-m-d') . '.csv';

    header('Content-Type: text/csv; charset=UTF-8');
    header('Content-Disposition: attachment; filename="' . $filename . '"');
    header('Cache-Control: max-age=0, no-cache, must-revalidate, private');
    header('Pragma: public');

    $out = fopen('php://output', 'w');
    if ($out === false) {
        throw new RuntimeException('Unable to open output stream for CSV export.');
    }

    fwrite($out, "\xEF\xBB\xBF");
    fputcsv($out, $header);

    foreach ($rowsData as $rd) {
        $sub = $rd['sub'];
        $date = '';
        if (!empty($sub['submitted_at'])) {
            $date = date('d F Y H:i', strtotime($sub['submitted_at']));
        }

        $row = [
            $sub['submission_id'],
            $date,
            $sub['teacher_name'],
            $sub['designation'] ?? '',
            $sub['district_name'],
            $sub['block_name'],
            $sub['school_name'],
            $sub['udise_code'],
            $sub['grade_name'],
            $sub['subject_name'] ?? 'School Leaders',
            $sub['cycle_name'],
            $sub['project_title'],
            $sub['duration'] ?? '',
            $sub['objective'] ?? '',
        ];

        for ($i = 0; $i < $maxTasks; $i++) {
            if (isset($rd['tasks'][$i])) {
                $t = $rd['tasks'][$i];
                $row[] = (string)($t['task_description'] ?? '');
                $row[] = (string)($t['completed'] ?? '');
            } else {
                $row[] = '';
                $row[] = '';
            }
        }

        $row[] = $rd['files'] ? implode('; ', $rd['files']) : '';
        $row[] = trim((string)($sub['video_link'] ?? ''));

        fputcsv($out, $row);
    }

    fclose($out);
    exit;
}
/**
 * Bulk download of all evidence files, organised by Submission ID.
 * Uses DB paths; skips missing files; restricts to uploads/evidence/.
 */
function exportAllEvidenceZip(PDO $pdo): void
{
    if (!class_exists('ZipArchive')) {
        throw new RuntimeException(
            'PHP ZipArchive extension is required to generate the evidence ZIP. ' .
            'Please enable the zip extension on the server.'
        );
    }

    $sql = "SELECT se.file_path, se.original_name, ts.submission_id
            FROM submission_evidence se
            INNER JOIN teacher_submissions ts ON ts.id = se.submission_id
            ORDER BY ts.submission_id ASC, se.id ASC";
    $rows = $pdo->query($sql)->fetchAll();

    if (!$rows) {
        throw new RuntimeException('No evidence files found to include in the ZIP.');
    }

    $evidenceRoot = realpath(EVIDENCE_PATH);
    if ($evidenceRoot === false || !is_dir($evidenceRoot)) {
        throw new RuntimeException('Evidence directory is not available on the server.');
    }

    $tmpBase = tempnam(sys_get_temp_dir(), 'lep_ev_');
    if ($tmpBase === false) {
        throw new RuntimeException('Unable to create temporary file for ZIP.');
    }
    $zipPath = $tmpBase . '.zip';
    @unlink($tmpBase);

    $zip = new ZipArchive();
    if ($zip->open($zipPath, ZipArchive::CREATE | ZipArchive::OVERWRITE) !== true) {
        throw new RuntimeException('Unable to create ZIP archive.');
    }

    $added = 0;
    $usedNames = [];

    foreach ($rows as $row) {
        $sid = preg_replace('/[^A-Za-z0-9\-]/', '', (string) $row['submission_id']);
        if ($sid === '') {
            continue;
        }

        $rel = str_replace('\\', '/', (string) $row['file_path']);
        if ($rel === '' || strpos($rel, '..') !== false) {
            continue;
        }
        // Must be under uploads/evidence/
        if (strpos($rel, 'uploads/evidence/') !== 0) {
            continue;
        }

        $abs = BASE_PATH . '/' . $rel;
        $real = realpath($abs);
        if ($real === false || !is_file($real) || !is_readable($real)) {
            continue;
        }
        // Must remain inside evidence root
        if (strpos($real, $evidenceRoot) !== 0) {
            continue;
        }

        $original = trim((string) ($row['original_name'] ?? ''));
        if ($original === '') {
            $original = basename($real);
        }
        // Basename only – strip any path components from original name
        $original = basename(str_replace(['\\', "\0"], '', $original));
        $original = preg_replace('/[\x00-\x1F\x7F<>:"|?*]/', '_', $original);
        $original = trim($original, " .");
        if ($original === '' || $original === '.' || $original === '..') {
            $original = 'file_' . ($added + 1);
        }

        if (!isset($usedNames[$sid])) {
            $usedNames[$sid] = [];
        }
        $key = strtolower($original);
        if (isset($usedNames[$sid][$key])) {
            $usedNames[$sid][$key]++;
            $ext  = pathinfo($original, PATHINFO_EXTENSION);
            $base = pathinfo($original, PATHINFO_FILENAME);
            $original = $base . '_' . $usedNames[$sid][$key] . ($ext !== '' ? '.' . $ext : '');
        } else {
            $usedNames[$sid][$key] = 1;
        }

        $entry = $sid . '/' . $original;
        if ($zip->addFile($real, $entry)) {
            $added++;
        }
    }

    $zip->close();

    if ($added < 1) {
        @unlink($zipPath);
        throw new RuntimeException(
            'No evidence files could be added to the ZIP. Files may be missing on the server.'
        );
    }

    $filename = 'LEP_All_Evidence_' . date('Y-m-d') . '.zip';
    header('Content-Type: application/zip');
    header('Content-Disposition: attachment; filename="' . $filename . '"');
    header('Content-Length: ' . (string) filesize($zipPath));
    header('Cache-Control: max-age=0, no-cache, must-revalidate, private');
    header('Pragma: public');
    readfile($zipPath);
    @unlink($zipPath);
    exit;
}


?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Export Submissions | LEP</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.css">
    <style>
        body { background: #f4f6f8; font-family: 'Segoe UI', system-ui, sans-serif; }
        .page-header {
            background: linear-gradient(135deg, #006400, #228B22);
            color: #fff; padding: 1.25rem 0;
        }
    </style>
</head>
<body>
<header class="page-header mb-4">
    <div class="container">
        <h1 class="h4 mb-0"><i class="bi bi-filetype-csv me-2"></i>Export LEP Submissions</h1>
        <div class="small opacity-75">Version <?= htmlspecialchars(APP_VERSION) ?> &middot; One submission = one CSV row</div>
    </div>
</header>

<div class="container" style="max-width:640px">
    <?php if ($error): ?>
        <div class="alert alert-danger"><?= htmlspecialchars($error) ?></div>
    <?php endif; ?>

    <div class="card shadow-sm mb-4">
        <div class="card-body">
            <p class="mb-2">
                Export all teacher submissions to a CSV file that opens directly in Microsoft Excel.
            </p>
            <ul class="small text-muted mb-3">
                <li>UTF-8 with BOM (Excel-compatible)</li>
                <li>Each submission occupies <strong>exactly one row</strong></li>
                <li>Task questions and Yes/No responses expand as columns</li>
                <li>All evidence filenames in one <em>Evidence Files</em> cell (separated by <code>; </code>)</li>
                <li>Video Link column (blank if not provided)</li>
            </ul>
            <p class="mb-3">
                Total Submissions: <strong><?= (int)$count ?></strong>
            </p>
            <form method="POST" class="d-flex flex-wrap gap-2">
                <button type="submit" name="export_csv" value="1" class="btn btn-success"
                    <?= $count < 1 ? 'disabled' : '' ?>>
                    <i class="bi bi-download me-1"></i>Download CSV (.csv)
                </button>
                <button type="submit" name="export_evidence_zip" value="1" class="btn btn-outline-success"
                    <?= $count < 1 ? 'disabled' : '' ?>>
                    <i class="bi bi-file-earmark-zip me-1"></i>Download All Evidence (.ZIP)
                </button>
                <a href="index.php" class="btn btn-outline-secondary">Back to Form</a>
            </form>
        </div>
    </div>
</div>
</body>
</html>
