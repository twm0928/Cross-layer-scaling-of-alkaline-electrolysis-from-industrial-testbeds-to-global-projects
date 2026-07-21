$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$evRoot = Split-Path -Parent $scriptDir
$outputs = Join-Path $evRoot "outputs"
$figDir = Join-Path $outputs "si_validation_clean_figures"
if (!(Test-Path -LiteralPath $figDir)) {
    New-Item -ItemType Directory -Force -Path $figDir | Out-Null
}

$curveCsv = Join-Path $outputs "step4_stack_efficiency_interface\stackB_piecewise_efficiency_curve.csv"
$steadyCsv = Join-Path $outputs "step6_steady_module_validation\steady_window_module_validation.csv"
$dynamicCsv = Join-Path $outputs "step7_dynamic_module_validation\dynamic_day_2023-11-05_module_validation_profile.csv"
$fullStateCsv = Join-Path $outputs "step8_full_statespace_single5MW_validation\fangshan_single5MW_full_statespace_validation_profile.csv"

foreach ($p in @($curveCsv, $steadyCsv, $dynamicCsv, $fullStateCsv)) {
    if (!(Test-Path -LiteralPath $p)) {
        throw "Required input file not found: $p"
    }
}

function Set-WhiteChartStyle {
    param(
        $chart,
        [int]$LegendPosition = -4152
    )
    $chart.HasTitle = $false
    $chart.HasLegend = $true
    $chart.Legend.Font.Name = "Times New Roman"
    $chart.Legend.Font.Size = 10
    $chart.Legend.Position = $LegendPosition

    $chart.ChartArea.Format.Fill.Visible = 1
    $chart.ChartArea.Format.Fill.Solid()
    $chart.ChartArea.Format.Fill.ForeColor.RGB = 16777215
    $chart.ChartArea.Format.Line.Visible = 0
    $chart.PlotArea.Format.Fill.Visible = 1
    $chart.PlotArea.Format.Fill.Solid()
    $chart.PlotArea.Format.Fill.ForeColor.RGB = 16777215
    $chart.PlotArea.Format.Line.Visible = 0

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
    $chart.Axes(1).Format.Line.ForeColor.RGB = 0
    $chart.Axes(2).Format.Line.ForeColor.RGB = 0
    $chart.Axes(1).MajorGridlines.Format.Line.Visible = 0
    $chart.Axes(2).MajorGridlines.Format.Line.Visible = 0
}

function Get-SmoothedStaticInterface {
    param($curveRows)

    $points = $curveRows | ForEach-Object {
        [pscustomobject]@{
            x = [double]$_.load_mean
            y = [double]$_.eta_stack_LHV_mean
            n = if ($_.PSObject.Properties.Name -contains 'n') { [double]$_.n } else { 1.0 }
        }
    } | Sort-Object x

    $xmin = ($points | Measure-Object -Property x -Minimum).Minimum
    $xmax = ($points | Measure-Object -Property x -Maximum).Maximum
    $bandwidth = 0.085
    $grid = @()
    for ($i = 0; $i -lt 240; $i++) {
        $x = $xmin + ($xmax - $xmin) * $i / 239.0
        $num = 0.0
        $den = 0.0
        foreach ($p in $points) {
            $w = $p.n * [Math]::Exp(-0.5 * [Math]::Pow(($x - $p.x) / $bandwidth, 2))
            $num += $w * $p.y
            $den += $w
        }
        $grid += [pscustomobject]@{ x = $x; y = $num / $den }
    }
    return $grid
}

