<?php
/**
 * Minimal XLSX writer (Office Open XML) – no external dependencies.
 * Requires PHP ZipArchive extension.
 */
declare(strict_types=1);

class SimpleXlsxWriter
{
    /** @var list<list<string|int|float|null>> */
    private array $rows = [];
    private string $sheetName;

    public function __construct(string $sheetName = 'Submissions')
    {
        $this->sheetName = $this->safeSheetName($sheetName);
    }

    /** @param list<string|int|float|null> $row */
    public function addRow(array $row): void
    {
        $this->rows[] = $row;
    }

    /**
     * Stream download headers and file body, then exit.
     */
    public function download(string $filename): void
    {
        if (!class_exists('ZipArchive')) {
            throw new RuntimeException(
                'PHP ZipArchive extension is required to generate Excel (.xlsx) files. ' .
                'Please enable the zip extension on the server.'
            );
        }

        $tmp = tempnam(sys_get_temp_dir(), 'lep_xlsx_');
        if ($tmp === false) {
            throw new RuntimeException('Unable to create temporary file for Excel export.');
        }
        $xlsx = $tmp . '.xlsx';
        @unlink($tmp);

        $this->buildFile($xlsx);

        $safeName = preg_replace('/[^\w.\- ()]+/', '_', $filename) ?: 'LEP_Export.xlsx';
        header('Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        header('Content-Disposition: attachment; filename="' . $safeName . '"');
        header('Content-Length: ' . (string)filesize($xlsx));
        header('Cache-Control: max-age=0, no-cache, must-revalidate, private');
        header('Pragma: public');
        readfile($xlsx);
        @unlink($xlsx);
        exit;
    }

    private function buildFile(string $path): void
    {
        $zip = new ZipArchive();
        if ($zip->open($path, ZipArchive::CREATE | ZipArchive::OVERWRITE) !== true) {
            throw new RuntimeException('Unable to create XLSX archive.');
        }

        $zip->addFromString('[Content_Types].xml', $this->contentTypes());
        $zip->addFromString('_rels/.rels', $this->rootRels());
        $zip->addFromString('xl/workbook.xml', $this->workbook());
        $zip->addFromString('xl/_rels/workbook.xml.rels', $this->workbookRels());
        $zip->addFromString('xl/styles.xml', $this->styles());
        $zip->addFromString('xl/worksheets/sheet1.xml', $this->sheetXml());
        $zip->close();
    }

    private function contentTypes(): string
    {
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            . '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            . '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            . '<Default Extension="xml" ContentType="application/xml"/>'
            . '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            . '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            . '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
            . '</Types>';
    }

    private function rootRels(): string
    {
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            . '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            . '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
            . '</Relationships>';
    }

    private function workbook(): string
    {
        $name = $this->xml($this->sheetName);
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            . '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            . 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            . '<sheets><sheet name="' . $name . '" sheetId="1" r:id="rId1"/></sheets>'
            . '</workbook>';
    }

    private function workbookRels(): string
    {
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            . '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            . '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
            . '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
            . '</Relationships>';
    }

    private function styles(): string
    {
        // style 0 = default, style 1 = bold header + wrap, style 2 = wrap text
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            . '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            . '<fonts count="2">'
            . '<font><sz val="11"/><name val="Calibri"/></font>'
            . '<font><b/><sz val="11"/><name val="Calibri"/></font>'
            . '</fonts>'
            . '<fills count="2">'
            . '<fill><patternFill patternType="none"/></fill>'
            . '<fill><patternFill patternType="gray125"/></fill>'
            . '</fills>'
            . '<borders count="1"><border/></borders>'
            . '<cellStyleXfs count="1"><xf/></cellStyleXfs>'
            . '<cellXfs count="3">'
            . '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>'
            . '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" applyFont="1" applyAlignment="1">'
            . '<alignment wrapText="1" vertical="top"/></xf>'
            . '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" applyAlignment="1">'
            . '<alignment wrapText="1" vertical="top"/></xf>'
            . '</cellXfs>'
            . '</styleSheet>';
    }

    private function sheetXml(): string
    {
        $colCount = 0;
        foreach ($this->rows as $row) {
            $colCount = max($colCount, count($row));
        }
        if ($colCount < 1) {
            $colCount = 1;
        }

        // Approximate widths: first 13 fixed-ish, task cols wider
        $colsXml = '<cols>';
        for ($c = 1; $c <= $colCount; $c++) {
            $width = ($c <= 7) ? 16 : (($c <= 13) ? 22 : 36);
            $colsXml .= '<col min="' . $c . '" max="' . $c . '" width="' . $width . '" customWidth="1"/>';
        }
        $colsXml .= '</cols>';

        $sheetData = '<sheetData>';
        foreach ($this->rows as $rIdx => $row) {
            $r = $rIdx + 1;
            $style = ($rIdx === 0) ? 1 : 2;
            $sheetData .= '<row r="' . $r . '" ht="45" customHeight="1">';
            foreach ($row as $cIdx => $value) {
                $cellRef = $this->colLetter($cIdx + 1) . $r;
                $text = $this->xml((string)($value ?? ''));
                // shared inline string
                $sheetData .= '<c r="' . $cellRef . '" t="inlineStr" s="' . $style . '">'
                    . '<is><t xml:space="preserve">' . $text . '</t></is></c>';
            }
            $sheetData .= '</row>';
        }
        $sheetData .= '</sheetData>';

        $lastCol = $this->colLetter($colCount);
        $lastRow = max(1, count($this->rows));
        $ref = 'A1:' . $lastCol . $lastRow;

        $autoFilter = count($this->rows) > 0
            ? '<autoFilter ref="' . $ref . '"/>'
            : '';

        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            . '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            . 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            . $colsXml
            . $sheetData
            . $autoFilter
            . '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
            . '</worksheet>';
    }

    private function colLetter(int $index): string
    {
        $name = '';
        while ($index > 0) {
            $index--;
            $name = chr(65 + ($index % 26)) . $name;
            $index = intdiv($index, 26);
        }
        return $name;
    }

    private function xml(string $value): string
    {
        return htmlspecialchars($value, ENT_QUOTES | ENT_XML1, 'UTF-8');
    }

    private function safeSheetName(string $name): string
    {
        $name = str_replace(['\\', '/', '?', '*', '[', ']'], '', $name);
        $name = mb_substr($name, 0, 31);
        return $name !== '' ? $name : 'Sheet1';
    }
}
