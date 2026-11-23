# Offline classifier test: crop issue screenshots to the game area, resize to
# 1600x900, and run the auto-clear classifier on a test copy of the script
# with coordinates scaled from the 1919x1031 screenshot space.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repo = "C:\Users\tatht\Downloads\source_code\tools_clear_map"
$dir  = Join-Path $repo "scratch\test"

# Game area inside the window captures: x 0..1887 (right toolbar ~32px), y 33..bottom (title bar ~33px)
$gameW = 1887
$titleBar = 33
$scaleX = 1600.0 / $gameW
$scaleY = 900.0 / (1031 - $titleBar)

function ConvertTo-GameCoords {
    param([int]$X, [int]$Y)
    return @([int][math]::Round($X * $scaleX), [int][math]::Round(($Y - $titleBar) * $scaleY))
}

# 1. Crop + resize each raw screenshot
foreach ($f in Get-ChildItem -LiteralPath $dir -Filter "*_raw.png") {
    $bmp = New-Object System.Drawing.Bitmap($f.FullName)
    $srcH = $bmp.Height - $titleBar
    $dst = New-Object System.Drawing.Bitmap(1600, 900, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $srcRect = New-Object System.Drawing.Rectangle(0, $titleBar, $gameW, $srcH)
    $dstRect = New-Object System.Drawing.Rectangle(0, 0, 1600, 900)
    $g.DrawImage($bmp, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $name = $f.BaseName -replace '_raw$', ''
    $dst.Save((Join-Path $dir "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $dst.Dispose()
    $bmp.Dispose()
    Write-Host "Prepared $name.png"
}

# 2. Build a test copy of the script with scaled coordinates
$src = Get-Content -LiteralPath (Join-Path $repo "run_auto_clear.ps1") -Raw

$pts = @{
    Toggle      = @(98, 237)
    UseItem     = @(1150, 675)
    Buy         = @(948, 595)
    VitCloseX   = @(1279, 306)
    Bread       = @(1457, 410)
    Hamburger   = @(1457, 637)
    QtyMax      = @(1250, 497)
    QtyUse      = @(1100, 632)
    QtyCancel   = @(788, 632)
    RaidClose   = @(801, 813)
    RaidX10     = @(1100, 813)
}
foreach ($k in $pts.Keys) {
    $c = ConvertTo-GameCoords -X $pts[$k][0] -Y $pts[$k][1]
    $pattern = "(?m)^(\s*$k\s*=\s*)\@\(.*?\)"
    $src = [regex]::Replace($src, $pattern, "`$1@($($c[0]), $($c[1]))")
}
$boxes = @{
    ToggleBox    = @(55, 154, 55, 68)
    StaminaBox   = @(230, 5, 90, 45)
    PopupBox     = @(400, 150, 800, 550)
    ItemPanelBox = @(1150, 200, 200, 480)
    QtyModalBox  = @(450, 200, 700, 450)
    RaidBox      = @(400, 200, 800, 500)
}
foreach ($k in $boxes.Keys) {
    $b = $boxes[$k]
    $pattern = "(?m)^(\s*$k\s*=\s*)\@\(.*?\)"
    $src = [regex]::Replace($src, $pattern, "`$1@($($b[0]), $($b[1]), $($b[2]), $($b[3]))")
}

$testScript = Join-Path $dir "run_auto_clear_test.ps1"
Set-Content -LiteralPath $testScript -Value $src -Encoding UTF8
Write-Host "Wrote test copy: $testScript"

# 3. Classify each prepared screenshot
$expected = @{
    raid_result    = 'RAID_RESULT'
    vit_purchase   = 'VIT_PURCHASE'
    vit_item_panel = 'VIT_ITEM_PANEL'
    qty_modal      = 'ITEM_QUANTITY'
}
$fail = 0
foreach ($k in $expected.Keys) {
    $img = Join-Path $dir "$k.png"
    Write-Host ""
    Write-Host "=== $k (expect $($expected[$k])) ==="
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $testScript -ClassifyFile $img 2>&1
    $out | ForEach-Object { Write-Host "  $_" }
    $joined = ($out -join " ")
    if ($joined -match "State\s*=\s*(\S+)") {
        $got = $Matches[1]
        if ($got -eq $expected[$k]) {
            Write-Host "  RESULT: PASS"
        } else {
            Write-Host "  RESULT: FAIL (got $got)"
            $fail++
        }
    } else {
        Write-Host "  RESULT: FAIL (no state parsed)"
        $fail++
    }
}
Write-Host ""
if ($fail -eq 0) { Write-Host "ALL OFFLINE CLASSIFIER TESTS PASSED" } else { Write-Host "$fail TEST(S) FAILED" }
exit $fail
