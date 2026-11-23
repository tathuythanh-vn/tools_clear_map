<#
.SYNOPSIS
    BlueStacks ADB auto-clear loop for the Pokemon "Safari" raid screen (1600x900).

.DESCRIPTION
    Keeps the game's built-in auto-click toggle running forever. When VIT (stamina)
    runs out, the game opens the "VIT Purchase" popup by itself; this script then:
      1. stops the auto-click toggle (square -> triangle),
      2. taps "Use Item" in the VIT Purchase popup,
      3. picks Hamburger in the VIT Item panel,
      4. taps MAX then Use in the quantity modal,
      5. closes the VIT Purchase popup with the top-right X,
      6. restarts the auto-click toggle, and loops again.

    Safety rules (see AGENTS.md):
      - NEVER taps the "Buy" button in the VIT Purchase popup (spends diamonds).
      - NEVER taps the "Bread" item (only Hamburger is ever used).
      - NEVER taps "Raid x10" / sweep buttons.
      - Stops cleanly (exit 0) when out of Hamburgers.
      - -DryRun classifies and logs intended taps but performs none.

    All UI coordinates live in the CALIBRATION TABLE below and MUST be calibrated
    against a real 1600x900 screencap before a live run (see -Calibrate).

.PARAMETER AdbPath
    Path to BlueStacks ADB executable. Default: "C:\Program Files\BlueStacks_nxt\HD-Adb.exe".

.PARAMETER Serial
    ADB device serial. Default: "127.0.0.1:5555".

.PARAMETER OutputDir
    Directory for screenshots. Default: "scratch" (relative to script folder if not rooted).

.PARAMETER DryRun
    Classify screens and log intended taps, but perform no ADB taps.

.PARAMETER MaxCycles
    Stop after this many refills. Default: 0 (infinite).

.PARAMETER PollSec
    Seconds between polls in the main loop. Default: 3.

.PARAMETER UnknownTimeoutSec
    Seconds an unrecognised screen may persist before aborting. Default: 30.

.PARAMETER Calibrate
    Capture the current screen, save it, and open a click-to-read-coordinates viewer.
    Re-run for each screen state you need to measure.

.PARAMETER SelfTest
    Run the tap-guard self-test (no ADB needed) and exit.

.PARAMETER ClassifyFile
    Classify a saved PNG screenshot (no ADB needed), print the detected state, and exit.

.EXAMPLE
    .\run_auto_clear.ps1 -Calibrate
    Capture the live screen and open the coordinate viewer for calibration.

.EXAMPLE
    .\run_auto_clear.ps1 -DryRun
    Watch state classification and intended taps without touching the emulator.

.EXAMPLE
    .\run_auto_clear.ps1
    Run the infinite auto-clear + refill loop.
#>
[CmdletBinding()]
param(
    [string]$AdbPath = "C:\Program Files\BlueStacks_nxt\HD-Adb.exe",
    [string]$Serial = "127.0.0.1:5555",
    [string]$OutputDir = "scratch",
    [switch]$DryRun,
    [ValidateRange(0, 1000000)][int]$MaxCycles = 0,
    [ValidateRange(1, 60)][int]$PollSec = 3,
    [ValidateRange(5, 600)][int]$UnknownTimeoutSec = 30,
    [switch]$Calibrate,
    [switch]$SelfTest,
    [string]$ClassifyFile = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Preload assemblies at script scope so [System.Drawing.Bitmap] parameter types always resolve
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime

# ============================================================================
# CALIBRATION TABLE (1600x900 game coordinates)
#
# ALL VALUES BELOW ARE PLACEHOLDERS. They were estimated from the issue
# screenshots, which are 1919x1031 BlueStacks window captures (title bar +
# right toolbar included) and are NOT valid game coordinates.
#
# Before a live run, capture real 1600x900 screencaps of each screen state
# (.\\run_auto_clear.ps1 -Calibrate) and replace every value here:
#   - ToggleBox   : bounding box (X, Y, W, H) around the auto-click toggle icon
#   - StaminaBox  : box (X, Y, W, H) around the green VIT counter digits
#   - PopupBox    : box around the VIT Purchase popup (for OCR)
#   - ItemPanelBox: box around the right-hand "VIT Item" panel (for OCR)
#   - QtyModalBox : box around the quantity modal (for OCR)
#   - RaidBox     : box around the "Raid Completed!" dialog (for OCR)
#   - * tap points: center of each button
# ============================================================================
$script:C = @{
    ToggleBox    = @(55, 154, 55, 68)  # auto-click toggle icon bounding box
    StaminaBox   = @(230, 5, 90, 45)  # green VIT counter digits
    PopupBox     = @(400, 150, 800, 550)  # VIT Purchase popup (OCR region)
    ItemPanelBox = @(1150, 200, 200, 480) # "VIT Item" side panel (OCR region)
    QtyModalBox  = @(450, 200, 700, 450)  # quantity modal (OCR region)
    RaidBox      = @(400, 200, 800, 500)  # "Raid Completed!" dialog (OCR region)

    Toggle       = @(83, 184)  # tap: auto-click toggle (triangle=stopped, square=running)
    UseItem      = @(975, 579)  # tap: "Use Item" in VIT Purchase popup
    Buy          = @(804, 507)  # FORBIDDEN: "Buy" button (spends diamonds)
    VitCloseX    = @(1084, 246)  # tap: VIT Purchase popup close X (top-right)
    Bread        = @(1235, 340)  # FORBIDDEN: "Bread" item entry
    Hamburger    = @(1235, 545)  # tap: "Hamburger" item entry
    QtyMax       = @(1060, 418)  # tap: quantity modal "MAX"
    QtyUse       = @(933, 540)  # tap: quantity modal "Use"
    QtyCancel    = @(668, 540)  # tap: quantity modal "Cancel"
    RaidClose    = @(679, 703)  # tap: "Raid Completed!" Close button
    RaidX10      = @(933, 703)  # FORBIDDEN: "Raid x10" sweep button
}
# ============================================================================

#region Logging
function Write-Log {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Message)
    $ts = (Get-Date).ToString("HH:mm:ss")
    Write-Host "[$ts] $Message"
}

