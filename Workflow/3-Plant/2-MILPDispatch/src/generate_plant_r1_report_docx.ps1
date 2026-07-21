$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$reportDir = Join-Path $root 'report'
$htmlPath = Join-Path $reportDir 'plant_dynamic_closed_loop_report_v1.html'
$docxPath = Join-Path $reportDir 'plant_dynamic_closed_loop_report_v1.docx'

$word = $null
$doc = $null

try {
    if (Test-Path -LiteralPath $docxPath) {
        Remove-Item -LiteralPath $docxPath -Force
    }

    $saveFormat = 16
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0
    $doc = $word.Documents.Open($htmlPath, $false, $true)
    $doc.SaveAs([string]$docxPath, [ref]$saveFormat)
}
finally {
    if ($doc -ne $null) { $doc.Close($false) | Out-Null }
    if ($word -ne $null) { $word.Quit() | Out-Null }
}

Write-Output $docxPath
