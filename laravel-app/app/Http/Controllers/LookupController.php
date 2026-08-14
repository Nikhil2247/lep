<?php

namespace App\Http\Controllers;

use App\Models\Grade;
use App\Models\Project;
use App\Models\ProjectTask;
use App\Models\School;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Ports ajax/get_blocks.php, get_schools.php, get_subjects.php and
 * get_project.php - same JSON response shapes as the legacy endpoints so
 * assets/js/app.js only needs its request URLs updated, not its parsing.
 */
class LookupController extends Controller
{
    public function blocks(Request $request): JsonResponse
    {
        $districtId = $request->integer('district_id');
        if (! $districtId) {
            return response()->json(['success' => false, 'message' => 'Invalid district'], 400);
        }

        $blocks = \App\Models\Block::where('district_id', $districtId)
            ->where('is_active', 1)
            ->orderBy('name')
            ->get(['id', 'name']);

        return response()->json(['success' => true, 'data' => $blocks]);
    }

    public function schools(Request $request): JsonResponse
    {
        $blockId = $request->integer('block_id');
        if (! $blockId) {
            return response()->json(['success' => false, 'message' => 'Invalid block'], 400);
        }

        $schools = School::where('block_id', $blockId)
            ->where('is_active', 1)
            ->orderBy('school_name')
            ->get(['id', 'school_name', 'udise_code']);

        return response()->json(['success' => true, 'data' => $schools]);
    }

    public function subjects(Request $request): JsonResponse
    {
        $gradeId = $request->integer('grade_id');
        if (! $gradeId) {
            return response()->json(['success' => false, 'message' => 'Invalid grade'], 400);
        }

        $grade = Grade::where('id', $gradeId)->where('is_active', 1)->first();
        if (! $grade) {
            return response()->json(['success' => false, 'message' => 'Grade not found'], 404);
        }

        if ($grade->is_school_leader) {
            return response()->json(['success' => true, 'is_school_leader' => true, 'data' => []]);
        }

        $subjects = $grade->subjects()
            ->where('subjects.is_active', 1)
            ->orderBy('subjects.sort_order')->orderBy('subjects.name')
            ->get(['subjects.id', 'subjects.name']);

        return response()->json(['success' => true, 'is_school_leader' => false, 'data' => $subjects]);
    }

    public function project(Request $request): JsonResponse
    {
        $gradeId = $request->integer('grade_id');
        $cycleId = $request->integer('cycle_id');
        $subjectId = $request->filled('subject_id') ? $request->integer('subject_id') : null;

        if (! $gradeId || ! $cycleId) {
            return response()->json(['success' => false, 'message' => 'Grade and Cycle are required'], 400);
        }

        $query = Project::query()
            ->where('grade_id', $gradeId)
            ->where('cycle_id', $cycleId)
            ->where('is_active', 1);

        $query = $subjectId === null
            ? $query->whereNull('subject_id')
            : $query->where('subject_id', $subjectId);

        $project = $query->first();

        if (! $project) {
            return response()->json([
                'success' => false,
                'message' => 'No project found for the selected Grade / Subject / Cycle combination.',
            ]);
        }

        $tasks = ProjectTask::where('project_id', $project->id)
            ->where('is_active', 1)
            ->orderBy('sort_order')->orderBy('task_number')
            ->get(['id', 'task_number', 'task_type', 'task_description']);

        return response()->json([
            'success' => true,
            'project' => [
                'id' => $project->id,
                'title' => $project->project_title,
                'duration' => $project->duration ?: '—',
                'objective' => $project->objective ?? '',
                'file' => $project->project_file,
                'has_download' => ! empty($project->project_file),
            ],
            'tasks' => $tasks,
        ]);
    }
}
