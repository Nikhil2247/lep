<?php

return [

    'default' => env('FILESYSTEM_DISK', 'minio'),

    'disks' => [

        'local' => [
            'driver' => 'local',
            'root' => storage_path('app/private'),
            'serve' => true,
            'throw' => false,
            'report' => false,
        ],

        'public' => [
            'driver' => 'local',
            'root' => storage_path('app/public'),
            'url' => env('APP_URL').'/storage',
            'visibility' => 'public',
            'throw' => false,
            'report' => false,
        ],

        // MinIO (S3-compatible object storage). Used for teacher evidence
        // uploads and master project documents - see App\Services\EvidenceUploadService
        // and App\Http\Controllers\ProjectDownloadController. Bucket ACLs stay
        // private; access control lives in application code instead - evidence
        // exports are streamed through a Laravel controller (auth-gated), and
        // project downloads redirect to a short-lived signed MinIO URL
        // (generated only after the is_active/path checks pass).
        'minio' => [
            'driver' => 's3',
            'key' => env('MINIO_KEY'),
            'secret' => env('MINIO_SECRET'),
            'region' => env('MINIO_REGION', 'us-east-1'),
            'bucket' => env('MINIO_BUCKET', 'lep'),
            'url' => env('MINIO_ENDPOINT'),
            'endpoint' => env('MINIO_ENDPOINT'),
            'use_path_style_endpoint' => env('MINIO_USE_PATH_STYLE_ENDPOINT', true),
            'visibility' => 'private',
            'throw' => true,
            'report' => false,
        ],

    ],

    'links' => [
        public_path('storage') => storage_path('app/public'),
    ],

];
