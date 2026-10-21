<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Adds Cycle 3 to the catalog: 1 cycle row, 27 projects, 168 tasks.
 *
 * database/seeders/data/cycle3_data.sql is the executable body of
 * lep_cycle3_import_FINAL_PRODUCTION_CANDIDATE.sql (preflight, baseline
 * capture, the INSERTs, and a verify-then-commit-or-rollback gate) - same
 * structure and safety conventions as Cycle2DataSeeder. Every INSERT is
 * guarded by NOT EXISTS on its natural key, so re-running this seeder is
 * safe and inserts nothing on a second pass. The gate re-measures Cycle 1
 * and Cycle 2 identity (row counts, id min/max/sum, content MD5) after the
 * writes and only commits when both are provably unchanged and Cycle 3
 * matches the expected 27 projects / 168 tasks / content hashes exactly -
 * otherwise it rolls back on the same connection.
 */
class Cycle3DataSeeder extends Seeder
{
    public function run(): void
    {
        $path = __DIR__.'/data/cycle3_data.sql';
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
            '@a_c3_proj_md5 AS cycle3_project_hash, @a_c3_task_md5 AS cycle3_task_hash')[0];

        if (! $result->import_ok) {
            throw new RuntimeException(
                'Cycle 3 import rolled back - one or more catalog checks failed (see table above). '.
                'No Cycle 1, Cycle 2, or Cycle 3 data was changed.'
            );
        }

        $this->command?->info("Cycle 3 import committed (action: {$result->action_taken}).");
        $this->command?->info("cycle3_project_hash={$result->cycle3_project_hash} cycle3_task_hash={$result->cycle3_task_hash}");
    }

    /**
     * Splits a SQL script into individual statements. Unlike a naive
     * explode(';', ...), this tracks `--`/`#` line comments and quoted
     * strings so a semicolon inside a comment sentence or inside a string
     * literal (e.g. a task description like "... for feedback; model
     * sentence starters ...") never produces a bogus statement boundary.
     *
     * @return string[]
     */
    private function splitStatements(string $sql): array
    {
        $statements = [];
        $current = '';
        $length = strlen($sql);
        $inSingle = false;
        $inDouble = false;

        for ($i = 0; $i < $length; $i++) {
            $char = $sql[$i];

            if (! $inSingle && ! $inDouble && $char === '-' && ($sql[$i + 1] ?? '') === '-') {
                $eol = strpos($sql, "\n", $i);
                $i = ($eol === false ? $length : $eol) - 1;

                continue;
            }

            if (! $inSingle && ! $inDouble && $char === '#') {
                $eol = strpos($sql, "\n", $i);
                $i = ($eol === false ? $length : $eol) - 1;

                continue;
            }

            if (! $inDouble && $char === "'") {
                if ($inSingle && ($sql[$i + 1] ?? '') === "'") {
                    $current .= "''";
                    $i++;

                    continue;
                }
                $inSingle = ! $inSingle;
                $current .= $char;

                continue;
            }

            if (! $inSingle && $char === '"') {
                if ($inDouble && ($sql[$i + 1] ?? '') === '"') {
                    $current .= '""';
                    $i++;

                    continue;
                }
                $inDouble = ! $inDouble;
                $current .= $char;

                continue;
            }

            if (! $inSingle && ! $inDouble && $char === ';') {
                $trimmed = trim($current);
                if ($trimmed !== '') {
                    $statements[] = $trimmed;
                }
                $current = '';

                continue;
            }

            $current .= $char;
        }

        $trimmed = trim($current);
        if ($trimmed !== '') {
            $statements[] = $trimmed;
        }

        return $statements;
    }
}
