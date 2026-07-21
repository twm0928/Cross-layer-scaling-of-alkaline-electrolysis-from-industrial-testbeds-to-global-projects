$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$evRoot = Split-Path -Parent $scriptDir
$outputs = Join-Path $evRoot "outputs"
$figDir = Join-Path $outputs "si_validation_clean_figures"

$src = Join-Path $scriptDir "templates\SI_validation_section_AB_template.docx"
$dst = Join-Path $outputs "SI_validation_section_AB_with_figures_clean.docx"

function Test-FileLocked($path) {
    if (!(Test-Path -LiteralPath $path)) { return $false }
    $stream = $null
    try {
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        return $false
    } catch {
        return $true
    } finally {
        if ($stream -ne $null) { $stream.Close() }
    }
}

if (!(Test-Path -LiteralPath $src)) {
    throw "Input Word file not found: $src"
}

if ((Test-Path -LiteralPath $dst) -and (Test-FileLocked $dst)) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $dst = Join-Path $outputs ("SI_validation_section_AB_with_figures_clean_" + $stamp + ".docx")
}

Copy-Item -LiteralPath $src -Destination $dst -Force

$figA1 = Join-Path $figDir "SX_validation_stackB_voltage.png"
$figA2 = Join-Path $figDir "SX_validation_stackB_full_state_H2.png"
$figB = Join-Path $figDir "SX_validation_stackA_current_distribution_envelope.png"
foreach ($p in @($figA1, $figA2, $figB)) {
    if (!(Test-Path -LiteralPath $p)) {
        throw "Required figure not found: $p"
    }
}

function Replace-All($doc, $oldText, $newText) {
    $range = $doc.Content
    $find = $range.Find
    $find.ClearFormatting()
    $find.Replacement.ClearFormatting()
    $find.Text = $oldText
    $find.Replacement.Text = $newText
    $find.Forward = $true
    $find.Wrap = 1 # wdFindContinue
    $find.Format = $false
    $find.MatchCase = $false
    $find.MatchWholeWord = $false
    $find.MatchWildcards = $false
    $find.Execute([ref]$oldText, [ref]$false, [ref]$false, [ref]$false, [ref]$false, [ref]$false, [ref]$true, [ref]1, [ref]$false, [ref]$newText, [ref]2) | Out-Null
}

function Find-Range($doc, $text) {
    $range = $doc.Content
    $find = $range.Find
    $find.ClearFormatting()
    $find.Text = $text
    $find.Forward = $true
    $find.Wrap = 0 # wdFindStop
    $find.Format = $false
    if ($find.Execute()) {
        return $range.Duplicate
    }
    return $null
}

function Add-Para($sel, $text, $size = 11, $bold = $false, $italic = $false) {
    $sel.Font.Name = "Times New Roman"
    $sel.Font.Size = $size
    $sel.Font.Bold = [int]$bold
    $sel.Font.Italic = [int]$italic
    $sel.TypeText($text)
    $sel.TypeParagraph()
    $sel.Font.Bold = 0
    $sel.Font.Italic = 0
}

function Add-Figure($doc, $sel, $path, $caption) {
    $shape = $sel.InlineShapes.AddPicture($path, $false, $true)
    if ($shape.Width -gt 430) {
        $shape.Width = 430
    }
    # Keep the caption immediately after the inserted inline figure. Do not use EndKey,
    # which jumps to the end of the Word story and separates figures from SX.6.
    $shape.Range.Select()
    $sel = $doc.Application.Selection
    $sel.Collapse(0) | Out-Null # wdCollapseEnd
    $sel.TypeParagraph()
    Add-Para $sel $caption 10 $false $false
    $sel.TypeParagraph()
}

function Set-CellText($table, $row, $col, $text, $bold = $false) {
    $cell = $table.Cell($row, $col)
    $range = $cell.Range
    $range.End = $range.End - 1
    $range.Text = $text
    $range.Font.Name = "Times New Roman"
    $range.Font.Size = 10
    $range.Font.Bold = [int]$bold
}

