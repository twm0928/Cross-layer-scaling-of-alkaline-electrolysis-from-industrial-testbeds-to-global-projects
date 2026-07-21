param(
    [string]$DestinationDocOverride
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$evRoot = Split-Path -Parent $scriptDir
$outputs = Join-Path $evRoot "outputs"
$srcDocCandidates = @(
    (Join-Path $outputs "SI_validation_section_AB_with_figures_clean_caseABC_final_stackBinterfaces_fig23merged_v2.docx"),
    (Join-Path $outputs "SI_validation_section_AB_with_figures_clean_caseABC_final_stackBinterfaces_fig23merged.docx"),
    (Join-Path $outputs "SI_validation_section_AB_with_figures_clean_caseABC_final_stackBinterfaces.docx"),
    (Join-Path $outputs "SI_validation_section_AB_with_figures_clean_caseABC_final.docx"),
    (Join-Path $outputs "SI_validation_section_AB_with_figures_clean_caseABC_final_stackBinterfaces_fig23merged_final.docx")
)
$srcDoc = $srcDocCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($srcDoc)) {
    throw "No valid source SI document found in outputs."
}
$dstDoc = if ([string]::IsNullOrWhiteSpace($DestinationDocOverride)) {
    Join-Path $outputs "SI_validation_section_AB_with_figures_clean_caseABC_final_stackBinterfaces_fig23merged.docx"
}
else {
    $DestinationDocOverride
}
$fig2 = Join-Path $outputs "si_validation_clean_figures\SX_validation_stackB_interfaces.png"
$fig3 = Join-Path $outputs "si_validation_clean_figures\SX_validation_stackB_full_state_H2.png"

foreach ($p in @($srcDoc, $fig2, $fig3)) {
    if (!(Test-Path -LiteralPath $p)) {
        throw "Required file not found: $p"
    }
}

Copy-Item -LiteralPath $srcDoc -Destination $dstDoc -Force

function Normalize-Text {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return (($Text -replace "[`r`a]+", " ") -replace "\s+", " ").Trim()
}

function Set-RangeRedTNR {
    param(
        $Range,
        [double]$FontSize = 10
    )
    $Range.Font.Name = "Times New Roman"
    $Range.Font.Size = $FontSize
    $Range.Font.Color = 255
}

function Get-ParagraphByPattern {
    param($Document, [string]$Pattern)
    for ($i = 1; $i -le $Document.Paragraphs.Count; $i++) {
        $para = $Document.Paragraphs.Item($i)
        $text = Normalize-Text $para.Range.Text
        if ($text -match $Pattern) {
            return $para
        }
    }
    throw "Paragraph pattern not found: $Pattern"
}

function Set-ParagraphText {
    param($Paragraph, [string]$Text, [double]$FontSize = 10)
    $Paragraph.Range.Text = $Text + "`r"
    $Paragraph.Range.ParagraphFormat.Alignment = 3
    Set-RangeRedTNR -Range $Paragraph.Range -FontSize $FontSize
}

function Cleanup-ValidationParagraphs {
    param($Document)

    $splitToken = "A separate single-5MW state-space model was then configured"
    for ($i = $Document.Paragraphs.Count; $i -ge 1; $i--) {
        $para = $Document.Paragraphs.Item($i)
        $raw = $para.Range.Text
        $text = Normalize-Text $raw

        if ($text -eq "/") {
            $para.Range.Delete()
            continue
        }

        if ($raw -match "/[`r`a]*$") {
            $clean = $raw -replace "/[`r`a]*$", ""
            $para.Range.Text = $clean + "`r"
            Set-RangeRedTNR -Range $para.Range -FontSize 10
            $text = Normalize-Text $para.Range.Text
        }

        if ($text -like "Fig. SX2. Stack B static efficiency-interface validation.*$splitToken*") {
            $parts = $raw -split [regex]::Escape($splitToken), 2
            if ($parts.Count -eq 2) {
                $caption = (Normalize-Text $parts[0]).Trim()
                $follow = ($splitToken + " " + (Normalize-Text $parts[1])).Trim()
                $para.Range.Text = $caption + "`r" + $follow + "`r"
                Set-RangeRedTNR -Range $para.Range -FontSize 10
            }
        }
    }
}

