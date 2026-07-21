$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$evRoot = Split-Path -Parent $scriptDir
$outputs = Join-Path $evRoot "outputs"
$figDir = Join-Path $outputs "si_validation_clean_figures"
if (!(Test-Path -LiteralPath $figDir)) {
    New-Item -ItemType Directory -Force -Path $figDir | Out-Null
}

$staticCurveCsv = Join-Path $outputs "step4_stack_efficiency_interface\stackB_piecewise_efficiency_curve.csv"
$steadyCsv = Join-Path $outputs "step6_steady_module_validation\steady_window_module_validation.csv"
$dynamicCsv = Join-Path $outputs "step7_dynamic_module_validation\dynamic_day_2023-11-05_module_validation_profile.csv"

foreach ($p in @($staticCurveCsv, $steadyCsv, $dynamicCsv)) {
    if (!(Test-Path -LiteralPath $p)) {
        throw "Required input file not found: $p"
    }
}

function Set-ChartStyle {
    param($chart)
    $chart.HasTitle = $false
    $chart.HasLegend = $true
    $chart.Legend.Font.Name = "Times New Roman"
    $chart.Legend.Font.Size = 9
    $chart.ChartArea.Format.Fill.Visible = 0
    $chart.PlotArea.Format.Fill.Visible = 0

    $chart.Axes(1).HasTitle = $true
    $chart.Axes(2).HasTitle = $true
    $chart.Axes(1).TickLabels.Font.Name = "Times New Roman"
    $chart.Axes(1).TickLabels.Font.Size = 10
    $chart.Axes(2).TickLabels.Font.Name = "Times New Roman"
    $chart.Axes(2).TickLabels.Font.Size = 10
    $chart.Axes(1).AxisTitle.Font.Name = "Times New Roman"
    $chart.Axes(1).AxisTitle.Font.Size = 12
    $chart.Axes(2).AxisTitle.Font.Name = "Times New Roman"
    $chart.Axes(2).AxisTitle.Font.Size = 12
}

