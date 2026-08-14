<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\View\View;
use RuntimeException;
use Symfony\Component\HttpFoundation\StreamedResponse;
use Throwable;
use ZipArchive;

/**
 * Ports export_submissions.php - identical CSV/ZIP export logic, now gated
 * behind the 'auth' middleware (routes/web.php). This endpoint used to be
 * reachable by anyone who knew the URL and could dump every teacher's
 * name/school/submission data plus every evidence file; that was the main
 * gap this Laravel migration was built to close.
 */
class ExportController extends Controller
{
    public function show(): View
    {
        return view('admin.export', [
            'count' => DB::table('teacher_submissions')->count(),
        ]);
    }

    public function csv(): StreamedResponse|RedirectResponse
    {
        try {
            return $this->streamCsv();
        } catch (Throwable $e) {
            report($e);

            return redirect()->route('admin.export')->with('error', $e->getMessage());
        }
    }

    public function evidenceZip(): StreamedResponse|RedirectResponse
    {
        try {
            return $this->streamEvidenceZip();
        } catch (Throwable $e) {
            report($e);

            return redirect()->route('admin.export')->with('error', $e->getMessage());
        }
    }

    private function streamCsv(): StreamedResponse
    {
        $submissions = DB::table('teacher_submissions as ts')
            ->join('districts as d', 'd.id', '=', 'ts.district_id')
            ->join('blocks as b', 'b.id', '=', 'ts.block_id')
            ->join('schools as sc', 'sc.id', '=', 'ts.school_id')
            ->join('grades as g', 'g.id', '=', 'ts.grade_id')
            ->join('cycles as c', 'c.id', '=', 'ts.cycle_id')
            ->join('projects as p', 'p.id', '=', 'ts.project_id')
            ->leftJoin('subjects as s', 's.id', '=', 'ts.subject_id')
            ->orderBy('ts.submitted_at')->orderBy('ts.id')
            ->select([
                'ts.id as db_id', 'ts.submission_id', 'ts.submitted_at', 'ts.teacher_name',
                'ts.designation', 'ts.video_link',
                'd.name as district_name', 'b.name as block_name',
                'sc.school_name', 'sc.udise_code',
                'g.name as grade_name', 's.name as subject_name', 'c.name as cycle_name',
                'p.project_title', 'p.duration', 'p.objective',
            ])
            ->get();

        if ($submissions->isEmpty()) {
            throw new RuntimeException('No submissions found to export.');
        }

        $rowsData = [];
        $maxTasks = 0;

        foreach ($submissions as $sub) {
            $tasks = DB::table('task_responses as tr')
                ->join('project_tasks as pt', 'pt.id', '=', 'tr.task_id')
                ->where('tr.submission_id', $sub->db_id)
                ->orderBy('pt.sort_order')->orderBy('pt.task_number')->orderBy('pt.id')
                ->select(['pt.task_number', 'pt.task_type', 'pt.task_description', 'tr.completed'])
                ->get();

            $maxTasks = max($maxTasks, $tasks->count());

            $files = DB::table('submission_evidence')
                ->where('submission_id', $sub->db_id)
                ->orderBy('id')
                ->pluck('original_name')
                ->map(fn ($name) => trim((string) $name))
                ->filter(fn ($name) => $name !== '')
                ->values();

            $rowsData[] = ['sub' => $sub, 'tasks' => $tasks, 'files' => $files];
        }

        $taskHeaders = [];
        for ($i = 0; $i < $maxTasks; $i++) {
            $label = 'Task '.($i + 1);
            foreach ($rowsData as $rd) {
                if (! isset($rd['tasks'][$i])) {
                    continue;
                }
                $tt = $rd['tasks'][$i]->task_type ?? 'Task';
                if ($tt === 'Showcase') {
                    $label = 'Showcase';

                    break;
                }
                $num = (int) ($rd['tasks'][$i]->task_number ?? ($i + 1));
                $label = 'Task '.$num;
            }
            $taskHeaders[] = $label;
        }

        $header = [
            'Submission ID', 'Submission Date', 'Name', 'Designation',
            'District', 'Block', 'School', 'UDISE Code',
            'Grade', 'Subject', 'Cycle', 'Project Title', 'Duration', 'Objective',
        ];
        foreach ($taskHeaders as $label) {
            $header[] = $label.' – Question';
            $header[] = $label.' – Response';
        }
        $header[] = 'Evidence Files';
        $header[] = 'Video Link';

        $filename = 'LEP_Submissions_'.now()->format('Y-m-d').'.csv';

        return response()->streamDownload(function () use ($rowsData, $maxTasks, $header) {
            $out = fopen('php://output', 'w');
            fwrite($out, "\xEF\xBB\xBF");
            fputcsv($out, $header);

            foreach ($rowsData as $rd) {
                $sub = $rd['sub'];
                $date = $sub->submitted_at ? date('d F Y H:i', strtotime($sub->submitted_at)) : '';

                $row = [
                    $sub->submission_id, $date, $sub->teacher_name, $sub->designation ?? '',
                    $sub->district_name, $sub->block_name, $sub->school_name, $sub->udise_code,
                    $sub->grade_name, $sub->subject_name ?? 'School Leaders', $sub->cycle_name,
                    $sub->project_title, $sub->duration ?? '', $sub->objective ?? '',
                ];

                for ($i = 0; $i < $maxTasks; $i++) {
                    if (isset($rd['tasks'][$i])) {
                        $t = $rd['tasks'][$i];
                        $row[] = (string) ($t->task_description ?? '');
                        $row[] = (string) ($t->completed ?? '');
                    } else {
                        $row[] = '';
                        $row[] = '';
                    }
                }

                $row[] = $rd['files']->isNotEmpty() ? $rd['files']->implode('; ') : '';
                $row[] = trim((string) ($sub->video_link ?? ''));

                fputcsv($out, $row);
            }

            fclose($out);
        }, $filename, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Cache-Control' => 'max-age=0, no-cache, must-revalidate, private',
        ]);
    }

    private function streamEvidenceZip(): StreamedResponse
    {
        if (! class_exists(ZipArchive::class)) {
            throw new RuntimeException(
                'PHP ZipArchive extension is required to generate the evidence ZIP. '.
                'Please enable the zip extension on the server.'
            );
        }

        $rows = DB::table('submission_evidence as se')
            ->join('teacher_submissions as ts', 'ts.id', '=', 'se.submission_id')
            ->orderBy('ts.submission_id')->orderBy('se.id')
            ->select(['se.file_path', 'se.original_name', 'ts.submission_id'])
            ->get();

        if ($rows->isEmpty()) {
            throw new RuntimeException('No evidence files found to include in the ZIP.');
        }

        $disk = Storage::disk('minio');

        $tmpBase = tempnam(sys_get_temp_dir(), 'lep_ev_');
        if ($tmpBase === false) {
            throw new RuntimeException('Unable to create temporary file for ZIP.');
        }
        $zipPath = $tmpBase.'.zip';
        @unlink($tmpBase);

        $zip = new ZipArchive;
        if ($zip->open($zipPath, ZipArchive::CREATE | ZipArchive::OVERWRITE) !== true) {
            throw new RuntimeException('Unable to create ZIP archive.');
        }

        $added = 0;
        $usedNames = [];

        foreach ($rows as $row) {
            $sid = preg_replace('/[^A-Za-z0-9\-]/', '', (string) $row->submission_id);
            if ($sid === '') {
                continue;
            }

            $key = ltrim(str_replace('\\', '/', (string) $row->file_path), '/');
            if ($key === '' || str_contains($key, '..') || ! str_starts_with($key, 'uploads/evidence/')) {
                continue;
            }

            if (! $disk->exists($key)) {
                continue;
            }

            $original = trim((string) ($row->original_name ?? ''));
            if ($original === '') {
                $original = basename($key);
            }
            $original = basename(str_replace(['\\', "\0"], '', $original));
            $original = preg_replace('/[\x00-\x1F\x7F<>:"|?*]/', '_', $original);
            $original = trim($original, ' .');
            if ($original === '' || $original === '.' || $original === '..') {
                $original = 'file_'.($added + 1);
            }

            $usedNames[$sid] ??= [];
            $nameKey = strtolower($original);
            if (isset($usedNames[$sid][$nameKey])) {
                $usedNames[$sid][$nameKey]++;
                $ext = pathinfo($original, PATHINFO_EXTENSION);
                $base = pathinfo($original, PATHINFO_FILENAME);
                $original = $base.'_'.$usedNames[$sid][$nameKey].($ext !== '' ? '.'.$ext : '');
            } else {
                $usedNames[$sid][$nameKey] = 1;
            }

            $entry = $sid.'/'.$original;
            if ($zip->addFromString($entry, $disk->get($key))) {
                $added++;
            }
        }

        $zip->close();

        if ($added < 1) {
            @unlink($zipPath);
            throw new RuntimeException(
                'No evidence files could be added to the ZIP. Files may be missing in storage.'
            );
        }

        $filename = 'LEP_All_Evidence_'.now()->format('Y-m-d').'.zip';

        return response()->streamDownload(function () use ($zipPath) {
            readfile($zipPath);
            @unlink($zipPath);
        }, $filename, [
            'Content-Type' => 'application/zip',
            'Cache-Control' => 'max-age=0, no-cache, must-revalidate, private',
        ]);
    }
}
