<?php
/**
 * LEP – Master School Data Import Utility (v1.3)
 * One-time developer setup page. Not linked from the main application.
 *
 * Reads the official Master_Schools file (CSV preferred, XLSX optional)
 * and populates: districts → blocks → schools
 *
 * Duplicate rules:
 *   - District : reuse by name
 *   - Block    : reuse by (district_id + name)
 *   - School   : skip if UDISE code already exists
 */
define('LEP_APP', true);
require_once __DIR__ . '/config/config.php';
require_once __DIR__ . '/includes/db.php';
require_once __DIR__ . '/includes/functions.php';

$pdo = getPDO();
$result  = null;
$error   = null;

$defaultCsv  = __DIR__ . '/data/Master_Schools-2026.csv';
$defaultXlsx = __DIR__ . '/data/Master_Schools-2026.xlsx';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['run_import'])) {
    try {
        $sourcePath = null;
        $uploaded   = false;
        $format     = null;

        // 1) Uploaded file takes priority
        if (!empty($_FILES['excel_file']['tmp_name']) && is_uploaded_file($_FILES['excel_file']['tmp_name'])) {
            $ext = strtolower(pathinfo($_FILES['excel_file']['name'], PATHINFO_EXTENSION));
            if (!in_array($ext, ['xlsx', 'csv'], true)) {
                throw new RuntimeException('Only .xlsx or .csv files are accepted.');
            }
            $tmpDest = sys_get_temp_dir() . '/lep_master_' . uniqid() . '.' . $ext;
            if (!move_uploaded_file($_FILES['excel_file']['tmp_name'], $tmpDest)) {
                throw new RuntimeException('Failed to store uploaded file.');
            }
            $sourcePath = $tmpDest;
            $format     = $ext;
            $uploaded   = true;
        }

        // 2) Pre-placed files
        if ($sourcePath === null) {
            if (is_file($defaultCsv)) {
                $sourcePath = $defaultCsv;
                $format     = 'csv';
            } elseif (is_file($defaultXlsx)) {
                $sourcePath = $defaultXlsx;
                $format     = 'xlsx';
            } else {
                throw new RuntimeException(
                    'Master data file not found. Place Master_Schools-2026.csv (or .xlsx) in the data/ folder, ' .
                    'or upload it using the form below.'
                );
            }
        }

        $clearFirst = !empty($_POST['clear_first']);
        $rows = loadMasterRows($sourcePath, $format);
        $result = runMasterImport($pdo, $rows, $clearFirst);

        if ($uploaded && is_file($sourcePath)) {
            @unlink($sourcePath);
        }
    } catch (Throwable $e) {
        $error = $e->getMessage();
        error_log('LEP master_import: ' . $e->getMessage());
    }
}

/**
 * Load rows from CSV or XLSX into a plain array of arrays.
 */
function loadMasterRows(string $path, string $format): array
{
    if ($format === 'csv') {
        $rows = [];
        $fh = fopen($path, 'r');
        if (!$fh) {
            throw new RuntimeException('Unable to open CSV file.');
        }
        // Handle UTF-8 BOM
        $first = fgets($fh);
        if ($first !== false && str_starts_with($first, "\xEF\xBB\xBF")) {
            $first = substr($first, 3);
        }
        if ($first !== false) {
            $rows[] = str_getcsv($first);
        }
        while (($data = fgetcsv($fh)) !== false) {
            $rows[] = $data;
        }
        fclose($fh);
        return $rows;
    }

    // XLSX – requires ZipArchive
    require_once __DIR__ . '/includes/SimpleXlsxReader.php';
    $reader = new SimpleXlsxReader($path);
    return $reader->getRows();
}

/**
 * Core import logic
 */
