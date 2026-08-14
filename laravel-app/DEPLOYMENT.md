# LEP (Laravel) — Deployment Guide for AlmaLinux 8.10 (Apache httpd)

> Same server/stack as your existing `almalinux_deployment_guide.md` for the
> PHP app: AlmaLinux 8.10, Apache httpd (already running your Node.js +
> PostgreSQL project too), php-fpm, MariaDB, SELinux enforcing. This guide
> covers the **delta** — what's new for the Laravel app — and reuses your
> existing PHP 8.2/php-fpm/MariaDB install rather than repeating it.

Deployed via `git clone` from `https://github.com/Nikhil2247/lep.git`
(push your local commit first — `git push origin main` — the server can't
clone what GitHub doesn't have yet). The old PHP app at `/var/www/lep` is
removed entirely and replaced by the cloned repo at that same path, so the
php-fpm pool/socket, SELinux context, and log paths you already have
configured for `/var/www/lep` keep working with no new config.

Because the repo root contains `laravel-app/` as a subfolder (alongside
`.git`), the app itself lives one level down: **`/var/www/lep/laravel-app/`**,
with `DocumentRoot` pointing at `/var/www/lep/laravel-app/public`.

## 0. What's different from the PHP deployment

| Then (PHP) | Now (Laravel) |
|---|---|
| Files deployed via SCP | Files deployed via `git clone` / `git pull` |
| Document root = `/var/www/lep` | Document root = `/var/www/lep/laravel-app/public` |
| DB credentials in `config/config.php` | DB credentials in `.env` |
| Evidence/project files on local disk under `uploads/` | Evidence/project files in **MinIO** (bucket `lep`) |
| `master_import.php` / `export_submissions.php` — no auth | Same features, behind `/admin/login` |
| No CSRF, no rate limiting | Both on by default |
| One schema SQL file with data baked in | One migration (schema) + two seeders (data) — §4 |

The MariaDB database itself is unchanged — same schema, same data, same
`lep_nagaland` database, same `lep_user` credentials your PHP app already
uses. This is an application-layer migration, not a data migration.

## 1. Already done — nothing to do here

- PHP 8.2 + php-fpm (Remi repo), the `lep` pool at `/run/php-fpm/lep.sock` —
  reused as-is. Confirm `gd` or `imagick` is present for Intervention Image:
  `php -m | grep -iE 'gd|imagick'`; install with `sudo dnf install -y php-gd`
  if missing, then `sudo systemctl restart php-fpm`.
- MariaDB, `lep_nagaland` database, `lep_user` — reused as-is.
- Apache httpd, SELinux enforcing, firewalld with 80/443 open, certbot.

New requirements: **git** and **Composer 2**.

```bash
sudo dnf install -y git
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
php -r "unlink('composer-setup.php');"
composer --version
```

## 2. Back up, then remove the old PHP app entirely

A quick tar backup costs nothing and is your only safety net once the old
files are gone — worth keeping even though the plan is a clean removal:

```bash
sudo tar -czf /root/lep-php-backup-$(date +%F).tar.gz -C /var/www lep
sudo rm -rf /var/www/lep
```

## 3. Clone the repo

```bash
sudo git clone https://github.com/Nikhil2247/lep.git /var/www/lep
cd /var/www/lep/laravel-app
composer install --no-dev --optimize-autoloader
```

`composer install` runs `artisan package:discover`, which needs
`bootstrap/cache/` (and `storage/framework/{cache,sessions,views}`,
`storage/logs`, `storage/app/public`) to already exist and be writable.
Git doesn't track empty directories, so these are committed with a
placeholder `.gitignore` file in each one specifically so `git clone`
creates them for you — if `composer install` still fails with
`"The .../bootstrap/cache directory must be present and writable"`, your
clone predates that fix; `git pull` first, or run this once as a stopgap:

```bash
mkdir -p bootstrap/cache storage/framework/{cache,sessions,views} storage/logs storage/app/public
composer install --no-dev --optimize-autoloader
```

For future updates, this becomes: `cd /var/www/lep && sudo git pull`, then
re-run `composer install` if `composer.json` changed and `php artisan
migrate` if new migrations were added.

## 4. Configure `.env`

```bash
cp .env.example .env
php artisan key:generate
```

Edit `.env`:

- `APP_URL=https://nagaland.lep.2026.vibha.org` — already set correctly in
  `.env.example`.
- `DB_HOST=localhost`, `DB_DATABASE=lep_nagaland`, `DB_USERNAME=lep_user`,
  `DB_PASSWORD=` — the **same** credentials your PHP app's `config/config.php`
  used.
- `MINIO_*` — endpoint/key/secret/bucket for the `lep` bucket you already set up.
- `LEP_ADMIN_EMAIL` / `LEP_ADMIN_PASSWORD` / `LEP_ADMIN_NAME` — the one admin
  account for `/admin/*`.
- `SESSION_SECURE_COOKIE=true` (you're going straight to the live HTTPS vhost
  in this flow, no separate HTTP staging step).

## 5. Database — one migration file, two seeders

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

  Or all three at once: `php artisan db:seed`.

## 6. Move content into MinIO

Two sets of real files need to land in your `lep` bucket, keeping the
**exact same object-key shape as the existing DB values** (`projects.project_file`
and `submission_evidence.file_path` already store paths like
`uploads/projects/School Leader.pdf` — kept on purpose so no DB rows change).

**a) Project PDFs** (staged at `storage/app/minio-migration/uploads/projects/`
in this repo — 17 official Cycle 1 documents):

