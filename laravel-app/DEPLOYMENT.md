# LEP (Laravel) — Deployment Guide for AlmaLinux 8.10 (Apache httpd)

> Same server/stack as your existing `almalinux_deployment_guide.md` for the
> PHP app: AlmaLinux 8.10, Apache httpd (already running your Node.js +
> PostgreSQL project too), php-fpm, MariaDB, SELinux enforcing. This guide
> only covers the **delta** — what's new for the Laravel app — and reuses
> your existing PHP 8.2/php-fpm/MariaDB install rather than repeating it.

Your PHP app is already live at `nagaland.lep.2026.vibha.org`, served from
`/var/www/lep`. The Laravel app ends up at that **exact same path** — same
name, so the php-fpm pool/socket, SELinux contexts, and log paths you
already have configured for `/var/www/lep` all keep working with zero
changes. To get there without ever mixing the two codebases' files
together, this builds/verifies Laravel in a throwaway staging folder first,
then does a directory **swap** into `/var/www/lep` at cutover (old app
renamed aside, not deleted — instant rollback).

## 0. What's different from the PHP deployment

| Then (PHP) | Now (Laravel) |
|---|---|
| Document root = `/var/www/lep` | Document root = `/var/www/lep/public` (one path segment added) |
| DB credentials in `config/config.php` | DB credentials in `.env` |
| Evidence/project files on local disk under `uploads/` | Evidence/project files in **MinIO** (bucket `lep`) |
| `master_import.php` / `export_submissions.php` — no auth | Same features, behind `/admin/login` |
| No CSRF, no rate limiting | Both on by default |
| One schema SQL file with data baked in | One migration (schema) + two seeders (data) — §4 |

The MariaDB database itself is unchanged — same schema, same data, same
`lep_nagaland` database, same `lep_user` credentials your PHP app already
uses. This is an application-layer migration, not a data migration.

## 1. Already done — nothing to do here

Per your existing setup, these are already installed and running, so this
guide skips them entirely:

- PHP 8.2 + php-fpm (Remi repo) — Laravel needs the same extensions your PHP
  app already required (`pdo_mysql`, `mbstring`, `zip`, `fileinfo`) plus
  `gd` or `imagick` (Intervention Image — check with `php -m | grep -iE 'gd|imagick'`;
  install with `sudo dnf install -y php-gd` if missing, then `sudo systemctl restart php-fpm`)
- MariaDB, `lep_nagaland` database, `lep_user` — reused as-is
- Apache httpd, SELinux enforcing, firewalld with 80/443 open, certbot
- The `lep` php-fpm pool at `/run/php-fpm/lep.sock` — reused as-is, no new pool

New requirement: **Composer 2**.

```bash
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
php -r "unlink('composer-setup.php');"
composer --version
```

## 2. Deploy the application files — to a staging path first

```bash
sudo mkdir -p /var/www/lep-new
# from your Windows machine, same pattern as your existing SCP step:
# scp -r "D:\chrome download\LEP_V2\LEP_V2\laravel-app\*" your_user@your.server.ip:/tmp/lep_laravel_upload/

sudo cp -r /tmp/lep_laravel_upload/* /var/www/lep-new/
cd /var/www/lep-new
composer install --no-dev --optimize-autoloader
```

`/var/www/lep-new` is **temporary** — it only exists for the verification
window in §7–8 and gets renamed to `/var/www/lep` at cutover (§9). Nothing
below treats it as a permanent path.

## 3. Configure `.env`

```bash
cp .env.example .env
php artisan key:generate
```

Edit `.env`:

- `APP_URL=https://nagaland.lep.2026.vibha.org` — already set to the real
  production domain in `.env.example`; leave it as-is even while testing on
  the staging port (§7) — Laravel infers the actual root URL for
  `asset()`/`url()` from the incoming request itself during normal web
  requests, not from `APP_URL` (that config only matters for CLI/queue
  contexts with no request to infer from), so assets load correctly on
  `:8080` too without any extra config.
- `DB_HOST=localhost`, `DB_DATABASE=lep_nagaland`, `DB_USERNAME=lep_user`,
  `DB_PASSWORD=` — the **same** credentials your PHP app's `config/config.php`
  already uses.
- `MINIO_*` — endpoint/key/secret/bucket for the `lep` bucket you already set up.
- `LEP_ADMIN_EMAIL` / `LEP_ADMIN_PASSWORD` / `LEP_ADMIN_NAME` — the one admin
  account for `/admin/*`.
