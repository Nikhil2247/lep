<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use RuntimeException;

// Creates/updates the single admin account from .env (LEP_ADMIN_*).
// Run once via: php artisan db:seed --class=AdminUserSeeder
// Re-run any time to rotate the password after changing LEP_ADMIN_PASSWORD.
class AdminUserSeeder extends Seeder
{
    public function run(): void
    {
        $email = env('LEP_ADMIN_EMAIL');
        $password = env('LEP_ADMIN_PASSWORD');
        $name = env('LEP_ADMIN_NAME', 'LEP Administrator');

        if (! $email || ! $password) {
            throw new RuntimeException(
                'Set LEP_ADMIN_EMAIL and LEP_ADMIN_PASSWORD in .env before seeding the admin user.'
            );
        }

        User::updateOrCreate(
            ['email' => $email],
            ['name' => $name, 'password' => Hash::make($password)]
        );

        $this->command?->info("Admin user ready: {$email}");
    }
}
