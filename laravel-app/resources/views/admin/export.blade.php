{{-- Ported from the legacy export_submissions.php presentation page.
     Now gated behind admin auth (routes/web.php) instead of being wide open. --}}
@extends('layouts.app')

@section('title', 'Export Submissions')

@section('content')
<div class="container my-4" style="max-width:640px">
    <div class="d-flex justify-content-end mb-2">
        <form method="POST" action="{{ route('admin.logout') }}">
            @csrf
            <button type="submit" class="btn btn-sm btn-outline-secondary">
                <i class="bi bi-box-arrow-right me-1"></i>Log out
            </button>
        </form>
    </div>

    @if (session('error'))
        <div class="alert alert-danger">{{ session('error') }}</div>
    @endif

    <div class="card shadow-sm mb-4">
        <div class="card-header bg-white fw-semibold">
            <i class="bi bi-filetype-csv me-2 text-success"></i>Export LEP Submissions
        </div>
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
                Total Submissions: <strong>{{ $count }}</strong>
            </p>
            <div class="d-flex flex-wrap gap-2">
                <form method="POST" action="{{ route('admin.export.csv') }}">
                    @csrf
                    <button type="submit" class="btn btn-success" @disabled($count < 1)>
                        <i class="bi bi-download me-1"></i>Download CSV (.csv)
                    </button>
                </form>
                <form method="POST" action="{{ route('admin.export.evidence-zip') }}">
                    @csrf
                    <button type="submit" class="btn btn-outline-success" @disabled($count < 1)>
                        <i class="bi bi-file-earmark-zip me-1"></i>Download All Evidence (.ZIP)
                    </button>
                </form>
                <a href="{{ route('home') }}" class="btn btn-outline-secondary">Back to Form</a>
                <a href="{{ route('admin.master-import') }}" class="btn btn-outline-secondary">Master Import</a>
            </div>
        </div>
    </div>
</div>
@endsection
