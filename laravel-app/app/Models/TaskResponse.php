<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class TaskResponse extends Model
{
    protected $table = 'task_responses';

    const UPDATED_AT = null;

    protected $fillable = ['submission_id', 'task_id', 'completed'];

    public function submission(): BelongsTo
    {
        return $this->belongsTo(TeacherSubmission::class, 'submission_id');
    }

    public function task(): BelongsTo
    {
        return $this->belongsTo(ProjectTask::class, 'task_id');
    }
}
