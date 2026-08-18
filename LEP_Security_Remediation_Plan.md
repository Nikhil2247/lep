# LEP — Security Remediation Plan

Based solely on the findings in `LEP_Security_Audit_Report.md` / `LEP_Security_Audit_Checklist_Completed.xlsx` (2026-08-18). **Nothing in this document has been implemented.** Scope is deliberately limited to what the existing app needs — no teacher login/registration/password-reset, no RBAC, no multi-tenancy, no API auth, no MFA for a general user base, no queue/Horizon infrastructure, no npm/node build pipeline — none of these are demonstrated as necessary by the actual code, which has none of those concepts today (submissions are anonymous, there is exactly one seeded admin, and all JS is hand-written vanilla JS served statically).

---

## CRITICAL

### C1. Rotate the database password and MinIO credentials
- **Security issue:** the `.env` reviewed uses a weak, guessable database password and MinIO access-key/secret still set to MinIO's factory default values.
- **Why it matters for LEP specifically:** these exact credentials, per `DEPLOYMENT.md`, protect the live `lep_nagaland` database and the `lep` MinIO bucket holding every teacher's uploaded evidence file (which can include photos of students/classrooms). A guessed/default credential is a direct path to all program data.
- **File(s):** `.env` only (`DB_PASSWORD`, `MINIO_KEY`, `MINIO_SECRET`) — no application code changes.
- **Type of change:** credential rotation on the MySQL server (`ALTER USER`) and MinIO server (new access key), then update the two `.env` values to match.
- **Can it affect existing functionality:** yes, briefly — the app cannot connect to the DB/MinIO until both sides are updated in the same maintenance window; sequence matters.
- **DB migration required:** no schema migration; this is a credential change on the DB server itself, not a Laravel migration.
- **Deployment/config changes required:** yes — must be done directly against the MySQL and MinIO servers on the VPS, coordinated with an `.env` update and a `php artisan config:clear` + php-fpm reload.
- **How we'll test it:** load the homepage and confirm district/block/school dropdowns still populate (DB connectivity), then submit a test evidence file and confirm it lands in MinIO, and download a project PDF (MinIO read path) — all before and after, to bound the maintenance window.

### C2. Confirm/generate `APP_KEY`
- **Security issue:** the reviewed `.env` has an empty `APP_KEY`. Without it, Laravel cannot securely encrypt sessions/cookies.
- **Why it matters for LEP specifically:** the admin session cookie and CSRF token both depend on `APP_KEY`; an empty key means either the app errors out or falls back to an insecure state.
- **File(s):** `.env` only.
- **Type of change:** run `php artisan key:generate` on whichever server this `.env` is actually deployed to.
- **Can it affect existing functionality:** no negative effect here, because the key is currently *empty* — generating it for the first time doesn't invalidate anything (this would be different if an *existing* key were being rotated, which would force-logout the admin and could affect anything else that also generates encrypted cookies for the same live site — reserve that for a planned maintenance window if it's ever needed).
- **DB migration required:** no.
- **Deployment/config changes required:** yes, one command on the server, then restart php-fpm.
- **How we'll test it:** log in as admin, submit a test submission, confirm no "no application encryption key" errors appear in `storage/logs/laravel.log`.

---

## HIGH

