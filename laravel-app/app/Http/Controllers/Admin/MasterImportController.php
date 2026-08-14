<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Services\MasterImportService;
use Illuminate\Http\Request;
use Illuminate\View\View;
use RuntimeException;
use Throwable;

/**
 * Ports master_import.php - identical import logic (see
 * App\Services\MasterImportService), now gated behind the 'auth'
 * middleware (routes/web.php) instead of being reachable by anyone who
 * knew the URL.
 */
class MasterImportController extends Controller
{
    public function show(): View
    {
        return view('admin.master-import', $this->defaultFileFlags());
    }

    public function store(Request $request, MasterImportService $importer): View
    {
        $request->validate([
            'excel_file' => ['nullable', 'file', 'mimes:xlsx,csv'],
            'clear_first' => ['nullable', 'boolean'],
        ]);

        $defaults = $this->defaultFileFlags();

        try {
            [$sourcePath, $format] = $this->resolveSource($request, $defaults);

            $rows = $importer->loadRows($sourcePath, $format);
            $result = $importer->run($rows, $request->boolean('clear_first'));

            return view('admin.master-import', [...$defaults, 'result' => $result]);
        } catch (Throwable $e) {
            report($e);

            return view('admin.master-import', [...$defaults, 'error' => $e->getMessage()]);
        }
    }

    private function resolveSource(Request $request, array $defaults): array
    {
        if ($request->hasFile('excel_file')) {
            $file = $request->file('excel_file');

            return [$file->getRealPath(), strtolower($file->getClientOriginalExtension())];
        }

        if ($defaults['hasDefaultCsv']) {
            return [$this->defaultCsvPath(), 'csv'];
        }

        if ($defaults['hasDefaultXlsx']) {
            return [$this->defaultXlsxPath(), 'xlsx'];
        }

        throw new RuntimeException(
            'Master data file not found. Place Master_Schools-2026.csv (or .xlsx) in '.
            'storage/app/master-import/, or upload it using the form below.'
        );
    }

    private function defaultFileFlags(): array
    {
        return [
            'hasDefaultCsv' => is_file($this->defaultCsvPath()),
            'hasDefaultXlsx' => is_file($this->defaultXlsxPath()),
        ];
    }

    private function defaultCsvPath(): string
    {
        return storage_path('app/master-import/Master_Schools-2026.csv');
    }

    private function defaultXlsxPath(): string
    {
        return storage_path('app/master-import/Master_Schools-2026.xlsx');
    }
}