$excel = $null
$wb = $null
try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $wb = $excel.Workbooks.Add()

    $curve = Import-Csv -LiteralPath $curveCsv
    $steady = Import-Csv -LiteralPath $steadyCsv
    $dynamic = Import-Csv -LiteralPath $dynamicCsv | Where-Object { [double]$_.time_h -gt 0 }
    $fullState = Import-Csv -LiteralPath $fullStateCsv | Where-Object { [double]$_.time_h -gt 0 }
    $smooth = Get-SmoothedStaticInterface $curve

    $ws1 = $wb.Worksheets.Item(1)
    $ws1.Name = "fig2_static"
    $ws1.Cells.Item(1,1).Value2 = "load_fraction"
    $ws1.Cells.Item(1,2).Value2 = "measured_eta_stack_LHV"
    $ws1.Cells.Item(1,3).Value2 = "predicted_eta_stack_LHV"
    $r = 2
    foreach ($row in $steady) {
        $ws1.Cells.Item($r,1).Value2 = [double]$row.load_fraction
        $ws1.Cells.Item($r,2).Value2 = [double]$row.measured_eta_stack_LHV
        $ws1.Cells.Item($r,3).Value2 = [double]$row.predicted_eta_stack_LHV
        $r++
    }
    $ws1.Cells.Item(1,6).Value2 = "load_mean"
    $ws1.Cells.Item(1,7).Value2 = "eta_stack_LHV_mean"
    $r = 2
    foreach ($row in $curve) {
        $ws1.Cells.Item($r,6).Value2 = [double]$row.load_mean
        $ws1.Cells.Item($r,7).Value2 = [double]$row.eta_stack_LHV_mean
        $r++
    }
    $ws1.Cells.Item(1,10).Value2 = "smooth_x"
    $ws1.Cells.Item(1,11).Value2 = "smooth_y"
    $r = 2
    foreach ($row in $smooth) {
        $ws1.Cells.Item($r,10).Value2 = [double]$row.x
        $ws1.Cells.Item($r,11).Value2 = [double]$row.y
        $r++
    }

    $chartObj1 = $ws1.ChartObjects().Add(20, 15, 820, 440)
    $chart1 = $chartObj1.Chart
    $chart1.ChartType = -4169

    $s = $chart1.SeriesCollection().NewSeries()
    $s.Name = "Measured steady windows"
    $s.XValues = $ws1.Range("A2:A" + ($steady.Count + 1))
    $s.Values = $ws1.Range("B2:B" + ($steady.Count + 1))
    $s.ChartType = -4169
    $s.MarkerStyle = 8
    $s.MarkerSize = 6
    $s.Format.Fill.ForeColor.RGB = 12566463
    $s.Format.Line.Visible = 0

    $s = $chart1.SeriesCollection().NewSeries()
    $s.Name = "Predicted steady windows"
    $s.XValues = $ws1.Range("A2:A" + ($steady.Count + 1))
    $s.Values = $ws1.Range("C2:C" + ($steady.Count + 1))
    $s.ChartType = -4169
    $s.MarkerStyle = 8
    $s.MarkerSize = 6
    $s.Format.Fill.ForeColor.RGB = 4868682
    $s.Format.Line.Visible = 0

    $s = $chart1.SeriesCollection().NewSeries()
    $s.Name = "Field-derived bin means"
    $s.XValues = $ws1.Range("F2:F" + ($curve.Count + 1))
    $s.Values = $ws1.Range("G2:G" + ($curve.Count + 1))
    $s.ChartType = -4169
    $s.MarkerStyle = 8
    $s.MarkerSize = 6
    $s.Format.Fill.ForeColor.RGB = 11489200
    $s.Format.Line.Visible = 0

    $s = $chart1.SeriesCollection().NewSeries()
    $s.Name = "Smoothed static interface"
    $s.XValues = $ws1.Range("J2:J" + ($smooth.Count + 1))
    $s.Values = $ws1.Range("K2:K" + ($smooth.Count + 1))
    $s.ChartType = 73
    $s.Format.Line.ForeColor.RGB = 11489200
    $s.Format.Line.Weight = 2.25
    $s.MarkerStyle = -4142

    Set-WhiteChartStyle $chart1 -LegendPosition -4152
    $chart1.Axes(1).AxisTitle.Text = "Load fraction (-)"
    $chart1.Axes(2).AxisTitle.Text = "Stack LHV efficiency (-)"
    $chart1.Axes(1).MinimumScale = 0.25
    $chart1.Axes(1).MaximumScale = 1.0
    $chart1.Axes(2).MinimumScale = 0.48
    $chart1.Axes(2).MaximumScale = 0.64
    $chart1.Export((Join-Path $figDir "SX_validation_stackB_interfaces.png")) | Out-Null

    $ws2 = $wb.Worksheets.Add()
    $ws2.Name = "fig3_overlay"
    $ws2.Cells.Item(1,1).Value2 = "time_h"
    $ws2.Cells.Item(1,2).Value2 = "measured_H2_rate"
    $ws2.Cells.Item(1,3).Value2 = "interface_replay_H2_rate"
    $ws2.Cells.Item(1,4).Value2 = "full_state_H2_rate"
    $r = 2
    foreach ($row in $fullState) {
        $time = [double]$row.time_h
        $match = $dynamic | Where-Object { [Math]::Abs(([double]$_.time_h) - $time) -lt 1e-9 } | Select-Object -First 1
        $ws2.Cells.Item($r,1).Value2 = $time
        $ws2.Cells.Item($r,2).Value2 = [double]$row.H2_rate_measured_Nm3h
        $ws2.Cells.Item($r,3).Value2 = if ($null -ne $match) { [double]$match.predicted_H2_rate_Nm3h } else { [double]::NaN }
        $ws2.Cells.Item($r,4).Value2 = [double]$row.H2_rate_model_Nm3h
        $r++
    }

    $chartObj2 = $ws2.ChartObjects().Add(20, 15, 820, 440)
    $chart2 = $chartObj2.Chart
    $chart2.ChartType = 75

    $s = $chart2.SeriesCollection().NewSeries()
    $s.Name = "Measured"
    $s.XValues = $ws2.Range("A2:A" + ($fullState.Count + 1))
    $s.Values = $ws2.Range("B2:B" + ($fullState.Count + 1))
    $s.ChartType = 75
    $s.Format.Line.ForeColor.RGB = 2001680
    $s.Format.Line.Weight = 2.25
    $s.MarkerStyle = -4142

    $s = $chart2.SeriesCollection().NewSeries()
    $s.Name = "Interface-only replay"
    $s.XValues = $ws2.Range("A2:A" + ($fullState.Count + 1))
    $s.Values = $ws2.Range("C2:C" + ($fullState.Count + 1))
    $s.ChartType = 75
    $s.Format.Line.ForeColor.RGB = 8421504
    $s.Format.Line.Weight = 2.0
    $s.Format.Line.DashStyle = 5
    $s.MarkerStyle = -4142

    $s = $chart2.SeriesCollection().NewSeries()
    $s.Name = "Full state-space model"
    $s.XValues = $ws2.Range("A2:A" + ($fullState.Count + 1))
    $s.Values = $ws2.Range("D2:D" + ($fullState.Count + 1))
    $s.ChartType = 75
    $s.Format.Line.ForeColor.RGB = 0
    $s.Format.Line.Weight = 2.25
    $s.MarkerStyle = -4142

    Set-WhiteChartStyle $chart2 -LegendPosition -4107
    $chart2.Axes(1).AxisTitle.Text = "Time (h)"
    $chart2.Axes(2).AxisTitle.Text = "Hydrogen production rate (Nm^3 h^-1)"
    $chart2.Axes(1).MinimumScale = 0
    $chart2.Axes(1).MaximumScale = 24
    $chart2.Axes(2).MinimumScale = 0
    $chart2.Axes(2).MaximumScale = 1200
    $chart2.Export((Join-Path $figDir "SX_validation_stackB_full_state_H2.png")) | Out-Null
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
