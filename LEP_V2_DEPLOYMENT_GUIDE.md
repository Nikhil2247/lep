# LEP Version 2 – Deployment Guide (Linux VPS)

## Recommended stack

| Component | Recommendation |
|-----------|----------------|
| OS | Ubuntu 22.04 LTS or 24.04 LTS (or equivalent Rocky/AlmaLinux 9) |
| Web server | Nginx **or** Apache 2.4 |
| PHP | **8.1, 8.2, or 8.3** (CLI + FPM/mod_php) |
| Database | **MySQL 8.0+** or **MariaDB 10.6+** |
| TLS | HTTPS required in production (Let’s Encrypt) |

### Required PHP extensions

- `pdo_mysql`
- `mbstring`
- `fileinfo`
- `json`
- `session`
- `zip` (required for **Download All Evidence (.ZIP)**)
- `gd` or `imagick` (optional)

### PHP settings (php.ini / pool)

```ini
upload_max_filesize = 10M
post_max_size = 12M
max_execution_time = 120
memory_limit = 256M
display_errors = Off
log_errors = On
```

Evidence uploads remain limited in **application code** to **5 files / 5 MB total**.  
Project PDF downloads are streamed and are **not** limited by the evidence rules.

---

## 1. Deploy application files

```bash
# Example
sudo mkdir -p /var/www/lep
sudo unzip LEP_V2.zip -d /var/www/lep
# Ensure document root points at the app folder that contains index.php
```

### Permissions

```bash
sudo chown -R www-data:www-data /var/www/lep
sudo find /var/www/lep -type d -exec chmod 755 {} \;
sudo find /var/www/lep -type f -exec chmod 644 {} \;

# Writable upload trees
sudo chmod -R 775 /var/www/lep/uploads
sudo chown -R www-data:www-data /var/www/lep/uploads
```

Ensure these exist and are not web-executable as PHP:

- `uploads/evidence/` (contains `.htaccess` deny scripts on Apache)
- `uploads/projects/` (official project PDFs)

---

## 2. Database

### Option A – script creates the database

```bash
mysql -u root -p < /var/www/lep/database/LEP_V2_Production.sql
```

The script runs:

- `CREATE DATABASE IF NOT EXISTS lep_nagaland`
- `USE lep_nagaland`
- Drops LEP tables if present (**fresh install only**)
- Creates all tables
- Seeds Cycle 1 grades, subjects, maps, projects, tasks, project file paths

### Option B – create DB manually, then import

```sql
CREATE DATABASE lep_nagaland CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'lep_user'@'localhost' IDENTIFIED BY 'STRONG_PASSWORD';
GRANT ALL PRIVILEGES ON lep_nagaland.* TO 'lep_user'@'localhost';
FLUSH PRIVILEGES;
```

Then import (you may comment out `CREATE DATABASE` / `USE` if preferred).

### Application credentials

Edit `config/config.php`:

```php
define('DB_HOST', 'localhost');
define('DB_NAME', 'lep_nagaland');
define('DB_USER', 'lep_user');
define('DB_PASS', 'STRONG_PASSWORD');
define('DB_CHARSET', 'utf8mb4');
```

**Do not commit real production passwords to git.**

---

## 3. School master data

Districts / blocks / schools are **not** fully seeded in the SQL (official Excel is the source of truth).

1. Place `Master_Schools-2026.xlsx` (or CSV) where `master_import.php` expects it, or upload via the import utility.
2. Open `master_import.php` once from a protected context and run the import.
3. Restrict or remove public access to `master_import.php` after use (HTTP auth, IP allowlist, or delete/rename).

---

## 4. Project PDF files

Copy the **17 official Cycle 1 PDFs** into:

```text
uploads/projects/
```

Filenames must match the database `project_file` values exactly (spaces, hyphens, parentheses preserved), for example:

- `School Leader.pdf`
- `Pre-Primary Teacher (Grade A & B).pdf`
- `Cycle 1 Class 4- Maths.pdf`
- …

---

## 5. Web server notes

### Nginx (example)

- Document root → application root (`index.php`)
- Pass PHP to php-fpm
- Deny execution under `/uploads/`

### Apache

- `AllowOverride` enabled so `uploads/**/.htaccess` can disable script engines
- Prefer `mod_php` or php-fpm + `proxy_fcgi`

### HTTPS

Terminate TLS at Nginx/Apache or a reverse proxy. Prefer HTTP → HTTPS redirect.

---

## 6. Post-deploy checklist

1. Open the site – form loads without PHP errors  
2. Cascading District → Block → School (after school import)  
3. Grade → Subject → Cycle → Project + tasks  
4. Download Project (large PDF streams)  
5. Submit with **0** evidence → rejected  
6. Submit with **1** evidence → folder `uploads/evidence/LEP-YYYY-######/`  
7. Certificate of Submission  
8. `export_submissions.php` → CSV (includes **Designation**)  
9. `export_submissions.php` → **Download All Evidence (.ZIP)** (needs `zip` extension)  

---

## 7. Security reminders

- `display_errors = Off` in production (already default in `config.php`)
- Protect `master_import.php` and `export_submissions.php` (not for public teachers)
- Keep `uploads/` non-executable
- Regular MySQL backups of `lep_nagaland`
- No cron is required for core LEP features

---

## 8. What Version 2 consolidates

Historical upgrade scripts (`v1.1` … `v1.6.1`) are **not** required on a fresh VPS install.

Use **only**:

```text
database/LEP_V2_Production.sql
```

Application version constant: **2.0**