function ToggleLabel {
    param($Value)
    if ($Value -eq $true)  { return 'RUNNING' }
    if ($Value -eq $false) { return 'STOPPED' }
    return 'UNKNOWN'
}
#endregion

#region WinRT OCR Engine (no C# native dependency)
function Initialize-PokemonOcr {
    if (Get-Variable -Name AutoClearOcrReady -Scope Script -ValueOnly -ErrorAction SilentlyContinue) { return }

    $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType = WindowsRuntime]

    $script:WinRtAsTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and
        $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    })[0]

    $avail = [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages
    $pref = $avail | Where-Object { $_.LanguageTag -eq 'en-US' } | Select-Object -First 1
    if ($pref) {
        $script:WinRtOcrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($pref)
    } else {
        $script:WinRtOcrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    }
    if (-not $script:WinRtOcrEngine) {
        throw "Failed to initialize Windows.Media.Ocr.OcrEngine (no recognizer language installed)."
    }
    Set-Variable -Name AutoClearOcrReady -Value $true -Scope Script
}

function Invoke-WinRtAwait {
    param(
        [Parameter(Mandatory = $true)]$WinRtAsyncOp,
        [Parameter(Mandatory = $true)][Type]$ResultType
    )
    $closedMethod = $script:WinRtAsTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $closedMethod.Invoke($null, @($WinRtAsyncOp))
    $netTask.Wait(-1) | Out-Null
    return $netTask.Result
}

