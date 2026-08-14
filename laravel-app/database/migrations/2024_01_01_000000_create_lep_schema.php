<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Single consolidated migration for the whole LEP schema - Laravel's own
 * auth/session/queue tables plus all 12 LEP domain tables (matching
 * database/LEP_V2_Production.sql exactly, in dependency order).
 *
 * Every table is wrapped in a Schema::hasTable() check, so this ONE file is
 * safe to run with a plain `php artisan migrate` in BOTH scenarios:
 *   - Fresh/empty database: every table gets created.
 *   - Existing production database: the 12 LEP domain tables already exist
 *     and are skipped untouched; only the new users/sessions/cache/jobs
 *     tables (needed for Laravel auth) get created.
 *
 * down() DOES drop everything unconditionally, including the 12 domain
 * tables - never run `php artisan migrate:rollback` or `migrate:fresh`
 * against a database with real LEP data in it.
 */
return new class extends Migration
{
    public function up(): void
    {
        // ── Laravel auth / session / cache / queue tables (new - the legacy
        //    PHP app had none of these) ──
        if (! Schema::hasTable('users')) {
            Schema::create('users', function (Blueprint $table) {
                $table->id();
                $table->string('name');
                $table->string('email')->unique();
                $table->timestamp('email_verified_at')->nullable();
                $table->string('password');
                $table->rememberToken();
                $table->timestamps();
            });
        }

        if (! Schema::hasTable('password_reset_tokens')) {
            Schema::create('password_reset_tokens', function (Blueprint $table) {
                $table->string('email')->primary();
                $table->string('token');
                $table->timestamp('created_at')->nullable();
            });
        }

        if (! Schema::hasTable('sessions')) {
            Schema::create('sessions', function (Blueprint $table) {
                $table->string('id')->primary();
                $table->foreignId('user_id')->nullable()->index();
                $table->string('ip_address', 45)->nullable();
                $table->text('user_agent')->nullable();
                $table->longText('payload');
                $table->integer('last_activity')->index();
            });
        }

        if (! Schema::hasTable('cache')) {
            Schema::create('cache', function (Blueprint $table) {
                $table->string('key')->primary();
                $table->mediumText('value');
                $table->integer('expiration');
            });
        }

        if (! Schema::hasTable('cache_locks')) {
            Schema::create('cache_locks', function (Blueprint $table) {
                $table->string('key')->primary();
                $table->string('owner');
                $table->integer('expiration');
            });
        }

        if (! Schema::hasTable('jobs')) {
            Schema::create('jobs', function (Blueprint $table) {
                $table->id();
                $table->string('queue')->index();
                $table->longText('payload');
                $table->unsignedTinyInteger('attempts');
                $table->unsignedInteger('reserved_at')->nullable();
                $table->unsignedInteger('available_at');
                $table->unsignedInteger('created_at');
            });
        }

        if (! Schema::hasTable('job_batches')) {
            Schema::create('job_batches', function (Blueprint $table) {
                $table->string('id')->primary();
                $table->string('name');
                $table->integer('total_jobs');
                $table->integer('pending_jobs');
                $table->integer('failed_jobs');
                $table->longText('failed_job_ids');
                $table->mediumText('options')->nullable();
                $table->integer('cancelled_at')->nullable();
                $table->integer('created_at');
                $table->integer('finished_at')->nullable();
            });
        }

        if (! Schema::hasTable('failed_jobs')) {
            Schema::create('failed_jobs', function (Blueprint $table) {
                $table->id();
                $table->string('uuid')->unique();
                $table->text('connection');
                $table->text('queue');
                $table->longText('payload');
                $table->longText('exception');
                $table->timestamp('failed_at')->useCurrent();
            });
        }

        // ── LEP domain tables (matches database/LEP_V2_Production.sql) -
        //    already exist in production, so these all no-op there. ──
        if (! Schema::hasTable('districts')) {
            Schema::create('districts', function (Blueprint $table) {
                $table->increments('id');
                $table->string('name', 100);
                $table->boolean('is_active')->default(true);
                $table->timestamp('created_at')->useCurrent();

                $table->unique('name', 'uq_district_name');
            });
        }

        if (! Schema::hasTable('blocks')) {
            Schema::create('blocks', function (Blueprint $table) {
                $table->increments('id');
                $table->unsignedInteger('district_id');
                $table->string('name', 100);
                $table->boolean('is_active')->default(true);
                $table->timestamp('created_at')->useCurrent();

                $table->foreign('district_id')->references('id')->on('districts')
                    ->restrictOnDelete()->cascadeOnUpdate();
                $table->unique(['district_id', 'name'], 'uq_block_district');
                $table->index('district_id', 'idx_blocks_district');
            });
        }

        if (! Schema::hasTable('schools')) {
            Schema::create('schools', function (Blueprint $table) {
                $table->increments('id');
                $table->unsignedInteger('block_id');
                $table->string('school_name', 255);
                $table->string('udise_code', 20);
                $table->boolean('is_active')->default(true);
                $table->timestamp('created_at')->useCurrent();

                $table->foreign('block_id')->references('id')->on('blocks')
                    ->restrictOnDelete()->cascadeOnUpdate();
                $table->unique('udise_code', 'uq_udise');
                $table->index('block_id', 'idx_schools_block');
            });
        }

        if (! Schema::hasTable('grades')) {
            Schema::create('grades', function (Blueprint $table) {
                $table->increments('id');
                $table->string('name', 100);
                $table->boolean('is_school_leader')->default(false)
                    ->comment('1 = School Leaders (no subject required)');
                $table->smallInteger('sort_order')->default(0);
                $table->boolean('is_active')->default(true);
                $table->timestamp('created_at')->useCurrent();

                $table->unique('name', 'uq_grade_name');
            });
        }

        if (! Schema::hasTable('subjects')) {
            Schema::create('subjects', function (Blueprint $table) {
                $table->increments('id');
                $table->string('name', 100);
                $table->smallInteger('sort_order')->default(0);
                $table->boolean('is_active')->default(true);
                $table->timestamp('created_at')->useCurrent();

                $table->unique('name', 'uq_subject_name');
            });
        }

        if (! Schema::hasTable('grade_subject_map')) {
            Schema::create('grade_subject_map', function (Blueprint $table) {
                $table->increments('id');
                $table->unsignedInteger('grade_id');
                $table->unsignedInteger('subject_id');
                $table->timestamp('created_at')->useCurrent();

                $table->foreign('grade_id')->references('id')->on('grades')
                    ->cascadeOnDelete()->cascadeOnUpdate();
                $table->foreign('subject_id')->references('id')->on('subjects')
                    ->cascadeOnDelete()->cascadeOnUpdate();
                $table->unique(['grade_id', 'subject_id'], 'uq_grade_subject');
            });
        }

        if (! Schema::hasTable('cycles')) {
            Schema::create('cycles', function (Blueprint $table) {
                $table->increments('id');
                $table->string('name', 50);
                $table->smallInteger('sort_order')->default(0);
                $table->boolean('is_active')->default(true);
                $table->timestamp('created_at')->useCurrent();

                $table->unique('name', 'uq_cycle_name');
            });
        }

        if (! Schema::hasTable('projects')) {
            Schema::create('projects', function (Blueprint $table) {
                $table->increments('id');
                $table->unsignedInteger('grade_id');
                $table->unsignedInteger('subject_id')->nullable()
                    ->comment('NULL when grade is School Leaders');
                $table->unsignedInteger('cycle_id');
                $table->string('project_title', 255);
                $table->string('duration', 50)->nullable()->comment('e.g. 1 Month');
                $table->text('objective')->nullable();
                $table->string('project_file', 255)->nullable()
                    ->comment('Object key under the minio disk, e.g. uploads/projects/xxx.pdf');
                $table->boolean('is_active')->default(true);
                $table->timestamp('created_at')->useCurrent();
                $table->timestamp('updated_at')->useCurrent()->useCurrentOnUpdate();

                $table->foreign('grade_id')->references('id')->on('grades')
                    ->restrictOnDelete()->cascadeOnUpdate();
                $table->foreign('subject_id')->references('id')->on('subjects')
                    ->restrictOnDelete()->cascadeOnUpdate();
                $table->foreign('cycle_id')->references('id')->on('cycles')
                    ->restrictOnDelete()->cascadeOnUpdate();
                $table->unique(['grade_id', 'subject_id', 'cycle_id'], 'uq_project');
                $table->index(['grade_id', 'subject_id', 'cycle_id'], 'idx_projects_lookup');
            });
        }

        if (! Schema::hasTable('project_tasks')) {
            Schema::create('project_tasks', function (Blueprint $table) {
                $table->increments('id');
                $table->unsignedInteger('project_id');
                $table->unsignedSmallInteger('task_number');
                $table->string('task_type', 20)->default('Task')->comment('Task or Showcase');
                $table->text('task_description');
                $table->smallInteger('sort_order')->default(0);
                $table->boolean('is_active')->default(true);
                $table->timestamp('created_at')->useCurrent();

                $table->foreign('project_id')->references('id')->on('projects')
                    ->cascadeOnDelete()->cascadeOnUpdate();
                $table->unique(['project_id', 'task_number'], 'uq_project_task');
                $table->index('project_id', 'idx_tasks_project');
            });
        }

        if (! Schema::hasTable('teacher_submissions')) {
            Schema::create('teacher_submissions', function (Blueprint $table) {
                $table->increments('id');
                $table->string('submission_id', 20)->comment('e.g. LEP-2026-000001');
                $table->string('teacher_name', 150);
                $table->string('designation', 100);
                $table->unsignedInteger('district_id');
                $table->unsignedInteger('block_id');
                $table->unsignedInteger('school_id');
                $table->unsignedInteger('grade_id');
                $table->unsignedInteger('subject_id')->nullable();
                $table->unsignedInteger('cycle_id');
                $table->unsignedInteger('project_id');
                $table->string('video_link', 500)->nullable()
                    ->comment('Optional project video link (v1.1)');
                $table->dateTime('submitted_at')->useCurrent();
                $table->string('ip_address', 45)->nullable();

                $table->foreign('district_id')->references('id')->on('districts')->restrictOnDelete();
                $table->foreign('block_id')->references('id')->on('blocks')->restrictOnDelete();
                $table->foreign('school_id')->references('id')->on('schools')->restrictOnDelete();
                $table->foreign('grade_id')->references('id')->on('grades')->restrictOnDelete();
                $table->foreign('subject_id')->references('id')->on('subjects')->restrictOnDelete();
                $table->foreign('cycle_id')->references('id')->on('cycles')->restrictOnDelete();
                $table->foreign('project_id')->references('id')->on('projects')->restrictOnDelete();
                $table->unique('submission_id', 'uq_submission_id');
                $table->index('submitted_at', 'idx_submissions_date');
                $table->index('school_id', 'idx_submissions_school');
            });
        }

        if (! Schema::hasTable('task_responses')) {
            Schema::create('task_responses', function (Blueprint $table) {
                $table->increments('id');
                $table->unsignedInteger('submission_id')->comment('FK to teacher_submissions.id');
                $table->unsignedInteger('task_id');
                $table->enum('completed', ['Yes', 'No']);
                $table->timestamp('created_at')->useCurrent();

                $table->foreign('submission_id')->references('id')->on('teacher_submissions')
                    ->cascadeOnDelete()->cascadeOnUpdate();
                $table->foreign('task_id')->references('id')->on('project_tasks')
                    ->restrictOnDelete()->cascadeOnUpdate();
                $table->unique(['submission_id', 'task_id'], 'uq_submission_task');
                $table->index('submission_id', 'idx_responses_submission');
            });
        }

        if (! Schema::hasTable('submission_evidence')) {
            Schema::create('submission_evidence', function (Blueprint $table) {
                $table->increments('id');
                $table->unsignedInteger('submission_id')->comment('FK to teacher_submissions.id');
                $table->string('file_path', 255)
                    ->comment('Object key under the minio disk, e.g. uploads/evidence/LEP-2026-000001/xxx.pdf');
                $table->string('original_name', 255)->nullable();
                $table->timestamp('created_at')->useCurrent();

                $table->foreign('submission_id')->references('id')->on('teacher_submissions')
                    ->cascadeOnDelete()->cascadeOnUpdate();
                $table->index('submission_id', 'idx_evidence_submission');
            });
        }
    }

    public function down(): void
    {
        // Reverse dependency order. Unconditional - see class docblock.
        Schema::dropIfExists('submission_evidence');
        Schema::dropIfExists('task_responses');
        Schema::dropIfExists('teacher_submissions');
        Schema::dropIfExists('project_tasks');
        Schema::dropIfExists('projects');
        Schema::dropIfExists('cycles');
        Schema::dropIfExists('grade_subject_map');
        Schema::dropIfExists('subjects');
        Schema::dropIfExists('grades');
        Schema::dropIfExists('schools');
        Schema::dropIfExists('blocks');
        Schema::dropIfExists('districts');

        Schema::dropIfExists('failed_jobs');
        Schema::dropIfExists('job_batches');
        Schema::dropIfExists('jobs');
        Schema::dropIfExists('cache_locks');
        Schema::dropIfExists('cache');
        Schema::dropIfExists('sessions');
        Schema::dropIfExists('password_reset_tokens');
        Schema::dropIfExists('users');
    }
};
