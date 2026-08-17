<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreSubmissionRequest;
use App\Models\Cycle;
use App\Models\District;
use App\Models\Grade;
use App\Models\SubmissionEvidence;
use App\Models\TaskResponse;
use App\Models\TeacherSubmission;
use App\Services\EvidenceUploadService;
use Illuminate\Support\Facades\DB;
use Illuminate\View\View;

/**
 * Ports index.php (public form + certificate) and process_submission.php
 * (form handler) from the legacy app.
 */
class SubmissionController extends Controller
{
    public function create(): View
    {
        $districts = District::where('is_active', 1)->orderBy('name')->get(['id', 'name']);
        $grades = Grade::where('is_active', 1)
            ->orderBy('sort_order')->orderBy('name')
            ->get(['id', 'name', 'is_school_leader']);
        $cycles = Cycle::where('is_active', 1)
            ->orderBy('sort_order')->orderBy('name')
            ->get(['id', 'name']);

        $success = session('success');
        $certificate = null;

        if ($success) {
            $certificate = TeacherSubmission::with(['school', 'grade', 'subject', 'project'])
                ->where('submission_id', $success)
                ->first();
        }

        return view('home', compact('districts', 'grades', 'cycles', 'success', 'certificate'));
    }

    public function store(StoreSubmissionRequest $request, EvidenceUploadService $evidence)
    {
        $grade = Grade::findOrFail($request->input('grade_id'));
        $isSchoolLeader = (bool) $grade->is_school_leader;
        $subjectId = $isSchoolLeader ? null : $request->input('subject_id');

        $taskCompleted = (array) $request->input('task_completed', []);
        $videoLink = trim((string) $request->input('project_video_link', ''));
        $files = array_values(array_filter((array) $request->file('project_evidence', [])));

        [$submission, $submissionCode] = DB::transaction(function () use (
            $request, $subjectId, $taskCompleted, $videoLink
        ) {
            $submissionCode = $this->generateSubmissionId();

            $submission = TeacherSubmission::create([
                'submission_id' => $submissionCode,
                'teacher_name' => trim((string) $request->input('teacher_name')),
                'designation' => trim((string) $request->input('designation')),
                'district_id' => $request->input('district_id'),
                'block_id' => $request->input('block_id'),
                'school_id' => $request->input('school_id'),
                'grade_id' => $request->input('grade_id'),
                'subject_id' => $subjectId,
                'cycle_id' => $request->input('cycle_id'),
                'project_id' => $request->input('project_id'),
                'video_link' => $videoLink !== '' ? $videoLink : null,
                'ip_address' => $request->ip(),
            ]);

            foreach ($taskCompleted as $taskId => $completed) {
                TaskResponse::create([
                    'submission_id' => $submission->id,
                    'task_id' => (int) $taskId,
                    'completed' => $completed,
                ]);
            }

            return [$submission, $submissionCode];
        });

        // Compression + MinIO upload happen outside the DB transaction - these
        // are network/CPU bound and previously held a MySQL transaction open
        // for their whole duration, slowing every other request on the pool.
        foreach ($files as $index => $file) {
            $ext = strtolower((string) pathinfo($file->getClientOriginalName(), PATHINFO_EXTENSION));
            $path = $evidence->store($file, $ext, $submissionCode, $index);

            SubmissionEvidence::create([
                'submission_id' => $submission->id,
                'file_path' => $path,
                'original_name' => $file->getClientOriginalName(),
            ]);
        }

        return redirect()->route('home')->with('success', $submissionCode);
    }

    /**
     * Generate the next Submission ID: LEP-YYYY-000001
     * (mirrors generateSubmissionId() in the legacy includes/functions.php).
     */
    private function generateSubmissionId(): string
    {
        $prefix = config('lep.submission_prefix_base').'-'.now()->format('Y').'-';

        $last = TeacherSubmission::where('submission_id', 'like', $prefix.'%')
            ->orderByDesc('id')
            ->value('submission_id');

        $next = $last ? ((int) substr($last, strlen($prefix)) + 1) : 1;

        return $prefix.str_pad((string) $next, 6, '0', STR_PAD_LEFT);
    }
}
