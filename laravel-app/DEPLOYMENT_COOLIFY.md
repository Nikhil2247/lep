# LEP — Deploying to the India VPS via Coolify

Why this exists: the US-hosted VPS (see `DEPLOYMENT.md`) puts every project-PDF
download and evidence export on a slow international hop for users in India —
measured around 60–115 KB/s in testing, vs. 40+ MB/s when the app and MinIO
are on the same local network. Moving both the app and MinIO onto the India
VPS removes that hop entirely for local users. This doc covers deploying
there through Coolify (Docker-based, not the raw Apache/php-fpm setup in
`DEPLOYMENT.md`).

## 0. What's already in this repo for Coolify

- **`Dockerfile`** — single container, nginx + php-fpm under supervisord (no
  separate frontend build stage — there's no `package.json`/`@vite`, just
  Blade views).
- **`docker/php.ini`** — raises `upload_max_filesize`/`post_max_size` to fit
  `LEP_MAX_EVIDENCE_FILES=5` × 5MB each (the legacy server's defaults of 2M/8M
  were actually too small for that — worth fixing here regardless of the VPS
  move).
- **`docker/nginx.conf`**, **`docker/supervisord.conf`**, **`docker/entrypoint.sh`**
  — web server, process manager, and the boot step that runs
  `config:cache`/`route:cache`/`view:cache` *at container start* (not at build
  time — Coolify injects env vars into the running container, not a `.env`
  file, so caching config at build time would bake in empty values).

Because the repo root has `laravel-app/` as a subfolder alongside `.git` (same
as the Apache deployment), Coolify's **Base Directory** must be set to
`/laravel-app` — see step 2.

## 1. Prerequisites on the India VPS

- Coolify already installed (per your setup) with a server added and reachable.
- A domain/subdomain you control for the app (e.g. reuse
  `nagaland.lep.2026.vibha.org` once you cut over, or use a staging subdomain
  first) and a **separate** subdomain for MinIO (e.g. `files-in.lep2026.vibha.org`)
  — MinIO needs its own public hostname, see step 4.
- `mc` (MinIO client) installed somewhere that can reach **both** the old and
  new MinIO endpoints, for the data migration in step 5. Install:
  ```bash
  curl https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
  chmod +x /usr/local/bin/mc
  ```

## 2. Create the application in Coolify

1. **Projects → New Resource → Public/Private Repository**, point at
   `https://github.com/Nikhil2247/lep.git`, branch `main`.
2. **Build Pack: Dockerfile**.
3. **Base Directory: `/laravel-app`** (the Dockerfile and everything it
   `COPY`s are relative to this).
4. **Dockerfile Location: `Dockerfile`** (default, relative to the base
   directory above).
5. **Ports Exposes: `80`**.
6. **Health Check Path: `/up`** (Laravel's built-in health route, already
   wired in `bootstrap/app.php`).
7. Don't deploy yet — set environment variables first (step 3).

## 3. Environment variables

Add these under the app's **Environment Variables** tab in Coolify (values
from `.env.example`, filled in for real). Do **not** commit a `.env` file —
Coolify's env vars are how config reaches the container.

