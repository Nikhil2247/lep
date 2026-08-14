<?php

// LEP application settings - replaces the constants previously defined in
// config/config.php in the legacy PHP app. Non-secret values only; secrets
// (DB, MinIO, admin seed credentials) live in .env / config/database.php /
// config/filesystems.php / config/auth.php instead of here.

return [

    'version' => '2.0',

    'app_year' => (int) date('Y'),

    // Combined size of ALL evidence files in a single submission, in bytes.
    'max_evidence_total_size' => (int) env('LEP_MAX_EVIDENCE_TOTAL_SIZE', 5 * 1024 * 1024),

    // Maximum number of evidence files per submission.
    'max_evidence_files' => (int) env('LEP_MAX_EVIDENCE_FILES', 5),

    'allowed_evidence_extensions' => ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],

    'allowed_evidence_mimes' => [
        'application/pdf',
        'image/jpeg',
        'image/png',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ],

    // Image extensions that get re-encoded/compressed via Intervention Image
    // before being pushed to MinIO.
    'compressible_image_extensions' => ['jpg', 'jpeg', 'png'],

    // Submission ID format: {prefix_base}-{YYYY}-000001
    'submission_prefix_base' => env('LEP_SUBMISSION_PREFIX_BASE', 'LEP'),

    'logo_path' => 'assets/images/logo.png',
    'logo_alt' => 'Samagra Shiksha Nagaland – LEP',

];
