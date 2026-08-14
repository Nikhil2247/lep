<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Block extends Model
{
    protected $table = 'blocks';

    const UPDATED_AT = null;

    protected $fillable = ['district_id', 'name', 'is_active'];

    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    public function district(): BelongsTo
    {
        return $this->belongsTo(District::class);
    }

    public function schools(): HasMany
    {
        return $this->hasMany(School::class);
    }
}
