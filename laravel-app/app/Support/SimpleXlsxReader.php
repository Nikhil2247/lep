<?php

namespace App\Support;

use RuntimeException;
use ZipArchive;

/**
 * Lightweight .xlsx reader (no external dependencies), ported unchanged
 * from the legacy includes/SimpleXlsxReader.php. Reads the first worksheet
 * using ZipArchive + SimpleXML - sufficient for the simple tabular
 * District/Block/School/UDISE master file this reads.
 */
class SimpleXlsxReader
{
    private string $path;

    private array $sharedStrings = [];

    private array $rows = [];

    public function __construct(string $path)
    {
        if (! is_file($path) || ! is_readable($path)) {
            throw new RuntimeException('Excel file not found or not readable: '.$path);
        }
        if (! class_exists('ZipArchive')) {
            throw new RuntimeException('PHP ZipArchive extension is required to read .xlsx files.');
        }
        $this->path = $path;
        $this->parse();
    }

    /**
     * @return array[] Each row is a 0-indexed array of cell values (strings)
     */
    public function getRows(): array
    {
        return $this->rows;
    }

    private function parse(): void
    {
        $zip = new ZipArchive;
        if ($zip->open($this->path) !== true) {
            throw new RuntimeException('Unable to open .xlsx file as ZIP archive.');
        }

        $ssXml = $zip->getFromName('xl/sharedStrings.xml');
        if ($ssXml !== false) {
            $this->loadSharedStrings($ssXml);
        }

        $sheetPath = 'xl/worksheets/sheet1.xml';
        $wbXml = $zip->getFromName('xl/workbook.xml');
        if ($wbXml !== false) {
            $relsXml = $zip->getFromName('xl/_rels/workbook.xml.rels');
            if ($relsXml !== false) {
                $sheetPath = $this->resolveFirstSheetPath($wbXml, $relsXml) ?: $sheetPath;
            }
        }

        $sheetXml = $zip->getFromName($sheetPath);
        $zip->close();

        if ($sheetXml === false) {
            throw new RuntimeException('Worksheet XML not found inside the .xlsx file.');
        }

        $this->loadSheet($sheetXml);
    }

    private function loadSharedStrings(string $xml): void
    {
        $sx = @simplexml_load_string($xml);
        if ($sx === false) {
            return;
        }
        $sx->registerXPathNamespace('m', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main');
        foreach ($sx->xpath('//m:si') as $si) {
            $text = '';
            foreach ($si->xpath('.//m:t') as $t) {
                $text .= (string) $t;
            }
            $this->sharedStrings[] = $text;
        }
    }

    private function resolveFirstSheetPath(string $wbXml, string $relsXml): ?string
    {
        $wb = @simplexml_load_string($wbXml);
        $rels = @simplexml_load_string($relsXml);
        if ($wb === false || $rels === false) {
            return null;
        }
        $wb->registerXPathNamespace('m', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main');
        $wb->registerXPathNamespace('r', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships');
        $sheets = $wb->xpath('//m:sheets/m:sheet');
        if (! $sheets) {
            return null;
        }
        $rid = (string) $sheets[0]->attributes('r', true)['id'];
        $rels->registerXPathNamespace('pr', 'http://schemas.openxmlformats.org/package/2006/relationships');
        foreach ($rels->xpath('//pr:Relationship') as $rel) {
            if ((string) $rel['Id'] === $rid) {
                $target = (string) $rel['Target'];

                return 'xl/'.ltrim($target, '/');
            }
        }

        return null;
    }

    private function loadSheet(string $xml): void
    {
        $sx = @simplexml_load_string($xml);
        if ($sx === false) {
            throw new RuntimeException('Unable to parse worksheet XML.');
        }
        $sx->registerXPathNamespace('m', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main');

        $rows = $sx->xpath('//m:sheetData/m:row');
        if (! $rows) {
            return;
        }

        foreach ($rows as $row) {
            $cells = [];
            $maxCol = -1;
            foreach ($row->c as $c) {
                $ref = (string) $c['r'];
                $col = $this->colIndex($ref);
                $maxCol = max($maxCol, $col);
                $type = (string) $c['t'];
                $value = '';
                if (isset($c->v)) {
                    $raw = (string) $c->v;
                    if ($type === 's') {
                        $idx = (int) $raw;
                        $value = $this->sharedStrings[$idx] ?? '';
                    } else {
                        $value = $raw;
                    }
                } elseif (isset($c->is->t)) {
                    $value = (string) $c->is->t;
                }
                $cells[$col] = $value;
            }
            $rowArr = [];
            for ($i = 0; $i <= $maxCol; $i++) {
                $rowArr[$i] = $cells[$i] ?? '';
            }
            $this->rows[] = $rowArr;
        }
    }

    /** Convert cell ref like "C12" to 0-based column index */
    private function colIndex(string $ref): int
    {
        if (! preg_match('/^([A-Z]+)/i', $ref, $m)) {
            return 0;
        }
        $letters = strtoupper($m[1]);
        $n = 0;
        for ($i = 0, $len = strlen($letters); $i < $len; $i++) {
            $n = $n * 26 + (ord($letters[$i]) - 64);
        }

        return $n - 1;
    }
}
