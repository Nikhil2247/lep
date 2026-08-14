<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SubmissionEvidence extends Model
{
    protected $table = 'submission_evidence';

    const UPDATED_AT = null;

    protected $fillable = ['submission_id', 'file_path', 'original_name'];

    public function submission(): BelongsTo
    {
        return $this->belongsTo(TeacherSubmission::class, 'submission_id');
    }
}
