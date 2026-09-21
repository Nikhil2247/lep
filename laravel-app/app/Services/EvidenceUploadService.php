<?php

namespace App\Services;

use App\Models\Cycle;
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
     * Compress (if an image) and push a validated file to MinIO under this
     * cycle's evidence prefix. Returns the stored object key.
     *
     * Cycle 1 keeps the legacy 'uploads/evidence/' prefix (saveEvidenceFile()
     * in the old includes/functions.php) - existing submission_evidence rows
     * already store file_path values in that exact shape. Cycle 2 onward use
     * 'uploads/cycle-{n}/evidence/' instead, so each cycle's evidence lives
     * in its own MinIO folder. See evidencePrefix().
     */
    public function store(UploadedFile $file, string $ext, string $submissionCode, int $index, Cycle $cycle): string
    {
        $folder = preg_replace('/[^A-Za-z0-9\-]/', '', $submissionCode);
        $safeName = 'evidence_'.($index + 1).'_'.bin2hex(random_bytes(4)).'.'.$ext;
        $key = $this->evidencePrefix($cycle)."/{$folder}/{$safeName}";

        $contents = in_array($ext, config('lep.compressible_image_extensions'), true)
            ? $this->compress($file, $ext)
            : file_get_contents($file->getRealPath());

        Storage::disk('minio')->put($key, $contents, ['visibility' => 'private']);

        return $key;
    }

    /**
     * Cycle 1 -> 'uploads/evidence' (unchanged, matches existing rows).
     * Cycle 2, 3, ... -> 'uploads/cycle-{n}/evidence', derived from the
     * cycle's name (e.g. "Cycle 2" -> 2) so a future Cycle 3 needs no code
     * change here.
     */
    private function evidencePrefix(Cycle $cycle): string
    {
        if ($cycle->name === 'Cycle 1') {
            return 'uploads/evidence';
        }

        $number = preg_replace('/[^0-9]/', '', $cycle->name);
        $number = $number !== '' ? $number : (string) $cycle->id;

        return "uploads/cycle-{$number}/evidence";
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
