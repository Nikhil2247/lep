<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Grade extends Model
{
    protected $table = 'grades';

    const UPDATED_AT = null;

    protected $fillable = ['name', 'is_school_leader', 'sort_order', 'is_active'];

    protected function casts(): array
    {
        return [
            'is_school_leader' => 'boolean',
            'is_active' => 'boolean',
        ];
    }

    public function subjects(): BelongsToMany
    {
        return $this->belongsToMany(Subject::class, 'grade_subject_map');
    }

    public function projects(): HasMany
    {
        return $this->hasMany(Project::class);
    }
}