function runMasterImport(PDO $pdo, array $rows, bool $clearFirst): array
{
    if (count($rows) < 2) {
        throw new RuntimeException('File appears empty or has no data rows.');
    }

    // Header row – locate columns by name (case-insensitive, trimmed)
    $header = array_map(fn($h) => strtolower(trim((string)$h)), $rows[0]);
    $colDistrict = array_search('district', $header, true);
    $colBlock    = array_search('block', $header, true);
    $colSchool   = array_search('school name', $header, true);
    $colUdise    = array_search('udise code', $header, true);

    if ($colDistrict === false || $colBlock === false || $colSchool === false || $colUdise === false) {
        throw new RuntimeException(
            'Required columns not found. Expected: District, Block, School Name, UDISE Code. ' .
            'Found: ' . implode(', ', $rows[0])
        );
    }

    $stats = [
        'districts_new'   => 0,
        'blocks_new'      => 0,
        'schools_new'     => 0,
        'schools_skipped' => 0,
        'rows_read'       => 0,
        'rows_invalid'    => 0,
    ];

    $pdo->beginTransaction();

    try {
        if ($clearFirst) {
            $subCount = (int)$pdo->query('SELECT COUNT(*) FROM teacher_submissions')->fetchColumn();
            if ($subCount > 0) {
                throw new RuntimeException(
                    "Cannot clear master data: {$subCount} teacher submission(s) already exist. " .
                    'Clear is only allowed on a fresh database.'
                );
            }
            $pdo->exec('DELETE FROM schools');
            $pdo->exec('DELETE FROM blocks');
            $pdo->exec('DELETE FROM districts');
        }

        $districtCache = [];
        $blockCache    = [];
        $existingUdise = [];

        foreach ($pdo->query('SELECT id, name FROM districts') as $r) {
            $districtCache[$r['name']] = (int)$r['id'];
        }
        foreach ($pdo->query('SELECT id, district_id, name FROM blocks') as $r) {
            $blockCache[$r['district_id'] . '|' . $r['name']] = (int)$r['id'];
        }
        foreach ($pdo->query('SELECT udise_code FROM schools') as $r) {
            $existingUdise[$r['udise_code']] = true;
        }

        $insDistrict = $pdo->prepare('INSERT INTO districts (name, is_active) VALUES (?, 1)');
        $insBlock    = $pdo->prepare('INSERT INTO blocks (district_id, name, is_active) VALUES (?, ?, 1)');
        $insSchool   = $pdo->prepare(
            'INSERT INTO schools (block_id, school_name, udise_code, is_active) VALUES (?, ?, ?, 1)'
        );

        for ($i = 1, $n = count($rows); $i < $n; $i++) {
            $row = $rows[$i];
            $district = trim((string)($row[$colDistrict] ?? ''));
            $block    = trim((string)($row[$colBlock] ?? ''));
            $school   = trim((string)($row[$colSchool] ?? ''));
            $udise    = trim((string)($row[$colUdise] ?? ''));

            if ($district === '' && $block === '' && $school === '' && $udise === '') {
                continue;
            }

            $stats['rows_read']++;

            if ($district === '' || $block === '' || $school === '' || $udise === '') {
                $stats['rows_invalid']++;
                continue;
            }

            // Normalise numeric UDISE from Excel
            if (is_numeric($udise)) {
                $udise = (string)(int)(float)$udise;
            }

            // District
            if (!isset($districtCache[$district])) {
                $insDistrict->execute([$district]);
                $districtCache[$district] = (int)$pdo->lastInsertId();
                $stats['districts_new']++;
            }
            $districtId = $districtCache[$district];

            // Block
            $blockKey = $districtId . '|' . $block;
            if (!isset($blockCache[$blockKey])) {
                $insBlock->execute([$districtId, $block]);
                $blockCache[$blockKey] = (int)$pdo->lastInsertId();
                $stats['blocks_new']++;
            }
            $blockId = $blockCache[$blockKey];

            // School
            if (isset($existingUdise[$udise])) {
                $stats['schools_skipped']++;
                continue;
            }

            $insSchool->execute([$blockId, $school, $udise]);
            $existingUdise[$udise] = true;
            $stats['schools_new']++;
        }

        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    }

    $stats['districts_total'] = (int)$pdo->query('SELECT COUNT(*) FROM districts WHERE is_active = 1')->fetchColumn();
    $stats['blocks_total']    = (int)$pdo->query('SELECT COUNT(*) FROM blocks WHERE is_active = 1')->fetchColumn();
    $stats['schools_total']   = (int)$pdo->query('SELECT COUNT(*) FROM schools WHERE is_active = 1')->fetchColumn();

    return $stats;
}

$hasDefaultCsv  = is_file($defaultCsv);
$hasDefaultXlsx = is_file($defaultXlsx);
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Master School Data Import | LEP</title>
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
        <h1 class="h4 mb-0"><i class="bi bi-database-up me-2"></i>Master School Data Import</h1>
        <div class="small opacity-75">LEP Setup Utility &middot; Version <?= htmlspecialchars(APP_VERSION) ?></div>
    </div>
</header>