- `SESSION_SECURE_COOKIE` — set to `false` for now (§7's staging vhost is
  plain HTTP); flip to `true` at cutover (§9).

## 4. Database — one migration file, two seeders

Unlike the old `LEP_V2_Production.sql` (schema + data in one script, meant
for a fresh install only), this is split cleanly:

- **One migration** (`database/migrations/2024_01_01_000000_create_lep_schema.php`)
  creates every table — but each table is wrapped in a `Schema::hasTable()`
  check, so it's **safe to run as-is against your existing production
  database**: the 12 LEP tables that already exist are silently skipped, and
  only the new `users`/`sessions`/`cache`/`jobs` tables (needed for Laravel
  auth) get created.

  ```bash
  php artisan migrate
  ```

  Never run `php artisan migrate:rollback` or `migrate:fresh` against this
  database — `down()` unconditionally drops all 20 tables, including your
  live LEP data.

- **Two seeders** for the data that used to be baked into the SQL dump:

  ```bash
  # Cycle 1 program content: cycles, grades, subjects, grade_subject_map,
  # projects, project_tasks (27 projects / 165 tasks) - idempotent, safe to
  # re-run (it won't duplicate existing rows).
  php artisan db:seed --class=ReferenceDataSeeder

  # Districts/blocks/schools from Master_Schools-2026.csv (already staged
  # at storage/app/master-import/) - idempotent, duplicate UDISE codes are
  # skipped. Your production DB almost certainly already has this data
  # (imported once via master_import.php), so this seeder will mostly no-op -
  # run it anyway to be sure, or skip it if you're confident.
  php artisan db:seed --class=SchoolMasterDataSeeder

  # The one admin account:
  php artisan db:seed --class=AdminUserSeeder
  ```

  Or all three at once via `database/seeders/DatabaseSeeder.php`:

  ```bash
  php artisan db:seed
  ```

This step is safe to run now, against production, from `/var/www/lep-new` —
the DB connection doesn't care which directory the app files live in.

## 5. Move content into MinIO

Two sets of real files need to land in your `lep` bucket, keeping the
**exact same object-key shape as the existing DB values** (`projects.project_file`
and `submission_evidence.file_path` already store paths like
`uploads/projects/School Leader.pdf` — kept on purpose so no DB rows change).

**a) Project PDFs** (staged at `storage/app/minio-migration/uploads/projects/`
in this repo — 17 official Cycle 1 documents):

```bash
mc mirror storage/app/minio-migration/uploads/projects myminio/lep/uploads/projects
```

**b) Evidence files already submitted through the live PHP app** — these
live on the server under `/var/www/lep/uploads/evidence/` (the PHP app's
current, still-live path), not in this repo:

```bash
mc mirror /var/www/lep/uploads/evidence myminio/lep/uploads/evidence
```

If no submissions have come in yet, skip this. (This path stays valid right
up until the §9 swap, since `/var/www/lep` still holds the live PHP app
until then.)

## 6. Permissions & SELinux (staging path)

```bash
sudo chown -R apache:apache /var/www/lep-new
sudo find /var/www/lep-new -type d -exec chmod 755 {} \;
sudo find /var/www/lep-new -type f -exec chmod 644 {} \;

sudo chmod -R 775 /var/www/lep-new/storage /var/www/lep-new/bootstrap/cache
sudo chown -R apache:apache /var/www/lep-new/storage /var/www/lep-new/bootstrap/cache

# Temporary SELinux rule for the staging path only - see §9 for why the
# final /var/www/lep path needs no new rule at all.
sudo semanage fcontext -a -t httpd_sys_content_t "/var/www/lep-new(/.*)?"
sudo restorecon -Rv /var/www/lep-new
sudo semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/lep-new/storage(/.*)?"
sudo semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/lep-new/bootstrap/cache(/.*)?"
sudo restorecon -Rv /var/www/lep-new/storage /var/www/lep-new/bootstrap/cache

# Already enabled for the PHP app, but confirm:
sudo setsebool -P httpd_can_network_connect_db 1
```

If MinIO is reached over the network (not `localhost`), also:

```bash
sudo setsebool -P httpd_can_network_connect 1
```

## 7. Apache VirtualHost — staging only

Your live vhosts (`:80` and `:443`, both `ServerName nagaland.lep.2026.vibha.org`,
`DocumentRoot /var/www/lep`) are untouched in this step. Staging uses the
**same hostname on port 8080** instead — no DNS or extra cert needed, and
nothing here conflicts with the live site:

