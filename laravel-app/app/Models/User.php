<?php

namespace App\Models;

// Note: this `users` table is new (added for Laravel admin auth) - it does
// not exist in the legacy PHP app's schema. It only ever holds the small
// number of admin accounts that can reach /admin/*; teachers never have
// an account.

use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;

class User extends Authenticatable
{
    use Notifiable;

    protected $fillable = [
        'name',
        'email',
        'password',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
        ];
    }
}
