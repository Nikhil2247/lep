<?php

namespace App\Http\Controllers;

use App\Models\Project;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Storage;
use Throwable;

/**
 * Ports download_project.php - project PDFs now live in MinIO (the 'minio'
 * disk) instead of the local filesystem, so the path-traversal guard
 * becomes an object-key prefix check instead of a realpath() comparison.
 * The existing production DB already stores project_file values as
 * 'uploads/projects/{name}.pdf' (see database/LEP_V2_Production.sql) -
 * that exact prefix is kept as the MinIO object key so no data migration
 * of the projects table is needed.
 */
class ProjectDownloadController extends Controller
{
    public function show(int $id): RedirectResponse
    {
        $project = Project::where('id', $id)->where('is_active', 1)->first();

        if (! $project || empty($project->project_file)) {
            abort(404, 'Project document not found.');
        }

        $key = ltrim(str_replace('\\', '/', $project->project_file), '/');

        // Must stay under the uploads/projects/ prefix - guards against a
        // bad/edited DB value ever letting this endpoint serve an arbitrary object.
        if (str_contains($key, '..') || ! str_starts_with($key, 'uploads/projects/')) {
            abort(404, 'File is missing on the server. Please contact the administrator.');
        }

        $disk = Storage::disk('minio');
        $filename = basename($key);

        // MinIO is reachable on a public URL, so redirect straight to a
        // short-lived signed link instead of proxying the file through
        // php-fpm - the browser downloads from MinIO directly, which is far
        // faster than streaming the whole file through a PHP worker. Access
        // stays controlled: the link is only generated after the is_active/
        // path checks above, and expires in 5 minutes.
        try {
            $url = $disk->temporaryUrl($key, now()->addMinutes(5), [
                'ResponseContentDisposition' => 'attachment; filename="'.$filename.'"',
            ]);
        } catch (Throwable $e) {
            abort(404, 'File is missing on the server. Please contact the administrator.');
        }

        return redirect()->away($url);
    }
}