function Open-UnlockedBitmap {
    param([Parameter(Mandatory = $true)][string]$ImagePath)
    Initialize-PokemonOcr
    $bytes = [System.IO.File]::ReadAllBytes($ImagePath)
    $ms = New-Object System.IO.MemoryStream(,$bytes)
    try {
        $tmp = New-Object System.Drawing.Bitmap($ms)
        try {
            $clone = New-Object System.Drawing.Bitmap($tmp.Width, $tmp.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($clone)
            try {
                $g.DrawImage($tmp, 0, 0, $tmp.Width, $tmp.Height)
            } finally {
                $g.Dispose()
            }
            return $clone
        } finally {
            $tmp.Dispose()
        }
    } finally {
        $ms.Dispose()
    }
}

function Remove-Diacritics {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $norm = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder($norm.Length)
    foreach ($ch in $norm.ToCharArray()) {
        $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    $clean = $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
    return ([regex]::Replace($clean, '\s+', ' ')).Trim()
}

function Invoke-RegionOcr {
    [CmdletBinding()]
    param(
        [string]$ImagePath,
        [System.Drawing.Bitmap]$Bitmap,
        [int]$X = 0,
        [int]$Y = 0,
        [int]$Width = 0,
        [int]$Height = 0,
        [ValidateRange(1, 4)][int]$Scale = 2
    )
    Initialize-PokemonOcr

    $ownsBitmap = $false
    if (-not $Bitmap) {
        $Bitmap = Open-UnlockedBitmap -ImagePath $ImagePath
        $ownsBitmap = $true
    }

    if ($Width -le 0)  { $Width  = $Bitmap.Width - $X }
    if ($Height -le 0) { $Height = $Bitmap.Height - $Y }
    if ($X -lt 0) { $X = 0 }
    if ($Y -lt 0) { $Y = 0 }
    if ($X + $Width -gt $Bitmap.Width)  { $Width  = $Bitmap.Width - $X }
    if ($Y + $Height -gt $Bitmap.Height) { $Height = $Bitmap.Height - $Y }
    if ($Width -le 0 -or $Height -le 0) {
        return [pscustomobject]@{ Text = ''; NormalizedText = ''; Words = @() }
    }

    $padBase = 12
    $padPx = $padBase * $Scale
    $crop = $null; $g = $null; $pngStream = $null; $memStream = $null; $ras = $null
    $decoder = $null; $softBmp = $null

    try {
        $dstW = $Width * $Scale + $padPx * 2
        $dstH = $Height * $Scale + $padPx * 2
        $crop = New-Object System.Drawing.Bitmap($dstW, $dstH, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $g = [System.Drawing.Graphics]::FromImage($crop)
        try {
            $g.Clear([System.Drawing.Color]::Black)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        # Precompute into plain variables: New-Object with unparenthesized binary
        # expressions inside the arg list fails to unroll on PowerShell 5.1.
        $srcRect = New-Object System.Drawing.Rectangle($X, $Y, $Width, $Height)
        $dstW = $Width * $Scale
        $dstH = $Height * $Scale
        $dstRect = New-Object System.Drawing.Rectangle($padPx, $padPx, $dstW, $dstH)
        $g.DrawImage($Bitmap, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        } finally {
            $g.Dispose(); $g = $null
        }

        $pngStream = New-Object System.IO.MemoryStream
        $crop.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngBytes = $pngStream.ToArray()
        $pngStream.Dispose(); $pngStream = $null
        $crop.Dispose(); $crop = $null

        $memStream = New-Object System.IO.MemoryStream(,$pngBytes)
        $ras = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($memStream)
        $decoder = Invoke-WinRtAwait ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $softBmp = Invoke-WinRtAwait ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $ocrResult = Invoke-WinRtAwait ($script:WinRtOcrEngine.RecognizeAsync($softBmp)) ([Windows.Media.Ocr.OcrResult])

        $words = New-Object System.Collections.Generic.List[object]
        foreach ($line in $ocrResult.Lines) {
            foreach ($w in $line.Words) {
                $sx  = [math]::Round($X + ($w.BoundingRect.X - $padPx) / $Scale, 1)
                $sy  = [math]::Round($Y + ($w.BoundingRect.Y - $padPx) / $Scale, 1)
                $swd = [math]::Round($w.BoundingRect.Width / $Scale, 1)
                $sht = [math]::Round($w.BoundingRect.Height / $Scale, 1)
                $words.Add([pscustomobject]@{
                    Text           = $w.Text
                    NormalizedText = (Remove-Diacritics $w.Text)
                    X              = $sx
                    Y              = $sy
                    Width          = $swd
                    Height         = $sht
                    CenterX        = [int][math]::Round($sx + $swd / 2.0)
                    CenterY        = [int][math]::Round($sy + $sht / 2.0)
                })
            }
        }

        $text = ($words | ForEach-Object { $_.Text }) -join ' '
        return [pscustomobject]@{
            Text           = $text
            NormalizedText = (Remove-Diacritics $text)
            Words          = $words.ToArray()
        }
    } finally {
        if ($softBmp)   { $softBmp.Dispose() }
        if ($ras)       { $ras.Dispose() }
        if ($memStream) { $memStream.Dispose() }
        if ($pngStream) { $pngStream.Dispose() }
        if ($crop)      { $crop.Dispose() }
        if ($g)         { $g.Dispose() }
        if ($ownsBitmap -and $Bitmap) { $Bitmap.Dispose() }
    }
}
#endregion

#region ADB Wrappers with Built-In Safety Guardrails
function Invoke-AdbRaw {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $AdbPath @Arguments 2>&1
        $code = $LASTEXITCODE
        return [pscustomobject]@{
            ExitCode = $code
            Output   = ($output -join "`n")
        }
    } finally {
        $ErrorActionPreference = $oldEap
    }
}

function Connect-AdbDevice {
    if (-not (Test-Path -LiteralPath $AdbPath)) {
        Write-Log "ERROR: ADB executable not found at '$AdbPath'. Pass -AdbPath to specify HD-Adb.exe."
        exit 1
    }
    Write-Log "Connecting to ADB device $Serial..."
    $conn = Invoke-AdbRaw -Arguments @('connect', $Serial)
    Write-Log "ADB connect: $($conn.Output.Trim())"

    $st = Invoke-AdbRaw -Arguments @('-s', $Serial, 'get-state')
    if ($st.ExitCode -ne 0 -or $st.Output.Trim() -ne 'device') {
        Write-Log "ERROR: ADB device '$Serial' is not ready (state='$($st.Output.Trim())', exit=$($st.ExitCode))."
        exit 1
    }
}

# Hard safety guard: throws if (X, Y) falls inside any forbidden button zone.
function Test-TapGuard {
    param(
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y
    )
    $margin = 30
    $zones = @(
        @{ Name = 'Buy (spends diamonds)'; P = $script:C.Buy },
        @{ Name = 'Bread (never used)';    P = $script:C.Bread },
        @{ Name = 'Raid x10 (sweep)';      P = $script:C.RaidX10 }
    )
    foreach ($z in $zones) {
        if ($z.P[0] -le 0 -or $z.P[1] -le 0) { continue }  # zone not calibrated yet
        if ([Math]::Abs($X - $z.P[0]) -le $margin -and [Math]::Abs($Y - $z.P[1]) -le $margin) {
            throw "SAFETY BLOCK: Refusing to tap ($X, $Y) inside forbidden '$($z.Name)' zone!"
        }
    }
}

function Invoke-AdbTap {
    param(
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [Parameter(Mandatory = $true)][string]$Reason
    )
    Test-TapGuard -X $X -Y $Y
    if ($DryRun) {
        Write-Log "DRY RUN: would TAP ($X, $Y) - $Reason"
        return
    }
    Write-Log "TAP ($X, $Y) - $Reason"
    $res = Invoke-AdbRaw -Arguments @('-s', $Serial, 'shell', 'input', 'tap', "$X", "$Y")
    if ($res.ExitCode -ne 0) {
        throw "ADB tap failed at ($X, $Y) (exit $($res.ExitCode)): $($res.Output)"
    }
}

function Capture-Screen {
    param([Parameter(Mandatory = $true)][string]$OutPath)
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        if (Test-Path -LiteralPath $OutPath) {
            Remove-Item -LiteralPath $OutPath -Force
        }
        $cap = Invoke-AdbRaw -Arguments @('-s', $Serial, 'shell', 'screencap', '-p', $script:RemoteScreenPath)
        if ($cap.ExitCode -eq 0) {
            $pull = Invoke-AdbRaw -Arguments @('-s', $Serial, 'pull', $script:RemoteScreenPath, $OutPath)
            if ($pull.ExitCode -eq 0 -and (Test-Path -LiteralPath $OutPath) -and ((Get-Item -LiteralPath $OutPath).Length -gt 0)) {
                return
            }
        }
        if ($attempt -lt 2) {
            Start-Sleep -Milliseconds 600
        }
    }
    throw "Failed to capture screenshot via ADB to '$OutPath'."
}
#endregion

#region Screen State Classifier
function Test-IsBlue {
    param([System.Drawing.Color]$p)
    return ($p.B -ge 150 -and ([int]$p.B - [int]$p.R) -ge 50 -and ([int]$p.B - [int]$p.G) -ge 25)
}

function Test-IsGoldAt {
    param([System.Drawing.Bitmap]$Bitmap, [int]$X, [int]$Y)
    if ($X -le 0 -or $Y -le 0) { return $false }
    $hits = 0
    for ($dx = -12; $dx -le 12; $dx += 6) {
        for ($dy = -12; $dy -le 12; $dy += 6) {
            $px = $X + $dx; $py = $Y + $dy
            if ($px -lt 0 -or $py -lt 0 -or $px -ge $Bitmap.Width -or $py -ge $Bitmap.Height) { continue }
            $c = $Bitmap.GetPixel($px, $py)
            if ($c.R -ge 170 -and $c.G -ge 130 -and $c.B -le 110 -and ([int]$c.R - [int]$c.B) -ge 70) { $hits++ }
        }
    }
    return ($hits -ge 4)
}

function Get-OwnCount {
    param([Parameter(Mandatory = $true)][System.Drawing.Bitmap]$Bitmap)
    $qb = $script:C.QtyModalBox
    if ($qb[2] -le 0 -or $qb[3] -le 0) { return $null }
    $ocr = Invoke-RegionOcr -Bitmap $Bitmap -X $qb[0] -Y $qb[1] -Width $qb[2] -Height $qb[3] -Scale 2
    $words = @($ocr.Words)
    # The "Own:" label is OCR'd as "own:" / "own" / sometimes "ovn". Tolerate n/v confusion.
    for ($i = 0; $i -lt $words.Count; $i++) {
        $t = $words[$i].NormalizedText -replace ':$', ''
        if ($t -match '^o[wv]n$' -and $i + 1 -lt $words.Count) {
            $next = $words[$i + 1].Text
            if ($next -match '^\d+$') { return [int]$next }
        }
    }
    return $null
}

function Test-HamburgerInPanel {
    param([Parameter(Mandatory = $true)][System.Drawing.Bitmap]$Bitmap)
    $pb = $script:C.ItemPanelBox
    if ($pb[2] -le 0 -or $pb[3] -le 0) { return $false }
    $ocr = Invoke-RegionOcr -Bitmap $Bitmap -X $pb[0] -Y $pb[1] -Width $pb[2] -Height $pb[3] -Scale 2
    return ($ocr.NormalizedText -match 'hamburger')
}

function Get-Stamina {
    param([Parameter(Mandatory = $true)][string]$ImagePath)
    $sb = $script:C.StaminaBox
    if ($sb[2] -le 0 -or $sb[3] -le 0) { return $null }
    $ocr = Invoke-RegionOcr -ImagePath $ImagePath -X $sb[0] -Y $sb[1] -Width $sb[2] -Height $sb[3] -Scale 3
    $m = [regex]::Matches($ocr.Text, '\d+')
    if ($m.Count -eq 0) { return $null }
    $best = 0
    foreach ($mm in $m) { $v = [int]$mm.Value; if ($v -gt $best) { $best = $v } }
    return $best
}

function Inspect-AutoClearScreen {
    param([Parameter(Mandatory = $true)][string]$ImagePath)
    $bmp = $null
    try {
        $bmp = Open-UnlockedBitmap -ImagePath $ImagePath
        if ($bmp.Width -ne 1600 -or $bmp.Height -ne 900) {
            throw "Unexpected resolution $($bmp.Width)x$($bmp.Height); expected 1600x900."
        }

        # 1. Toggle state (pixel check; evaluated in every state)
        #    Square (running): top-left corner of the icon box is blue.
        #    Triangle (stopped, points right): top-left corner is NOT blue, center is.
        $toggleRunning = $null
        $tb = $script:C.ToggleBox
        if ($tb[2] -gt 0 -and $tb[3] -gt 0) {
            $tlX = [int]($tb[0] + $tb[2] * 0.18); $tlY = [int]($tb[1] + $tb[3] * 0.18)
            $tcX = [int]($tb[0] + $tb[2] / 2);     $tcY = [int]($tb[1] + $tb[3] / 2)
            if (Test-IsBlue $bmp.GetPixel($tcX, $tcY)) {
                $toggleRunning = Test-IsBlue $bmp.GetPixel($tlX, $tlY)
            }
        }

        # 2. Quantity modal (topmost layer). Its defining feature is the "Own: <number>"
        #    label; the small MAX button text is unreliable for OCR. Detect by reading it.
        $isQtyModal = $false
        $ownCount = $null
        $qb = $script:C.QtyModalBox
        if ($qb[2] -gt 0 -and $qb[3] -gt 0) {
            $ownCount = Get-OwnCount -Bitmap $bmp
            if ($null -ne $ownCount) {
                $isQtyModal = $true
            }
        }

        # 3. VIT Item side panel (right of the popup)
        $isItemPanel = $false
        $pb = $script:C.ItemPanelBox
        if (-not $isQtyModal -and $pb[2] -gt 0 -and $pb[3] -gt 0) {
            $isItemPanel = Test-HamburgerInPanel -Bitmap $bmp
        }

        # 4. VIT Purchase popup (gold X + OCR; banner can mask the title, so "Use Item" is the anchor)
        $isVitPurchase = $false
        $ob = $script:C.PopupBox
        if (-not $isQtyModal -and -not $isItemPanel -and $ob[2] -gt 0 -and $ob[3] -gt 0) {
            $goldX = Test-IsGoldAt -Bitmap $bmp -X $script:C.VitCloseX[0] -Y $script:C.VitCloseX[1]
            if ($goldX) {
                $oOcr = Invoke-RegionOcr -Bitmap $bmp -X $ob[0] -Y $ob[1] -Width $ob[2] -Height $ob[3] -Scale 2
                $oNorm = $oOcr.NormalizedText
                $isVitPurchase = ($oNorm -match 'use\s*i[tl]em') -or ($oNorm -match 'purchase')
            }
        }

        # 5. Raid Completed dialog
        $isRaidResult = $false
        $rb = $script:C.RaidBox
        if (-not $isQtyModal -and -not $isItemPanel -and -not $isVitPurchase -and $rb[2] -gt 0 -and $rb[3] -gt 0) {
            $rOcr = Invoke-RegionOcr -Bitmap $bmp -X $rb[0] -Y $rb[1] -Width $rb[2] -Height $rb[3] -Scale 2
            $rNorm = $rOcr.NormalizedText
            $isRaidResult = ($rNorm -match 'completed') -or ($rNorm -match 'close' -and $rNorm -match 'raid')
        }

        $stateName = if ($isQtyModal)        { 'ITEM_QUANTITY' }
                     elseif ($isItemPanel)   { 'VIT_ITEM_PANEL' }
                     elseif ($isVitPurchase) { 'VIT_PURCHASE' }
                     elseif ($isRaidResult)  { 'RAID_RESULT' }
                     elseif ($toggleRunning -eq $true)  { 'AUTO_RUNNING' }
                     elseif ($toggleRunning -eq $false) { 'AUTO_STOPPED' }
                     else { 'UNKNOWN' }

        return [pscustomobject]@{
            State         = $stateName
            ToggleRunning = $toggleRunning
            OwnCount      = $ownCount
        }
    } finally {
        if ($null -ne $bmp) { $bmp.Dispose() }
    }
}
#endregion

#region Refill Flow
function Save-Snapshot {
    param([Parameter(Mandatory = $true)][string]$Name)
    $path = Join-Path $script:ResolvedOutputDir $Name
    try { Copy-Item -LiteralPath $script:LiveScreenPath -Destination $path -Force } catch {}
    return $path
}

function Wait-ForToggle {
    param([Parameter(Mandatory = $true)][bool]$WantRunning, [int]$TimeoutSec = 15)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        Capture-Screen -OutPath $script:LiveScreenPath
        $st = Inspect-AutoClearScreen -ImagePath $script:LiveScreenPath
        if ($st.ToggleRunning -eq $WantRunning) { return $true }
        Start-Sleep -Milliseconds 800
    }
    return $false
}

function Invoke-RefillStamina {
    param([Parameter(Mandatory = $true)][bool]$PanelAlreadyOpen)

    # 1. Stop the auto-click toggle (it stays "running" behind the popup until tapped)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Capture-Screen -OutPath $script:LiveScreenPath
        $st = Inspect-AutoClearScreen -ImagePath $script:LiveScreenPath
        if ($st.ToggleRunning -eq $false) { break }
        Invoke-AdbTap -X $script:C.Toggle[0] -Y $script:C.Toggle[1] -Reason "Stop auto-click before refill (attempt $attempt)"
        Start-Sleep -Milliseconds 1200
    }
    if (-not (Wait-ForToggle -WantRunning $false -TimeoutSec 8)) {
        $snap = Save-Snapshot "refill_toggle_stuck.png"
        Write-Log "ERROR: Auto-click toggle did not stop while VIT popup is open. Saved '$snap'."
        exit 2
    }

    # 2. Open the VIT Item panel
    if (-not $PanelAlreadyOpen) {
        Invoke-AdbTap -X $script:C.UseItem[0] -Y $script:C.UseItem[1] -Reason 'Tap Use Item in VIT Purchase popup'
        Start-Sleep -Milliseconds 1500
        Capture-Screen -OutPath $script:LiveScreenPath
        $st = Inspect-AutoClearScreen -ImagePath $script:LiveScreenPath
        if ($st.State -ne 'VIT_ITEM_PANEL') {
            $snap = Save-Snapshot "refill_no_item_panel.png"
            Write-Log "ERROR: VIT Item panel did not open after Use Item (state=$($st.State)). Saved '$snap'."
            exit 2
        }
    }

    # 3. Verify Hamburger is listed (never tap Bread)
    Capture-Screen -OutPath $script:LiveScreenPath
    $bmp = Open-UnlockedBitmap -ImagePath $script:LiveScreenPath
    try {
        if (-not (Test-HamburgerInPanel -Bitmap $bmp)) {
            $snap = Save-Snapshot "out_of_hamburgers.png"
            Write-Log "========================================================"
            Write-Log "[OUT OF HAMBURGERS] No 'Hamburger' entry in VIT Item panel. Stopping cleanly."
            Write-Log "Saved snapshot: '$snap'"
            Write-Log "========================================================"
            return 'OUT_OF_HAMBURGERS'
        }
    } finally {
        $bmp.Dispose()
    }

    # 4. Tap Hamburger -> quantity modal
    Invoke-AdbTap -X $script:C.Hamburger[0] -Y $script:C.Hamburger[1] -Reason 'Select Hamburger in VIT Item panel'
    Start-Sleep -Milliseconds 1500
    Capture-Screen -OutPath $script:LiveScreenPath
    $st = Inspect-AutoClearScreen -ImagePath $script:LiveScreenPath
    if ($st.State -ne 'ITEM_QUANTITY') {
        $snap = Save-Snapshot "out_of_hamburgers_no_modal.png"
        Write-Log "========================================================"
        Write-Log "[OUT OF HAMBURGERS] Quantity modal did not open (state=$($st.State)). Stopping cleanly."
        Write-Log "Saved snapshot: '$snap'"
        Write-Log "========================================================"
        return 'OUT_OF_HAMBURGERS'
    }

    # 5. Verify Own count > 0
    $own = $st.OwnCount
    if ($null -eq $own) {
        Start-Sleep -Milliseconds 1000
        Capture-Screen -OutPath $script:LiveScreenPath
        $bmp = Open-UnlockedBitmap -ImagePath $script:LiveScreenPath
        try { $own = Get-OwnCount -Bitmap $bmp } finally { $bmp.Dispose() }
    }
    if ($null -eq $own) {
        $snap = Save-Snapshot "refill_own_count_unreadable.png"
        Write-Log "ERROR: Could not read 'Own: N' in quantity modal. Saved '$snap'."
        exit 2
    }
    if ($own -le 0) {
        Invoke-AdbTap -X $script:C.QtyCancel[0] -Y $script:C.QtyCancel[1] -Reason 'Cancel quantity modal (Own = 0)'
        $snap = Save-Snapshot "out_of_hamburgers_own0.png"
        Write-Log "========================================================"
        Write-Log "[OUT OF HAMBURGERS] Own: 0 in quantity modal. Stopping cleanly. Saved '$snap'."
        Write-Log "========================================================"
        return 'OUT_OF_HAMBURGERS'
    }
    Write-Log "Quantity modal: Own=$own. Using MAX."

    # 6. MAX -> Use
    $staminaBefore = Get-Stamina -ImagePath $script:LiveScreenPath
    Invoke-AdbTap -X $script:C.QtyMax[0] -Y $script:C.QtyMax[1] -Reason 'Tap MAX in quantity modal'
    Start-Sleep -Milliseconds 1200
    Invoke-AdbTap -X $script:C.QtyUse[0] -Y $script:C.QtyUse[1] -Reason 'Tap Use in quantity modal'
    Start-Sleep -Milliseconds 2000

    # 7. Modal must close (back to VIT Purchase or Item Panel)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $modalClosed = $false
    while ($sw.Elapsed.TotalSeconds -lt 10) {
        Capture-Screen -OutPath $script:LiveScreenPath
        $st = Inspect-AutoClearScreen -ImagePath $script:LiveScreenPath
        if ($st.State -in @('VIT_PURCHASE', 'VIT_ITEM_PANEL')) { $modalClosed = $true; break }
        Start-Sleep -Milliseconds 800
    }
    if (-not $modalClosed) {
        $snap = Save-Snapshot "refill_modal_stuck.png"
        Write-Log "ERROR: Quantity modal did not close after Use. Saved '$snap'."
        exit 2
    }

    # 8. Optional stamina sanity check (warning only, never blocks)
    $staminaAfter = Get-Stamina -ImagePath $script:LiveScreenPath
    if ($null -ne $staminaBefore -and $null -ne $staminaAfter) {
        if ($staminaAfter -lt $staminaBefore) {
            Write-Log "WARNING: Stamina did not increase after Use (before=$staminaBefore, after=$staminaAfter)."
        } else {
            Write-Log "Stamina refilled: $staminaBefore -> $staminaAfter."
        }
    }

    # 9. Close the VIT Purchase popup
    Invoke-AdbTap -X $script:C.VitCloseX[0] -Y $script:C.VitCloseX[1] -Reason 'Close VIT Purchase popup (X)'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $popupClosed = $false
    while ($sw.Elapsed.TotalSeconds -lt 10) {
        Capture-Screen -OutPath $script:LiveScreenPath
        $st = Inspect-AutoClearScreen -ImagePath $script:LiveScreenPath
        if ($st.State -eq 'AUTO_STOPPED') { $popupClosed = $true; break }
        Start-Sleep -Milliseconds 800
    }
    if (-not $popupClosed) {
        $snap = Save-Snapshot "refill_popup_stuck.png"
        Write-Log "ERROR: VIT Purchase popup did not close (state=$(Inspect-AutoClearScreen -ImagePath $script:LiveScreenPath).State). Saved '$snap'."
        exit 2
    }

    return 'REFILLED'
}
#endregion

