<?php

namespace App\Services;

use App\Support\SimpleXlsxReader;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Ports loadMasterRows()/runMasterImport() from the legacy master_import.php.
 * Districts/Blocks/Schools stay in MySQL (unlike evidence/project files,
 * this master-data import has nothing to do with object storage).
 */
class MasterImportService
{
    /**
     * @return array[]
     */
    public function loadRows(string $path, string $format): array
    {
        if ($format === 'csv') {
            return $this->loadCsvRows($path);
        }

        return (new SimpleXlsxReader($path))->getRows();
    }

    private function loadCsvRows(string $path): array
    {
        $rows = [];
        $fh = fopen($path, 'r');
        if (! $fh) {
            throw new RuntimeException('Unable to open CSV file.');
        }

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

    /**
     * @param  array[]  $rows
     * @return array<string, int>
     */
    public function run(array $rows, bool $clearFirst): array
    {
        if (count($rows) < 2) {
            throw new RuntimeException('File appears empty or has no data rows.');
        }

        $header = array_map(fn ($h) => strtolower(trim((string) $h)), $rows[0]);
        $colDistrict = array_search('district', $header, true);
        $colBlock = array_search('block', $header, true);
        $colSchool = array_search('school name', $header, true);
        $colUdise = array_search('udise code', $header, true);

        if ($colDistrict === false || $colBlock === false || $colSchool === false || $colUdise === false) {
            throw new RuntimeException(
                'Required columns not found. Expected: District, Block, School Name, UDISE Code. '.
                'Found: '.implode(', ', $rows[0])
            );
        }

        $stats = [
            'districts_new' => 0,
            'blocks_new' => 0,
            'schools_new' => 0,
            'schools_skipped' => 0,
            'rows_read' => 0,
            'rows_invalid' => 0,
        ];

        DB::transaction(function () use ($rows, $clearFirst, $colDistrict, $colBlock, $colSchool, $colUdise, &$stats) {
            if ($clearFirst) {
                $subCount = DB::table('teacher_submissions')->count();
                if ($subCount > 0) {
                    throw new RuntimeException(
                        "Cannot clear master data: {$subCount} teacher submission(s) already exist. ".
                        'Clear is only allowed on a fresh database.'
                    );
                }
                DB::table('schools')->delete();
                DB::table('blocks')->delete();
                DB::table('districts')->delete();
            }

            $districtCache = [];
            $blockCache = [];
            $existingUdise = [];

            foreach (DB::table('districts')->select('id', 'name')->get() as $r) {
                $districtCache[$r->name] = (int) $r->id;
            }
            foreach (DB::table('blocks')->select('id', 'district_id', 'name')->get() as $r) {
                $blockCache[$r->district_id.'|'.$r->name] = (int) $r->id;
            }
            foreach (DB::table('schools')->select('udise_code')->get() as $r) {
                $existingUdise[$r->udise_code] = true;
            }

            for ($i = 1, $n = count($rows); $i < $n; $i++) {
                $row = $rows[$i];
                $district = trim((string) ($row[$colDistrict] ?? ''));
                $block = trim((string) ($row[$colBlock] ?? ''));
                $school = trim((string) ($row[$colSchool] ?? ''));
                $udise = trim((string) ($row[$colUdise] ?? ''));

                if ($district === '' && $block === '' && $school === '' && $udise === '') {
                    continue;
                }

                $stats['rows_read']++;

                if ($district === '' || $block === '' || $school === '' || $udise === '') {
                    $stats['rows_invalid']++;

                    continue;
                }

                if (is_numeric($udise)) {
                    $udise = (string) (int) (float) $udise;
                }

                if (! isset($districtCache[$district])) {
                    $districtCache[$district] = DB::table('districts')->insertGetId([
                        'name' => $district, 'is_active' => 1,
                    ]);
                    $stats['districts_new']++;
                }
                $districtId = $districtCache[$district];

                $blockKey = $districtId.'|'.$block;
                if (! isset($blockCache[$blockKey])) {
                    $blockCache[$blockKey] = DB::table('blocks')->insertGetId([
                        'district_id' => $districtId, 'name' => $block, 'is_active' => 1,
                    ]);
                    $stats['blocks_new']++;
                }
                $blockId = $blockCache[$blockKey];

                if (isset($existingUdise[$udise])) {
                    $stats['schools_skipped']++;

                    continue;
                }

                DB::table('schools')->insert([
                    'block_id' => $blockId, 'school_name' => $school, 'udise_code' => $udise, 'is_active' => 1,
                ]);
                $existingUdise[$udise] = true;
                $stats['schools_new']++;
            }
        });

        $stats['districts_total'] = DB::table('districts')->where('is_active', 1)->count();
        $stats['blocks_total'] = DB::table('blocks')->where('is_active', 1)->count();
        $stats['schools_total'] = DB::table('schools')->where('is_active', 1)->count();

        return $stats;
    }
}
