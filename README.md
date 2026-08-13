# Learning Enhancement Program (LEP) – Version 1.8

**Government of Nagaland | Samagra Shiksha Nagaland**

Internal programme reporting application for teachers and School Leaders.

---

## Technology Stack

- PHP 8+
- MySQL 5.7+ / 8.x
- Bootstrap 5.3
- Vanilla JavaScript
- No frameworks (Laravel, React, etc.)

---

## Folder Structure

```
lep/
├── ajax/                   # AJAX endpoints (blocks, schools, subjects, project+tasks)
├── assets/
│   ├── css/style.css
│   ├── js/app.js
│   └── images/lep_logo.png # ← replace with official logo
├── config/
│   └── config.php          # DB credentials + app settings
├── includes/
│   ├── db.php              # PDO connection
│   ├── functions.php       # helpers
│   ├── header.php
│   └── footer.php
├── uploads/
│   ├── evidence/           # teacher-uploaded evidence files
│   └── projects/           # master project PDF documents
├── sql/
│   └── schema.sql          # full schema + sample master data
├── exports/                # reserved for future export features
├── index.php               # main form
├── process_submission.php  # form handler
├── download_project.php    # secure project file download
└── README.md
```

---

## Installation Steps

1. **Copy** the entire `lep` folder to your web server document root (or a subdirectory).

2. **Create the database**
   ```bash
   mysql -u root -p < sql/schema.sql
   ```
   Or import `sql/schema.sql` via phpMyAdmin / MySQL Workbench.
   The script creates the database objects and inserts sample master data.

3. **Update database credentials** in `config/config.php`:
   ```php
   define('DB_HOST', 'localhost');
   define('DB_NAME', 'lep_nagaland');
   define('DB_USER', 'your_user');
   define('DB_PASS', 'your_password');
   ```

4. **Set folder permissions**
   ```bash
   chmod -R 755 uploads/
   chown -R www-data:www-data uploads/   # or the web-server user
   ```

5. **Replace the logo**
   - Place the official logo file at: `assets/images/lep_logo.png`
   - Recommended height: 40–60 px. No code change required.

6. **Replace project documents**
   - Place the real PDF files in `uploads/projects/`
   - Filenames must match the `project_file` column in the `projects` table
     (or update the paths in the database).

7. **(Optional)** If the application is installed in a subdirectory, set:
   ```php
   define('BASE_URL', '/lep');
   ```

8. Open the application in a browser: `http://your-server/lep/`

---

## Master-Driven Design

Nothing is hardcoded in the PHP application for:

| Entity          | Table                  | How to extend                          |
|-----------------|------------------------|----------------------------------------|
| Grades          | `grades`               | INSERT new row                         |
| Subjects        | `subjects` + mapping   | INSERT into `subjects` + `grade_subject_map` |
| Cycles          | `cycles`               | INSERT new row                         |
| Projects        | `projects`             | INSERT with correct grade/subject/cycle |
| Project Tasks   | `project_tasks`        | INSERT any number of tasks per project |
| Districts/Blocks/Schools | respective tables | INSERT master records             |

**School Leaders** special case: set `grades.is_school_leader = 1`.  
The Subject dropdown is automatically hidden and projects are looked up with `subject_id IS NULL`.

---

## Key Features (v1.7)

- Cascading District → Block → School (UDISE auto-filled)
- Grade → Subject (dynamic mapping) → Cycle → Project → Tasks
- Variable number of tasks per project (no hard-coded limit)
- Simplified task cards – only Task Number, Description and Yes/No
- **Download Project Document** button in Programme Information (enabled when project loads)
- **Project Completion Evidence** – Gmail-style multi-file uploader
  - “Add Evidence” appends files one-by-one (does not replace previous)
  - Live list with file name, size and Remove button
  - Counter: *n / 5 files selected*
  - Max 5 files, combined total ≤ 5 MB
  - Single optional Video Link for the whole project
- Unique Submission ID format: `LEP-2026-000001`
- Transactional insert (submission + task responses + evidence files)
- Secure project document download
- Responsive Bootstrap 5 government-style UI
- Clean modular PHP structure

### Upgrading from v1.0

Run the upgrade script once:

```bash
mysql -u root -p lep_nagaland < sql/upgrade_v1.1.sql
```

This adds the `video_link` column to `teacher_submissions` and creates the `submission_evidence` table.

---


## Master School Data Import (v1.3)

The official school master is provided in `data/Master_Schools-2026.csv` (and `.xlsx`).

1. Import `sql/schema.sql` (creates empty/sample geo tables plus grades, subjects, projects, etc.).
2. Open **`master_import.php`** in the browser (not linked from the main app).
3. Optionally tick **Clear existing Districts / Blocks / Schools** for a clean first import.
4. Click **Run Import**.

Expected result (approx.):
- Districts: 16
- Blocks: 46
- Schools: 1,863

Duplicate UDISE codes are skipped. Existing districts/blocks are reused by name.

School dropdown display format: `School Name (UDISE Code)`.

No external PHP libraries are required for CSV import. XLSX import needs the PHP `zip` extension (`SimpleXlsxReader`).


## Official Cycle 1 Grade → Subject Mapping (v1.4)

| Grade | Subjects |
|-------|----------|
| School Leaders | *(no subject – dropdown hidden)* |
| Pre-Primary (A-B) | Pre-Primary Teacher (Grade A & B); Arts Teacher (A & B) |
| Grade 1–3 | Literacy Teacher (Grade 1, 2 & 3); Numeracy Teacher (Grade 1, 2 & 3); Arts Teacher (Grade 1-5) |
| Grade 4–5 | Math (4,5); English (4,5); Arts Teacher (Grade 1-5) |
| Grade 6–8 | Math (6,7,8); Science (6,7,8); Art Education (Grade 6-8) |

Upgrade existing database:

```bash
mysql -u root -p lep_nagaland < sql/upgrade_v1.4.sql
```

Subjects are loaded dynamically via AJAX from `grade_subject_map` — nothing is hardcoded in the UI.

## Future Enhancements (not in v1.0)

- Admin panel for master data management
- Export / reporting dashboards
- Authentication / role-based access
- Content management for the Information section
- Email notifications

---

## Security Notes

- All database queries use prepared statements (PDO)
- File uploads validated by extension + MIME type + size
- Upload directory should not be executable
- Turn `display_errors` off in production (`config/config.php`)
- Consider adding CSRF token for the form in a later version if the environment requires it

---

## Support

For programme-related questions contact the Samagra Shiksha Nagaland LEP cell.  
For technical issues contact the development team that maintains this application.