#region Calibration & Self-Test Helpers
function Test-CoordsCalibrated {
    $required = @('Toggle','UseItem','Buy','VitCloseX','Bread','Hamburger','QtyMax','QtyUse','QtyCancel','RaidClose','RaidX10')
    $missing = @()
    foreach ($k in $required) {
        $p = $script:C[$k]
        if ($p[0] -le 0 -or $p[1] -le 0) { $missing += $k }
    }
    $tb = $script:C.ToggleBox
    if ($tb[2] -le 0 -or $tb[3] -le 0) { $missing += 'ToggleBox' }
    return $missing
}

function Invoke-SelfTest {
    Write-Log "=== Tap-Guard Self-Test (no ADB) ==="
    $saved = $script:C
    $script:C.Buy = @(948, 595)
    $script:C.Bread = @(1457, 410)
    $script:C.RaidX10 = @(1100, 813)
    $script:C.Toggle = @(98, 237)
    $pass = $true
    try {
        $forbidden = @(@(948, 595), @(950, 600), @(1457, 410), @(1450, 430), @(1100, 813))
        foreach ($pt in $forbidden) {
            try {
                Test-TapGuard -X $pt[0] -Y $pt[1]
                Write-Log "FAIL: guard allowed forbidden tap ($($pt[0]), $($pt[1]))"
                $pass = $false
            } catch {
                Write-Log "PASS: guard blocked ($($pt[0]), $($pt[1]))"
            }
        }
        try {
            Test-TapGuard -X 98 -Y 237
            Write-Log "PASS: guard allowed legitimate toggle tap (98, 237)"
        } catch {
            Write-Log "FAIL: guard blocked legitimate tap (98, 237)"
            $pass = $false
        }
    } finally {
        $script:C = $saved
    }
    if (-not $pass) {
        Write-Log "Self-test FAILED."
        exit 1
    }
    Write-Log "Self-test PASSED."
}

