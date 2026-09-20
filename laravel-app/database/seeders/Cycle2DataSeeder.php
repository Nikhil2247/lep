<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Adds Cycle 2 to the catalog: 1 cycle row, 27 projects, 146 tasks.
 *
 * database/seeders/data/cycle2_data.sql is the executable body of the
 * reviewed lep_cycle2_import_FINAL_PRODUCTION_v1.2.sql (preflight, baseline
 * capture, the INSERTs, and a verify-then-commit-or-rollback gate). Every
 * INSERT is guarded by NOT EXISTS on its natural key, so re-running this
 * seeder is safe and inserts nothing on a second pass. The gate re-measures
 * Cycle 1 identity (row counts, id min/max/sum, content MD5) after the
 * writes and only commits when Cycle 1 is provably unchanged and Cycle 2
 * matches the expected 27 projects / 146 tasks / content hashes exactly -
 * otherwise it rolls back on the same connection.
 */
class Cycle2DataSeeder extends Seeder
{
    public function run(): void
    {
        $path = __DIR__.'/data/cycle2_data.sql';
        $sql = file_get_contents($path);

        foreach ($this->splitStatements($sql) as $statement) {
            if (preg_match('/^SELECT\b/i', $statement)) {
                $rows = DB::select($statement);

                if ($rows !== []) {
                    $this->command?->table(array_keys((array) $rows[0]), array_map(fn ($row) => (array) $row, $rows));
                }

                continue;
            }

            DB::unprepared($statement);
        }

        $result = DB::select('SELECT @import_ok AS import_ok, @finish_sql AS action_taken, '.
            '@a_c2_proj_md5 AS cycle2_project_hash, @a_c2_task_md5 AS cycle2_task_hash')[0];

        if (! $result->import_ok) {
            throw new RuntimeException(
                'Cycle 2 import rolled back - one or more catalog checks failed (see table above). '.
                'No Cycle 1 or Cycle 2 data was changed.'
            );
        }

        $this->command?->info("Cycle 2 import committed (action: {$result->action_taken}).");
        $this->command?->info("cycle2_project_hash={$result->cycle2_project_hash} cycle2_task_hash={$result->cycle2_task_hash}");
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
