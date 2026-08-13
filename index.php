<?php
/**
 * LEP – Learning Enhancement Program
 * Main Entry Point / Form Page
 * Version 1.7
 */
define('LEP_APP', true);
require_once __DIR__ . '/config/config.php';
require_once __DIR__ . '/includes/db.php';
require_once __DIR__ . '/includes/functions.php';

session_start();

$pdo = getPDO();

// Flash messages
$errors  = $_SESSION['lep_errors'] ?? [];
$old     = $_SESSION['lep_old'] ?? [];
$success = $_SESSION['lep_success'] ?? null; // submission_id code e.g. LEP-2026-000001

unset($_SESSION['lep_errors'], $_SESSION['lep_old'], $_SESSION['lep_success']);

// Certificate data for successful submission
$certificate = null;
if ($success) {
    try {
        $stmt = $pdo->prepare(
            "SELECT ts.submission_id, ts.teacher_name, ts.submitted_at,
                    sc.school_name, sc.udise_code,
                    g.name AS grade_name,
                    s.name AS subject_name,
                    c.name AS cycle_name,
                    p.project_title
             FROM teacher_submissions ts
             INNER JOIN schools  sc ON sc.id = ts.school_id
             INNER JOIN grades   g  ON g.id  = ts.grade_id
             INNER JOIN cycles   c  ON c.id  = ts.cycle_id
             INNER JOIN projects p  ON p.id  = ts.project_id
             LEFT  JOIN subjects s  ON s.id  = ts.subject_id
             WHERE ts.submission_id = :sid
             LIMIT 1"
        );
        $stmt->execute(['sid' => $success]);
        $certificate = $stmt->fetch() ?: null;
    } catch (Exception $e) {
        error_log('LEP certificate lookup: ' . $e->getMessage());
        $certificate = null;
    }
}

// Master data for initial render
$districts = getDistricts($pdo);
$grades    = getGrades($pdo);
$cycles    = getCycles($pdo);

require_once __DIR__ . '/includes/header.php';
?>

<div class="container my-4 flex-grow-1">

<?php if ($success): ?>
    <!-- ===================== CERTIFICATE OF SUBMISSION ===================== -->
    <?php
        $certLogoCandidates = [
            __DIR__ . '/assets/images/logo.png',
            __DIR__ . '/' . LOGO_PATH,
        ];
        $certLogoUrl = BASE_URL . '/assets/images/logo.png';
        foreach ($certLogoCandidates as $cand) {
            if (is_file($cand)) {
                $rel = str_replace(__DIR__ . '/', '', $cand);
                $certLogoUrl = BASE_URL . '/' . ltrim($rel, '/');
                break;
            }
        }
        $fmtDate = '';
        if (!empty($certificate['submitted_at'])) {
            $fmtDate = date('d F Y', strtotime($certificate['submitted_at']));
        }
    ?>
    <div class="certificate-wrap mx-auto my-2">
        <div class="certificate-card">
            <div class="certificate-inner">

                <div class="certificate-brand">
                    <img src="<?= sanitize($certLogoUrl) ?>"
                         alt="Samagra Shiksha Nagaland"
                         class="certificate-logo"
                         onerror="this.style.display='none'">
                    <div class="certificate-brand-text">
                        <h1 class="certificate-heading">CERTIFICATE OF SUBMISSION</h1>
                        <p class="certificate-subhead">Learning Enhancement Program (LEP)</p>
                    </div>
                </div>

                <p class="certificate-ack">
                    This is to acknowledge that the following teacher has successfully
                    submitted their Learning Enhancement Program (LEP) response.
                </p>

                <?php if ($certificate): ?>
                <div class="cert-name-line">
                    <span class="cert-inline-label">NAME</span>
                    <span class="cert-name-value"><?= sanitize($certificate['teacher_name']) ?></span>
                </div>

                <div class="cert-compact-rows">
                    <div class="cert-row-inline">
                        <span class="cert-pair"><span class="cert-inline-label">SCHOOL:</span> <span class="cert-inline-value"><?= sanitize($certificate['school_name']) ?></span></span>
                        <span class="cert-pair"><span class="cert-inline-label">UDISE CODE:</span> <span class="cert-inline-value"><?= sanitize($certificate['udise_code']) ?></span></span>
                    </div>
                    <div class="cert-row-inline">
                        <span class="cert-pair"><span class="cert-inline-label">GRADE:</span> <span class="cert-inline-value"><?= sanitize($certificate['grade_name']) ?></span></span>
                        <span class="cert-pair"><span class="cert-inline-label">SUBJECT:</span> <span class="cert-inline-value"><?= sanitize($certificate['subject_name'] ?? 'School Leaders') ?></span></span>
                    </div>
                    <div class="cert-row-inline cert-row-full">
                        <span class="cert-pair cert-pair-full"><span class="cert-inline-label">PROJECT TITLE:</span> <span class="cert-inline-value"><?= sanitize($certificate['project_title']) ?></span></span>
                    </div>
                    <div class="cert-row-inline cert-row-sid">
                        <span class="cert-pair"><span class="cert-inline-label">SUBMISSION ID:</span> <span class="cert-inline-value cert-sid"><?= sanitize($certificate['submission_id']) ?></span></span>
                        <span class="cert-pair"><span class="cert-inline-label">DATE:</span> <span class="cert-inline-value"><?= sanitize($fmtDate) ?></span></span>
                    </div>
                </div>

                <p class="certificate-footer-note">
                    This acknowledges successful submission of the LEP response for the specified
                    Grade, Subject and Cycle. It does not constitute evaluation or approval of the project work.
                </p>
                <?php else: ?>
                <div class="text-center py-2">
                    <div class="cert-sid"><?= sanitize($success) ?></div>
                    <p class="text-muted small mb-0">Submission recorded. Please note your Submission ID.</p>
                </div>
                <?php endif; ?>
            </div>
        </div>

        <div class="text-center mt-2 mb-1">
            <a href="index.php" class="btn btn-success px-4">
                <i class="bi bi-plus-circle me-1"></i>Submit Another Response
            </a>
        </div>
    </div>

