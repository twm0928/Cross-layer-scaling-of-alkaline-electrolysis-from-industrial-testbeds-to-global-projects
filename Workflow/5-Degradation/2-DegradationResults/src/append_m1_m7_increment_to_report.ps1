$ErrorActionPreference = 'Stop'

function Decode-Base64Text {
    param(
        [Parameter(Mandatory = $true)] [string] $Text
    )
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Text))
}

function Add-Paragraph {
    param(
        [Parameter(Mandatory = $true)] $Selection,
        [Parameter(Mandatory = $true)] [string] $Text,
        [int] $Bold = 0,
        [int] $FontSize = 11
    )
    $Selection.Font.Bold = $Bold
    $Selection.Font.Size = $FontSize
    $Selection.TypeText($Text)
    $Selection.TypeParagraph()
    $Selection.Font.Bold = 0
}

function Add-Heading {
    param(
        [Parameter(Mandatory = $true)] $Selection,
        [Parameter(Mandatory = $true)] [string] $Text
    )
    Add-Paragraph -Selection $Selection -Text $Text -Bold 1 -FontSize 14
}

function Add-ImageWithCaption {
    param(
        [Parameter(Mandatory = $true)] $Selection,
        [Parameter(Mandatory = $true)] [string] $ImagePath,
        [Parameter(Mandatory = $true)] [string] $Caption,
        [double] $WidthCm = 15.8
    )
    if (-not (Test-Path -LiteralPath $ImagePath)) {
        throw "Image not found: $ImagePath"
    }
    $shape = $Selection.InlineShapes.AddPicture($ImagePath)
    $shape.LockAspectRatio = $true
    $shape.Width = [math]::Round($WidthCm * 28.3465, 0)
    $Selection.TypeParagraph()
    Add-Paragraph -Selection $Selection -Text $Caption -FontSize 10
}

function Add-CsvTable {
    param(
        [Parameter(Mandatory = $true)] $Selection,
        [Parameter(Mandatory = $true)] [string] $CsvPath,
        [Parameter(Mandatory = $true)] [string] $Caption
    )
    if (-not (Test-Path -LiteralPath $CsvPath)) {
        throw "CSV not found: $CsvPath"
    }

    $rows = Import-Csv -LiteralPath $CsvPath
    if ($rows.Count -eq 0) {
        throw "CSV is empty: $CsvPath"
    }

    Add-Paragraph -Selection $Selection -Text $Caption -FontSize 10

    $headers = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $rows[0].PSObject.Properties.Name) {
        [void]$headers.Add([string]$p)
    }

    $table = $Selection.Tables.Add($Selection.Range, $rows.Count + 1, $headers.Count)
    try {
        $table.Style = "Table Grid"
    }
    catch {
        # Some local Word installations do not expose the English style name.
    }
    $table.Range.Font.Size = 9
    $table.Borders.Enable = 1

    for ($c = 0; $c -lt $headers.Count; $c++) {
        $table.Cell(1, $c + 1).Range.Text = $headers[$c]
        $table.Cell(1, $c + 1).Range.Bold = 1
    }

    for ($r = 0; $r -lt $rows.Count; $r++) {
        for ($c = 0; $c -lt $headers.Count; $c++) {
            $table.Cell($r + 2, $c + 1).Range.Text = [string]$rows[$r].($headers[$c])
        }
    }

    $table.Rows.Alignment = 1
    $table.Range.ParagraphFormat.SpaceAfter = 0
    $table.AutoFitBehavior(2) | Out-Null
    $Selection.MoveDown() | Out-Null
    $Selection.TypeParagraph()
}

function Remove-ExistingSection {
    param(
        [Parameter(Mandatory = $true)] $Document,
        [Parameter(Mandatory = $true)] [string] $Marker
    )
    $range = $Document.Content
    $find = $range.Find
    $find.ClearFormatting()
    $find.Text = $Marker
    $found = $find.Execute()
    if ($found) {
        $deleteRange = $Document.Range($range.Start, $Document.Content.End)
        $deleteRange.Delete()
    }
}