### H1. Pin dependencies and commit `composer.lock`
- **Security issue:** no `composer.lock` exists anywhere in the repo; `composer.json` currently allows `laravel/framework: ^11.9|^12.0`, and Laravel 11 is already past end-of-life (2026-03-12).
- **Why it matters for LEP specifically:** every future `composer install` on a new server or after a wipe can silently resolve a different (possibly EOL, unpatched) framework version than what's running today, with no way to detect the drift.
- **File(s):** `composer.json` (tighten the constraint to `^12.0` and `php: ^8.3` to match what's actually running in production), plus the generated `composer.lock` (new file, committed).
- **Type of change:** dependency constraint edit + `composer update` run on a machine with PHP 8.3/Composer (not available in this sandbox — needs to be run on the VPS or a dev machine), then commit both files.
- **Can it affect existing functionality:** possibly — `composer update` can pull in minor/patch bumps to any package, not just Laravel, so a full functional pass is warranted afterward.
- **DB migration required:** no.
- **Deployment/config changes required:** yes — going forward, deploys must use `composer install` (honors the lockfile) rather than `composer update`; `DEPLOYMENT.md` should be updated to say so explicitly.
- **How we'll test it:** run through the existing manual verification checklist in `README.md` (form submission, cascading dropdowns, evidence upload + compression, project download, certificate render, CSV/ZIP export, login throttle) after the update, plus `composer audit` to confirm no known vulnerabilities remain in the locked versions.

### H2. Add baseline security response headers
- **Security issue:** live testing confirmed zero security headers on any response — no HSTS, CSP, X-Content-Type-Options, X-Frame-Options, or Referrer-Policy.
- **Why it matters for LEP specifically:** this is the only public-facing government form in scope; these headers are cheap, standard defense-in-depth against clickjacking/MIME-sniffing/downgrade attacks and cost nothing functionally if configured correctly.
- **File(s):** new `app/Http/Middleware/SecurityHeaders.php`; one-line registration in `bootstrap/app.php`.
- **Type of change:** new middleware class that appends the headers to every response; registered app-wide (not tied to Apache config, so it works regardless of what's verified/fixed at the VPS level).
- **Can it affect existing functionality — important caveat:** `resources/views/layouts/app.blade.php` and `resources/views/home.blade.php` use inline `onerror="..."` JS attributes on `<img>` tags (logo fallback), and both load Bootstrap/Bootstrap Icons from `cdn.jsdelivr.net`. A strict CSP (`script-src 'self'`) would silently disable those inline `onerror` fallbacks and would need `cdn.jsdelivr.net` explicitly allow-listed for `style-src`/`script-src`. Two options, your call:
  - **(a) Fast path:** ship a CSP that allow-lists `cdn.jsdelivr.net` and keeps `'unsafe-inline'` for now — gets HSTS/X-Frame-Options/nosniff/Referrer-Policy in place immediately with zero risk to the existing pages, defers CSP strictness.
  - **(b) Cleaner path:** first move the 3 inline `onerror` handlers out of the Blade templates into `public/assets/js/app.js` (small, mechanical change), then ship a strict CSP with no `'unsafe-inline'`.
- **DB migration required:** no.
- **Deployment/config changes required:** no — pure application-layer middleware, works without any Apache/vhost edit.
- **How we'll test it:** `curl -I` the homepage and admin pages to confirm headers are present; load every page in a browser and confirm Bootstrap CSS/JS/icons still render, dropdowns/AJAX cascades still work, and the browser console shows no CSP violations.

### H3. Add Subresource Integrity (SRI) to the CDN-loaded assets
- **Security issue:** Bootstrap CSS, Bootstrap Icons CSS, and Bootstrap JS are all loaded from `cdn.jsdelivr.net` with no integrity check — if that CDN were ever compromised, it could inject malicious JS into the admin login page.
- **Why it matters for LEP specifically:** the admin login page is the single point of compromise for every teacher's exportable data; it's currently trusting a third-party CDN unconditionally.
- **File(s):** `resources/views/layouts/app.blade.php` (the 3 `<link>`/`<script>` tags only).
- **Type of change:** add `integrity="sha384-…"` (the official published hash for the exact pinned versions, 5.3.3 / 1.11.3) and `crossorigin="anonymous"` attributes. No build tooling, no npm — just static HTML attributes on the existing tags.
- **Can it affect existing functionality:** no, as long as the hash matches the exact byte content jsdelivr serves for that pinned version (which is why versions must stay pinned, not `@latest`).
- **DB migration required:** no. **Deployment/config changes required:** no.
- **How we'll test it:** reload every page and confirm Bootstrap CSS/JS/icons still load (check browser console for an SRI mismatch error, which would show as the asset failing to apply).

---

## MEDIUM

### M1. Log admin export actions
- **Security issue:** neither the CSV export nor the evidence-ZIP export currently creates any record of who ran it or when.
- **Why it matters for LEP specifically:** this is the single most sensitive action the app can perform (bulk download of every teacher's PII + evidence files) and it's currently unauditable beyond generic web-server access logs.
- **File(s):** `app/Http/Controllers/Admin/ExportController.php` (add a `Log::info(...)` call at the top of `csv()` and `evidenceZip()`, with `auth()->user()->email`, timestamp, and export type).
- **Type of change:** a couple of added lines, log-based (no new table) to keep this proportionate to the app's size.
- **Can it affect existing functionality:** no — purely additive, doesn't change the response.
- **DB migration required:** no (log-file based). *If you'd rather have a queryable audit trail instead of grepping logs, a small `export_logs` table + migration is a reasonable alternative — flagging as an option, not proposing it as the default.*
- **Deployment/config changes required:** none beyond normal deploy.
- **How we'll test it:** run both exports as the seeded admin, confirm a log line appears in `storage/logs/laravel.log` with the admin's email, timestamp, and export type, and confirm the export itself still downloads correctly.

### M2. Log admin authentication events (success + failure)
- **Security issue:** no durable record of admin login attempts (who, when, success/fail, IP) beyond the in-memory rate limiter.
- **Why it matters for LEP specifically:** the admin account is the only credential guarding program data; if it's ever targeted, there's currently no way to see a login-attempt history after the fact.
- **File(s):** `app/Providers/AppServiceProvider.php` (register listeners on `Illuminate\Auth\Events\Login` and `Illuminate\Auth\Events\Failed` inside `boot()`).
- **Type of change:** a small closure or listener class writing `Log::info/warning(...)` with email attempted, IP, timestamp, outcome.
- **Can it affect existing functionality:** no — purely observational, doesn't touch the login flow itself.
- **DB migration required:** no. **Deployment/config changes required:** none.
- **How we'll test it:** attempt one successful and one failed login, confirm both are logged with the right fields, and confirm the login flow/throttle behavior is unchanged.

### M3. Rate-limit the `/ajax/*` lookup endpoints
- **Security issue:** `/ajax/blocks`, `/ajax/schools`, `/ajax/subjects`, `/ajax/project` have no throttle at all, unlike `/submissions` (`throttle:10,1`) and `/admin/login` (`throttle:5,1`).
- **Why it matters for LEP specifically:** low sensitivity (the data returned is public school/reference data, not PII), but these routes hit the database on every call and are currently open to unlimited scripted requests.
- **File(s):** `routes/web.php` (add `->middleware('throttle:60,1')` to the 4 existing route definitions, or wrap them in a `Route::middleware('throttle:60,1')->group()`).
- **Type of change:** route middleware addition, one line per route (or one group wrapper).
- **Can it affect existing functionality:** very unlikely — normal use of the cascading District→Block→School→Grade→Subject form is nowhere near 60 requests/minute per IP. Shared-NAT school networks with many teachers submitting concurrently from the same public IP are the one scenario worth a quick sanity check against the chosen limit.
- **DB migration required:** no. **Deployment/config changes required:** no.
- **How we'll test it:** use the real form end-to-end several times in a row and confirm no unexpected 429s, then script 60+ rapid requests to one endpoint and confirm the throttle engages.

### M4. Harden `SimpleXlsxReader`'s XML parsing
- **Security issue:** the hand-rolled `.xlsx` reader calls `simplexml_load_string()` three times without explicit libxml hardening flags, when parsing an admin-uploaded file.
- **Why it matters for LEP specifically:** this is the one place in the app that parses an uploaded binary/XML-based file format; modern PHP/libxml already disables external entity resolution by default, so this isn't a demonstrated exploitable bug today, but it's the app's only untrusted-file-parsing code path and costs one line per call to harden explicitly.
- **File(s):** `app/Support/SimpleXlsxReader.php` (the 3 `simplexml_load_string()` call sites).
- **Type of change:** add the `LIBXML_NONET` option flag (and confirm no `LIBXML_NOENT`/external-entity-enabling flags are ever added later).
- **Can it affect existing functionality:** no — restricts what the parser is *allowed* to do; legitimate `Master_Schools-2026.xlsx` imports are unaffected.
- **DB migration required:** no. **Deployment/config changes required:** no.
- **How we'll test it:** re-run the master-import feature against the existing `storage/app/master-import/Master_Schools-2026.xlsx` and confirm identical import stats (districts/blocks/schools counts) before and after.

### M5. Update `DEPLOYMENT.md`'s git-credential guidance
- **Security issue:** the troubleshooting section suggests `git config --global credential.helper store` for private-repo pulls, which stores the Git credential in plaintext on disk on the VPS.
- **Why it matters for LEP specifically:** this is documentation your own team will follow on the production server — as written, it invites a plaintext credential to sit on the same box as the app.
- **File(s):** `DEPLOYMENT.md` (troubleshooting section only).
- **Type of change:** text edit — replace the `credential.helper store` suggestion with a recommendation to use a deploy key (SSH) instead.
- **Can it affect existing functionality:** no — documentation only.
- **DB migration required:** no. **Deployment/config changes required:** no code/app change; only affects how the *next* person deploys.
- **How we'll test it:** N/A (doc review only) — confirm the updated instructions actually work by doing one `git pull` on the VPS using a deploy key.

---

## LOW

### L1. Enable session payload encryption
- **Security issue:** `SESSION_ENCRYPT=false` — session data is stored unencrypted in the `sessions` table.
- **Why it matters for LEP specifically:** the session payload here is small (admin auth state only, no PII stored in-session), so this is minor, but it's a one-value config change with no downside.
- **File(s):** `.env` only (`SESSION_ENCRYPT=true`). No PHP code change — `config/session.php` already reads this env var.
- **Type of change:** config value flip.
- **Can it affect existing functionality:** yes, momentarily — any session active at the moment of the change (i.e., the current admin login) will be invalidated, requiring a fresh login. No other users are affected (no teacher accounts exist).
- **DB migration required:** no. **Deployment/config changes required:** update `.env` on the server, `php artisan config:clear` if config is cached, restart php-fpm.
- **How we'll test it:** log in again after the change, confirm the session persists correctly across page loads and logout still works.

---

## OPTIONAL

### O1. Add a second factor (TOTP) to the single admin login
- **Security issue:** the admin account is protected by password alone.
- **Note on scope:** this is **not** a request to build general MFA/user-management infrastructure — there is exactly one seeded admin account, created via `AdminUserSeeder`, and this would add one optional TOTP check to that one login form. Framed as optional because the original audit flagged it as defense-in-depth, not a confirmed exploitable gap — the login is already rate-limited and uses bcrypt hashing correctly.
- **File(s):** `app/Http/Controllers/Auth/LoginController.php`, `resources/views/admin/login.blade.php`, `app/Models/User.php` (a `two_factor_secret` column), plus a small package (e.g. `pragmarx/google2fa`) or hand-rolled TOTP check.
- **Type of change:** additive fields + an extra verification step in the login flow.
- **Can it affect existing functionality:** yes — changes the login flow; needs a recovery path (e.g. a documented way to disable 2FA via `artisan tinker` if the admin loses their device) since there's no self-service account-recovery flow in this app.
- **DB migration required:** yes — one new nullable column on `users`.
- **Deployment/config changes required:** none beyond the migration.
- **How we'll test it:** enroll TOTP for the seeded admin, confirm login requires the code, confirm the documented recovery path works.
- **Recommendation:** worth doing eventually given what the account can export, but reasonable to defer — it's the one item here with real login-flow risk and a migration, for a single-admin app.

### O2. Add magic-byte validation for `.doc`/`.docx` uploads
- **Security issue:** none demonstrated — `EvidenceUploadService` already validates the server-detected MIME type (via PHP's Fileinfo extension), not just the client-supplied extension, which is the correct check.
- **Why it's optional, not required:** this would be an additional content-sniffing layer on top of an already-correct check, with no confirmed bypass found in this codebase.
- **File(s):** `app/Services/EvidenceUploadService.php` (`validate()` method).
- **Type of change:** add a check of the file's leading bytes (ZIP magic number for `.docx`, OLE magic number for legacy `.doc`) in addition to the existing MIME check.
- **Can it affect existing functionality:** low risk, but any real teacher-submitted Word document that Fileinfo already accepts should also pass a correct magic-byte check — worth testing with a real sample file either way.
- **DB migration required:** no. **Deployment/config changes required:** no.
- **How we'll test it:** upload a genuine `.docx` and `.doc` and confirm they're still accepted; upload a renamed non-Office file with a `.docx` extension and confirm it's now rejected.

---

## NOT APPLICABLE

These were explicitly out of scope, and the code confirms why:

| Item | Why it's not applicable here |
|---|---|
| Teacher login / registration / password reset | The public submission form is intentionally anonymous by design (`StoreSubmissionRequest::authorize()` returns `true` unconditionally, no `User` record is ever created for a teacher). Adding accounts would be a product change, not a security fix. |
| RBAC | There is exactly one role in the entire schema (the single seeded admin via `AdminUserSeeder`); no permission model exists to secure. |
| Multi-tenancy | No "program"/tenant partitioning exists anywhere in the schema or queries; the single admin is meant to see all data. |
| API authentication | The only unauthenticated endpoints (`/ajax/*`) return non-sensitive, already-public reference data (district/block/school names); the genuinely sensitive endpoints are already behind `auth`. There is no token-based API surface to secure. |
| MFA for a general user base | There is no general user base — one seeded admin account, created and rotated manually via `.env` + a seeder command. (A *narrower*, single-account TOTP addition is listed separately above as O1, purely optional.) |
| Queue/Horizon infrastructure | `QUEUE_CONNECTION=database` is configured but the codebase never dispatches a single `Job` (no `app/Jobs` directory; `SubmissionController` does all work synchronously). Building worker infrastructure for a queue that isn't used would be speculative. |
| npm/node build pipeline | No `package.json`, no `node_modules`, no frontend build step exists — Bootstrap is CDN-loaded and `app.js` is hand-written vanilla JS. All fixes above (SRI, header middleware) work with this as-is; none require introducing a build tool. |

---

## VPS / PRODUCTION VERIFICATION

Not code changes — these require direct server access this review didn't have. Each is one or two commands; see the completed checklist spreadsheet for the exact command per row.

- **Patch Apache/OpenSSL** — live headers show `Apache/2.4.37` / `OpenSSL/1.1.1k`, both years past their support window if genuine (`httpd -v`, `sudo dnf update httpd openssl`).
- **Disable stack fingerprinting at the server level** — `ServerTokens Prod`, `ServerSignature Off` (Apache), `expose_php = Off` (php.ini) — the app-layer header middleware (H2) doesn't remove the `Server`/`X-Powered-By` headers, since those are added by Apache/PHP before Laravel ever runs.
- **Confirm OS patch level** — AlmaLinux version/`dnf check-update`.
- **Firewall review** — confirm only 22 (restricted)/80/443 are internet-facing; MySQL (3306), Redis (6379), MinIO (9000) should be loopback/internal-only.
- **SSH hardening** — key-only auth, no root login.
- **Confirm the app runs as the `lep` user, not root/`apache`** — matches `DEPLOYMENT.md`'s intent; needs live confirmation it was actually applied.
- **Unused services audit** on the shared VPS (it also hosts an unrelated Node.js/PostgreSQL app per `DEPLOYMENT.md`).
- **File permission sweep** — no stray world-writable paths outside `storage/`/`bootstrap/cache`.
- **MySQL grants** — confirm `lep_user` has only the privileges it needs, not `GRANT`/`SUPER`/`FILE`.
- **MySQL/MinIO not publicly bound** — confirm both are loopback-only at the network layer, not just at the `.env` level.
- **Automated, off-server backups + one test restore** — currently only a single manual cutover tarball exists, stored on the same VPS.
- **PHP hardening** — `log_errors` on with a non-web-accessible path, review `open_basedir`/`disable_functions`, confirm `upload_max_filesize`/`post_max_size` are sensibly bounded (slightly above the app's 5MB cap, not unbounded).
- **TLS protocol/cipher scan** — a proper `testssl.sh` or SSL Labs run, since the OpenSSL disclosure above suggests this hasn't been checked recently.
- **Basic server monitoring** — disk/CPU/failed-login alerting.

---

## CHANGES I SHOULD ACTUALLY AUTHORIZE

1. **C1** — Rotate the DB password and MinIO credentials.
2. **C2** — Confirm/generate `APP_KEY` on the real deployment target.
3. **H1** — Pin `composer.json` to Laravel 12 / PHP 8.3 and commit `composer.lock`.
4. **H2** — Add the security-headers middleware (start with the fast-path CSP, option (a)).
5. **H3** — Add SRI attributes to the 3 CDN tags.
6. **M1** — Log admin export actions.
7. **M2** — Log admin login success/failure.
8. **M3** — Rate-limit the `/ajax/*` endpoints.

Everything else (M4, M5, L1, O1, O2) is reasonable but lower-value or higher-effort relative to the risk it addresses — worth doing, not worth blocking on.