```bash
sudo nano /etc/httpd/conf.d/lep-staging.conf
```

```apache
<VirtualHost *:8080>
    ServerName nagaland.lep.2026.vibha.org
    DocumentRoot /var/www/lep-new/public

    <Directory /var/www/lep-new/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted

        <FilesMatch \.php$>
            SetHandler "proxy:unix:/run/php-fpm/lep.sock|fcgi://localhost"
        </FilesMatch>
    </Directory>

    ErrorLog  /var/log/httpd/lep-staging_error.log
    CustomLog /var/log/httpd/lep-staging_access.log combined
</VirtualHost>
```

```bash
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
sudo apachectl configtest
sudo systemctl reload httpd
```

This staging vhost, `lep-staging.conf`, and the `8080` firewall rule are all
deleted in §9 — none of it persists past cutover.

## 8. Verify before cutover

Against `http://nagaland.lep.2026.vibha.org:8080/`, work through
`README.md`'s verification checklist — form submission, cascading
dropdowns, evidence upload + compression, project download, certificate
rendering — and confirm `/admin/export` and `/admin/master-import` now
require login (they didn't before). Also check:

```bash
sudo tail -f /var/log/httpd/lep-staging_error.log
sudo tail -f /var/www/lep-new/storage/logs/laravel.log
```

## 9. Cutover — swap the directory, edit two lines

Once verified, this is the entire cutover:

```bash
# 1. Tear down staging
sudo rm /etc/httpd/conf.d/lep-staging.conf
sudo firewall-cmd --permanent --remove-port=8080/tcp
sudo firewall-cmd --reload

# 2. Swap directories (old app renamed aside, not deleted - instant rollback)
sudo mv /var/www/lep /var/www/lep-legacy-backup
sudo mv /var/www/lep-new /var/www/lep

# 3. Re-apply the SAME SELinux path rule your PHP app already had -
#    no new semanage rule needed, the pattern "/var/www/lep(/.*)?" is
#    unchanged, restorecon just needs to relabel the new contents.
sudo restorecon -Rv /var/www/lep
sudo semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/lep/storage(/.*)?"
sudo semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/lep/bootstrap/cache(/.*)?"
sudo restorecon -Rv /var/www/lep/storage /var/www/lep/bootstrap/cache
```

Then edit `.env` (now at `/var/www/lep/.env`): set `SESSION_SECURE_COOKIE=true`.

Last step — the **only** vhost edit, in `/etc/httpd/conf.d/lep-vhost.conf`
(your existing `:80` config). Certbot typically writes the matching `:443`
vhost to a sibling file named `lep-vhost-le-ssl.conf` in the same
`conf.d/` directory — check for it and apply the identical change there too:

```diff
-    DocumentRoot /var/www/lep
+    DocumentRoot /var/www/lep/public

-    <Directory /var/www/lep>
+    <Directory /var/www/lep/public>
```

And remove the now-unused `<Directory /var/www/lep/uploads>` block — MinIO
means Laravel never writes user-uploaded files under the document root, so
there's nothing there left to block execution on.

```bash
sudo apachectl configtest
sudo systemctl reload httpd
```

That's it — same directory name, same php-fpm socket, same SELinux base
rule, same log filenames, only `DocumentRoot`/`<Directory>` gained
`/public` and the `uploads/` block was removed.

Watch `/var/www/lep/storage/logs/laravel.log` for the first real traffic.
After a few days of clean operation, `/var/www/lep-legacy-backup` can be
archived/removed.

## 10. Rollback

```bash
sudo mv /var/www/lep /var/www/lep-laravel-failed
sudo mv /var/www/lep-legacy-backup /var/www/lep
sudo restorecon -Rv /var/www/lep
```

Then revert the `DocumentRoot`/`<Directory>` edit in both vhosts back to
`/var/www/lep` (no `/public`), restore the `uploads/` `<Directory>` block,
and reload Apache. The database wasn't touched destructively by this
migration (only new tables were added via the guarded migration; nothing
existing was altered), so the PHP app keeps working exactly as it did
before.

## Troubleshooting

Same first moves as your PHP app's guide:

```bash
# 500 errors
sudo tail -f /var/log/httpd/lep_error.log
sudo tail -f /var/www/lep/storage/logs/laravel.log

# Permission/SELinux denials
sudo ausearch -c httpd --raw | audit2why

# php-fpm socket
sudo systemctl status php-fpm
ls -la /run/php-fpm/lep.sock

# MariaDB connection
mysql -u lep_user -p -e "SELECT 1;"
```
