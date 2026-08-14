<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

/**
 * Seeds cycles/grades/subjects/grade_subject_map/projects/project_tasks -
 * the Cycle 1 program content that used to be baked into
 * database/LEP_V2_Production.sql as inline INSERT statements (27 projects,
 * 165 tasks) rather than a separate import feature. Without this, a fresh
 * migration leaves those tables empty and the app has nothing to select.
 *
 * database/seeders/data/reference_data.sql is that same SQL, extracted
 * unchanged (still the original idempotent INSERT...SELECT...WHERE NOT
 * EXISTS / UPDATE...WHERE pattern - safe to re-run against a database that
 * already has this data; it inserts nothing new and just re-confirms the
 * project_file mappings).
 */
class ReferenceDataSeeder extends Seeder
{
    public function run(): void
    {
        $path = __DIR__.'/data/reference_data.sql';
        $sql = file_get_contents($path);

        foreach ($this->splitStatements($sql) as $statement) {
            DB::unprepared($statement);
        }

        $this->command?->info('Reference data seeded: cycles, grades, subjects, grade_subject_map, projects, project_tasks.');
    }

    /**
     * @return string[]
     */
    private function splitStatements(string $sql): array
    {
        $statements = [];

        foreach (explode(';', $sql) as $chunk) {
            $chunk = trim($chunk);

            // Skip chunks that are empty or contain only `--` comment lines.
            $meaningful = trim(preg_replace('/^\s*--.*$/m', '', $chunk));

            if ($meaningful === '') {
                continue;
            }

            $statements[] = $chunk;
        }

        return $statements;
    }
}