<?php else: ?>

    <?php if (!empty($errors)): ?>
    <div class="alert alert-danger alert-dismissible fade show" role="alert">
        <strong><i class="bi bi-exclamation-triangle-fill me-2"></i>Submission Failed</strong>
        <ul class="mb-0 mt-2">
            <?php foreach ($errors as $err): ?>
                <li><?= sanitize($err) ?></li>
            <?php endforeach; ?>
        </ul>
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
    <?php endif; ?>

    <!-- ===================== INFORMATION SECTION ===================== -->
    <div class="card lep-card mb-4">
        <div class="card-header section-header">
            <i class="bi bi-info-circle me-2"></i>Programme Information
        </div>
        <div class="card-body">
            <div id="infoContent">
                <p class="mb-2">Dear Teachers,</p>
                <p class="mb-2">
                    We invite you to fill out this form to submit your micro-improvement projects.
                </p>
                <ol class="mb-3">
                    <li class="mb-2">
                        Download the assigned Project Document.
                        <div class="alert alert-info py-2 px-3 mt-2 mb-0 small" role="note">
                            <i class="bi bi-info-circle me-1"></i>
                            Select the Grade, Subject and Cycle below to load your assigned project.
                            The Project Information section will display the project title and the Download Project button.
                        </div>
                    </li>
                    <li>Execute all the assigned project tasks.</li>
                    <li>Mark each task as <strong>"Yes"</strong> or <strong>"No"</strong> depending on whether it has been completed.</li>
                    <li>Upload the supporting evidence and, where applicable, provide the project video link before submitting your report.</li>
                </ol>
                <p class="mb-0">
                    Your contribution will help us capture and celebrate the efforts you are making towards improving teaching and learning in your school.
                </p>
            </div>
        </div>
    </div>

    <!-- ===================== MAIN FORM ===================== -->
    <form id="lepForm" method="POST" action="process_submission.php" enctype="multipart/form-data" novalidate>

        <!-- SECTION A – Teacher & School Details -->
        <div class="card lep-card mb-4">
            <div class="card-header section-header">
                <i class="bi bi-person-badge me-2"></i>Section A – Teacher &amp; School Details
            </div>
            <div class="card-body">
                <div class="row g-3">
                    <div class="col-12 col-md-6">
                        <label for="teacher_name" class="form-label required">Teacher Name</label>
                        <input type="text" class="form-control" id="teacher_name" name="teacher_name"
                               value="<?= sanitize($old['teacher_name'] ?? '') ?>" required maxlength="150">
                    </div>
                    <div class="col-12 col-md-6">
                        <label for="designation" class="form-label required">Designation</label>
                        <input type="text" class="form-control" id="designation" name="designation"
                               value="<?= sanitize($old['designation'] ?? '') ?>" required maxlength="100"
                               placeholder="e.g. Primary Teacher, Head Teacher, etc.">
                    </div>
                    <div class="col-12 col-sm-6 col-md-4">
                        <label for="district_id" class="form-label required">District</label>
                        <select class="form-select" id="district_id" name="district_id" required>
                            <option value="">-- Select District --</option>
                            <?php foreach ($districts as $d): ?>
                                <option value="<?= (int)$d['id'] ?>"
                                    <?= (($old['district_id'] ?? '') == $d['id']) ? 'selected' : '' ?>>
                                    <?= sanitize($d['name']) ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <div class="col-12 col-sm-6 col-md-4">
                        <label for="block_id" class="form-label required">Block</label>
                        <select class="form-select" id="block_id" name="block_id" required disabled>
                            <option value="">-- Select District first --</option>
                        </select>
                    </div>
                    <div class="col-12 col-md-4">
                        <label for="school_id" class="form-label required">School</label>
                        <select class="form-select" id="school_id" name="school_id" required disabled>
                            <option value="">-- Select Block first --</option>
                        </select>
                    </div>
                    <div class="col-12 col-md-4">
                        <label for="udise_code" class="form-label">UDISE Code</label>
                        <input type="text" class="form-control bg-light font-monospace" id="udise_code"
                               readonly placeholder="Auto-filled after school selection">
                    </div>
                </div>
            </div>
        </div>

        <!-- SECTION B – Project Selection -->
        <div class="card lep-card mb-4">
            <div class="card-header section-header">
                <i class="bi bi-journal-bookmark me-2"></i>Section B – Project Selection
            </div>
            <div class="card-body">
                <div class="row g-3">
                    <div class="col-12 col-md-4">
                        <label for="grade_id" class="form-label required">Grade</label>
                        <select class="form-select" id="grade_id" name="grade_id" required>
                            <option value="">-- Select Grade --</option>
                            <?php foreach ($grades as $g): ?>
                                <option value="<?= (int)$g['id'] ?>"
                                        data-school-leader="<?= (int)$g['is_school_leader'] ?>"
                                    <?= (($old['grade_id'] ?? '') == $g['id']) ? 'selected' : '' ?>>
                                    <?= sanitize($g['name']) ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <div class="col-12 col-md-4" id="subjectWrapper">
                        <label for="subject_id" class="form-label required">Subject</label>
                        <select class="form-select" id="subject_id" name="subject_id">
                            <option value="">-- Select Grade first --</option>
                        </select>
                    </div>
                    <div class="col-12 col-md-4">
                        <label for="cycle_id" class="form-label required">Cycle</label>
                        <select class="form-select" id="cycle_id" name="cycle_id" required>
                            <option value="">-- Select Cycle --</option>
                            <?php foreach ($cycles as $c): ?>
                                <option value="<?= (int)$c['id'] ?>"
                                    <?= (($old['cycle_id'] ?? '') == $c['id']) ? 'selected' : '' ?>>
                                    <?= sanitize($c['name']) ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                </div>

                <!-- Project Information (loaded dynamically) -->
                <div id="projectInfoCard" class="card mt-4 border-success d-none">
                    <div class="card-body">
                        <h5 class="card-title text-success mb-3">
                            <i class="bi bi-folder2-open me-2"></i>Project Information
                        </h5>
                        <div class="row g-3 align-items-start">
                            <div class="col-12 col-md-8">
                                <label class="form-label lep-field-label mb-0">Project Title</label>
                                <div id="projectTitle" class="fw-semibold fs-5"></div>
                            </div>
                            <div class="col-6 col-md-2">
                                <label class="form-label lep-field-label mb-0">Duration</label>
                                <div id="projectDuration" class="fw-semibold">—</div>
                            </div>
                            <div class="col-6 col-md-2 text-md-end">
                                <a id="downloadProjectBtn" href="#" class="btn btn-outline-success" target="_blank">
                                    <i class="bi bi-download me-1"></i>Download Project
                                </a>
                            </div>
                            <div class="col-12" id="projectObjectiveWrap">
                                <label class="form-label lep-field-label mb-0">Objective</label>
                                <div id="projectObjective" class="lep-readable-text"></div>
                            </div>
                        </div>
                        <input type="hidden" name="project_id" id="project_id" value="">
                    </div>
                </div>

                <div id="projectNotFound" class="alert alert-warning mt-3 d-none mb-0">
                    <i class="bi bi-exclamation-circle me-2"></i>
                    <span id="projectNotFoundMsg">No project found for the selected combination.</span>
                </div>
            </div>
        </div>

        <!-- SECTION C – Project Tasks (dynamic) -->
        <div class="card lep-card mb-4 d-none" id="tasksSection">
            <div class="card-header section-header">
                <i class="bi bi-list-task me-2"></i>Section C – Project Tasks
            </div>
            <div class="card-body">
                <p class="text-muted small mb-3">
                    Mark each task as <strong>Yes</strong> or <strong>No</strong> depending on whether it has been completed.
                </p>
                <div id="tasksContainer">
                    <!-- Tasks injected by JavaScript -->
                </div>
            </div>
        </div>

        <!-- PROJECT COMPLETION EVIDENCE (v1.2) – Gmail-style multi-file uploader -->
        <div class="card lep-card mb-4 d-none" id="evidenceSection">
            <div class="card-header section-header">
                <i class="bi bi-cloud-upload me-2"></i>Project Completion Evidence
            </div>
            <div class="card-body">
                <div class="mb-4">
                    <label class="form-label fw-semibold d-block required">Evidence Upload</label>
                    <!-- Hidden native input – used by JS to pick one file at a time -->
                    <input type="file" id="evidencePicker" class="d-none"
                           accept=".pdf,.doc,.docx,.jpg,.jpeg,.png">
                    <!-- This input receives the final FileList on submit via DataTransfer -->
                    <input type="file" id="project_evidence" name="project_evidence[]"
                           class="d-none" multiple accept=".pdf,.doc,.docx,.jpg,.jpeg,.png">

                    <button type="button" class="btn btn-outline-success" id="addEvidenceBtn">
                        <i class="bi bi-plus-lg me-1"></i>Add Evidence
                    </button>
                    <div class="form-text mt-2">
                        Please upload at least 1 and up to 5 supporting documents or images.
                        Total combined upload size must not exceed 5 MB.<br>
                        Accepted file types: PDF, DOC, DOCX, JPG, JPEG, PNG.
                    </div>

                    <div id="evidenceListWrap" class="mt-3 d-none">
                        <div class="fw-semibold small mb-2">Selected Files</div>
                        <ul id="evidenceFileList" class="list-group list-group-flush border rounded"></ul>
                        <div id="evidenceCounter" class="small text-muted mt-2">
                            0 / 5 files selected<br>
                            Total upload size: 0 MB / 5 MB
                        </div>
                        <div id="evidenceError" class="text-danger small mt-1 d-none"></div>
                    </div>
                </div>
                <div>
                    <label for="project_video_link" class="form-label fw-semibold">
                        Video Link <span class="text-muted fw-normal">(Optional)</span>
                    </label>
                    <input type="url" class="form-control" id="project_video_link" name="project_video_link"
                           placeholder="https://...">
                    <div class="form-text">
                        Paste a YouTube, Google Drive or any publicly accessible video link related to this project.
                    </div>
                </div>
            </div>
        </div>

        <!-- SUBMIT -->
        <div class="card lep-card mb-4">
            <div class="card-body">
                <div class="d-flex flex-wrap justify-content-end gap-2">
                    <button type="button" class="btn btn-outline-secondary btn-lg px-4" id="resetBtn">
                        <i class="bi bi-arrow-counterclockwise me-2"></i>Reset
                    </button>
                    <button type="submit" class="btn btn-success btn-lg px-5" id="submitBtn" disabled>
                        <i class="bi bi-send-check me-2"></i>Submit Report
                    </button>
                </div>
                <div class="small text-muted mt-2 text-end">
                    Fields marked <span class="text-danger">*</span> are mandatory.
                    Ensure all tasks have a Yes/No response before submitting.
                </div>
            </div>
        </div>
    </form>

<?php endif; ?>
</div>

<?php require_once __DIR__ . '/includes/footer.php'; ?>