$excel = $null
$wb = $null
try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $wb = $excel.Workbooks.Add()

    $steady = Import-Csv -LiteralPath $steadyCsv
    $curve = Import-Csv -LiteralPath $staticCurveCsv
    $dynamic = Import-Csv -LiteralPath $dynamicCsv

    $ws1 = $wb.Worksheets.Item(1)
    $ws1.Name = "static_interface"
    $ws1.Cells.Item(1,1).Value2 = "load_fraction"
    $ws1.Cells.Item(1,2).Value2 = "measured_eta_stack_LHV"
    $ws1.Cells.Item(1,3).Value2 = "predicted_eta_stack_LHV"
    $row = 2
    foreach ($r in $steady) {
        $ws1.Cells.Item($row,1).Value2 = [double]$r.load_fraction
        $ws1.Cells.Item($row,2).Value2 = [double]$r.measured_eta_stack_LHV
        $ws1.Cells.Item($row,3).Value2 = [double]$r.predicted_eta_stack_LHV
        $row++
    }
    $ws1.Cells.Item(1,6).Value2 = "load_mean"
    $ws1.Cells.Item(1,7).Value2 = "eta_stack_LHV_mean"
    $row = 2
    foreach ($r in $curve) {
        $ws1.Cells.Item($row,6).Value2 = [double]$r.load_mean
        $ws1.Cells.Item($row,7).Value2 = [double]$r.eta_stack_LHV_mean
        $row++
    }

    $chartObj1 = $ws1.ChartObjects().Add(25, 20, 700, 400)
    $chart1 = $chartObj1.Chart
    $chart1.ChartType = -4169
    $series = $chart1.SeriesCollection().NewSeries()
    $series.Name = "Measured steady windows"
    $series.XValues = $ws1.Range("A2:A" + ($steady.Count + 1))
    $series.Values = $ws1.Range("B2:B" + ($steady.Count + 1))
    $series.MarkerStyle = 8
    $series.MarkerSize = 5
    $series.Format.Fill.ForeColor.RGB = 11842740
    $series.Border.LineStyle = -4142

    $series = $chart1.SeriesCollection().NewSeries()
    $series.Name = "Predicted steady windows"
    $series.XValues = $ws1.Range("A2:A" + ($steady.Count + 1))
    $series.Values = $ws1.Range("C2:C" + ($steady.Count + 1))
    $series.MarkerStyle = 8
    $series.MarkerSize = 5
    $series.Format.Fill.ForeColor.RGB = 12255232
    $series.Border.LineStyle = -4142

    $series = $chart1.SeriesCollection().NewSeries()
    $series.Name = "Piecewise static interface"
    $series.XValues = $ws1.Range("F2:F" + ($curve.Count + 1))
    $series.Values = $ws1.Range("G2:G" + ($curve.Count + 1))
    $series.ChartType = 74
    $series.Format.Line.ForeColor.RGB = 2960685
    $series.Format.Line.Weight = 1.75
    $series.MarkerStyle = 8
    $series.MarkerSize = 6
    $series.Format.Fill.ForeColor.RGB = 2960685

    Set-ChartStyle $chart1
    $chart1.Axes(1).AxisTitle.Text = "Load fraction (-)"
    $chart1.Axes(2).AxisTitle.Text = "Stack LHV efficiency (-)"
    $chart1.Axes(1).MinimumScale = 0.25
    $chart1.Axes(1).MaximumScale = 1.0
    $chart1.Axes(2).MinimumScale = 0.45
    $chart1.Axes(2).MaximumScale = 0.64
    $chart1.Export((Join-Path $figDir "SX_validation_stackB_static_interface.png")) | Out-Null

    $ws2 = $wb.Worksheets.Add()
    $ws2.Name = "dynamic_interface"
    $ws2.Cells.Item(1,1).Value2 = "time_h"
    $ws2.Cells.Item(1,2).Value2 = "measured_H2_rate_Nm3h"
    $ws2.Cells.Item(1,3).Value2 = "predicted_H2_rate_Nm3h"
    $row = 2
    foreach ($r in $dynamic) {
        $ws2.Cells.Item($row,1).Value2 = [double]$r.time_h
        $ws2.Cells.Item($row,2).Value2 = [double]$r.measured_H2_rate_Nm3h
        $ws2.Cells.Item($row,3).Value2 = [double]$r.predicted_H2_rate_Nm3h
        $row++
    }

    $chartObj2 = $ws2.ChartObjects().Add(25, 20, 700, 400)
    $chart2 = $chartObj2.Chart
    $chart2.ChartType = 74

    $series = $chart2.SeriesCollection().NewSeries()
    $series.Name = "Measured 2023-11-05 profile"
    $series.XValues = $ws2.Range("A2:A" + ($dynamic.Count + 1))
    $series.Values = $ws2.Range("B2:B" + ($dynamic.Count + 1))
    $series.Format.Line.ForeColor.RGB = 1981540
    $series.Format.Line.Weight = 1.75
    $series.MarkerStyle = -4142

    $series = $chart2.SeriesCollection().NewSeries()
    $series.Name = "Dynamic interface replay"
    $series.XValues = $ws2.Range("A2:A" + ($dynamic.Count + 1))
    $series.Values = $ws2.Range("C2:C" + ($dynamic.Count + 1))
    $series.Format.Line.ForeColor.RGB = 12255232
    $series.Format.Line.Weight = 1.75
    $series.MarkerStyle = -4142

    Set-ChartStyle $chart2
    $chart2.Axes(1).AxisTitle.Text = "Time (h)"
    $chart2.Axes(2).AxisTitle.Text = "Hydrogen production rate (Nm^3 h^-^1)"
    $chart2.Axes(1).MinimumScale = 0
    $chart2.Axes(1).MaximumScale = 24
    $chart2.Export((Join-Path $figDir "SX_validation_stackB_dynamic_interface.png")) | Out-Null
}
finally {
    if ($wb -ne $null) {
        $wb.Close($false) | Out-Null
    }
    if ($excel -ne $null) {
        $excel.Quit() | Out-Null
    }
}

Write-Output $figDir
