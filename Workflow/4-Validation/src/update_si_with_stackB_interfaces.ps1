param(
    [string]$DocPathOverride
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$evRoot = Split-Path -Parent $scriptDir
$outputsDir = Join-Path $evRoot "outputs"
$docPath = if ([string]::IsNullOrWhiteSpace($DocPathOverride)) {
    Join-Path $outputsDir "SI_validation_section_AB_with_figures_clean_caseABC_final.docx"
}
else {
    $DocPathOverride
}
$figPath = Join-Path $outputsDir "si_validation_clean_figures\SX_validation_stackB_interfaces.png"

if (!(Test-Path -LiteralPath $docPath)) {
    throw "Document not found: $docPath"
}
if (!(Test-Path -LiteralPath $figPath)) {
    throw "Figure not found: $figPath"
}

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
    param(
        $Document,
        [string]$Pattern
    )
    for ($i = 1; $i -le $Document.Paragraphs.Count; $i++) {
        $para = $Document.Paragraphs.Item($i)
        $text = Normalize-Text $para.Range.Text
        if ($text -match $Pattern) {
            return $para
        }
    }
    throw "Paragraph pattern not found: $Pattern"
}

function Try-GetParagraphByPattern {
    param(
        $Document,
        [string]$Pattern
    )
    for ($i = 1; $i -le $Document.Paragraphs.Count; $i++) {
        $para = $Document.Paragraphs.Item($i)
        $text = Normalize-Text $para.Range.Text
        if ($text -match $Pattern) {
            return $para
        }
    }
    return $null
}

function Set-ParagraphText {
    param(
        $Paragraph,
        [string]$Text,
        [double]$FontSize = 10
    )
    $Paragraph.Range.Text = $Text
    $Paragraph.Range.ParagraphFormat.Alignment = 3
    Set-RangeRedTNR -Range $Paragraph.Range -FontSize $FontSize
}

function Set-CellText {
    param(
        $Table,
        [int]$Row,
        [int]$Column,
        [string]$Text
    )
    $cell = $Table.Cell($Row, $Column)
    $cell.Range.Text = $Text
    $cell.Range.ParagraphFormat.Alignment = 3
    Set-RangeRedTNR -Range $cell.Range -FontSize 10
}

