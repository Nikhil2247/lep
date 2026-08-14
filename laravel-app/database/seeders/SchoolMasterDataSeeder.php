<?php

namespace Database\Seeders;

use App\Services\MasterImportService;
use Illuminate\Database\Seeder;
use RuntimeException;

/**
 * Seeds districts/blocks/schools from the official Master_Schools-2026 file
 * (the same file/logic behind /admin/master-import - see
 * App\Services\MasterImportService). Looks for it at
 * storage/app/master-import/Master_Schools-2026.{csv,xlsx} first (already
 * staged there in this repo); falls back to a --path=... option.
 *
 * Safe to re-run: duplicate UDISE codes are skipped, not re-inserted.
 *
 *   php artisan db:seed --class=SchoolMasterDataSeeder
 */
class SchoolMasterDataSeeder extends Seeder
{
    public function run(): void
    {
        $csv = storage_path('app/master-import/Master_Schools-2026.csv');
        $xlsx = storage_path('app/master-import/Master_Schools-2026.xlsx');

        if (is_file($csv)) {
            [$path, $format] = [$csv, 'csv'];
        } elseif (is_file($xlsx)) {
            [$path, $format] = [$xlsx, 'xlsx'];
        } else {
            throw new RuntimeException(
                'Master_Schools-2026.csv (or .xlsx) not found in storage/app/master-import/. '.
                'Place the official file there, or import it via /admin/master-import instead.'
            );
        }

        $importer = new MasterImportService;
        $rows = $importer->loadRows($path, $format);
        $stats = $importer->run($rows, clearFirst: false);

        $this->command?->info(sprintf(
            'School master data seeded: %d new districts, %d new blocks, %d new schools (%d duplicate UDISE codes skipped).',
            $stats['districts_new'],
            $stats['blocks_new'],
            $stats['schools_new'],
            $stats['schools_skipped']
        ));
    }
}