function Invoke-InteractiveCalibrate {
    param([Parameter(Mandatory = $true)][string]$ImagePath)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap($ImagePath)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Auto-Clear Calibration - click the image to read coordinates (1600x900). Close to exit."
    $form.StartPosition = 'CenterScreen'
    $form.Width = $bmp.Width + 40
    $form.Height = $bmp.Height + 80
    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(10, 5)
    $label.AutoSize = $true
    $label.Text = "X=?  Y=?"
    $pb = New-Object System.Windows.Forms.PictureBox
    $pb.Image = $bmp
    $pb.Location = New-Object System.Drawing.Point(10, 30)
    $pb.Size = New-Object System.Drawing.Size($bmp.Width, $bmp.Height)
    $pb.Add_MouseClick({
        param($s, $e)
        $label.Text = "X=$($e.X)  Y=$($e.Y)"
    })
    $form.Controls.Add($pb)
    $form.Controls.Add($label)
    try {
        [System.Windows.Forms.Application]::Run($form)
    } finally {
        $form.Dispose()
        $bmp.Dispose()
    }
}
#endregion

# ============================================================================
# Mode dispatch
# ============================================================================
$baseDir = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { (Get-Location).Path }
$script:ResolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir
} else {
    Join-Path $baseDir $OutputDir
}
if (-not (Test-Path -LiteralPath $script:ResolvedOutputDir)) {
    New-Item -ItemType Directory -Path $script:ResolvedOutputDir -Force | Out-Null
}
$script:LiveScreenPath = Join-Path $script:ResolvedOutputDir "auto_clear_live.png"
$script:RemoteScreenPath = "/sdcard/pokemon_auto_clear.png"

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