$word = $null
$doc = $null
try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0
    $doc = $word.Documents.Open($docPath, $false, $false)

    $tableSX3 = $doc.Tables.Item(5)
    Set-CellText -Table $tableSX3 -Row 5 -Column 3 -Text "SX.4; Table SX5; Fig. SX2"
    Set-CellText -Table $tableSX3 -Row 6 -Column 3 -Text "SX.4; Table SX5; Fig. SX2"
    Set-CellText -Table $tableSX3 -Row 7 -Column 3 -Text "SX.4; Table SX5; Fig. SX3"

    $tableSupport = $doc.Tables.Item(8)
    Set-CellText -Table $tableSupport -Row 4 -Column 1 -Text "Stack B voltage, current-to-hydrogen conversion, static/dynamic interface propagation and module-boundary hydrogen production are quantitatively tested."

    $paraStackBChain = Get-ParagraphByPattern -Document $doc -Pattern "^The Stack B stack-to-module validation is reported as three increasingly strict checks"
    Set-ParagraphText -Paragraph $paraStackBChain -Text "The Stack B stack-to-module validation is reported as three increasingly strict checks, as mapped in Table SX3. The quasi-steady closure first isolates the field-derived static efficiency interface by converting measured DC power to hydrogen production without the full BOP state dynamics. The daily dynamic interface validation then applies the same interface to the complete 96-point day to test propagation under time-varying operation. Finally, the single-5MW full state-space validation includes the Fangshan BOP states and therefore tests the complete Stack B-to-module dynamic model. Fig. SX2 visualises the first two interface-level checks. These checks are complementary: they isolate the interface error, the time-varying propagation error and the full module-state error, respectively."

    $tableSX5 = $doc.Tables.Item(7)
    $standaloneTableSX5Caption = Try-GetParagraphByPattern -Document $doc -Pattern "^Table SX5\. Stack B efficiency-interface and hydrogen-production validation metrics\.$"
    if ($null -eq $standaloneTableSX5Caption) {
        $selection = $word.Selection
        $selection.SetRange($tableSX5.Range.Start, $tableSX5.Range.Start)
        $selection.ParagraphFormat.Alignment = 3
        $selection.Font.Name = "Times New Roman"
        $selection.Font.Size = 10
        $selection.Font.Color = 255
        $selection.TypeText("Table SX5. Stack B efficiency-interface and hydrogen-production validation metrics.")
        $selection.TypeParagraph()
    }

    $paraRetainedFigures = Get-ParagraphByPattern -Document $doc -Pattern "^Only the figures that directly support the validation chain are retained"
    Set-ParagraphText -Paragraph $paraRetainedFigures -Text "Only the figures that directly support the validation chain are retained. Fig. SX2 explicitly reports the two interface-level checks: the left panel shows the field-derived piecewise static interface together with measured and predicted steady-window efficiencies, and the right panel shows the daily dynamic interface replay against the measured 2023-11-05 hydrogen-production history. The raw outlet-temperature profile and raw Stack A voltage/current traces are not retained as figures to avoid duplicating the full-system closure or over-emphasising high-frequency cell-level noise."

    $paraFullStateCaption = Try-GetParagraphByPattern -Document $doc -Pattern "^Fig\. SX2\. Single-5MW full state-space hydrogen-rate validation"
    if ($null -ne $paraFullStateCaption) {
        Set-ParagraphText -Paragraph $paraFullStateCaption -Text "Fig. SX3. Single-5MW full state-space hydrogen-rate validation over the 2023-11-05 dynamic profile. The first 15 min point is excluded from the visual comparison and reported separately as an initialisation-sensitive point."
    }

    $paraStackACaption = Try-GetParagraphByPattern -Document $doc -Pattern "^Fig\. SX3\. Stack A rated-current current-distribution diagnostic"
    if ($null -ne $paraStackACaption) {
        Set-ParagraphText -Paragraph $paraStackACaption -Text "Fig. SX4. Stack A rated-current current-distribution diagnostic. The distributed-circuit model predicts the cell-wise electrolysis current distribution at the 7000 A operating point, using the Stack A structural parameters and the voltage relation fitted from effective electrolysis current. The experimental current is reconstructed from measured cell voltage and interpolated local temperature. The shaded band shows the local interquartile range of the reconstructed cell-level values, and the blue curve shows the adaptive local average used to compare the low-frequency spatial envelope. The comparison indicates a broadly similar edge-enhanced, core-reduced envelope, while the high-frequency channel-to-channel scatter is not used for point-by-point validation because direct per-cell current sensors are unavailable."
    }

    $existingInterfaceCaption = Try-GetParagraphByPattern -Document $doc -Pattern "^Fig\. SX2\. Stack B module-boundary efficiency-interface validation"
    if ($null -eq $existingInterfaceCaption) {
        $targetPara = Get-ParagraphByPattern -Document $doc -Pattern "^A separate single-5MW state-space model was then configured"
        $selection = $word.Selection
        $selection.SetRange($targetPara.Range.Start, $targetPara.Range.Start)

        $selection.ParagraphFormat.Alignment = 3
        $selection.Font.Name = "Times New Roman"
        $selection.Font.Size = 10
        $selection.Font.Color = 255
        $selection.TypeText("For the static interface, the window-wise stack LHV-efficiency MAE is 0.0173 and the hydrogen-rate MAE is 20.54 Nm^3 h^-1 across 73 accepted steady windows, while the cumulative hydrogen error is -0.126%. For the dynamic interface, replay of the complete 2023-11-05 96-point day gives a hydrogen-rate MAE of 39.84 Nm^3 h^-1 and a daily hydrogen error of -4.626%. Thus, the Stack B case can directly quantify the two module-boundary efficiency representations before the full Fangshan state-space model is introduced.")
        $selection.TypeParagraph()

        $selection.ParagraphFormat.Alignment = 1
        $picture = $selection.InlineShapes.AddPicture($figPath, $false, $true)
        $picture.LockAspectRatio = -1
        if ($picture.Width -gt 470) {
            $picture.Width = 470
        }
        $selection.TypeParagraph()

        $selection.ParagraphFormat.Alignment = 3
        $selection.Font.Name = "Times New Roman"
        $selection.Font.Size = 10
        $selection.Font.Color = 255
        $selection.TypeText("Fig. SX2. Stack B module-boundary efficiency-interface validation. Left: static interface derived from 73 accepted steady windows, shown as the field-derived piecewise load-efficiency map together with measured and predicted steady-window efficiencies. Right: dynamic interface replay over the complete 2023-11-05 96-point profile, comparing measured and interface-replayed hydrogen-production rates. These two panels isolate the static and dynamic efficiency interfaces before the full Fangshan single-5MW state-space validation in Fig. SX3.")
        $selection.TypeParagraph()
    }

    $doc.Save()
}
finally {
    if ($doc -ne $null) {
        $doc.Close([ref]$true) | Out-Null
    }
    if ($word -ne $null) {
        $word.Quit() | Out-Null
    }
}

Write-Output $docPath
