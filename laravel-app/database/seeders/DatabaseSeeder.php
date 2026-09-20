<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $this->call([
            ReferenceDataSeeder::class,
            Cycle2DataSeeder::class,
            SchoolMasterDataSeeder::class,
            AdminUserSeeder::class,
        ]);
    }
}