if ($ClassifyFile) {
    if (-not (Test-Path -LiteralPath $ClassifyFile)) {
        Write-Log "ERROR: File not found: '$ClassifyFile'"
        exit 1
    }
    $resolved = (Resolve-Path -LiteralPath $ClassifyFile).Path
    $st = Inspect-AutoClearScreen -ImagePath $resolved
    $stamina = Get-Stamina -ImagePath $resolved
    Write-Log "Classify '$resolved':"
    Write-Log "  State   = $($st.State)"
    Write-Log "  Toggle  = $(ToggleLabel $st.ToggleRunning)"
    Write-Log "  OwnCount= $(if ($null -ne $st.OwnCount) { "$($st.OwnCount)" } else { '?' })"
    Write-Log "  Stamina = $(if ($null -ne $stamina) { "$stamina" } else { '?' })"
    exit 0
}

if ($Calibrate) {
    Connect-AdbDevice
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $calPath = Join-Path $script:ResolvedOutputDir "calibrate_$ts.png"
    Capture-Screen -OutPath $calPath
    Write-Log "Saved calibration capture: '$calPath'"
    Write-Log "Click on the image to read coordinates, then update the CALIBRATION TABLE in run_auto_clear.ps1."
    Write-Log "Re-run -Calibrate for each screen state you need to measure (raid list, VIT popup, item panel, quantity modal, raid result)."
    Invoke-InteractiveCalibrate -ImagePath $calPath
    exit 0
}