$textMap = @{
    section_marker = 'OC4gUGxhbnTlsYLpgIDljJblop7ph4/nu5PmnpzvvIhNMS1NN++8iQ=='
    p1 = '5pys6IqC6KGl5YWF55qE5piv5LuK5aSp5paw5aKe5a6M5oiQ55qEIHBsYW50IOWxgumAgOWMluWQjuWkhOeQhue7k+aenOOAgui/memHjOS4jeWGjeiuqOiuuiBzdGFjayDlkowgbW9kdWxlIOWGhemDqOmAgOWMluacuueQhu+8jOiAjOaYr+WcqOWbuuWumiBNMS1NNyDlpJbmjqXlj6PjgIHlm7rlrpogcGxhbnQg5bel5Ya16L6555WM5LiL77yM5q+U6L6D5LiN5ZCM6LCD5bqm562W55Wl5Zyo5bm05bC65bqm5LiK55qE6YCA5YyW6K+x5a+85Lqn5rCi5o2f5aSx5beu5byC44CC'
    p2 = '5YW35L2T5YGa5rOV5piv77ya5a+55Y6f5paHIHBsYW50IOWxgueahCBQVuOAgVdUIOWSjCBDb25zdGFudCDkuInnsbvlt6XlhrXvvIzliIbliKvmjIkgzrggPSAwOjAuMToxIOeahOinhOWImeiwg+W6pu+8jOS7peWPiuaWsOWinueahCBNSUxQIOiwg+W6pu+8jOeUn+aIkOWQhCBtb2R1bGUg55qE5pel5Yqf546H6L2o6L+577yb5YaN5oyJ5bey57uP56Gu5a6a55qE6YCA5YyW5o6l5Y+j77yM5oqK5Yqf546H6L2o6L+55pig5bCE5Li65pel6YCA5YyW55S15Y6L5aKe6YeP77yM5bm26L+b5LiA5q2l5oqY566X5Li65bm057Sv6K6h5Lqn5rCi5o2f5aSx44CC55Sx5LqOIENvbnN0YW50IOW3peWGteS4i+WQhOetlueVpeeahOWKn+eOh+WIhumFjeWujOWFqOS4gOiHtO+8jOaJgOS7peWFtumAgOWMlue7k+aenOWcqOaJgOaciSDOuCDlkowgTUlMUCDkuIvph43lkIjjgII='
    p3 = '5LuO57uT5p6c55yL77yMUFYg5LiOIFdUIOS4i+eahOmAgOWMluaNn+WksemDveWvueiwg+W6puetlueVpeaVj+aEn++8jOS9huaVj+aEn+eoi+W6puaciemZkO+8jOS4u+imgeS9k+eOsOWcqOeZvuWIhuS5i+mbtueCueWHoOeahOaNn+WkseeOh+W3ruW8gu+8m+S4juatpOWQjOaXtu+8jENvbnN0YW50IOW3peWGteaPkOS+m+S6huS4gOS4quWfuuWHhui+ueeVjO+8jOivtOaYjuW9k+iwg+W6puiHqueUseW6pua2iOWkseaXtu+8jOi/meadoemAgOWMluaUr+e6v+S4jeS8muWHreepuuWItumAoOetlueVpeW3ruW8guOAgg=='
    fig1 = '5Zu+OC0xLiBQViDkuI4gV1Qg5Zy65pmv5LiL77yMTTEtTTcg5LiN5ZCMIM64IOinhOWImeiwg+W6puWPiiBNSUxQIOiwg+W6puWvueW6lOeahOW5tOmAgOWMluivseWvvOS6p+awouaNn+WkseeOh+OAguWbvuS4rSBDb25zdGFudCDmnKrljZXliJflsZXnpLrvvIzlm6DkuLrlhbblhajpg6jnrZbnlaXnu5Pmnpzph43lkIjjgII='
    fig2 = '5Zu+OC0yLiDku6XmnIDkvJggzrjjgIFNSUxQ44CB5pyA5beuIM64IOS4ieexu+S7o+ihqOaAp+etlueVpeaxh+aAuyBNMS1NNyDnmoTpgIDljJbor7Hlr7zkuqfmsKLmjZ/lpLHjgILlt6bliJfkuLrmjZ/lpLHnjofvvIzlj7PliJfkuLrlubTntK/orqHnu53lr7nkuqfmsKLmjZ/lpLHjgII='
    table1 = '6KGoOC0xLiBNMS1NNyDlnKggQ29uc3RhbnTjgIFQViDlkowgV1Qg5LiJ57G75Zy65pmv5LiL55qE5o2f5aSx546H5rGH5oC744CC'
    table2 = '6KGoOC0yLiBNMS1NNyDlnKggQ29uc3RhbnTjgIFQViDlkowgV1Qg5LiJ57G75Zy65pmv5LiL55qE5bm057Sv6K6h57ud5a+55Lqn5rCi5o2f5aSx5rGH5oC744CC'
    subheading = 'OC4xIOe7k+aenOino+ivuw=='
    d1 = 'MSkgQ29uc3RhbnQg5Zy65pmv5LiL77yMTTEtTTcg55qEIGJlc3QgzrjjgIF3b3JzdCDOuCDkuI4gTUlMUCDlrozlhajph43lkIjvvIzor7TmmI7lnKjmgZLlip/njofovpPlhaXkuIvvvIzmnKzova7pgIDljJblkI7lpITnkIbkuI3kvJrkurrkuLrlvJXlhaXosIPluqblt67lvILjgII='
    d2 = 'MikgUFYg5Zy65pmv5LiL77yM5LiN5ZCMIM64IOeahOacgOS8mOeCueW5tuS4jeWujOWFqOS4gOiHtO+8jOS9huaVtOS9k+i2i+WKv+avlOi+g+a4nealmu+8mk0x44CBTTLjgIFNM+OAgU0244CBTTcg55qE6L6D5LyY562W55Wl5pu05YGP5ZCR6auYIM6477ybTTTjgIFNNSDnmoTovoPkvJjnrZbnlaXmm7TpnaDov5HkuK3kvY4gzrjjgIJNSUxQIOWkp+WkmuiQveWcqCBiZXN0IM64IOS4jiB3b3JzdCDOuCDkuYvpl7TvvIzkvYblubbkuI3mgLvmmK/mnIDkvJjjgII='
    d3 = 'MykgV1Qg5Zy65pmv5LiL77yM5pyA5LyYIM64IOabtOmbhuS4reWcqOmrmCDOuCDkuIDkvqfvvIzlpJrmlbDmi5PmiLHnmoQgYmVzdCDOuCDkuLogMS4w77yM5LuFIE02IOeahCBiZXN0IM64IOiQveWcqCAwLjLjgILnm7jovoMgUFbvvIxXVCDkuIvkuI3lkIznrZbnlaXkuYvpl7TnmoTmnIDlt64t5pyA5LyY5beu5YC86YCa5bi45pu05aSn44CC'
    d4 = 'NCkg5LuO5pWw6YeP57qn5LiK55yL77yM5bm06YCA5YyW6K+x5a+85Lqn5rCi5o2f5aSx546H5aSn5L2T5L2N5LqOIDMuMSXigJMzLjYlIOWMuumXtO+8m+WQjOS4gOaLk+aJkeWGheeUseiwg+W6puetlueVpeW8lei1t+eahCBiZXN0LXdvcnN0IOW3ruWAvOmAmuW4uOWcqCAwLjHigJMwLjM2IOS4queZvuWIhueCuemHj+e6p+OAgui/meivtOaYjumAgOWMluiwg+W6puehruWunuacieW9seWTje+8jOS9huWFtumHj+e6p+S7jemcgOS4juS4u+e6v+aViOeOh+aUtuebiuWFseWQjOadg+ihoe+8jOiAjOS4jeiDveiEseemu+aViOeOh+WNleeLrOWGs+etluOAgg=='
    d5 = 'NSkg5pys6IqC57uT5p6c55qE5a6a5L2N5pivIHBsYW50IOWxgumAgOWMluWQjuWkhOeQhui+ueeVjOWIhuaekO+8muWug+ivtOaYjuWcqOWbuuWumuWkluaOpeWPo+S4i++8jOiwg+W6puetlueVpeS8muaKiumAgOWMluS7o+S7t+aUvuWkp+aIluWOi+e8qeWIsOaAjuagt+eahOeoi+W6pu+8m+S9huWug+W5tuS4jeebtOaOpeivgeaYjuafkOS4gCBtb2R1bGUg5ouT5omR5pys6Lqr5YW35pyJ5pu05by65oiW5pu05byx55qE5Zu65pyJ6YCA5YyW5py655CG44CC'
}

$srcDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $srcDir
$reportDir = Join-Path $rootDir 'report'
$docPath = (Get-ChildItem -LiteralPath $reportDir -Filter '*.docx' | Select-Object -First 1).FullName
$figDir = Join-Path $reportDir 'figures'
$tableDir = Join-Path $reportDir 'tables'

$figA = Join-Path $figDir 'FigA_theta_loss_ratio_profiles_PV_WT.png'
$figB = Join-Path $figDir 'FigB_best_milp_worst_loss_summary.png'
$ratioTable = Join-Path $tableDir 'plant_m1_m7_increment_ratio_table.csv'
$absTable = Join-Path $tableDir 'plant_m1_m7_increment_absolute_table.csv'

if (-not $docPath) {
    throw 'No Word report found under report directory.'
}

$marker = Decode-Base64Text $textMap.section_marker

$word = $null
$doc = $null
try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0
    $doc = $word.Documents.Open($docPath)

    Remove-ExistingSection -Document $doc -Marker $marker

    $selection = $word.Selection
    $selection.EndKey(6) | Out-Null
    $selection.InsertBreak(7)

    Add-Heading -Selection $selection -Text $marker
    Add-Paragraph -Selection $selection -Text (Decode-Base64Text $textMap.p1)
    Add-Paragraph -Selection $selection -Text (Decode-Base64Text $textMap.p2)
    Add-Paragraph -Selection $selection -Text (Decode-Base64Text $textMap.p3)

    Add-ImageWithCaption -Selection $selection -ImagePath $figA -Caption (Decode-Base64Text $textMap.fig1)
    Add-ImageWithCaption -Selection $selection -ImagePath $figB -Caption (Decode-Base64Text $textMap.fig2)

    Add-CsvTable -Selection $selection -CsvPath $ratioTable -Caption (Decode-Base64Text $textMap.table1)
    Add-CsvTable -Selection $selection -CsvPath $absTable -Caption (Decode-Base64Text $textMap.table2)

    Add-Heading -Selection $selection -Text (Decode-Base64Text $textMap.subheading)
    Add-Paragraph -Selection $selection -Text (Decode-Base64Text $textMap.d1)
    Add-Paragraph -Selection $selection -Text (Decode-Base64Text $textMap.d2)
    Add-Paragraph -Selection $selection -Text (Decode-Base64Text $textMap.d3)
    Add-Paragraph -Selection $selection -Text (Decode-Base64Text $textMap.d4)
    Add-Paragraph -Selection $selection -Text (Decode-Base64Text $textMap.d5)

    $doc.Save()
}
finally {
    if ($doc -ne $null) {
        $doc.Close() | Out-Null
    }
    if ($word -ne $null) {
        $word.Quit() | Out-Null
    }
}

Write-Output $docPath