<div class="container" style="max-width:720px">

    <div class="alert alert-warning">
        <i class="bi bi-exclamation-triangle me-1"></i>
        <strong>Developer utility only.</strong>
        This page is not linked from the main application. Use it once during initial setup.
    </div>

    <?php if ($error): ?>
        <div class="alert alert-danger">
            <strong>Import failed</strong><br>
            <?= htmlspecialchars($error) ?>
        </div>
    <?php endif; ?>

    <?php if ($result): ?>
        <div class="alert alert-success">
            <h5 class="alert-heading"><i class="bi bi-check-circle me-2"></i>Master School Data Imported Successfully</h5>
            <hr>
            <ul class="mb-2">
                <li>Districts Imported (new) : <strong><?= (int)$result['districts_new'] ?></strong>
                    &nbsp;(total active: <?= (int)$result['districts_total'] ?>)</li>
                <li>Blocks Imported (new) : <strong><?= (int)$result['blocks_new'] ?></strong>
                    &nbsp;(total active: <?= (int)$result['blocks_total'] ?>)</li>
                <li>Schools Imported (new) : <strong><?= number_format((int)$result['schools_new']) ?></strong>
                    &nbsp;(total active: <?= number_format((int)$result['schools_total']) ?>)</li>
                <li>Duplicate Schools Skipped : <strong><?= (int)$result['schools_skipped'] ?></strong></li>
                <li>Data rows read : <?= (int)$result['rows_read'] ?>
                    <?php if ($result['rows_invalid']): ?>
                        &nbsp;(invalid/incomplete rows skipped: <?= (int)$result['rows_invalid'] ?>)
                    <?php endif; ?>
                </li>
            </ul>
            <p class="mb-0">Import Completed Successfully.</p>
        </div>
        <p>
            <a href="index.php" class="btn btn-success">
                <i class="bi bi-arrow-right me-1"></i>Open LEP Application
            </a>
        </p>
    <?php endif; ?>

    <div class="card shadow-sm mb-4">
        <div class="card-header bg-white fw-semibold">
            <i class="bi bi-file-earmark-excel me-2 text-success"></i>Import Official Master School Data
        </div>
        <div class="card-body">
            <p class="text-muted small">
                Expected columns: <code>District</code>, <code>Block</code>, <code>School Name</code>, <code>UDISE Code</code>.
                The <code>Sl No</code> column is ignored.
            </p>

            <?php if ($hasDefaultCsv || $hasDefaultXlsx): ?>
                <div class="alert alert-info py-2 small mb-3">
                    <i class="bi bi-info-circle me-1"></i>
                    Official file found in <code>data/</code>
                    (<?= $hasDefaultCsv ? 'CSV' : '' ?><?= ($hasDefaultCsv && $hasDefaultXlsx) ? ' + ' : '' ?><?= $hasDefaultXlsx ? 'XLSX' : '' ?>).
                    You can import it directly without uploading.
                </div>
            <?php else: ?>
                <div class="alert alert-secondary py-2 small mb-3">
                    No pre-placed file in <code>data/</code>. Please upload the Excel or CSV file below.
                </div>
            <?php endif; ?>

            <form method="POST" enctype="multipart/form-data">
                <div class="mb-3">
                    <label class="form-label">Upload file (.xlsx or .csv) <span class="text-muted">— optional if file is in data/</span></label>
                    <input type="file" name="excel_file" class="form-control" accept=".xlsx,.csv">
                </div>

                <div class="form-check mb-3">
                    <input class="form-check-input" type="checkbox" name="clear_first" value="1" id="clear_first">
                    <label class="form-check-label" for="clear_first">
                        Clear existing Districts / Blocks / Schools before import
                        <span class="text-muted small d-block">
                            Only allowed when there are no teacher submissions yet. Use for a clean first-time setup
                            (removes the sample master data from schema.sql).
                        </span>
                    </label>
                </div>

                <button type="submit" name="run_import" value="1" class="btn btn-success">
                    <i class="bi bi-cloud-upload me-1"></i>Run Import
                </button>
                <a href="index.php" class="btn btn-outline-secondary ms-2">Cancel</a>
            </form>
        </div>
    </div>

    <div class="card shadow-sm mb-4">
        <div class="card-header bg-white fw-semibold">How to use</div>
        <div class="card-body small">
            <ol class="mb-0">
                <li>Import the database schema: <code>sql/schema.sql</code></li>
                <li>Ensure <code>data/Master_Schools-2026.csv</code> (or .xlsx) is present, <em>or</em> upload the official file.</li>
                <li>Open <code>master_import.php</code> in the browser.</li>
                <li>Tick <strong>Clear existing…</strong> for a clean first import, then click <strong>Run Import</strong>.</li>
                <li>Open the main application — District → Block → School dropdowns will use the imported data.</li>
            </ol>
        </div>
    </div>
</div>
</body>
</html>