function Update-Table9CurrentEfficiency($doc) {
    if ($doc.Tables.Count -lt 9) {
        throw "Expected at least 9 tables in SI validation template."
    }
    $table = $doc.Tables.Item(9)
    $rows = @(
        @("Diagnostic item", "Metric", "Value"),
        @("Stable-window filtering", "Accepted 15 min windows", "9"),
        @("Stable-window filtering", "Load-fraction range", "0.302-1.001"),
        @("7000 A cell-resolved segment", "Mean rectifier current", "7003.9 A"),
        @("7000 A cell-resolved segment", "Valid cell-voltage channels", "363"),
        @("Voltage-temperature current inference", "Inferred eta_I, raw valid-channel mean", "0.859"),
        @("Voltage-temperature current inference", "Inferred eta_I, adaptive local-average mean", "0.871"),
        @("Distributed-circuit current-efficiency prediction", "Modelled eta_I at 7000 A", "0.878"),
        @("Model-vs-experiment current-efficiency error", "Deviation from raw inferred eta_I", "+0.019 p.u."),
        @("Model-vs-experiment current-efficiency error", "Deviation from adaptive inferred eta_I", "+0.007 p.u.")
    )
    while ($table.Rows.Count -lt $rows.Count) {
        $table.Rows.Add() | Out-Null
    }
    while ($table.Rows.Count -gt $rows.Count) {
        $table.Rows.Item($table.Rows.Count).Delete()
    }
    for ($r = 0; $r -lt $rows.Count; $r++) {
        for ($c = 0; $c -lt 3; $c++) {
            Set-CellText $table ($r + 1) ($c + 1) $rows[$r][$c] ($r -eq 0)
        }
    }
}

function Update-Table6HydrogenMetrics($doc) {
    if ($doc.Tables.Count -lt 6) {
        throw "Expected at least 6 tables in SI validation template."
    }
    $table = $doc.Tables.Item(6)
    $rows = @(
        @("Validation step", "Integral hydrogen-production metric", "Value"),
        @("Stack-to-module quasi-steady closure", "Cumulative H2 relative error", "-0.126%"),
        @("2023-11-05 dynamic interface validation", "Daily H2 relative error", "-4.626%"),
        @("Single-5MW full state-space validation", "Full-day H2 relative error", "-0.681%"),
        @("Single-5MW full state-space validation, excluding first 15 min", "Daily H2 relative error", "+0.694%")
    )
    while ($table.Rows.Count -lt $rows.Count) {
        $table.Rows.Add() | Out-Null
    }
    while ($table.Rows.Count -gt $rows.Count) {
        $table.Rows.Item($table.Rows.Count).Delete()
    }
    for ($r = 0; $r -lt $rows.Count; $r++) {
        for ($c = 0; $c -lt 3; $c++) {
            Set-CellText $table ($r + 1) ($c + 1) $rows[$r][$c] ($r -eq 0)
        }
    }
}

