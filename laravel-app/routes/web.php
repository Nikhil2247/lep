<?php

use App\Http\Controllers\Admin\ExportController;
use App\Http\Controllers\Admin\MasterImportController;
use App\Http\Controllers\Auth\LoginController;
use App\Http\Controllers\LookupController;
use App\Http\Controllers\ProjectDownloadController;
use App\Http\Controllers\SubmissionController;
use Illuminate\Support\Facades\Route;

// ── Public teacher-facing routes (port of index.php / process_submission.php) ──
Route::get('/', [SubmissionController::class, 'create'])->name('home');

Route::post('/submissions', [SubmissionController::class, 'store'])
    ->name('submissions.store')
    ->middleware('throttle:10,1'); // 10 submissions/minute/IP - the public form has no auth to rate limit by user

Route::get('/ajax/blocks', [LookupController::class, 'blocks'])->name('ajax.blocks');
Route::get('/ajax/schools', [LookupController::class, 'schools'])->name('ajax.schools');
Route::get('/ajax/subjects', [LookupController::class, 'subjects'])->name('ajax.subjects');
Route::get('/ajax/project', [LookupController::class, 'project'])->name('ajax.project');

Route::get('/projects/{id}/download', [ProjectDownloadController::class, 'show'])
    ->whereNumber('id')
    ->name('projects.download');

// ── Admin authentication ──
Route::middleware('guest')->group(function () {
    Route::get('/admin/login', [LoginController::class, 'create'])->name('admin.login');
    Route::post('/admin/login', [LoginController::class, 'store'])
        ->middleware('throttle:5,1')
        ->name('admin.login.attempt');
});

Route::post('/admin/logout', [LoginController::class, 'destroy'])
    ->middleware('auth')
    ->name('admin.logout');

// ── Admin-only utilities (previously export_submissions.php / master_import.php
//    with NO authentication at all - this is the security gap this migration closes) ──
Route::middleware('auth')->prefix('admin')->name('admin.')->group(function () {
    Route::get('/export', [ExportController::class, 'show'])->name('export');
    Route::post('/export/csv', [ExportController::class, 'csv'])->name('export.csv');
    Route::post('/export/evidence-zip', [ExportController::class, 'evidenceZip'])->name('export.evidence-zip');

    Route::get('/master-import', [MasterImportController::class, 'show'])->name('master-import');
    Route::post('/master-import', [MasterImportController::class, 'store'])->name('master-import.store');
});
