# LEP — Laravel Edition

Laravel port of the legacy PHP `LEP_V2` app (Government of Nagaland / Samagra
Shiksha — Learning Enhancement Program). Same teacher-facing behavior as the
original; the reason for this rewrite is to close a real security gap using
Laravel's built-in primitives instead of hand-rolled code:

- **`master_import.php` and `export_submissions.php` had no authentication at
  all** in the legacy app — anyone who knew the URL could export every
  teacher's data/evidence files, or wipe school master data. Here, both live
  under `/admin/*` behind a real session login (`app/Http/Controllers/Auth/LoginController.php`).
- CSRF protection (`@csrf`) is now on the public submission form — it had
  none before.
- DB/MinIO credentials live in `.env`, not hardcoded in a committed PHP file.
- The public submission endpoint is rate-limited (`throttle:10,1` in
  `routes/web.php`).
- Evidence files and project PDFs are stored in **MinIO** (S3-compatible
  object storage) instead of a web-servable `uploads/` folder — there is no
  longer any user-uploaded content living under the document root at all.

This machine had no PHP/Composer/MySQL available while writing this app, so
everything here is hand-authored source — nothing has been run yet. Follow
the steps below on a machine/server that has PHP 8.2+.

## Requirements

- PHP 8.2+
- Extensions: `pdo_mysql`, `mbstring`, `fileinfo`, `zip`, and either `gd` or
  `imagick` (for Intervention Image evidence-photo compression)
- Composer 2
- MySQL 8.0+/MariaDB 10.6+ — **the existing `lep_nagaland` database**
- A MinIO server (or any S3-compatible endpoint) reachable from the app

## Setup

```bash
cd laravel-app
composer install
cp .env.example .env
php artisan key:generate
```

Edit `.env`:

- `DB_*` — point at the **existing** `lep_nagaland` database (same
  credentials the legacy `config/config.php` used).
- `MINIO_*` — your MinIO endpoint/key/secret/bucket. Create the bucket first
  (e.g. `mc mb myminio/lep`); the app never creates it automatically.
- `LEP_ADMIN_EMAIL` / `LEP_ADMIN_PASSWORD` / `LEP_ADMIN_NAME` — the one admin
  account that can reach `/admin/*`. Use a strong, unique password — this
  account can export every teacher's data.
- `SESSION_SECURE_COOKIE` — leave `true` for HTTPS production. Set to
  `false` only if you're smoke-testing over plain HTTP on a private network.

### Database migration — one file, safe either way

`database/migrations/2024_01_01_000000_create_lep_schema.php` is a single
consolidated migration for the whole schema — Laravel's own auth/session/
queue tables plus all 12 LEP domain tables (matching
`database/LEP_V2_Production.sql`). Every table is wrapped in a
`Schema::hasTable()` check, so a plain:

```bash
php artisan migrate
```

is safe in both cases:

- **Fresh/empty database:** every table gets created.
- **Existing production database:** the 12 LEP domain tables already exist
  and are skipped untouched; only the new `users`/`sessions`/`cache`/`jobs`
  tables get created.

Never run `php artisan migrate:rollback` or `migrate:fresh` against a
database with real LEP data — `down()` drops all 20 tables unconditionally.

### Seeding data

Three seeders, run individually or together via `php artisan db:seed`
(calls all three in order — see `database/seeders/DatabaseSeeder.php`):

- **`ReferenceDataSeeder`** — cycles, grades, subjects, grade_subject_map,
  projects, project_tasks (27 projects / 165 tasks). This is the Cycle 1
  program content that used to be baked into `LEP_V2_Production.sql` as
  inline `INSERT` statements rather than a separate import feature — without
  it, a fresh database has no projects/tasks to select. Idempotent (reuses
  the original SQL's `INSERT ... WHERE NOT EXISTS` guards), safe to re-run.
- **`SchoolMasterDataSeeder`** — districts/blocks/schools from
  `storage/app/master-import/Master_Schools-2026.csv` (already staged there
  in this repo — the equivalent of the legacy app's pre-placed
  `data/Master_Schools-2026.csv` next to `master_import.php`). Idempotent —
  duplicate UDISE codes are skipped. You can also always upload the file
  directly from `/admin/master-import` instead.
- **`AdminUserSeeder`** — the one admin account, from `.env`.

```bash
php artisan db:seed --class=ReferenceDataSeeder
php artisan db:seed --class=SchoolMasterDataSeeder
php artisan db:seed --class=AdminUserSeeder
```

### Web server

Document root must point at `laravel-app/public` (not the app root — this is
the one Laravel-specific deployment change). `storage/` and
`bootstrap/cache/` must be writable by the web server user:

```bash
chown -R www-data:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache
```

Nginx/Apache should proxy everything to `public/index.php` (standard Laravel
`public/.htaccess` is included for Apache; for Nginx use Laravel's standard
`try_files $uri $uri/ /index.php?$query_string;` block).

## Verification checklist (run before cutting over from the PHP app)

Point `.env` at a **copy** of the production database first, not production
directly:

1. `/` loads — districts/grades/cycles render; District→Block→School cascade
   works and auto-fills UDISE.
2. Grade→Subject cascade (including School Leaders hiding the Subject
   select) and Grade→Subject→Cycle→Project/task loading match the old JSON
   shapes.
3. Submit with 0 evidence files → rejected with the same message; 1–5 files
   under/over 5 MB → same pass/fail behavior; confirm objects land in MinIO
   under `uploads/evidence/{submission_id}/...` and jpg/png files are visibly
   smaller than the original (compression working).
4. Certificate of Submission renders with the correct joined data.
5. Download a project PDF from MinIO; confirm a tampered/invalid project id
   still 404s.
6. Visiting `/admin/export` or `/admin/master-import` while logged out
   redirects to `/admin/login` (previously: wide open). Log in as the seeded
   admin and confirm CSV export, evidence ZIP export, and master import
   (including the "blocked if submissions exist" clear-first rule) all
   reproduce the old output.
7. Confirm `.env` isn't committed, `APP_DEBUG=false`, and login attempts are
   throttled (6th rapid attempt gets a 429).

Only after this passes should you point the real `.env` at production and
swap the web server document root — keep the legacy PHP app in place
(different port/path) as a rollback option until you're confident.