| Key | Value / note |
|---|---|
| `APP_NAME` | `Learning Enhancement Program (LEP)` |
| `APP_ENV` | `production` |
| `APP_KEY` | Generate **once**, locally: `php artisan key:generate --show`. Paste the output — don't regenerate this on every deploy, it'll invalidate existing sessions/encrypted data. |
| `APP_DEBUG` | `false` |
| `APP_TIMEZONE` | `Asia/Kolkata` |
| `APP_URL` | `https://nagaland.lep.2026.vibha.org` (or your staging subdomain first) |
| `LOG_CHANNEL` / `LOG_LEVEL` | `stack` / `error` |
| `DB_CONNECTION` | `mysql` |
| `DB_HOST` / `DB_PORT` | Internal Coolify hostname/port of the database resource from step 4 (Coolify shows this on the database's resource page) |
| `DB_DATABASE` | `lep_nagaland` |
| `DB_USERNAME` / `DB_PASSWORD` | From the database resource |
| `SESSION_DRIVER` / `CACHE_STORE` / `QUEUE_CONNECTION` | `database` / `database` / `database` (all DB-backed on purpose — the container is stateless, no local files to lose on redeploy) |
| `SESSION_SECURE_COOKIE` | `true` |
| `FILESYSTEM_DISK` | `minio` |
| `MINIO_KEY` / `MINIO_SECRET` | A **scoped** access key for the `lep` bucket only — see step 5's security note, don't reuse the `minioadmin` root credentials |
| `MINIO_REGION` | `us-east-1` (MinIO ignores this but the S3 client requires a value) |
| `MINIO_BUCKET` | `lep` |
| `MINIO_ENDPOINT` | **The public MinIO domain**, e.g. `https://files-in.lep2026.vibha.org` — must be the same URL a browser can reach, because project downloads and evidence-ZIP exports redirect the browser here directly (see `app/Http/Controllers/Admin/ExportController.php` / note in `config/filesystems.php`). Pointing this at an internal-only Coolify service hostname will silently break both features. |
| `MINIO_USE_PATH_STYLE_ENDPOINT` | `true` |
| `LEP_MAX_EVIDENCE_TOTAL_SIZE` | `5242880` |
| `LEP_MAX_EVIDENCE_FILES` | `5` |
| `LEP_SUBMISSION_PREFIX_BASE` | `LEP` |
| `LEP_ADMIN_NAME` / `LEP_ADMIN_EMAIL` / `LEP_ADMIN_PASSWORD` | The one admin account — use a strong, unique password |

## 4. Database — add a Coolify MySQL/MariaDB resource

1. **Projects → New Resource → Databases → MySQL** (or MariaDB) in the same
   Coolify project.
2. Once it's running, copy its internal host/port/credentials into the app's
   `DB_*` env vars from step 3.
3. This starts as an **empty** database — data comes from the migration in
   step 5, not from `php artisan migrate` alone (that only creates the schema).

## 5. MinIO — deploy it, expose it publicly, migrate the data

### 5a. Deploy MinIO on Coolify

1. **Projects → New Resource → Services → MinIO** (Coolify's one-click
   service template) in the same project.
2. Give it a **public domain** in Coolify's domain settings for the app —
   e.g. `files-in.lep2026.vibha.org` — with SSL enabled (Coolify issues a
   Let's Encrypt cert automatically once DNS points at this VPS). This is the
   value you put in `MINIO_ENDPOINT` above. Do not rely on the internal
   service hostname; browsers can't reach that.
3. Log into the MinIO console (also exposed by Coolify) with the
   auto-generated root credentials, create the bucket:
   ```bash
   mc alias set newminio https://files-in.lep2026.vibha.org <root-key> <root-secret>
   mc mb newminio/lep
   ```
4. **Create a scoped access key instead of using the root credentials in the
   app** (the old deployment's presigned URLs used `minioadmin` — the root
   account — which is more access than the app needs):
   ```bash
   mc admin user add newminio lep-app <new-secret>
   mc admin policy create newminio lep-app-policy - <<'EOF'
   {
     "Version": "2012-10-17",
     "Statement": [
       {"Effect": "Allow", "Action": ["s3:*"], "Resource": ["arn:aws:s3:::lep/*", "arn:aws:s3:::lep"]}
     ]
   }
   EOF
   mc admin policy attach newminio lep-app-policy --user lep-app
   ```
   Use `lep-app` / `<new-secret>` as `MINIO_KEY` / `MINIO_SECRET` in step 3.
5. Add the lifecycle rule for temporary export ZIPs (same reasoning as the US
   deployment — `ExportController::streamEvidenceZip()` uploads a fresh ZIP
   under `exports/evidence/` on every admin export and lets it expire rather
   than caching it):
   ```bash
   mc ilm add --expire-days 1 --prefix "exports/evidence/" newminio/lep
   ```

### 5b. Migrate existing data from the US VPS

Run from a machine that can reach both endpoints (the India VPS itself is
fine if outbound to the US VPS is allowed):

```bash
mc alias set oldminio http://<old-vps-ip>:9000 <old-key> <old-secret>
mc mirror oldminio/lep newminio/lep
```

For the database, on the **old** US VPS:

```bash
mysqldump -u lep_user -p lep_nagaland > lep_nagaland.sql
scp lep_nagaland.sql user@<india-vps-ip>:/tmp/
```

Then on the India VPS, into the Coolify-managed database from step 4 (use
the connection details from that resource's page):

```bash
mysql -h <db-host> -P <db-port> -u <db-user> -p lep_nagaland < /tmp/lep_nagaland.sql
```

This restores the real schema and data, so `php artisan migrate` in step 6
will find the 12 LEP domain tables already present and skip them (see
`database/migrations/2024_01_01_000000_create_lep_schema.php` — every table
is wrapped in `Schema::hasTable()`), only creating the new
`users`/`sessions`/`cache`/`jobs` tables.

## 6. Deploy, migrate, seed

1. In Coolify, click **Deploy** on the app resource. Watch the build log —
   this runs `composer install` inside the Dockerfile build.
2. Run the one-off setup commands via Coolify's **Terminal** for the app
   (or its "Execute Command" feature if your Coolify version has one) —
   these must run once per environment, not on every container boot, so they
   are **not** in `entrypoint.sh`:
   ```bash
   php artisan migrate --force
   php artisan db:seed --class=AdminUserSeeder
   ```
   Skip `ReferenceDataSeeder` / `SchoolMasterDataSeeder` if step 5b's
   `mysqldump` restore already brought that data over (it did, if the dump
   included the full `lep_nagaland` database).
3. **Never run `php artisan migrate:rollback` or `migrate:fresh`** against
   this database — `down()` in the migration drops all 20 tables
   unconditionally, same warning as `DEPLOYMENT.md`.

## 7. Domain + SSL + cutover

1. Add the real domain (`nagaland.lep.2026.vibha.org`) to the app resource in
   Coolify once you're ready to cut over; Coolify issues the Let's Encrypt
   cert automatically after DNS resolves to this VPS.
2. Update your DNS record for that domain to point at the India VPS.
3. Keep the old US VPS running and untouched for a rollback window — same
   approach as `DEPLOYMENT.md`'s rollback section. Nothing there needs to
   change until you're confident the new deployment is stable.

## 8. Verify before calling it done

Reuse the checklist in `README.md` ("Verification checklist"): form
submission end-to-end, evidence upload + compression landing in the new
MinIO bucket, project PDF download, admin login gating on `/admin/*`, CSV and
evidence-ZIP export. Additionally, since the whole point of this move is
speed:

```bash
curl -o /dev/null -w "speed: %{speed_download} bytes/s\n" \
  "https://nagaland.lep.2026.vibha.org/projects/25/download"
```
run from a machine actually in/near India — should be dramatically faster
than the ~113 KB/s measured against the US deployment.
