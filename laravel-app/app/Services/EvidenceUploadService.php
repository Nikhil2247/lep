<?php

namespace App\Services;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Intervention\Image\Drivers\Gd\Driver as GdDriver;
use Intervention\Image\Drivers\Imagick\Driver as ImagickDriver;
use Intervention\Image\ImageManager;

/**
 * Ports validateEvidenceFile()/saveEvidenceFile() from the legacy
 * includes/functions.php, with two changes: files are stored in MinIO
 * (via the 'minio' filesystem disk) instead of the local uploads/ folder,
 * and jpg/png images are re-encoded through Intervention Image before
 * upload (the PHP-native equivalent of Sharp) to shrink file size.
 */
class EvidenceUploadService
{
    private ImageManager $images;

    public function __construct()
    {
        $driver = extension_loaded('imagick') ? new ImagickDriver() : new GdDriver();
        $this->images = new ImageManager($driver);
    }

    /**
     * @return array{ok: bool, error?: string, ext?: string}
     */
    public function validate(UploadedFile $file): array
    {
        if (! $file->isValid()) {
            return ['ok' => false, 'error' => 'Upload error code: '.$file->getError()];
        }

        // Single file must not exceed the total budget (same rule as the legacy app).
        if ($file->getSize() > config('lep.max_evidence_total_size')) {
            return ['ok' => false, 'error' => 'File exceeds the maximum allowed size of 5 MB.'];
        }

        $ext = strtolower((string) pathinfo($file->getClientOriginalName(), PATHINFO_EXTENSION));
        if (! in_array($ext, config('lep.allowed_evidence_extensions'), true)) {
            return [
                'ok' => false,
                'error' => 'Invalid file type. Allowed: '.implode(', ', config('lep.allowed_evidence_extensions')),
            ];
        }

        $mime = $file->getMimeType();
        if (! in_array($mime, config('lep.allowed_evidence_mimes'), true)) {
            return ['ok' => false, 'error' => 'Invalid file content type.'];
        }

        return ['ok' => true, 'ext' => $ext];
    }

    /**
     * Compress (if an image) and push a validated file to MinIO under
     * uploads/evidence/{submission_id}/. Returns the stored object key.
     *
     * The 'uploads/evidence/' prefix matches the legacy saveEvidenceFile()
     * convention (includes/functions.php) - any submission_evidence rows
     * that already exist in the production DB store file_path values in
     * that exact shape, so new rows keep using it too.
     */
    public function store(UploadedFile $file, string $ext, string $submissionCode, int $index): string
    {
        $folder = preg_replace('/[^A-Za-z0-9\-]/', '', $submissionCode);
        $safeName = 'evidence_'.($index + 1).'_'.bin2hex(random_bytes(4)).'.'.$ext;
        $key = "uploads/evidence/{$folder}/{$safeName}";

        $contents = in_array($ext, config('lep.compressible_image_extensions'), true)
            ? $this->compress($file, $ext)
            : file_get_contents($file->getRealPath());

        Storage::disk('minio')->put($key, $contents, ['visibility' => 'private']);

        return $key;
    }

    private function compress(UploadedFile $file, string $ext): string
    {
        $image = $this->images->read($file->getRealPath());

        // Never upscale; cap the long edge for typical phone-camera evidence photos.
        $image = $image->scaleDown(width: 1920, height: 1920);

        return (string) match ($ext) {
            'png' => $image->toPng(),
            default => $image->toJpeg(quality: 75),
        };
    }
}
