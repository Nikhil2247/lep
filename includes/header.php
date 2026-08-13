<?php
/**
 * Common HTML Header + Government Style Banner
 * LEP Application
 */
if (!defined('LEP_APP')) {
    die('Direct access not permitted.');
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= sanitize(APP_NAME) ?> | Samagra Shiksha Nagaland</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.css">
    <link rel="stylesheet" href="<?= BASE_URL ?>/assets/css/style.css">
</head>
<body>
<!-- Government Header -->
<header class="gov-header">
    <div class="container">
        <div class="d-flex align-items-center justify-content-between flex-wrap gap-3">
            <div class="d-flex align-items-center gap-3">
                <div class="logo-box">
                    <img src="<?= BASE_URL ?>/<?= LOGO_PATH ?>"
                         alt="<?= sanitize(LOGO_ALT) ?>"
                         onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
                    <div class="logo-fallback" style="display:none;">
                        <i class="bi bi-building"></i>
                    </div>
                </div>
                <div>
                    <div class="gov-title">Government of Nagaland</div>
                    <div class="dept-title">Samagra Shiksha Nagaland</div>
                    <h1 class="app-title mb-0">
                        <i class="bi bi-journal-richtext me-2"></i><?= sanitize(APP_NAME) ?>
                    </h1>
                </div>
            </div>
            <div class="text-end">
                <span class="badge bg-light text-dark px-3 py-2">
                    <i class="bi bi-calendar3 me-1"></i>
                    <strong>Version <?= APP_VERSION ?></strong>
                </span>
                <div class="small mt-1 text-white-50">Internal Programme Use</div>
            </div>
        </div>
    </div>
</header>