```bash
mc mirror storage/app/minio-migration/uploads/projects myminio/lep/uploads/projects
```

**b) Evidence files already submitted through the live PHP app** — recover
these from the backup tarball made in §2, since the live `uploads/` folder
is gone now:

```bash
sudo tar -xzf /root/lep-php-backup-$(date +%F).tar.gz -C /tmp lep/uploads/evidence
mc mirror /tmp/lep/uploads/evidence myminio/lep/uploads/evidence
```

If no submissions had come in yet, skip this.

## 7. Permissions & SELinux

```bash
sudo chown -R apache:apache /var/www/lep
sudo find /var/www/lep -type d -exec chmod 755 {} \;
sudo find /var/www/lep -type f -exec chmod 644 {} \;

sudo chmod -R 775 /var/www/lep/laravel-app/storage /var/www/lep/laravel-app/bootstrap/cache
sudo chown -R apache:apache /var/www/lep/laravel-app/storage /var/www/lep/laravel-app/bootstrap/cache

# Same path pattern your PHP app already had a rule for - restorecon just
# needs to relabel the freshly-cloned content, no new semanage rule needed
# for /var/www/lep itself.
sudo restorecon -Rv /var/www/lep

# storage/ and bootstrap/cache/ are new writable subpaths that didn't exist
# under the PHP app, so these two new rules are needed:
sudo semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/lep/laravel-app/storage(/.*)?"
sudo semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/lep/laravel-app/bootstrap/cache(/.*)?"
sudo restorecon -Rv /var/www/lep/laravel-app/storage /var/www/lep/laravel-app/bootstrap/cache

# Already enabled for the PHP app, but confirm:
sudo setsebool -P httpd_can_network_connect_db 1
```

If MinIO is reached over the network (not `localhost`), also:

```bash
sudo setsebool -P httpd_can_network_connect 1
```

## 8. Update the Apache VirtualHost

Edit `/etc/httpd/conf.d/lep-vhost.conf` (your existing `:80` config).
Certbot typically writes the matching `:443` vhost to a sibling file named
`lep-vhost-le-ssl.conf` in the same `conf.d/` directory — check for it and
apply the identical change there too:

```diff
-    DocumentRoot /var/www/lep
+    DocumentRoot /var/www/lep/laravel-app/public

-    <Directory /var/www/lep>
+    <Directory /var/www/lep/laravel-app/public>
```

Remove the now-unused `<Directory /var/www/lep/uploads>` block entirely —
MinIO means Laravel never writes user-uploaded files under the document
root, so there's nothing there left to block execution on.

```bash
sudo apachectl configtest
sudo systemctl reload httpd
```

## 9. Verify

Visit `https://nagaland.lep.2026.vibha.org/` and work through `README.md`'s
verification checklist — form submission, cascading dropdowns, evidence
upload + compression, project download, certificate rendering — and confirm
`/admin/export` and `/admin/master-import` now require login (they didn't
before).

```bash
sudo tail -f /var/log/httpd/lep_error.log
sudo tail -f /var/www/lep/laravel-app/storage/logs/laravel.log
```

If something's broken, see Rollback below before teachers start using it —
once real submissions start landing in the live DB, rolling back to the PHP
app is still safe (nothing existing was altered), but any evidence uploaded
through the Laravel app in the meantime lives in MinIO, not the PHP app's
local `uploads/`, so the PHP app won't be able to see it.

## Rollback

```bash
sudo rm -rf /var/www/lep
sudo mkdir -p /var/www/lep
sudo tar -xzf /root/lep-php-backup-$(date +%F).tar.gz -C /var/www lep --strip-components=1
sudo restorecon -Rv /var/www/lep
```

Then revert the `DocumentRoot`/`<Directory>` edit in both vhosts back to
`/var/www/lep` (no `/laravel-app/public`), restore the `uploads/`
`<Directory>` block, and reload Apache.

## Troubleshooting

```bash
# 500 errors
sudo tail -f /var/log/httpd/lep_error.log
sudo tail -f /var/www/lep/laravel-app/storage/logs/laravel.log

# Permission/SELinux denials
sudo ausearch -c httpd --raw | audit2why

# php-fpm socket
sudo systemctl status php-fpm
ls -la /run/php-fpm/lep.sock

# MariaDB connection
mysql -u lep_user -p -e "SELECT 1;"

# git clone/pull auth issues (private repo)
git config --global credential.helper store   # or set up a deploy key instead
```
