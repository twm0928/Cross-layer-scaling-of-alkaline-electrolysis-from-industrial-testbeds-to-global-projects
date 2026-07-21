$ErrorActionPreference = "Stop"

<#
.SYNOPSIS
Create an editable Excel plotting workbook for revised Fig. 2b.

.DESCRIPTION
This script reads the curated Fig. 2b wide CSV exported by the stack
workflow, builds a clean Excel workbook with a plot-ready sheet, creates
an embedded Excel chart, and exports the chart preview as PNG.

The script is path-portable within the R1 workspace: paths are resolved
relative to this script location under Workflow/1-Stack/src.
#>

function Get-RgbInt {
    param(
        [int]$R,
        [int]$G,
        [int]$B
    )
    return $R + ($G * 256) + ($B * 65536)
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Log-Step {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$stamp] $Message"
    Write-Host $line
    if (-not [string]::IsNullOrWhiteSpace($script:LogPath)) {
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
    }
}

function Convert-ExcelValue {
    param(
        $Value
    )
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    $number = 0.0
    if ([double]::TryParse([string]$Value, [ref]$number)) {
        return $number
    } else {
        return [string]$Value
    }
}

function Get-ExcelColumnName {
    param([int]$ColumnNumber)
    $name = ""
    while ($ColumnNumber -gt 0) {
        $mod = ($ColumnNumber - 1) % 26
        $name = [char](65 + $mod) + $name
        $ColumnNumber = [math]::Floor(($ColumnNumber - $mod) / 26)
    }
    return $name
}

function Set-RangeArray {
    param(
        $Sheet,
        [object[,]]$Data
    )
    $rowCount = $Data.GetLength(0)
    $colCount = $Data.GetLength(1)
    $lastCol = Get-ExcelColumnName $colCount
    $range = $Sheet.Range("A1:$lastCol$rowCount")
    $range.Value2 = $Data
    return $range
}

