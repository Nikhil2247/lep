{{-- Ported from the legacy master_import.php. Now gated behind admin auth
     (routes/web.php) instead of being wide open. --}}
@extends('layouts.app')

@section('title', 'Master School Data Import')

@section('content')
<div class="container my-4" style="max-width:720px">
    <div class="d-flex justify-content-end mb-2">
        <form method="POST" action="{{ route('admin.logout') }}">
            @csrf
            <button type="submit" class="btn btn-sm btn-outline-secondary">
                <i class="bi bi-box-arrow-right me-1"></i>Log out
            </button>
        </form>
    </div>

    <div class="alert alert-warning">
        <i class="bi bi-exclamation-triangle me-1"></i>
        <strong>Admin utility only.</strong>
        This page is not linked from the main teacher-facing application.
    </div>

    @if ($errors->any())
        <div class="alert alert-danger">
            <ul class="mb-0">
                @foreach ($errors->all() as $err)
                    <li>{{ $err }}</li>
                @endforeach
            </ul>
        </div>
    @endif

    @if (!empty($error))
        <div class="alert alert-danger">
            <strong>Import failed</strong><br>
            {{ $error }}
        </div>
    @endif

    @if (!empty($result))
        <div class="alert alert-success">
            <h5 class="alert-heading"><i class="bi bi-check-circle me-2"></i>Master School Data Imported Successfully</h5>
            <hr>
            <ul class="mb-2">
                <li>Districts Imported (new) : <strong>{{ $result['districts_new'] }}</strong>
                    &nbsp;(total active: {{ $result['districts_total'] }})</li>
                <li>Blocks Imported (new) : <strong>{{ $result['blocks_new'] }}</strong>
                    &nbsp;(total active: {{ $result['blocks_total'] }})</li>
                <li>Schools Imported (new) : <strong>{{ number_format($result['schools_new']) }}</strong>
                    &nbsp;(total active: {{ number_format($result['schools_total']) }})</li>
                <li>Duplicate Schools Skipped : <strong>{{ $result['schools_skipped'] }}</strong></li>
                <li>Data rows read : {{ $result['rows_read'] }}
                    @if ($result['rows_invalid'])
                        &nbsp;(invalid/incomplete rows skipped: {{ $result['rows_invalid'] }})
                    @endif
                </li>
            </ul>
            <p class="mb-0">Import Completed Successfully.</p>
        </div>
        <p>
            <a href="{{ route('home') }}" class="btn btn-success">
                <i class="bi bi-arrow-right me-1"></i>Open LEP Application
            </a>
        </p>
    @endif

    <div class="card shadow-sm mb-4">
        <div class="card-header bg-white fw-semibold">
            <i class="bi bi-file-earmark-excel me-2 text-success"></i>Import Official Master School Data
        </div>
        <div class="card-body">
            <p class="text-muted small">
                Expected columns: <code>District</code>, <code>Block</code>, <code>School Name</code>, <code>UDISE Code</code>.
                The <code>Sl No</code> column is ignored.
            </p>

            @if ($hasDefaultCsv || $hasDefaultXlsx)
                <div class="alert alert-info py-2 small mb-3">
                    <i class="bi bi-info-circle me-1"></i>
                    Official file found in <code>storage/app/master-import/</code>
                    ({{ $hasDefaultCsv ? 'CSV' : '' }}{{ ($hasDefaultCsv && $hasDefaultXlsx) ? ' + ' : '' }}{{ $hasDefaultXlsx ? 'XLSX' : '' }}).
                    You can import it directly without uploading.
                </div>
            @else
                <div class="alert alert-secondary py-2 small mb-3">
                    No pre-placed file in <code>storage/app/master-import/</code>. Please upload the Excel or CSV file below.
                </div>
            @endif

            <form method="POST" action="{{ route('admin.master-import.store') }}" enctype="multipart/form-data">
                @csrf
                <div class="mb-3">
                    <label class="form-label">Upload file (.xlsx or .csv) <span class="text-muted">— optional if file is pre-placed</span></label>
                    <input type="file" name="excel_file" class="form-control" accept=".xlsx,.csv">
                </div>

                <div class="form-check mb-3">
                    <input class="form-check-input" type="checkbox" name="clear_first" value="1" id="clear_first">
                    <label class="form-check-label" for="clear_first">
                        Clear existing Districts / Blocks / Schools before import
                        <span class="text-muted small d-block">
                            Only allowed when there are no teacher submissions yet. Use for a clean first-time setup.
                        </span>
                    </label>
                </div>

                <button type="submit" class="btn btn-success">
                    <i class="bi bi-cloud-upload me-1"></i>Run Import
                </button>
                <a href="{{ route('admin.export') }}" class="btn btn-outline-secondary ms-2">Cancel</a>
            </form>
        </div>
    </div>
</div>
@endsection