# Live / DryRun: coordinates must be calibrated
$missing = Test-CoordsCalibrated
if ($missing.Count -gt 0) {
    Write-Log "ERROR: Coordinates not calibrated: $($missing -join ', ')."
    Write-Log "Run: .\run_auto_clear.ps1 -Calibrate  (then update the CALIBRATION TABLE in run_auto_clear.ps1)"
    exit 1
}

Initialize-PokemonOcr
Connect-AdbDevice

Write-Log "=== Auto-Clear Loop (DryRun=$DryRun, MaxCycles=$MaxCycles, PollSec=$PollSec) ==="
if ($DryRun) {
    Write-Log "DRY RUN: no ADB taps will be performed. Stop with Ctrl+C when done."
}

# ============================================================================
# Main loop
# ============================================================================
$refills = 0
$unknownSince = $null

while ($true) {
    if ($MaxCycles -gt 0 -and $refills -ge $MaxCycles) {
        Write-Log "Reached -MaxCycles $MaxCycles refills. Stopping cleanly."
        break
    }

    Capture-Screen -OutPath $script:LiveScreenPath
    $st = Inspect-AutoClearScreen -ImagePath $script:LiveScreenPath
    $stamina = Get-Stamina -ImagePath $script:LiveScreenPath
    Write-Log "State=$($st.State) Toggle=$(ToggleLabel $st.ToggleRunning) Stamina=$(if ($null -ne $stamina) { "$stamina" } else { '?' })"

    switch ($st.State) {
        'RAID_RESULT' {
            Invoke-AdbTap -X $script:C.RaidClose[0] -Y $script:C.RaidClose[1] -Reason 'Close Raid Completed dialog'
            Start-Sleep -Milliseconds 1200
        }
        'VIT_PURCHASE' {
            $res = Invoke-RefillStamina -PanelAlreadyOpen $false
            if ($res -eq 'OUT_OF_HAMBURGERS') { exit 0 }
            $refills++
            Write-Log "Refill #$refills done. Resuming auto-click..."
            Invoke-AdbTap -X $script:C.Toggle[0] -Y $script:C.Toggle[1] -Reason 'Resume auto-click after refill'
            if (-not (Wait-ForToggle -WantRunning $true)) {
                $snap = Save-Snapshot "resume_failed.png"
                Write-Log "ERROR: Auto-click did not resume after refill. Saved '$snap'."
                exit 2
            }
        }
        'VIT_ITEM_PANEL' {
            $res = Invoke-RefillStamina -PanelAlreadyOpen $true
            if ($res -eq 'OUT_OF_HAMBURGERS') { exit 0 }
            $refills++
            Write-Log "Refill #$refills done. Resuming auto-click..."
            Invoke-AdbTap -X $script:C.Toggle[0] -Y $script:C.Toggle[1] -Reason 'Resume auto-click after refill'
            if (-not (Wait-ForToggle -WantRunning $true)) {
                $snap = Save-Snapshot "resume_failed.png"
                Write-Log "ERROR: Auto-click did not resume after refill. Saved '$snap'."
                exit 2
            }
        }
        'AUTO_STOPPED' {
            Invoke-AdbTap -X $script:C.Toggle[0] -Y $script:C.Toggle[1] -Reason 'Start auto-click'
            if (-not (Wait-ForToggle -WantRunning $true)) {
                Write-Log "Auto-click did not start; retrying next poll."
            }
        }
        'AUTO_RUNNING' {
            # nothing to do
        }
        default {
            if ($null -eq $unknownSince) {
                $unknownSince = Get-Date
            } elseif (((Get-Date) - $unknownSince).TotalSeconds -ge $UnknownTimeoutSec) {
                $snap = Save-Snapshot "unknown_screen.png"
                Write-Log "ERROR: Unknown screen for ${UnknownTimeoutSec}s. Saved '$snap'. Exiting."
                exit 2
            }
        }
    }

    if ($st.State -ne 'UNKNOWN') { $unknownSince = $null }
    Start-Sleep -Seconds $PollSec
}

Write-Log "Auto-clear loop stopped ($refills refill(s) performed)."
exit 0