function Add-Series {
    param(
        $Chart,
        [string]$Name,
        $XRange,
        $YRange,
        [int]$ChartType,
        [int]$AxisGroup,
        [int]$Color,
        [double]$LineWeight = 1.5,
        [double]$Transparency = 0.0,
        [bool]$IsFilledArea = $false,
        [bool]$IsDashed = $false
    )

    $series = $Chart.SeriesCollection().NewSeries()
    $series.Name = $Name
    $series.XValues = $XRange
    $series.Values = $YRange
    $series.ChartType = $ChartType
    $series.AxisGroup = $AxisGroup

    if ($IsFilledArea) {
        $series.Format.Fill.Solid()
        $series.Format.Fill.ForeColor.RGB = $Color
        $series.Format.Fill.Transparency = $Transparency
        $series.Format.Line.Visible = 0
    } else {
        $series.Format.Line.Visible = -1
        $series.Format.Line.ForeColor.RGB = $Color
        $series.Format.Line.Weight = $LineWeight
        if ($IsDashed) {
            $series.Format.Line.DashStyle = 4
        }
        $series.MarkerStyle = -4142
    }
    return $series
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$workspaceRoot = Resolve-Path (Join-Path $scriptDir "..\..\..")
$figureDir = Join-Path $workspaceRoot "Figure\Figure 2b"
$dataDir = Join-Path $figureDir "data"
$excelDir = Join-Path $figureDir "excel"
$outputDir = Join-Path $figureDir "output"
$cleanDir = Join-Path $workspaceRoot "Clean"
$logDir = Join-Path $cleanDir "fig2b_excel_automation"

Ensure-Directory $excelDir
Ensure-Directory $outputDir
Ensure-Directory $logDir

$script:LogPath = Join-Path $logDir "create_fig2b_excel_workbook.log"
if (Test-Path -LiteralPath $script:LogPath) {
    Remove-Item -LiteralPath $script:LogPath -Force
}

$inputCsv = Join-Path $dataDir "Fig2b_R1_distribution_origin_ready_wide.csv"
$workbookPath = Join-Path $excelDir "Fig2b_R1_distribution_excel_automated.xlsx"
$pngPath = Join-Path $outputDir "Fig2b_R1_distribution_excel_automated.png"

if (-not (Test-Path -LiteralPath $inputCsv)) {
    throw "Missing Fig. 2b source CSV: $inputCsv"
}

Log-Step "Reading source CSV: $inputCsv"
$rows = Import-Csv -LiteralPath $inputCsv
if ($rows.Count -lt 1) {
    throw "The Fig. 2b source CSV is empty: $inputCsv"
}
Log-Step "Loaded $($rows.Count) rows."

$excel = $null
$workbook = $null

try {
    Log-Step "Starting Excel COM."
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $excel.ScreenUpdating = $false
    $excel.EnableEvents = $false
    try {
        $excel.Calculation = -4135
    } catch {
        Log-Step "Skipping manual calculation mode because Excel rejected the setting."
    }

    Log-Step "Creating workbook and sheets."
    $workbook = $excel.Workbooks.Add()
    Log-Step "Workbook created with $($workbook.Worksheets.Count) worksheet(s)."
    while ($workbook.Worksheets.Count -lt 3) {
        Log-Step "Adding worksheet $($workbook.Worksheets.Count + 1)."
        $workbook.Worksheets.Add() | Out-Null
    }

    Log-Step "Preparing source_wide sheet."
    $sourceSheet = $workbook.Worksheets.Item(1)
    $sourceSheet.Name = "source_wide"
    Log-Step "Preparing plot_data sheet."
    $plotSheet = $workbook.Worksheets.Item(2)
    $plotSheet.Name = "plot_data"
    Log-Step "Preparing Fig2b_chart sheet."
    $chartSheet = $workbook.Worksheets.Item(3)
    $chartSheet.Name = "Fig2b_chart"

    $sourceHeaders = @($rows[0].PSObject.Properties.Name)
    $sourceArray = New-Object 'object[,]' ($rows.Count + 1), $sourceHeaders.Count
    for ($c = 0; $c -lt $sourceHeaders.Count; $c++) {
        $sourceArray[0, $c] = $sourceHeaders[$c]
    }
    for ($r = 0; $r -lt $rows.Count; $r++) {
        $rowIndex = $r + 1
        for ($c = 0; $c -lt $sourceHeaders.Count; $c++) {
            $sourceArray[$rowIndex, $c] = Convert-ExcelValue $rows[$r].($sourceHeaders[$c])
        }
    }
    Log-Step "Writing source_wide sheet."
    Set-RangeArray $sourceSheet $sourceArray | Out-Null

    $plotHeaders = @(
        "Cell ID",
        "Current equal length",
        "Current equal V/A",
        "Current equal width",
        "Current equal V/A, kseg=2",
        "Voltage T=90C equal length",
        "Voltage T=90C equal V/A",
        "Voltage T=90C equal width",
        "Voltage T=90C equal V/A, kseg=2",
        "Voltage T=60C equal length",
        "Voltage T=60C equal V/A",
        "Voltage T=60C equal width"
    )
    $plotArray = New-Object 'object[,]' ($rows.Count + 1), $plotHeaders.Count
    for ($c = 0; $c -lt $plotHeaders.Count; $c++) {
        $plotArray[0, $c] = $plotHeaders[$c]
    }
    for ($r = 0; $r -lt $rows.Count; $r++) {
        $rowIndex = $r + 1
        $plotArray[$rowIndex, 0] = Convert-ExcelValue $rows[$r].row_index
        $plotArray[$rowIndex, 1] = Convert-ExcelValue $rows[$r].current_pu_equal_length
        $plotArray[$rowIndex, 2] = Convert-ExcelValue $rows[$r].current_pu_equal_VA
        $plotArray[$rowIndex, 3] = Convert-ExcelValue $rows[$r].current_pu_equal_width
        $plotArray[$rowIndex, 4] = Convert-ExcelValue $rows[$r].current_pu_equal_VA_k2
        $plotArray[$rowIndex, 5] = Convert-ExcelValue $rows[$r].voltage_T90_equal_length
        $plotArray[$rowIndex, 6] = Convert-ExcelValue $rows[$r].voltage_T90_equal_VA
        $plotArray[$rowIndex, 7] = Convert-ExcelValue $rows[$r].voltage_T90_equal_width
        $plotArray[$rowIndex, 8] = Convert-ExcelValue $rows[$r].voltage_T90_equal_VA_k2
        $plotArray[$rowIndex, 9] = Convert-ExcelValue $rows[$r].voltage_T60_equal_length
        $plotArray[$rowIndex, 10] = Convert-ExcelValue $rows[$r].voltage_T60_equal_VA
        $plotArray[$rowIndex, 11] = Convert-ExcelValue $rows[$r].voltage_T60_equal_width
    }
    Log-Step "Writing plot_data sheet."
    Set-RangeArray $plotSheet $plotArray | Out-Null
    $plotSheet.Range("A1:L1").Font.Bold = $true

    Log-Step "Autofitting data sheets."
    $sourceSheet.Columns.AutoFit() | Out-Null
    $plotSheet.Columns.AutoFit() | Out-Null

    $lastRow = $rows.Count + 1
    $xRange = $plotSheet.Range("A2:A$lastRow")

    # Excel constants used here:
    # xlArea = 1, xlLine = 4, xlPrimary = 1, xlSecondary = 2
    $xlArea = 1
    $xlLine = 4
    $xlPrimary = 1
    $xlSecondary = 2

    $orange = Get-RgbInt 245 166 35
    $teal = Get-RgbInt 0 145 117
    $blue = Get-RgbInt 36 126 194
    $red = Get-RgbInt 210 45 45
    $black = Get-RgbInt 0 0 0

    Log-Step "Creating chart object."
    $chartObject = $chartSheet.ChartObjects().Add(20, 20, 690, 380)
    $chart = $chartObject.Chart
    $chart.ChartType = $xlLine
    $chart.HasTitle = $false
    $chart.HasLegend = $true
    $chart.DisplayBlanksAs = 1

    Log-Step "Adding current series."
    Add-Series $chart "S3 current (equal length)" $xRange $plotSheet.Range("B2:B$lastRow") $xlArea $xlSecondary $orange 1.0 0.65 $true $false | Out-Null
    Add-Series $chart "S3 current (equal V/A)" $xRange $plotSheet.Range("C2:C$lastRow") $xlArea $xlSecondary $teal 1.0 0.68 $true $false | Out-Null
    Add-Series $chart "S3 current (equal width)" $xRange $plotSheet.Range("D2:D$lastRow") $xlArea $xlSecondary $blue 1.0 0.68 $true $false | Out-Null
    Add-Series $chart "S3 current (equal V/A, kseg=2)" $xRange $plotSheet.Range("E2:E$lastRow") $xlLine $xlSecondary $red 1.75 0.0 $false $true | Out-Null

    Log-Step "Adding voltage series."
    Add-Series $chart "S3 voltage T=90C" $xRange $plotSheet.Range("F2:F$lastRow") $xlLine $xlPrimary $black 1.25 0.0 $false $false | Out-Null
    Add-Series $chart "S3 voltage T=90C" $xRange $plotSheet.Range("G2:G$lastRow") $xlLine $xlPrimary $black 1.25 0.0 $false $false | Out-Null
    Add-Series $chart "S3 voltage T=90C" $xRange $plotSheet.Range("H2:H$lastRow") $xlLine $xlPrimary $black 1.25 0.0 $false $false | Out-Null
    Add-Series $chart "S3 voltage T=90C, kseg=2" $xRange $plotSheet.Range("I2:I$lastRow") $xlLine $xlPrimary $red 1.35 0.0 $false $true | Out-Null

    Add-Series $chart "S3 voltage T=60C" $xRange $plotSheet.Range("J2:J$lastRow") $xlLine $xlPrimary $black 1.1 0.0 $false $true | Out-Null
    Add-Series $chart "S3 voltage T=60C" $xRange $plotSheet.Range("K2:K$lastRow") $xlLine $xlPrimary $black 1.1 0.0 $false $true | Out-Null
    Add-Series $chart "S3 voltage T=60C" $xRange $plotSheet.Range("L2:L$lastRow") $xlLine $xlPrimary $black 1.1 0.0 $false $true | Out-Null

    Log-Step "Formatting axes and legend."
    $chart.Axes(1).HasTitle = $true
    $chart.Axes(1).AxisTitle.Text = "Cell ID"
    $chart.Axes(2, $xlPrimary).HasTitle = $true
    $chart.Axes(2, $xlPrimary).AxisTitle.Text = "Cell voltage (V)"
    $chart.Axes(2, $xlSecondary).HasTitle = $true
    $chart.Axes(2, $xlSecondary).AxisTitle.Text = "Cell current (per unit)"

    $chart.Axes(2, $xlPrimary).MinimumScale = 1.5
    $chart.Axes(2, $xlPrimary).MaximumScale = 2.5
    $chart.Axes(2, $xlSecondary).MinimumScale = 0
    $chart.Axes(2, $xlSecondary).MaximumScale = 1

    $chart.ChartArea.Format.Fill.ForeColor.RGB = Get-RgbInt 255 255 255
    $chart.PlotArea.Format.Fill.ForeColor.RGB = Get-RgbInt 255 255 255
    $chart.Legend.Position = -4160

    if (Test-Path -LiteralPath $workbookPath) {
        Remove-Item -LiteralPath $workbookPath -Force
    }
    if (Test-Path -LiteralPath $pngPath) {
        Remove-Item -LiteralPath $pngPath -Force
    }

    Log-Step "Saving workbook: $workbookPath"
    $workbook.SaveAs($workbookPath, 51)
    Log-Step "Exporting preview PNG: $pngPath"
    $chart.Export($pngPath, "PNG") | Out-Null
    Log-Step "Finished Excel automation."

    [PSCustomObject]@{
        Workbook = $workbookPath
        PreviewPng = $pngPath
        SourceCsv = $inputCsv
    } | Format-List | Out-String
}
catch {
    Log-Step "ERROR: $($_.Exception.Message)"
    throw
}
finally {
    Log-Step "Closing Excel COM."
    if ($workbook -ne $null) {
        $workbook.Close($false) | Out-Null
    }
    if ($excel -ne $null) {
        $excel.Quit() | Out-Null
    }
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