$word = $null
$doc = $null
try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0
    $doc = $word.Documents.Open($dstDoc, $false, $false)

    if ($doc.InlineShapes.Count -lt 2) {
        throw "Expected at least 2 inline figures, found $($doc.InlineShapes.Count)"
    }

    $shape2Range = $doc.InlineShapes.Item(1).Range
    $doc.InlineShapes.Item(1).Delete()
    $new2 = $shape2Range.InlineShapes.AddPicture($fig2, $false, $true)
    $new2.LockAspectRatio = -1
    if ($new2.Width -gt 430) { $new2.Width = 430 }

    $shape3Range = $doc.InlineShapes.Item(2).Range
    $doc.InlineShapes.Item(2).Delete()
    $new3 = $shape3Range.InlineShapes.AddPicture($fig3, $false, $true)
    $new3.LockAspectRatio = -1
    if ($new3.Width -gt 430) { $new3.Width = 430 }

    $p = Get-ParagraphByPattern $doc "^The Stack B stack-to-module validation is reported as three increasingly strict checks"
    Set-ParagraphText $p "The Stack B stack-to-module validation is reported as three increasingly strict checks, as mapped in Table SX3. The quasi-steady closure first isolates the field-derived static efficiency interface by converting measured DC power to hydrogen production without the full BOP state dynamics. The second check is not a dynamic-efficiency model; instead, it directly replays the same static efficiency interface over the complete 96-point day, thereby quantifying the error incurred when a static efficiency representation is applied under time-varying operation without module/BOP states. Finally, the single-5MW full state-space validation includes the Fangshan BOP states and therefore tests the complete Stack B-to-module dynamic model. Fig. SX2 reports the static interface itself, whereas Fig. SX3 directly compares the static-interface replay with the full state-space model. These checks are complementary: they isolate the static interface error, the additional error introduced by applying a static interface under dynamic conditions, and the recovered dynamic closure, respectively."

    $p = Get-ParagraphByPattern $doc "^Fig\. SX2\. Stack B module-boundary efficiency-interface validation"
    Set-ParagraphText $p "Fig. SX2. Stack B static efficiency-interface validation. Grey circles show the measured steady windows, blue circles show the interface-predicted steady windows, and the coloured bin means show the field-derived piecewise interface points. The solid display curve is a smoothed visual guide of the field-derived static interface; the quantitative evaluation in Table SX5 still uses the original piecewise load-to-efficiency map."

    $p = Get-ParagraphByPattern $doc "^Fig\. SX3\. Single-5MW full state-space hydrogen-rate validation"
    Set-ParagraphText $p "Fig. SX3. Measured hydrogen-production history, static-interface replay, and full state-space module model over the 2023-11-05 dynamic profile. The first 15 min point is excluded from the plotted comparison. The dashed static-interface replay highlights the error introduced when the static efficiency interface is directly applied under dynamic operation without module/BOP dynamic states, whereas the solid full state-space model shows the recovered dynamic closure."

    $p = Get-ParagraphByPattern $doc "^Only the figures that directly support the validation chain are retained"
    Set-ParagraphText $p "Only the figures that directly support the validation chain are retained. Fig. SX2 focuses on the field-derived static interface itself and therefore avoids the visually misleading zig-zag produced by directly connecting sparse bin means. Fig. SX3 then overlays the static-interface replay and the full state-space model against the same measured 2023-11-05 profile, so the error of directly applying a static efficiency representation under dynamic operation, and the benefit of restoring module/BOP dynamic states, can both be seen directly. The raw outlet-temperature profile and raw Stack A voltage/current traces are not retained as figures to avoid duplicating the full-system closure or over-emphasising high-frequency cell-level noise."

    Cleanup-ValidationParagraphs $doc

    $doc.Save()
}
finally {
    if ($doc) {
        try { $doc.Close($false) | Out-Null } catch {}
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc)
    }
    if ($word) {
        try { $word.Quit() | Out-Null } catch {}
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($word)
    }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}

Write-Output $dstDoc