function Update-Table4StackAWorkflow($doc) {
    if ($doc.Tables.Count -lt 4) {
        throw "Expected at least 4 tables in SI validation template."
    }
    $table = $doc.Tables.Item(4)
    while ($table.Columns.Count -lt 5) {
        $table.Columns.Add() | Out-Null
    }
    $rows = @(
        @("Step", "Validation target", "Reported in", "Key quantitative output", "Role in validation chain"),
        @("A1", "Stack B / Fangshan object and field-data alignment", "SX.1; Table SX2", "Single 5 MW Stack B with one-to-one Fangshan BOP; 15 min aligned PLC data", "Defines the industrial object and input data used by all subsequent Stack B checks."),
        @("A2", "Stack-voltage interface", "SX.3; Table SX4; Fig. SX1", "Independent-window voltage MAPE = 0.903%; RMSE = 15.55 mV cell-1", "Checks whether the stack voltage relation can reproduce measured voltage before it is used in efficiency propagation."),
        @("A3", "Current-to-hydrogen and stack-efficiency interface", "SX.3; text immediately after Table SX4", "73 pressure/flow-stable H2 windows; mean eta_I = 0.7726", "Checks whether measured current and hydrogen flow support the current-efficiency component of the stack interface."),
        @("A4", "Quasi-steady stack-to-module closure", "SX.4; Table SX5", "Cumulative H2 error = -0.126%", "Isolates the field-derived stack efficiency interface by converting measured DC power to hydrogen production without full BOP state dynamics."),
        @("A5", "Daily dynamic interface propagation", "SX.4; Table SX5", "2023-11-05 daily H2 error = -4.626%", "Applies the same interface to a full 96-point day to test propagation under time-varying operation."),
        @("A6", "Single-5MW full state-space module validation", "SX.4; Table SX5; Fig. SX2", "Full-day H2 error = -0.681%; excluding first 15 min: +0.694%", "Tests the complete Stack B plus Fangshan BOP state-space representation, including module-level dynamic states.")
    )
    while ($table.Rows.Count -lt $rows.Count) {
        $table.Rows.Add() | Out-Null
    }
    while ($table.Rows.Count -gt $rows.Count) {
        $table.Rows.Item($table.Rows.Count).Delete()
    }
    for ($r = 0; $r -lt $rows.Count; $r++) {
        for ($c = 0; $c -lt 5; $c++) {
            Set-CellText $table ($r + 1) ($c + 1) $rows[$r][$c] ($r -eq 0)
        }
    }
}

function Delete-CaptionAndTable($doc, $captionText, $tableIndex) {
    $captionRange = Find-Range $doc $captionText
    if ($null -eq $captionRange) {
        throw "Could not locate caption for deletion: $captionText"
    }
    if ($doc.Tables.Count -lt $tableIndex) {
        throw "Could not locate table index $tableIndex for deletion."
    }
    $captionPara = $captionRange.Paragraphs.Item(1).Range
    $tableRange = $doc.Tables.Item($tableIndex).Range
    $deleteRange = $doc.Range($captionPara.Start, $tableRange.End)
    $deleteRange.Delete() | Out-Null
}

function Replace-ParagraphContaining($doc, $needle, $newText) {
    for ($i = 1; $i -le $doc.Paragraphs.Count; $i++) {
        $paraRange = $doc.Paragraphs.Item($i).Range
        $text = $paraRange.Text
        if ($text -like ("*" + $needle + "*")) {
            $paraRange.End = $paraRange.End - 1
            $paraRange.Text = $newText
            $paraRange.Font.Name = "Times New Roman"
            $paraRange.Font.Size = 11
            return $true
        }
    }
    return $false
}

function Renumber-TableCaptionsAfterPruning($doc) {
    $replacements = @(
        @("Table SX10.", "__TABLE_SX8__."),
        @("Table SX9.", "__TABLE_SX7__."),
        @("Table SX8.", "__TABLE_SX6__."),
        @("Table SX6.", "__TABLE_SX5__."),
        @("Table SX5.", "__TABLE_SX4__."),
        @("Table SX4.", "__TABLE_SX3__."),
        @("__TABLE_SX8__.", "Table SX8."),
        @("__TABLE_SX7__.", "Table SX7."),
        @("__TABLE_SX6__.", "Table SX6."),
        @("__TABLE_SX5__.", "Table SX5."),
        @("__TABLE_SX4__.", "Table SX4."),
        @("__TABLE_SX3__.", "Table SX3.")
    )
    foreach ($item in $replacements) {
        Replace-All $doc $item[0] $item[1]
    }
}

