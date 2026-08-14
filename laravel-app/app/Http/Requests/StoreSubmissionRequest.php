<?php

namespace App\Http\Requests;

use App\Models\Grade;
use App\Models\ProjectTask;
use App\Services\EvidenceUploadService;
use Illuminate\Contracts\Validation\Validator as ValidatorContract;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Ports the manual $errors[] checks from the legacy process_submission.php,
 * keeping the same fields, rules and (where practical) the exact wording of
 * error messages so the teacher-facing behavior is unchanged.
 */
class StoreSubmissionRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'teacher_name' => ['required', 'string', 'max:150'],
            'designation' => ['required', 'string', 'max:100'],
            'district_id' => ['required', 'integer', 'exists:districts,id'],
            'block_id' => ['required', 'integer', 'exists:blocks,id'],
            'school_id' => ['required', 'integer', 'exists:schools,id'],
            'grade_id' => ['required', 'integer', 'exists:grades,id'],
            'subject_id' => ['nullable', 'integer', 'exists:subjects,id'],
            'cycle_id' => ['required', 'integer', 'exists:cycles,id'],
            'project_id' => ['required', 'integer', 'exists:projects,id'],
            'project_video_link' => ['nullable', 'url'],
            'task_completed' => ['nullable', 'array'],
            'task_completed.*' => ['in:Yes,No'],
            'project_evidence' => ['required', 'array', 'max:'.config('lep.max_evidence_files')],
            'project_evidence.*' => ['file'],
        ];
    }

    public function messages(): array
    {
        return [
            'teacher_name.required' => 'Teacher Name is required.',
            'designation.required' => 'Designation is required.',
            'district_id.required' => 'District is required.',
            'district_id.exists' => 'District is required.',
            'block_id.required' => 'Block is required.',
            'block_id.exists' => 'Block is required.',
            'school_id.required' => 'School is required.',
            'school_id.exists' => 'School is required.',
            'grade_id.required' => 'Grade is required.',
            'grade_id.exists' => 'Grade is required.',
            'cycle_id.required' => 'Cycle is required.',
            'cycle_id.exists' => 'Cycle is required.',
            'project_id.required' => 'Project could not be determined. Please re-select Grade / Subject / Cycle.',
            'project_id.exists' => 'Project could not be determined. Please re-select Grade / Subject / Cycle.',
            'project_video_link.url' => 'Video Link must be a valid URL.',
            'project_evidence.required' => 'Please upload at least one evidence file before submitting your response.',
            'project_evidence.max' => 'You may upload a maximum of '.config('lep.max_evidence_files').' evidence files.',
        ];
    }

    public function withValidator(ValidatorContract $validator): void
    {
        $validator->after(function (ValidatorContract $validator) {
            $this->validateSubjectRequiredUnlessSchoolLeader($validator);
            $this->validateTaskResponses($validator);
            $this->validateEvidenceFiles($validator);
        });
    }

    private function validateSubjectRequiredUnlessSchoolLeader(ValidatorContract $validator): void
    {
        $gradeId = $this->input('grade_id');
        if (! $gradeId || $validator->errors()->has('grade_id')) {
            return;
        }

        $isSchoolLeader = (bool) Grade::find($gradeId)?->is_school_leader;

        if (! $isSchoolLeader && ! $this->filled('subject_id')) {
            $validator->errors()->add('subject_id', 'Subject is required for the selected Grade.');
        }
    }

    private function validateTaskResponses(ValidatorContract $validator): void
    {
        $taskCompleted = (array) $this->input('task_completed', []);

        if (empty($taskCompleted)) {
            $validator->errors()->add(
                'task_completed',
                'No task responses received. Please complete the Project Tasks section.'
            );

            return;
        }

        $projectId = $this->input('project_id');
        if (! $projectId || ! $validator->errors()->isEmpty()) {
            return;
        }

        $expectedTaskIds = ProjectTask::where('project_id', $projectId)
            ->where('is_active', 1)
            ->pluck('id');

        foreach ($expectedTaskIds as $taskId) {
            if (! isset($taskCompleted[$taskId]) || ! in_array($taskCompleted[$taskId], ['Yes', 'No'], true)) {
                $validator->errors()->add('task_completed', 'Please select Yes or No for all tasks.');
                break;
            }
        }
    }

    private function validateEvidenceFiles(ValidatorContract $validator): void
    {
        if ($validator->errors()->has('project_evidence')) {
            return;
        }

        $files = array_filter((array) $this->file('project_evidence', []));

        if (empty($files)) {
            $validator->errors()->add(
                'project_evidence',
                'Please upload at least one evidence file before submitting your response.'
            );

            return;
        }

        $service = app(EvidenceUploadService::class);
        $totalSize = 0;
        $anyValid = false;

        foreach ($files as $file) {
            $result = $service->validate($file);

            if (! $result['ok']) {
                $validator->errors()->add(
                    'project_evidence',
                    'Evidence file "'.$file->getClientOriginalName().'": '.$result['error']
                );

                continue;
            }

            $anyValid = true;
            $totalSize += $file->getSize();
        }

        if (! $anyValid) {
            $validator->errors()->add(
                'project_evidence',
                'Please upload at least one evidence file before submitting your response.'
            );

            return;
        }

        if ($totalSize > config('lep.max_evidence_total_size')) {
            $validator->errors()->add(
                'project_evidence',
                'The total combined size of all uploaded evidence files cannot exceed 5 MB. '.
                'Please remove one or more files and try again.'
            );
        }
    }
}
