<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class School extends Model
{
    protected $table = 'schools';

    const UPDATED_AT = null;

    protected $fillable = ['block_id', 'school_name', 'udise_code', 'is_active'];

    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    public function block(): BelongsTo
    {
        return $this->belongsTo(Block::class);
    }
}