function Insert-ParagraphBefore($doc, $anchorText, $newText) {
    $anchorRange = Find-Range $doc $anchorText
    if ($null -eq $anchorRange) {
        throw "Could not locate paragraph anchor: $anchorText"
    }
    $para = $anchorRange.Paragraphs.Item(1).Range
    $insertRange = $doc.Range($para.Start, $para.Start)
    $insertRange.InsertBefore($newText + [Environment]::NewLine)
    $insertRange.Font.Name = "Times New Roman"
    $insertRange.Font.Size = 11
}

$word = $null
$doc = $null
try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0
    $doc = $word.Documents.Open($dst, $false, $false)

    Replace-All $doc "0.114 p.u." "0.158 p.u."
    Replace-All $doc "0.096 p.u." "0.158 p.u."
    Replace-All $doc "0.079 p.u." "0.158 p.u."
    Replace-All $doc "0.061 p.u." "0.158 p.u."
    Replace-All $doc "0.249 p.u." "0.158 p.u."
    Replace-All $doc "0.518" "0.473"
    $templateStackC = "Stack " + "A"
    $templateStackD = "Stack " + "B"
    Replace-All $doc $templateStackC "Stack A"
    Replace-All $doc $templateStackD "Stack B"
    Replace-All $doc "Stack Ahanges" "tested stack changes"
    Replace-All $doc "20 MW segmented-Stack Besigns" "20 MW segmented-stack designs"
    Replace-All $doc "20 MW segmented- Stack B esigns" "20 MW segmented-stack designs"
    Replace-All $doc "Figures that only document raw Stack B hydrogen-flow closure or duplicate the spatial diagnostic are omitted from the main SI validation narrative." "Only the figures that directly support the validation chain are retained below: Stack A voltage validation, Stack A full-system hydrogen-production closure, and Stack B current-distribution envelope comparison."

    Update-Table6HydrogenMetrics $doc
    Update-Table4StackAWorkflow $doc
    Update-Table9CurrentEfficiency $doc
    Replace-All $doc "Table SX6. Stack-to-module closure metrics using the  Stack A  interface." "Table SX6. Stack A hydrogen-production validation metrics."
    Replace-All $doc "Table SX9. Key  Stack B  diagnostic metrics." "Table SX9. Stack B voltage-inferred current-efficiency diagnostic metrics."
    Replace-ParagraphContaining $doc "The accepted process windows are used to fit" "For Stack B, the primary quantitative comparison is based on the cell-voltage and temperature measurements. In the 7000 A steady segment, the measured cell voltage and interpolated local temperature are used to reconstruct an equivalent electrolysis-current distribution, and its mean current efficiency is compared with the distributed-circuit model prediction. Hydrogen-flow closure is retained only as a secondary consistency check and is not used as the main model-experiment comparison in Table SX7." | Out-Null
    Replace-ParagraphContaining $doc "supports the existence" "The Stack B diagnostic provides an independent consistency check for the current-efficiency magnitude predicted by the stack model through voltage-temperature-inferred equivalent current. The cell-resolved field also provides an envelope-level consistency check for spatial non-uniformity, because direct per-cell current measurements are unavailable." | Out-Null
    Delete-CaptionAndTable $doc "Table SX7." 7
    Delete-CaptionAndTable $doc "Table SX3." 3
    Renumber-TableCaptionsAfterPruning $doc
    Replace-ParagraphContaining $doc "Condensed" "Table SX3. Stack A validation workflow and traceability to reported evidence." | Out-Null
    Replace-ParagraphContaining $doc "Stack-to-module closure metrics" "Table SX5. Stack A hydrogen-production validation metrics." | Out-Null
    Replace-ParagraphContaining $doc "diagnostic metrics" "Table SX7. Stack B voltage-inferred current-efficiency diagnostic metrics." | Out-Null
    Replace-ParagraphContaining $doc "The module-boundary closure maps measured DC power" "The Stack A stack-to-module validation is reported as three increasingly strict checks, as mapped in Table SX3. The quasi-steady closure first isolates the field-derived stack efficiency interface by converting measured DC power to hydrogen production without the full BOP state dynamics. The daily dynamic interface validation then applies the same interface to the complete 96-point day to test propagation under time-varying operation. Finally, the single-5MW full state-space validation includes the Fangshan BOP states and therefore tests the complete Stack A-to-module dynamic model. These checks are complementary: they isolate the interface error, the time-varying propagation error and the full module-state error, respectively." | Out-Null
    Insert-ParagraphBefore $doc "SX.6 Validation figures" "Overall, the validation chain gives three quantitative checks. First, the Stack A voltage model reproduces independent test windows with a MAPE of 0.903% (15.55 mV cell-1 RMSE), supporting the voltage interface used at the stack layer. Second, the Stack B voltage-temperature-inferred current efficiency at the 7000 A segment is 0.859 using the raw valid-channel mean and 0.871 using the adaptive local-average mean, while the distributed-circuit model predicts 0.878; the corresponding deviations are +0.019 p.u. and +0.007 p.u., respectively. Third, after propagating the validated Stack A interface to the Fangshan BOP, the stack-to-module hydrogen-production closure is evaluated using integral hydrogen output: the quasi-steady cumulative H2 error is -0.126%, the dynamic 2023-11-05 interface-level daily H2 error is -4.626%, and the single-5MW full state-space model gives a full-day H2 error of -0.681% or +0.694% after excluding the first 15 min initialisation-sensitive point."

    $startRange = Find-Range $doc "SX.6 Validation figures"
    $endRange = Find-Range $doc "SX.7 Validation claims and boundaries"
    if ($null -eq $startRange -or $null -eq $endRange) {
        throw "Could not locate SX.6/SX.7 section boundaries."
    }
    if ($endRange.Start -le $startRange.Start) {
        throw "Invalid section boundary order."
    }

    $deleteRange = $doc.Range($startRange.Start, $endRange.Start)
    $deleteRange.Select()
    $sel = $word.Selection
    $sel.Delete() | Out-Null

    Add-Para $sel "SX.6 Validation figures" 13 $true $false
    Add-Para $sel "Only the figures that directly support the validation chain are retained. The field-derived efficiency curve is reported numerically rather than as a connected line plot because the sparse field windows make the piecewise curve visually jagged. The intermediate interface-only hydrogen profile, the outlet-temperature profile, and raw Stack B voltage/current traces are not retained as figures to avoid duplicating the full-system closure or over-emphasising high-frequency cell-level noise."

    Add-Figure $doc $sel $figA1 "Fig. SX1. Stack A voltage validation. Predicted stack voltage is compared with measured stack voltage for the accepted training and independent test windows. The independent-window MAPE is 0.903%."
    Add-Figure $doc $sel $figA2 "Fig. SX2. Single-5MW full state-space hydrogen-rate validation over the 2023-11-05 dynamic profile. The first 15 min point is excluded from the visual comparison and reported separately as an initialisation-sensitive point."
    Add-Figure $doc $sel $figB "Fig. SX3. Stack B rated-current current-distribution diagnostic. The distributed-circuit model predicts the cell-wise electrolysis current distribution at the 7000 A operating point, using the Stack B structural parameters and the voltage relation fitted from effective electrolysis current. The experimental current is reconstructed from measured cell voltage and interpolated local temperature. The shaded band shows the local interquartile range of the reconstructed cell-level values, and the blue curve shows the adaptive local average used to compare the low-frequency spatial envelope. The comparison indicates a broadly similar edge-enhanced, core-reduced envelope, while the high-frequency channel-to-channel scatter is not used for point-by-point validation because direct per-cell current sensors are unavailable."

    $doc.Save()
}
finally {
    if ($doc -ne $null) { $doc.Close($false) | Out-Null }
    if ($word -ne $null) { $word.Quit() | Out-Null }
}

Write-Output $dst
