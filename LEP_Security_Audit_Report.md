# LEP (Laravel) — Security Audit Report

**Application:** Learning Enhancement Program (LEP), Samagra Shiksha Nagaland
**Target:** `https://nagaland.lep.2026.vibha.org` (live production) + full source review of `laravel-app/`
**Audit date:** 2026-08-18
**Method:** Static source-code review (100% of `app/`, `routes/`, `config/`, `resources/views/`, `public/assets/js`, migrations, seeders) + a limited, read-only live-traffic check against the production URL (headers, TLS, redirects, sensitive-path probes, and the login-throttle test the project's own README calls for). **No VPS/SSH access, no PHP/Composer runtime, and no staging database were available** — this bounds what could be verified; every such gap is called out explicitly below with the exact command to run to close it.

Companion file: `LEP_Security_Audit_Checklist_Completed.xlsx` — all 106 checklist rows filled in with Status/Risk/Finding/Remediation, in the same layout as the original checklist.

---

## 1. Executive summary

The application itself — the Laravel code — is well built. Every routine web-app vulnerability class was checked at the code level and came back clean: no raw SQL, no mass-assignment, no unescaped Blade output, no dangerous PHP functions, CSRF on every form, server-side validation everywhere, path-traversal guards on both file-serving endpoints, and a working login throttle (verified live: the 6th rapid login attempt returned HTTP 429, exactly as the app's own README predicts). This is a genuine improvement over the legacy PHP app it replaces, which had no authentication at all on its export/import endpoints.

The risk in this deployment is concentrated in three places outside the application code itself:

1. **Credentials.** The `.env` reviewed for this audit contains a weak, guessable database password and MinIO object-storage credentials that are still the product's well-known default values, not unique rotated ones — protecting the same production database and the bucket holding every teacher's evidence uploads. **This should be rotated immediately** (see §3.1).
2. **Missing baseline web hardening**, confirmed live: no security headers at all (no HSTS, CSP, X-Frame-Options, X-Content-Type-Options), and a `Server`/`X-Powered-By` response that hands an attacker the exact Apache, OpenSSL, PHP and OS stack.
3. **Dependency/deploy hygiene.** There is no `composer.lock` in the repository at all, so every install can silently resolve different framework versions — and the version range in `composer.json` currently permits Laravel 11, which is already past end-of-life.

Everything requiring VPS/SSH access (firewall rules, OS patch level, file permissions, backup jobs, DB user privileges) could not be verified from here and is listed as **Not Tested** with the exact command to run — this is the "other tests that are done elsewhere" the checklist calls for.

---

## 2. What was tested, and how

| Method | What it covers | What it can't cover |
|---|---|---|
| Full source review | Auth, authorization, input validation, SQLi, mass assignment, XSS, file upload, routes, dangerous functions, secrets-in-code | Anything only visible at runtime on the real server |
| Live HTTP probing (read-only GET/HEAD + the login-throttle test) | HTTPS/redirect, TLS cert, headers, sensitive-file exposure, directory listing, error-page disclosure, admin-route gating, CORS, brute-force throttle | TLS cipher/protocol deep-scan, full DAST/fuzzing (deliberately not run against a live government production system) |
| Documentation review (`DEPLOYMENT.md`, `README.md`) | Intended VPS/web-server/firewall/permissions setup | Whether that intended setup was actually and fully applied on the real server |
| Git history review | Whether secrets were ever committed | — |
| Dependency-support research | PHP/Laravel EOL dates, any public CVEs matching the pinned version ranges | Anything specific to the exact resolved versions (no `composer.lock` exists to pin them) |

No SQL injection, XSS, or file-upload payloads were fired at the live production system — this is a real system holding real teacher/student-program data, so those checks were done by reading the code instead. Recommend re-running them against a staging copy per the "Security Testing" section of the checklist.

---

## 3. Findings, worst first

### 3.1 Critical — Weak/default credentials in `.env`
The `.env` used for this review contains a database password that follows an easily-guessable pattern (database name + a short number), and MinIO access-key/secret values that are still MinIO's out-of-the-box default rather than unique generated ones. `DEPLOYMENT.md` confirms these are "the **same** credentials your PHP app's `config/config.php` used" — i.e. this is not a throwaway dev value, it's tied to the live `lep_nagaland` database and the `lep` MinIO bucket holding every teacher's uploaded evidence.
**Do this now:**
```bash
# New DB password
mysql -u root -p -e "ALTER USER 'lep_user'@'localhost' IDENTIFIED BY '<new-strong-random-password>';"
# then update DB_PASSWORD in .env and restart php-fpm

# New MinIO credentials (via mc or the MinIO console), then update
# MINIO_KEY / MINIO_SECRET in .env and restart php-fpm
```
Also worth a quick look: MinIO server access logs, for any request to the `lep` bucket from an IP you don't recognize, while default credentials were live.

### 3.2 High — No `composer.lock`, and the version range allows an EOL Laravel
No `composer.lock` exists anywhere in the repository (the README notes this app "has never had composer install run against it"). Combined with `"laravel/framework": "^11.9|^12.0"` in `composer.json`, this means a fresh `composer install` today could resolve to **Laravel 11, which reached end-of-life on 2026-03-12** (no more security patches), and there's no lockfile to prevent that drifting between environments. Laravel 12 itself finished bug-fix support on 2026-08-13; security support runs to 2027-02-24.
```bash
composer require laravel/framework:^12.0
composer require php:^8.3 --no-update   # tighten the platform requirement in composer.json
composer update
git add composer.lock composer.json
git commit -m "Pin dependencies, drop EOL Laravel 11 support"
```
Then run `composer audit` and fix anything it reports (not run here — no PHP/Composer available in this review environment).

### 3.3 High — Outdated web server / TLS library disclosed
The live `Server` header reads `Apache/2.4.37 (AlmaLinux) OpenSSL/1.1.1k mod_wsgi/4.6.4 Python/3.6`. Apache 2.4.37 shipped in 2018 and OpenSSL 1.1.1 left security support in September 2023. If that's genuinely what's running (not just a stale compiled-in banner), it means years of missed CVE patches on the TLS/HTTP layer this app's cookies and login form depend on.
```bash
httpd -v                 # confirm the real version
sudo dnf update httpd openssl
sudo systemctl restart httpd
```

### 3.4 Medium-High — No security response headers at all
Confirmed live: no `Strict-Transport-Security`, `Content-Security-Policy`, `X-Content-Type-Options`, `X-Frame-Options`, or `Referrer-Policy` on any response. There's no middleware or web-server config setting any of these. Add them at the Apache vhost level (simplest, covers every response):
```apache
Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
Header always set X-Content-Type-Options "nosniff"
Header always set X-Frame-Options "SAMEORIGIN"
Header always set Referrer-Policy "strict-origin-when-cross-origin"
```
A CSP is the one that needs care here, because the login/home pages load Bootstrap and Bootstrap Icons straight from `cdn.jsdelivr.net` with no Subresource Integrity hash — either self-host those assets or add `integrity="sha384-…"` + `crossorigin="anonymous"` to the two `<link>`/`<script>` tags in `resources/views/layouts/app.blade.php`, then write the CSP to match.

### 3.5 Medium — No MFA and no export audit trail on the one admin account
A single password now gates every teacher's PII and every evidence file (a real improvement over the legacy app's *no* auth — but still a single factor guarding a high-value bulk-export action). Recommend adding TOTP MFA, and recommend logging who ran an export and when (currently nothing records this beyond generic web-server access logs) — see the Logging & Monitoring rows in the checklist for both.

### 3.6 Medium — `APP_KEY` empty in the reviewed `.env`
Without `APP_KEY`, Laravel cannot securely encrypt sessions/cookies. This wasn't observable live (the key itself is never exposed, which is correct), but it must be confirmed set — `php artisan key:generate` — on whichever server this exact `.env` is deployed to before it goes live with it.

### 3.7 Medium — No automated/off-server backups documented
`DEPLOYMENT.md` documents exactly one backup: a manual tarball taken once during the PHP→Laravel cutover, stored in `/root/` **on the same VPS**. There's no recurring database/MinIO backup job and nothing off-server, so a single VPS failure would be unrecoverable. See the Backup & Disaster Recovery rows in the checklist.

### 3.8 Low-Medium — Server/PHP version fingerprinting
`X-Powered-By: PHP/8.3.33` is sent on every response (`expose_php` not disabled), on top of the Apache/OpenSSL disclosure above. Set `expose_php = Off` and `ServerTokens Prod` / `ServerSignature Off`.

### 3.9 Everything that came back clean
Worth stating plainly, since a report that's all findings can understate how solid the app code is: **no SQL injection surface, no mass-assignment holes, no unescaped output/XSS in any Blade view or the hand-written JS, no dangerous PHP functions, CSRF present everywhere, file uploads are extension+real-MIME checked and stored outside the web root, both file-serving endpoints (project PDF, evidence ZIP) have working path-traversal guards, admin routes correctly redirect to login when unauthenticated (verified live), and the login brute-force throttle works (verified live — 429 on the 6th attempt).** These are exactly the classes of bug most Laravel security incidents come from, and none of them are present here.

---

## 4. Full results

See `LEP_Security_Audit_Checklist_Completed.xlsx` for the item-by-item results against all 106 rows of the original checklist, in its original column order, with `Status`, `Risk`, `Finding / Evidence`, `Remediation / Action`, and suggested `Target Date` filled in. `Owner` and final `Target Date` are left for your team to assign.

Status legend used in the spreadsheet:
- **Pass** — verified (by code review, and/or live where noted) with no material gap.
- **Fail** — a real, confirmed gap.
- **Partial** — mostly in place but with a caveat worth tracking.
- **N/A** — the feature/scenario the checklist item assumes doesn't exist in this app (e.g. no self-service password reset, no multi-role RBAC).
- **Not Tested** — requires access this review didn't have (VPS/SSH, PHP+Composer runtime, or a staging DB) — the exact command to run yourself is given in the Remediation column.

## 5. Recommended next steps, in order

1. Rotate the DB and MinIO credentials (§3.1) — today.
2. Confirm `APP_KEY` is actually set on the live server (§3.6) — today.
3. Pin and lock dependencies, drop Laravel 11 from the version range, run `composer audit` (§3.2).
4. Patch/verify Apache + OpenSSL on the VPS (§3.3), then add the security headers (§3.4).
5. Work through every "Not Tested" row in the spreadsheet directly on the VPS — they're all one or two commands each.
6. Add export audit logging and admin MFA (§3.5).
7. Set up automated, off-server backups and do one test restore (§3.7).
8. Once 1–4 are done, run a proper DAST pass (e.g. OWASP ZAP) and a manual SQLi/XSS/upload test against a **staging copy** of the app — not production.
