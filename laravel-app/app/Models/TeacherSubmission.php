<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class TeacherSubmission extends Model
{
    protected $table = 'teacher_submissions';

    // No created_at/updated_at columns - the table has its own
    // `submitted_at` (DB-defaulted to CURRENT_TIMESTAMP on insert).
    public $timestamps = false;

    protected $fillable = [
        'submission_id', 'teacher_name', 'designation',
        'district_id', 'block_id', 'school_id',
        'grade_id', 'subject_id', 'cycle_id', 'project_id',
        'video_link', 'ip_address',
    ];

    public function district(): BelongsTo
    {
        return $this->belongsTo(District::class);
    }

    public function block(): BelongsTo
    {
        return $this->belongsTo(Block::class);
    }

    public function school(): BelongsTo
    {
        return $this->belongsTo(School::class);
    }

    public function grade(): BelongsTo
    {
        return $this->belongsTo(Grade::class);
    }

    public function subject(): BelongsTo
    {
        return $this->belongsTo(Subject::class);
    }

    public function cycle(): BelongsTo
    {
        return $this->belongsTo(Cycle::class);
    }

    public function project(): BelongsTo
    {
        return $this->belongsTo(Project::class);
    }

    public function taskResponses(): HasMany
    {
        return $this->hasMany(TaskResponse::class, 'submission_id');
    }

    public function evidence(): HasMany
    {
        return $this->hasMany(SubmissionEvidence::class, 'submission_id');
    }
}
