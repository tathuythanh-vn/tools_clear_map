<#
.SYNOPSIS
    Reusable BlueStacks ADB stage-automation script for Pokemon (1600x900).

.DESCRIPTION
    Automates navigating to any Region 1 Adventure chapter map (Normal or Hard/Elite mode),
    dynamically scrolling the stage list to any stage number (1..50), verifying stage lock and
    earned star status via local zero-dependency WinRT OCR + fast C# pixel/7-segment decoding,
    and running stages sequentially through completion.

    Built-in safety rules:
      - Never taps "Tiếp" (1500, 700) on the Victory screen (taps "Tiếp tục" at 1500, 805 to return directly to STAGE_MODAL for the next stage).
      - Never taps "Quét" / "Quét 10" sweep buttons or spends diamonds.
      - Never enters battle when -DryRun or -ListMaps is specified.
      - Disposes all Bitmap and Stream instances immediately in finally blocks.

.PARAMETER MapName
    Target chapter/map name in Vietnamese (with or without diacritics, e.g. "Tình Ca Sa Mạc",
    "Tinh Ca Sa Mac", "Đồng Bằng Sao", "Dong Bang Sao") or map ground label (e.g. "Deserto de Love Song").
    If omitted ("") while a Stage Selection Modal is already open, uses the currently open map.

.PARAMETER Mode
    Difficulty mode: "Normal" / "Thuong" for Normal mode, or "Hard" / "Elite" / "TinhAnh" for Hard/Elite mode.
    Defaults to "Normal" (or preserves the open modal's mode if both -MapName and -Mode are omitted while inside STAGE_MODAL).

.PARAMETER StartStage
    First stage number (Ải <N>) to run or preview (1..50). Default: 1.

.PARAMETER EndStage
    Last stage number (Ải <N>) to run. Default: 0 (runs through the final stage of the chapter).
    When > 0, must be >= StartStage, and execution stops immediately once EndStage finishes.

.PARAMETER SkipCleared
    If set, skips any stage in the requested range that already has >= 1 earned star.

.PARAMETER ListMaps
    Navigates to the Adventure Map selector, prints all discoverable chapter names and CLI aliases,
    saves a map screenshot, and exits without fighting.

.PARAMETER DryRun
    Navigates to -MapName and -Mode, opens STAGE_MODAL, scrolls to and selects -StartStage,
    logs lock/star/button status, saves a preview screenshot, and exits WITHOUT tapping "Vào ải".

.PARAMETER StageTimeoutSec
    Maximum seconds to wait for a single stage battle to reach VICTORY_EVAL. Default: 120.

.PARAMETER AdbPath
    Path to BlueStacks ADB executable. Default: "C:\Program Files\BlueStacks_nxt\HD-Adb.exe".

.PARAMETER Serial
    ADB device serial. Default: "127.0.0.1:5555".

.PARAMETER OutputDir
    Directory for live/preview/victory screenshots. Default: "scratch" (relative to script folder if not rooted).

.EXAMPLE
    .\run_pokemon_stages.ps1 -ListMaps
    Opens the Adventure Map and lists all discoverable Vietnamese & ASCII map names without starting a battle.

.EXAMPLE
    .\run_pokemon_stages.ps1 -MapName "Tinh Ca Sa Mac" -Mode Hard -StartStage 7 -EndStage 7 -DryRun
    Navigates to Tình Ca Sa Mạc [Elite], selects Ải 7, logs star/lock status, saves a preview PNG, and exits.

.EXAMPLE
    .\run_pokemon_stages.ps1 -MapName "Dong Bang Sao" -Mode Hard -StartStage 1 -EndStage 8 -DryRun
    Navigates to Đồng Bằng Sao [Elite], selects Ải 1, verifies status, saves a preview PNG, and exits.

.EXAMPLE
    .\run_pokemon_stages.ps1 -MapName "Tình Ca Sa Mạc" -Mode Normal -StartStage 8 -EndStage 12 -SkipCleared
    Runs Ải 8 through Ải 12 on Tình Ca Sa Mạc (Normal), skipping stages that already have >= 1 star.

.EXAMPLE
    .\run_pokemon_stages.ps1 -MapName "Đồng Bằng Sao" -Mode Hard -StartStage 1 -EndStage 0 -SkipCleared
    Runs Đồng Bằng Sao [Elite] from Ải 1 through the end of the chapter, stopping cleanly after the last stage.

.EXAMPLE
    .\run_pokemon_stages.ps1 -Mode Hard -StartStage 5 -EndStage 7
    Uses the currently open Stage Modal's map, ensures Hard/Elite mode, and clears Ải 5 through Ải 7.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string]$MapName = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Normal", "Hard", "Elite", "Thuong", "TinhAnh")]
    [string]$Mode = "Normal",

    [Parameter(Mandatory = $false)]
    [int]$StartStage = 1,

    [Parameter(Mandatory = $false)]
    [int]$EndStage = 0,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCleared,

    [Parameter(Mandatory = $false)]
    [switch]$Chain,

    [Parameter(Mandatory = $false)]
    [switch]$ListMaps,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [ValidateRange(15, 600)]
    [int]$StageTimeoutSec = 120,

    [Parameter(Mandatory = $false)]
    [string]$AdbPath = "C:\Program Files\BlueStacks_nxt\HD-Adb.exe",

    [Parameter(Mandatory = $false)]
    [string]$Serial = "127.0.0.1:5555",

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = "scratch",

    [Parameter(Mandatory = $false)]
    [ValidateSet("auto", "en", "vi")]
    [string]$Lang = "auto"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Preload assemblies at script scope so [System.Drawing.Bitmap] parameter types always resolve
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime

#region Logging & Parameter Validation
function Write-Log {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Message)
    $ts = (Get-Date).ToString("HH:mm:ss")
    Write-Host "[$ts] $Message"
}

if (-not $ListMaps) {
    if ($StartStage -lt 1 -or $StartStage -gt 50) {
        Write-Log "ERROR: Invalid -StartStage ($StartStage). Must be between 1 and 50."
        exit 1
    }
    if ($EndStage -lt 0 -or $EndStage -gt 50) {
        Write-Log "ERROR: Invalid -EndStage ($EndStage). Must be 0 (run to chapter end) or between 1 and 50."
        exit 1
    }
    if ($EndStage -gt 0 -and $EndStage -lt $StartStage) {
        Write-Log "ERROR: Invalid stage range: -EndStage ($EndStage) must be >= -StartStage ($StartStage) (or 0 for chapter end)."
        exit 1
    }
}

$script:ModeExplicitlyBound = $PSBoundParameters.ContainsKey('Mode')
$script:WantElite = ($Mode -in @('Hard', 'Elite', 'TinhAnh'))
$script:CanonicalMode = if ($script:WantElite) { 'Hard' } else { 'Normal' }

$baseDir = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { (Get-Location).Path }
$script:ResolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir
} else {
    Join-Path $baseDir $OutputDir
}
if (-not (Test-Path -LiteralPath $script:ResolvedOutputDir)) {
    New-Item -ItemType Directory -Path $script:ResolvedOutputDir -Force | Out-Null
}
$script:LiveScreenPath = Join-Path $script:ResolvedOutputDir "screen_live.png"
$script:RemoteScreenPath = "/sdcard/pokemon_stage_runner.png"
#endregion

#region WinRT OCR & Fast C# LockBits Engine
function Initialize-PokemonOcr {
    if (Get-Variable -Name PokemonStageOcrReady -Scope Script -ValueOnly -ErrorAction SilentlyContinue) { return }

    $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime]

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

    if (-not ('PokemonStageNative' -as [type])) {
        $csCode = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public sealed class PokemonStageRow {
    public int Stage;
    public int CenterY;
    public int AiTopY;
    public int AiBottomY;
    public bool IsSelected;
    public bool IsLocked;
    public int Stars;
}

public static class PokemonStageNative {
    public static Bitmap CropAndScale(Bitmap src, int x, int y, int w, int h, int scale, int mode, int padBase, out int redShiftStartCol, out int redShiftPx) {
        redShiftStartCol = -1;
        redShiftPx = 0;
        if (scale < 1) scale = 1;
        if (x < 0) x = 0;
        if (y < 0) y = 0;
        if (x + w > src.Width) w = src.Width - x;
        if (y + h > src.Height) h = src.Height - y;
        if (w <= 0 || h <= 0) throw new ArgumentException("Empty crop rectangle.");

        int pad = padBase * scale;
        int extraGap = (mode == 1) ? (6 * scale) : 0;

        int redStartSrcX = -1;
        if (mode == 1) {
            BitmapData sbd = src.LockBits(new Rectangle(x, y, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try {
                byte[] sbuf = new byte[Math.Abs(sbd.Stride) * h];
                Marshal.Copy(sbd.Scan0, sbuf, 0, sbuf.Length);
                bool seenWhite = false;
                for (int cx = 0; cx < w; cx++) {
                    int redCol = 0, whiteCol = 0;
                    for (int cy = 0; cy < h; cy++) {
                        int idx = cy * sbd.Stride + cx * 4;
                        byte b = sbuf[idx], g = sbuf[idx + 1], r = sbuf[idx + 2];
                        if (r > 185 && g > 185 && b > 185) whiteCol++;
                        else if (r > 165 && (r - g) > 75 && (r - b) > 75) redCol++;
                    }
                    if (whiteCol >= 2) seenWhite = true;
                    if (seenWhite && redCol >= 2) {
                        redStartSrcX = cx;
                        break;
                    }
                }
            } finally {
                src.UnlockBits(sbd);
            }
        }

        if (redStartSrcX < 0) extraGap = 0;
        int dstW = w * scale + pad * 2 + extraGap;
        int dstH = h * scale + pad * 2;

        Bitmap dst = new Bitmap(dstW, dstH, PixelFormat.Format24bppRgb);
        using (Graphics g = Graphics.FromImage(dst)) {
            g.Clear(mode == 0 ? Color.Black : Color.White);
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.SmoothingMode = SmoothingMode.HighQuality;
            if (redStartSrcX > 0 && extraGap > 0) {
                int leftW = redStartSrcX;
                int rightW = w - redStartSrcX;
                g.DrawImage(src, new Rectangle(pad, pad, leftW * scale, h * scale), new Rectangle(x, y, leftW, h), GraphicsUnit.Pixel);
                g.DrawImage(src, new Rectangle(pad + leftW * scale + extraGap, pad, rightW * scale, h * scale), new Rectangle(x + redStartSrcX, y, rightW, h), GraphicsUnit.Pixel);
                redShiftStartCol = pad + leftW * scale + extraGap;
                redShiftPx = extraGap;
            } else {
                g.DrawImage(src, new Rectangle(pad, pad, w * scale, h * scale), new Rectangle(x, y, w, h), GraphicsUnit.Pixel);
            }
        }

        if (mode == 0) return dst;

        BitmapData dbd = dst.LockBits(new Rectangle(0, 0, dstW, dstH), ImageLockMode.ReadWrite, PixelFormat.Format24bppRgb);
        try {
            byte[] buf = new byte[Math.Abs(dbd.Stride) * dstH];
            Marshal.Copy(dbd.Scan0, buf, 0, buf.Length);
            for (int py = pad; py < dstH - pad; py++) {
                int row = py * dbd.Stride;
                for (int px = pad; px < dstW - pad; px++) {
                    int idx = row + px * 3;
                    byte b = buf[idx], g = buf[idx + 1], r = buf[idx + 2];
                    int maxc = r > g ? (r > b ? r : b) : (g > b ? g : b);
                    int v = 255;
                    if (mode == 1) {
                        bool isRed = (r > 150 && (r - g) > 55 && (r - b) > 55);
                        if (isRed) {
                            int strength = Math.Min(255, (r - 115) * 2 + (r - g));
                            v = 255 - Math.Min(255, strength);
                        } else if (maxc > 155 && g > 135) {
                            int strength = Math.Min(255, (maxc - 125) * 2);
                            v = 255 - strength;
                        }
                    } else if (mode == 2) {
                        int luma = (r * 299 + g * 587 + b * 114) / 1000;
                        int sig = g > luma ? g : luma;
                        if (sig > 165) {
                            int strength = Math.Min(255, (sig - 130) * 2);
                            v = 255 - strength;
                        }
                    }
                    byte bv = (byte)(v < 0 ? 0 : (v > 255 ? 255 : v));
                    buf[idx] = bv; buf[idx + 1] = bv; buf[idx + 2] = bv;
                }
            }
            Marshal.Copy(buf, 0, dbd.Scan0, buf.Length);
        } finally {
            dst.UnlockBits(dbd);
        }
        return dst;
    }

    public static bool HasRedBadge(Bitmap src, int x, int y, int w, int h) {
        if (x < 0) x = 0; if (y < 0) y = 0;
        if (x + w > src.Width) w = src.Width - x;
        if (y + h > src.Height) h = src.Height - y;
        if (w <= 0 || h <= 0) return false;
        BitmapData bd = src.LockBits(new Rectangle(x, y, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try {
            byte[] buf = new byte[Math.Abs(bd.Stride) * h];
            Marshal.Copy(bd.Scan0, buf, 0, buf.Length);
            int hits = 0;
            for (int py = 0; py < h; py++) {
                int row = py * bd.Stride;
                for (int px = 0; px < w; px++) {
                    int idx = row + px * 4;
                    byte b = buf[idx], g = buf[idx + 1], r = buf[idx + 2];
                    if (r >= 175 && g <= 65 && b <= 65 && (r - g) >= 110) hits++;
                }
            }
            return hits >= 20;
        } finally {
            src.UnlockBits(bd);
        }
    }

    private static bool IsCloseWhitePx(byte r, byte g, byte b) {
        if (r < 195 || g < 190 || b < 190) return false;
        int max = r > g ? (r > b ? r : b) : (g > b ? g : b);
        int min = r < g ? (r < b ? r : b) : (g < b ? g : b);
        return (max - min) <= 40;
    }

    private static bool IsCloseRedPx(byte r, byte g, byte b) {
        return (r >= 145 && g <= 125 && b <= 135 && (r - g) >= 68 && (r - b) >= 55);
    }

    private static bool HasCloseWhiteNear(byte[] buf, int stride, int w, int h, int x, int y, int tol) {
        for (int dy = -tol; dy <= tol; dy++) {
            int py = y + dy;
            if (py < 0 || py >= h) continue;
            int row = py * stride;
            for (int dx = -tol; dx <= tol; dx++) {
                int px = x + dx;
                if (px < 0 || px >= w) continue;
                int idx = row + px * 4;
                if (IsCloseWhitePx(buf[idx + 2], buf[idx + 1], buf[idx])) return true;
            }
        }
        return false;
    }

    private static bool HasCloseRedNear(byte[] buf, int stride, int w, int h, int x, int y, int tol) {
        for (int dy = -tol; dy <= tol; dy++) {
            int py = y + dy;
            if (py < 0 || py >= h) continue;
            int row = py * stride;
            for (int dx = -tol; dx <= tol; dx++) {
                int px = x + dx;
                if (px < 0 || px >= w) continue;
                int idx = row + px * 4;
                if (IsCloseRedPx(buf[idx + 2], buf[idx + 1], buf[idx])) return true;
            }
        }
        return false;
    }

    private static readonly double[] CloseDirX = new double[] { 1, -1, 0, 0, 0.7071, -0.7071, 0.7071, -0.7071 };
    private static readonly double[] CloseDirY = new double[] { 0, 0, 1, -1, 0.7071, 0.7071, -0.7071, -0.7071 };
    private static readonly int[] CloseRingRadii = new int[] { 18, 21, 24, 27, 29, 31 };

    public static Point FindRedCloseX(Bitmap src, int x1, int y1, int x2, int y2) {
        if (x1 < 0) x1 = 0; if (y1 < 0) y1 = 0;
        if (x2 >= src.Width) x2 = src.Width - 1;
        if (y2 >= src.Height) y2 = src.Height - 1;
        int w = x2 - x1 + 1, h = y2 - y1 + 1;
        if (w <= 50 || h <= 50) return new Point(-1, -1);

        BitmapData bd = src.LockBits(new Rectangle(x1, y1, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try {
            int stride = bd.Stride;
            byte[] buf = new byte[Math.Abs(stride) * h];
            Marshal.Copy(bd.Scan0, buf, 0, buf.Length);
            Point bestPt = new Point(-1, -1);
            int bestScore = 0;

            for (int cy = 22; cy < h - 22; cy += 2) {
                for (int cx = 22; cx < w - 22; cx += 2) {
                    if (!HasCloseWhiteNear(buf, stride, w, h, cx, cy, 1)) continue;

                    foreach (int ringR in CloseRingRadii) {
                        if (cx - ringR - 4 < 0 || cx + ringR + 4 >= w || cy - ringR - 4 < 0 || cy + ringR + 4 >= h) continue;

                        // 1. Require 4 symmetric cardinal red wedges (E, W, S, N) between the X strokes
                        int c1 = (int)Math.Round(ringR * 0.46);
                        int c2 = (int)Math.Round(ringR * 0.66);
                        if (!HasCloseRedNear(buf, stride, w, h, cx + c1, cy, 1) || !HasCloseRedNear(buf, stride, w, h, cx + c2, cy, 1)) continue;
                        if (!HasCloseRedNear(buf, stride, w, h, cx - c1, cy, 1) || !HasCloseRedNear(buf, stride, w, h, cx - c2, cy, 1)) continue;
                        if (!HasCloseRedNear(buf, stride, w, h, cx, cy + c1, 1) || !HasCloseRedNear(buf, stride, w, h, cx, cy + c2, 1)) continue;
                        if (!HasCloseRedNear(buf, stride, w, h, cx, cy - c1, 1) || !HasCloseRedNear(buf, stride, w, h, cx, cy - c2, 1)) continue;

                        // 2. Require 4 diagonal white X arms (SE, SW, NE, NW)
                        int d1 = (int)Math.Round(ringR * 0.30);
                        int d2 = (int)Math.Round(ringR * 0.47);
                        if (!HasCloseWhiteNear(buf, stride, w, h, cx + d1, cy + d1, 1) || !HasCloseWhiteNear(buf, stride, w, h, cx + d2, cy + d2, 1)) continue;
                        if (!HasCloseWhiteNear(buf, stride, w, h, cx - d1, cy + d1, 1) || !HasCloseWhiteNear(buf, stride, w, h, cx - d2, cy + d2, 1)) continue;
                        if (!HasCloseWhiteNear(buf, stride, w, h, cx + d1, cy - d1, 1) || !HasCloseWhiteNear(buf, stride, w, h, cx + d2, cy - d2, 1)) continue;
                        if (!HasCloseWhiteNear(buf, stride, w, h, cx - d1, cy - d1, 1) || !HasCloseWhiteNear(buf, stride, w, h, cx - d2, cy - d2, 1)) continue;

                        // 3. Require circular white outer ring across >=7/8 compass directions & non-red exterior
                        int ringWhiteDirs = 0;
                        int outsideRedDirs = 0;
                        for (int dir = 0; dir < 8; dir++) {
                            bool hitRing = false;
                            for (int dr = -2; dr <= 2; dr++) {
                                int rx = cx + (int)Math.Round((ringR + dr) * CloseDirX[dir]);
                                int ry = cy + (int)Math.Round((ringR + dr) * CloseDirY[dir]);
                                int rIdx = ry * stride + rx * 4;
                                if (IsCloseWhitePx(buf[rIdx + 2], buf[rIdx + 1], buf[rIdx])) {
                                    hitRing = true;
                                    break;
                                }
                            }
                            if (hitRing) ringWhiteDirs++;

                            int ox = cx + (int)Math.Round((ringR + 6) * CloseDirX[dir]);
                            int oy = cy + (int)Math.Round((ringR + 6) * CloseDirY[dir]);
                            if (ox >= 0 && ox < w && oy >= 0 && oy < h) {
                                int oIdx = oy * stride + ox * 4;
                                if (IsCloseRedPx(buf[oIdx + 2], buf[oIdx + 1], buf[oIdx])) outsideRedDirs++;
                            }
                        }
                        if (ringWhiteDirs < 7 || outsideRedDirs > 2) continue;

                        // 4. Score interior red disc + white X density
                        int redCnt = 0, whiteCnt = 0;
                        int innerR = ringR - 4;
                        for (int dy = -innerR; dy <= innerR; dy += 2) {
                            int row = (cy + dy) * stride;
                            for (int dx = -innerR; dx <= innerR; dx += 2) {
                                if (dx * dx + dy * dy > innerR * innerR) continue;
                                int idx = row + (cx + dx) * 4;
                                byte b = buf[idx], g = buf[idx + 1], r = buf[idx + 2];
                                if (IsCloseRedPx(r, g, b)) redCnt++;
                                else if (IsCloseWhitePx(r, g, b)) whiteCnt++;
                            }
                        }
                        int areaSamples = Math.Max(1, (innerR * innerR * 3) / 4);
                        if (redCnt < areaSamples * 0.30 || whiteCnt < areaSamples * 0.12) continue;

                        int score = ringWhiteDirs * 50 + redCnt + whiteCnt * 2;
                        if (score > bestScore) {
                            bestScore = score;
                            bestPt = new Point(x1 + cx, y1 + cy);
                        }
                    }
                }
            }
            return bestPt;
        } finally {
            src.UnlockBits(bd);
        }
    }

    private static bool IsCyanGlyph(byte r, byte g, byte b) {
        return (r >= 58 && g >= 198 && b >= 185);
    }

    private static readonly int[] WideDigits = new int[] { 0, 2, 3, 4, 5, 6, 7, 8, 9 };
    private static readonly double[,] Prototypes = new double[,] {
        { 0.80, 0.67, 0.67, 0.42, 0.67, 0.67, 0.00 }, // 0
        { 0.80, 0.72, 0.31, 0.46, 0.89, 0.14, 0.80 }, // 2
        { 0.82, 0.86, 0.89, 0.46, 0.22, 0.11, 0.82 }, // 3
        { 0.06, 0.67, 0.89, 0.00, 0.67, 0.83, 0.32 }, // 4
        { 0.80, 0.14, 0.81, 0.40, 0.31, 0.78, 0.80 }, // 5
        { 0.80, 0.17, 0.78, 0.42, 0.78, 0.75, 0.82 }, // 6
        { 0.84, 0.64, 0.14, 0.51, 0.03, 0.00, 0.47 }, // 7
        { 0.80, 0.72, 0.81, 0.44, 0.81, 0.72, 0.80 }, // 8
        { 0.80, 0.86, 0.89, 0.40, 0.33, 0.86, 0.80 }  // 9
    };

    private static double BoxDensity(byte[] buf, int stride, int x1, int y1, int w, int h, double rx1, double rx2, double ry1, double ry2) {
        int px1 = x1 + (int)Math.Floor(rx1 * (w - 1));
        int px2 = x1 + (int)Math.Ceiling(rx2 * (w - 1));
        int py1 = y1 + (int)Math.Floor(ry1 * (h - 1));
        int py2 = y1 + (int)Math.Ceiling(ry2 * (h - 1));
        int tot = 0, hit = 0;
        for (int yy = py1; yy <= py2; yy++) {
            int row = yy * stride;
            for (int xx = px1; xx <= px2; xx++) {
                tot++;
                int idx = row + xx * 4;
                if (IsCyanGlyph(buf[idx + 2], buf[idx + 1], buf[idx])) hit++;
            }
        }
        return tot == 0 ? 0.0 : (double)hit / tot;
    }

    private static int DecodeSingleDigit(byte[] buf, int stride, int x1, int x2, int y1, int y2) {
        int w = x2 - x1 + 1;
        int h = y2 - y1 + 1;
        if (h < 15 || h > 27 || w < 4 || w > 25) return -1;
        if ((double)w / h < 0.58) return 1;

        double[] feat = new double[7] {
            BoxDensity(buf, stride, x1, y1, w, h, 0.28, 0.72, 0.00, 0.20),
            BoxDensity(buf, stride, x1, y1, w, h, 0.74, 1.00, 0.20, 0.42),
            BoxDensity(buf, stride, x1, y1, w, h, 0.74, 1.00, 0.58, 0.80),
            BoxDensity(buf, stride, x1, y1, w, h, 0.28, 0.72, 0.80, 1.00),
            BoxDensity(buf, stride, x1, y1, w, h, 0.00, 0.26, 0.58, 0.80),
            BoxDensity(buf, stride, x1, y1, w, h, 0.00, 0.26, 0.20, 0.42),
            BoxDensity(buf, stride, x1, y1, w, h, 0.28, 0.72, 0.40, 0.60)
        };

        int bestDigit = -1;
        double bestDist = 999.0;
        for (int i = 0; i < WideDigits.Length; i++) {
            double dist = 0.0;
            for (int k = 0; k < 7; k++) {
                dist += Math.Abs(feat[k] - Prototypes[i, k]);
            }
            if (dist < bestDist) {
                bestDist = dist;
                bestDigit = WideDigits[i];
            }
        }
        return bestDist <= 1.35 ? bestDigit : -1;
    }

    private static int DecodeNumberInBox(byte[] buf, int stride, int imgW, int imgH, int bx1, int bx2, int by1, int by2) {
        if (bx1 < 0) bx1 = 0; if (by1 < 0) by1 = 0;
        if (bx2 >= imgW) bx2 = imgW - 1; if (by2 >= imgH) by2 = imgH - 1;
        bool inCol = false;
        int sx = 0;
        int acc = 0;
        int digitsFound = 0;

        for (int x = bx1; x <= bx2 + 1; x++) {
            int cc = 0;
            if (x <= bx2) {
                for (int y = by1; y <= by2; y++) {
                    int idx = y * stride + x * 4;
                    if (IsCyanGlyph(buf[idx + 2], buf[idx + 1], buf[idx])) cc++;
                }
            }
            if (cc >= 1 && !inCol) {
                inCol = true;
                sx = x;
            } else if (cc == 0 && inCol) {
                inCol = false;
                int ex = x - 1;
                int bw = ex - sx + 1;
                if (bw < 4 || bw > 25) continue;
                int ty1 = 9999, ty2 = -1;
                for (int yy = by1; yy <= by2; yy++) {
                    int row = yy * stride;
                    for (int xx = sx; xx <= ex; xx++) {
                        int idx = row + xx * 4;
                        if (IsCyanGlyph(buf[idx + 2], buf[idx + 1], buf[idx])) {
                            if (yy < ty1) ty1 = yy;
                            if (yy > ty2) ty2 = yy;
                        }
                    }
                }
                if (ty2 >= ty1) {
                    int d = DecodeSingleDigit(buf, stride, sx, ex, ty1, ty2);
                    if (d >= 0) {
                        acc = acc * 10 + d;
                        digitsFound++;
                    }
                }
            }
        }
        return digitsFound > 0 ? acc : -1;
    }

    public static int ReadTopBannerStage(Bitmap src) {
        if (src.Width < 1150 || src.Height < 100) return -1;
        BitmapData bd = src.LockBits(new Rectangle(0, 0, src.Width, src.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try {
            byte[] buf = new byte[Math.Abs(bd.Stride) * src.Height];
            Marshal.Copy(bd.Scan0, buf, 0, buf.Length);
            return DecodeNumberInBox(buf, bd.Stride, src.Width, src.Height, 1020, 1130, 44, 76);
        } finally {
            src.UnlockBits(bd);
        }
    }

    public static PokemonStageRow[] ScanStageRows(Bitmap src) {
        List<PokemonStageRow> list = new List<PokemonStageRow>();
        if (src.Width < 520 || src.Height < 880) return list.ToArray();

        BitmapData bd = src.LockBits(new Rectangle(0, 0, src.Width, src.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try {
            int stride = bd.Stride;
            byte[] buf = new byte[Math.Abs(stride) * src.Height];
            Marshal.Copy(bd.Scan0, buf, 0, buf.Length);

            bool inRow = false;
            int startY = 0;
            for (int y = 218; y <= 877; y++) {
                int cnt = 0;
                if (y <= 876) {
                    int row = y * stride;
                    for (int x = 168; x <= 208; x++) {
                        int idx = row + x * 4;
                        if (IsCyanGlyph(buf[idx + 2], buf[idx + 1], buf[idx])) cnt++;
                    }
                }
                if (cnt >= 3 && !inRow) {
                    inRow = true;
                    startY = y;
                } else if (cnt < 3 && inRow) {
                    inRow = false;
                    int endY = y - 1;
                    int h = endY - startY + 1;
                    if (h >= 19 && startY >= 222 && endY <= 872) {
                        int cy = (startY + endY) / 2;
                        int stageNum = DecodeNumberInBox(buf, stride, src.Width, src.Height, 265, 355, Math.Max(215, startY - 16), Math.Min(878, startY + 13));
                        if (stageNum > 0) {
                            int selIdx = (cy - 8) * stride + 250 * 4;
                            bool isSelected = (buf[selIdx + 2] < 25 && buf[selIdx + 1] > 150 && buf[selIdx] > 200);

                            int goldPts = 0;
                            for (int py = cy - 28; py <= cy + 12; py += 2) {
                                int prow = py * stride;
                                for (int px = 408; px <= 446; px += 2) {
                                    int pidx = prow + px * 4;
                                    byte pb = buf[pidx], pg = buf[pidx + 1], pr = buf[pidx + 2];
                                    if (pr > 185 && pg > 155 && pb > 85 && pb < 175 && (pr - pb) > 40) goldPts++;
                                }
                            }
                            int s1Idx = (cy - 5) * stride + 372 * 4;
                            byte s1b = buf[s1Idx], s1g = buf[s1Idx + 1], s1r = buf[s1Idx + 2];
                            bool s1Orange = (s1r > 200 && s1g > 130 && s1b < 140);
                            bool s1EmptyStar = (s1r < 40 && s1g < 85 && s1b < 130);
                            bool isLocked = (goldPts >= 70 && !s1Orange && !s1EmptyStar);

                            int stars = 0;
                            if (!isLocked) {
                                int[] starXs = new int[] { 372, 407, 442, 477 };
                                foreach (int sx in starXs) {
                                    int sIdx = (cy - 5) * stride + sx * 4;
                                    byte sb = buf[sIdx], sg = buf[sIdx + 1], sr = buf[sIdx + 2];
                                    if (sr > 205 && sg > 120 && sg < 205 && (sr - sg) >= 20 && sb < 110) stars++;
                                }
                            }

                            PokemonStageRow info = new PokemonStageRow();
                            info.Stage = stageNum;
                            info.CenterY = cy;
                            info.AiTopY = startY;
                            info.AiBottomY = endY;
                            info.IsSelected = isSelected;
                            info.IsLocked = isLocked;
                            info.Stars = stars;
                            list.Add(info);
                        }
                    }
                }
            }
        } finally {
            src.UnlockBits(bd);
        }
        return list.ToArray();
    }
}
"@
        Add-Type -TypeDefinition $csCode -ReferencedAssemblies System.Drawing
    }

    $script:PokemonStageOcrReady = $true
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

    $s = $Text.Replace([char]0x0111, 'd').Replace([char]0x0110, 'd').Replace([char]0x00F0, 'd').Replace([char]0x00D0, 'd')
    $norm = $s.Normalize([System.Text.NormalizationForm]::FormD)
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

function Clean-MapQueryText {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $norm = Remove-Diacritics $Text
    if (-not $norm) { return '' }
    $norm = [regex]::Replace($norm, '\s*(?:[\[\(i1l\|]*\s*)?(elite|hard|norma\w*|nornna\w*|thuong|tinh\s*anh|t\.a)(?:\s*[\]\)]*)?\s*$', '')
    return ($norm -replace '[-_]+', ' ' -replace '\s+', ' ').Trim()
}

function Normalize-OcrVietnamese {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $b = Clean-MapQueryText $Text
    if (-not $b) { return '' }
    return ($b `
        -replace 'lcra', 'lua' `
        -replace 'lila', 'lua' `
        -replace 'vcrc', 'vuc' `
        -replace 'thcrc', 'thuc' `
        -replace 'hoi crc', 'hoi uc' `
        -replace 'hoi lrc', 'hoi uc' `
        -replace 'suang', 'suong' `
        -replace 'trdi', 'troi' `
        -replace 'mot troi', 'mat troi' `
        -replace 'chu vong', 'cau vong')
}

function Get-StringSimilarity {
    param([string]$A, [string]$B)
    if (-not $A -or -not $B) { return 0.0 }
    if ($A -eq $B) { return 1.0 }
    $n = $A.Length; $m = $B.Length
    $dp = New-Object 'int[,]' ($n + 1), ($m + 1)
    for ($i = 0; $i -le $n; $i++) { $dp[$i, 0] = $i }
    for ($j = 0; $j -le $m; $j++) { $dp[0, $j] = $j }
    for ($i = 1; $i -le $n; $i++) {
        for ($j = 1; $j -le $m; $j++) {
            $cost = if ($A[$i - 1] -eq $B[$j - 1]) { 0 } else { 1 }
            $del = $dp[($i - 1), $j] + 1
            $ins = $dp[$i, ($j - 1)] + 1
            $sub = $dp[($i - 1), ($j - 1)] + $cost
            $dp[$i, $j] = [Math]::Min($del, [Math]::Min($ins, $sub))
        }
    }
    $maxLen = [Math]::Max($n, $m)
    return (1.0 - ($dp[$n, $m] / [double]$maxLen))
}

function Test-MapNameMatch {
    param(
        [AllowNull()][AllowEmptyString()][string]$ExpectedMapName = "",
        [AllowNull()][AllowEmptyString()][string]$OcrText = "",
        [double]$MinSimilarity = 0.78
    )
    $a = Normalize-OcrVietnamese $ExpectedMapName
    $b = Normalize-OcrVietnamese $OcrText
    if (-not $a -or -not $b) { return $false }
    if ($a -eq $b -or $b.Contains($a) -or $a.Contains($b)) { return $true }
    return ((Get-StringSimilarity -A $a -B $b) -ge $MinSimilarity)
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
        [ValidateRange(1, 4)][int]$Scale = 2,
        [ValidateSet('None', 'HeaderWithRed', 'LightText')][string]$Preprocess = 'None'
    )
    Initialize-PokemonOcr
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $ownsBitmap = $false
    if (-not $Bitmap) {
        $Bitmap = Open-UnlockedBitmap -ImagePath $ImagePath
        $ownsBitmap = $true
    }

    $modeInt = switch ($Preprocess) {
        'None'          { 0 }
        'HeaderWithRed' { 1 }
        'LightText'     { 2 }
    }

    $padBase = 12
    $padPx = $padBase * $Scale
    $subBmp = $null
    $pngStream = $null
    $memStream = $null
    $ras = $null
    $softBmp = $null

    try {
        if ($Width -le 0)  { $Width  = $Bitmap.Width - $X }
        if ($Height -le 0) { $Height = $Bitmap.Height - $Y }

        $redShiftStartCol = -1
        $redShiftPx = 0
        $subBmp = [PokemonStageNative]::CropAndScale($Bitmap, $X, $Y, $Width, $Height, $Scale, $modeInt, $padBase, [ref]$redShiftStartCol, [ref]$redShiftPx)

        $pngStream = New-Object System.IO.MemoryStream
        $subBmp.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngBytes = $pngStream.ToArray()
        $pngStream.Dispose(); $pngStream = $null
        $subBmp.Dispose(); $subBmp = $null

        $memStream = New-Object System.IO.MemoryStream(,$pngBytes)
        $ras = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($memStream)
        $decoder = Invoke-WinRtAwait ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $softBmp = Invoke-WinRtAwait ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $ocrResult = Invoke-WinRtAwait ($script:WinRtOcrEngine.RecognizeAsync($softBmp)) ([Windows.Media.Ocr.OcrResult])

        $allWords = New-Object System.Collections.Generic.List[object]
        $allLines = New-Object System.Collections.Generic.List[object]

        foreach ($line in $ocrResult.Lines) {
            $lineWords = New-Object System.Collections.Generic.List[object]
            $minX = [double]::PositiveInfinity; $minY = [double]::PositiveInfinity
            $maxX = [double]::NegativeInfinity; $maxY = [double]::NegativeInfinity

            foreach ($w in $line.Words) {
                $bx = $w.BoundingRect.X
                if ($redShiftStartCol -ge 0 -and $bx -ge $redShiftStartCol) {
                    $bx -= $redShiftPx
                }
                $sx = [math]::Round($X + ($bx - $padPx) / $Scale, 1)
                $sy = [math]::Round($Y + ($w.BoundingRect.Y - $padPx) / $Scale, 1)
                $swd = [math]::Round($w.BoundingRect.Width / $Scale, 1)
                $sht = [math]::Round($w.BoundingRect.Height / $Scale, 1)
                $cx = [int][math]::Round($sx + $swd / 2.0)
                $cy = [int][math]::Round($sy + $sht / 2.0)

                if ($sx -lt $minX) { $minX = $sx }
                if ($sy -lt $minY) { $minY = $sy }
                if (($sx + $swd) -gt $maxX) { $maxX = $sx + $swd }
                if (($sy + $sht) -gt $maxY) { $maxY = $sy + $sht }

                $wObj = [pscustomobject]@{
                    Text           = $w.Text
                    NormalizedText = (Remove-Diacritics $w.Text)
                    X              = $sx
                    Y              = $sy
                    Width          = $swd
                    Height         = $sht
                    CenterX        = $cx
                    CenterY        = $cy
                }
                $lineWords.Add($wObj)
                $allWords.Add($wObj)
            }

            $lw = if ($lineWords.Count -gt 0) { [math]::Round($maxX - $minX, 1) } else { 0 }
            $lh = if ($lineWords.Count -gt 0) { [math]::Round($maxY - $minY, 1) } else { 0 }
            $lx = if ($lineWords.Count -gt 0) { $minX } else { 0 }
            $ly = if ($lineWords.Count -gt 0) { $minY } else { 0 }

            $allLines.Add([pscustomobject]@{
                Text           = $line.Text
                NormalizedText = (Remove-Diacritics $line.Text)
                X              = $lx
                Y              = $ly
                Width          = $lw
                Height         = $lh
                CenterX        = [int][math]::Round($lx + $lw / 2.0)
                CenterY        = [int][math]::Round($ly + $lh / 2.0)
                Words          = $lineWords.ToArray()
            })
        }

        $joinedText = ($allLines | ForEach-Object { $_.Text }) -join ' '
        $sw.Stop()

        return [pscustomobject]@{
            Text           = $joinedText
            NormalizedText = (Remove-Diacritics $joinedText)
            Lines          = $allLines.ToArray()
            Words          = $allWords.ToArray()
            ElapsedMs      = $sw.ElapsedMilliseconds
        }
    } finally {
        if ($softBmp)   { $softBmp.Dispose() }
        if ($ras)       { $ras.Dispose() }
        if ($memStream) { $memStream.Dispose() }
        if ($pngStream) { $pngStream.Dispose() }
        if ($subBmp)    { $subBmp.Dispose() }
        if ($ownsBitmap -and $Bitmap) { $Bitmap.Dispose() }
    }
}

function Get-StageListRows {
    param(
        [string]$ImagePath,
        [System.Drawing.Bitmap]$Bitmap
    )
    Initialize-PokemonOcr
    $owns = $false
    if (-not $Bitmap) {
        $Bitmap = Open-UnlockedBitmap -ImagePath $ImagePath
        $owns = $true
    }
    try {
        $rawRows = [PokemonStageNative]::ScanStageRows($Bitmap)
        $list = [System.Collections.Generic.List[object]]::new()
        if ($null -ne $rawRows) {
            foreach ($r in $rawRows) {
                $list.Add([pscustomobject]@{
                    Stage      = $r.Stage
                    CenterY    = $r.CenterY
                    TapX       = 200
                    TapY       = $r.CenterY
                    IsSelected = $r.IsSelected
                    IsLocked   = $r.IsLocked
                    Stars      = $r.Stars
                })
            }
        }
        return ,$list.ToArray()
    } finally {
        if ($owns -and $Bitmap) { $Bitmap.Dispose() }
    }
}

function Get-StageModalInfo {
    param(
        [string]$ImagePath,
        [System.Drawing.Bitmap]$Bitmap
    )
    Initialize-PokemonOcr
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $owns = $false
    if (-not $Bitmap) {
        $Bitmap = Open-UnlockedBitmap -ImagePath $ImagePath
        $owns = $true
    }
    try {
        $titleOcr = Invoke-RegionOcr -Bitmap $Bitmap -X 145 -Y 66 -Width 420 -Height 40 -Scale 3 -Preprocess HeaderWithRed
        if ($titleOcr.NormalizedText.Length -lt 4) {
            $titleOcr = Invoke-RegionOcr -Bitmap $Bitmap -X 145 -Y 66 -Width 360 -Height 40 -Scale 3 -Preprocess LightText
        }
        $progOcr  = Invoke-RegionOcr -Bitmap $Bitmap -X 235 -Y 148 -Width 195 -Height 42 -Scale 2 -Preprocess LightText
        $hasRed   = [PokemonStageNative]::HasRedBadge($Bitmap, 145, 66, 375, 40)
        $topStage = [PokemonStageNative]::ReadTopBannerStage($Bitmap)
        $rows     = Get-StageListRows -Bitmap $Bitmap   # already Object[] from ,$list.ToArray()

        $pFrame   = $Bitmap.GetPixel(534, 96)
        $marqueeOccluded = (([int]$pFrame.B - [int]$pFrame.R) -ge 25) -or ($pFrame.R -lt 45)

        $rawTitle = $titleOcr.Text
        $normTitle = $titleOcr.NormalizedText
        $baseMap   = ([regex]::Replace($normTitle, '\s*[\[\(i1l\|]*\s*(elite|hard|normal|thuong)\s*[\]\)]*\s*$', '')).Trim()
        $isHeaderOccluded = $marqueeOccluded -or ($baseMap.Length -lt 4)

        $triesRaw = ""
        $isElite  = if ($rawTitle -match '(?i)elite') {
            $true
        } elseif ($rawTitle -match '(?i)norma|nornna|thuong') {
            $false
        } else {
            $hasRed
        }

        if ($isHeaderOccluded) {
            # Marquee-immune mode verification via 'Số lần còn' / 'Tries Left' at (1020, 248, 140, 46): '9/9' (Elite) vs 'Vô hạn' / 'Endless' (Normal)
            $triesOcr = Invoke-RegionOcr -Bitmap $Bitmap -X 1020 -Y 248 -Width 140 -Height 46 -Scale 2 -Preprocess LightText
            $triesRaw = $triesOcr.Text.Trim()
            if ($triesOcr.NormalizedText -match '/\s*9') {
                $isElite = $true
            } elseif ($triesOcr.NormalizedText -match 'vo\s*han|han|endless') {
                $isElite = $false
            }
        }

        $rawDisplay = if ($isElite -and $titleOcr.Text -and $titleOcr.Text -notmatch 'Elite') { "$($titleOcr.Text.Trim()) [Elite]" } else { $titleOcr.Text.Trim() }

        $sw.Stop()
        return [pscustomobject]@{
            ChapterTitleRaw        = $rawDisplay
            ChapterTitleNormalized = $normTitle
            MapBaseNameNormalized  = $baseMap
            IsHeaderOccluded       = $isHeaderOccluded
            IsElite                = $isElite
            TriesRaw               = $triesRaw
            StarProgress           = $progOcr.Text.Trim()
            SelectedStageBanner    = $topStage
            StageRows              = @($rows)
            ElapsedMs              = $sw.ElapsedMilliseconds
        }
    } finally {
        if ($owns -and $Bitmap) { $Bitmap.Dispose() }
    }
}

function Get-StableStageModalInfo {
    param([int]$MaxAttempts = 4)
    if ($MaxAttempts -lt 1) { $MaxAttempts = 1 }
    for ($waitTry = 1; $waitTry -le $MaxAttempts; $waitTry++) {
        $info = Get-StageModalInfo -ImagePath $script:LiveScreenPath
        if (-not $info.IsHeaderOccluded) {
            return $info
        }
        if ($waitTry -lt $MaxAttempts) {
            Write-Log "Server marquee banner temporarily occluding STAGE_MODAL header; waiting 0.8s ($waitTry/$($MaxAttempts - 1))..."
            Start-Sleep -Milliseconds 800
            Capture-Screen -OutPath $script:LiveScreenPath
        } else {
            return $info
        }
    }
}
function Get-MaxStagesFromStarProgress {
    param([AllowNull()][AllowEmptyString()][string]$StarProgress)
    if ([string]::IsNullOrWhiteSpace($StarProgress)) { return 0 }
    $clean = $StarProgress.Trim() -replace '(?<=[\d/])[oO]|[oO](?=[\d/])', '0'
    if ($clean -match '(\d+)\s*/\s*(\d+)') {
        $earnedStars = 0
        $totalStars  = 0
        if ([int]::TryParse($Matches[1], [ref]$earnedStars) -and [int]::TryParse($Matches[2], [ref]$totalStars)) {
            if ($totalStars -ge 4 -and $totalStars -le 200 -and ($totalStars % 4) -eq 0 -and $earnedStars -ge 0 -and $earnedStars -le $totalStars) {
                return [int]($totalStars / 4)
            }
        }
    }
    return 0
}
#endregion

#region Region 1 Chapter Catalog & Map Matching
$script:Region1Catalog = @(
    [pscustomobject]@{ Chapter = 1;  ViName = "Đầm Lầy Cầu Vồng"; AsciiName = "Dam Lay Cau Vong"; Normalized = "dam lay cau vong"; PtLabel = "Campo Arco-Íris";      PtNormalized = "campo arco iris";      Anchor = "Left";  TapX = 335;  TapY = 650; NormalStages = "6";           HardStages = "Unlocked"; ModalVerified = $true  }
    [pscustomobject]@{ Chapter = 2;  ViName = "Rừng Sương Mù";    AsciiName = "Rung Suong Mu";    Normalized = "rung suong mu";    PtLabel = "Floresta da Névoa";    PtNormalized = "floresta da nevoa";    Anchor = "Left";  TapX = 710;  TapY = 285; NormalStages = "10";          HardStages = "Unlocked"; ModalVerified = $true  }
    [pscustomobject]@{ Chapter = 3;  ViName = "Bờ Biển Mặt Trời"; AsciiName = "Bo Bien Mat Troi"; Normalized = "bo bien mat troi"; PtLabel = "Costa Ensolarada";     PtNormalized = "costa ensolarada";     Anchor = "Left";  TapX = 1230; TapY = 665; NormalStages = "14";          HardStages = "Unlocked"; ModalVerified = $true  }
    [pscustomobject]@{ Chapter = 4;  ViName = "Núi Lửa";          AsciiName = "Nui Lua";          Normalized = "nui lua";          PtLabel = "Vulcão Gritante";      PtNormalized = "vulcao gritante";      Anchor = "Left";  TapX = 1095; TapY = 340; NormalStages = "14";          HardStages = "8";        ModalVerified = $true  }
    [pscustomobject]@{ Chapter = 5;  ViName = "Vực Tia Sét";      AsciiName = "Vuc Tia Set";      Normalized = "vuc tia set";      PtLabel = "Canyon do Trovão";     PtNormalized = "canyon do trovao";     Anchor = "Mid";   TapX = 435;  TapY = 290; NormalStages = "16";          HardStages = "7";        ModalVerified = $true  }
    [pscustomobject]@{ Chapter = 6;  ViName = "Tình Ca Sa Mạc";   AsciiName = "Tinh Ca Sa Mac";   Normalized = "tinh ca sa mac";   PtLabel = "Deserto de Love Song"; PtNormalized = "deserto de love song"; Anchor = "Mid";   TapX = 665;  TapY = 635; NormalStages = "16";          HardStages = "7";        ModalVerified = $true  }
    [pscustomobject]@{ Chapter = 7;  ViName = "Đồng Bằng Sao";    AsciiName = "Dong Bang Sao";    Normalized = "dong bang sao";    PtLabel = "Planície Estrelada";   PtNormalized = "planicie estrelada";   Anchor = "Mid";   TapX = 755;  TapY = 335; NormalStages = "18";          HardStages = "8";        ModalVerified = $true  }
    [pscustomobject]@{ Chapter = 8;  ViName = "Sông Ánh Trăng";   AsciiName = "Song Anh Trang";   Normalized = "song anh trang";   PtLabel = "Vale do Luar";         PtNormalized = "vale do luar";         Anchor = "Mid";   TapX = 1025; TapY = 485; NormalStages = "18";          HardStages = "8";        ModalVerified = $true  }
    [pscustomobject]@{ Chapter = 9;  ViName = "Núi Tuyết";        AsciiName = "Nui Tuyet";        Normalized = "nui tuyet";        PtLabel = "Montanha Cuckoo";      PtNormalized = "montanha cuckoo";      Anchor = "Mid";   TapX = 1210; TapY = 315; NormalStages = "18";          HardStages = "Locked";   ModalVerified = $true  }
    [pscustomobject]@{ Chapter = 10; ViName = "Đảo Rạng Đông";    AsciiName = "Dao Rang Dong";    Normalized = "dao rang dong";    PtLabel = "Ilha do Alvorecer";     PtNormalized = "ilha do alvorecer";    Anchor = "Mid";   TapX = 1435; TapY = 655; NormalStages = "20";          HardStages = "Locked";   ModalVerified = $true  }
    [pscustomobject]@{ Chapter = 11; ViName = "Đồi Vận Mệnh";     AsciiName = "Doi Van Menh";     Normalized = "doi van menh";     PtLabel = "Vale do Destino";      PtNormalized = "vale do destino";      Anchor = "Right"; TapX = 610;  TapY = 325; NormalStages = "20";          HardStages = "Locked";   ModalVerified = $true  }
    [pscustomobject]@{ Chapter = 12; ViName = "Đầm Hồi Ức";       AsciiName = "Dam Hoi Uc";       Normalized = "dam hoi uc";       PtLabel = "Pântano Esquecido";    PtNormalized = "pantano esquecido";    Anchor = "Right"; TapX = 535;  TapY = 620; NormalStages = "Locked (20)"; HardStages = "Locked";   ModalVerified = $false }
    [pscustomobject]@{ Chapter = 13; ViName = "Hồ Thủy Tinh";     AsciiName = "Ho Thuy Tinh";     Normalized = "ho thuy tinh";     PtLabel = "Lago de Gelo";         PtNormalized = "lago de gelo";         Anchor = "Right"; TapX = 995;  TapY = 325; NormalStages = "Locked (22)"; HardStages = "Locked";   ModalVerified = $false }
    [pscustomobject]@{ Chapter = 14; ViName = "Di Tích Rồng";     AsciiName = "Di Tich Rong";     Normalized = "di tich rong";     PtLabel = "Ruínas Dragão";        PtNormalized = "ruinas dragao";        Anchor = "Right"; TapX = 1170; TapY = 735; NormalStages = "Locked";      HardStages = "Locked";   ModalVerified = $false }
)

function Initialize-LocaleCatalog {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
    if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
    $localesDir = Join-Path $scriptDir "locales"
    if (-not (Test-Path -LiteralPath $localesDir)) {
        $localesDir = Join-Path (Join-Path $scriptDir "leetcode") "locales"
    }

    $script:Locales = @{}
    if (Test-Path -LiteralPath $localesDir) {
        Get-ChildItem -Path $localesDir -Filter "*.json" | ForEach-Object {
            try {
                $rawJson = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
                $localeObj = ConvertFrom-Json $rawJson
                if ($localeObj.language) {
                    $script:Locales[$localeObj.language] = $localeObj
                }
            } catch {
                Write-Log "Warning: Failed to parse locale file '$($_.Name)': $_"
            }
        }
    }

    $enLocale = if ($script:Locales.ContainsKey('en')) { $script:Locales['en'] } else { $null }
    $viLocale = if ($script:Locales.ContainsKey('vi')) { $script:Locales['vi'] } else { $null }

    foreach ($m in $script:Region1Catalog) {
        $chKey = [string]$m.Chapter
        $allAliases = New-Object System.Collections.Generic.List[string]
        $allAliases.Add($m.Normalized)
        $allAliases.Add($m.PtNormalized)

        if ($null -ne $enLocale -and $null -ne $enLocale.chapters -and $null -ne $enLocale.chapters.PSObject.Properties[$chKey]) {
            $chEn = $enLocale.chapters.PSObject.Properties[$chKey].Value
            $m | Add-Member -MemberType NoteProperty -Name 'EnName' -Value $chEn.name -Force
            $enNorm = Normalize-OcrVietnamese $chEn.name
            $m | Add-Member -MemberType NoteProperty -Name 'EnNormalized' -Value $enNorm -Force
            $allAliases.Add($enNorm)
            if ($null -ne $chEn.aliases) {
                foreach ($al in $chEn.aliases) {
                    $allAliases.Add((Normalize-OcrVietnamese $al))
                }
            }
        }

        if ($null -ne $viLocale -and $null -ne $viLocale.chapters -and $null -ne $viLocale.chapters.PSObject.Properties[$chKey]) {
            $chVi = $viLocale.chapters.PSObject.Properties[$chKey].Value
            if ($null -ne $chVi.aliases) {
                foreach ($al in $chVi.aliases) {
                    $allAliases.Add((Normalize-OcrVietnamese $al))
                }
            }
        }

        $m | Add-Member -MemberType NoteProperty -Name 'AllAliases' -Value @($allAliases | Select-Object -Unique) -Force
    }

    $script:ProgressionZone1 = if ($null -ne $enLocale -and $null -ne $enLocale.progression -and $null -ne $enLocale.progression.zone1) { @($enLocale.progression.zone1) } else { @() }
    $script:ProgressionZone2 = if ($null -ne $enLocale -and $null -ne $enLocale.progression -and $null -ne $enLocale.progression.zone2) { @($enLocale.progression.zone2) } else { @() }
}
Initialize-LocaleCatalog

function Test-MapIsOpenable {
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Entry,
        [Parameter(Mandatory = $true)][bool]$WantElite
    )
    $stagesField = if ($WantElite) { $Entry.HardStages } else { $Entry.NormalStages }
    if ([string]::IsNullOrWhiteSpace($stagesField)) { return $true }
    return ($stagesField -notmatch '(?i)^locked')
}

function Get-NextProgressionChapterEntry {
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$CurrentEntry,
        [Parameter(Mandatory = $false)][bool]$WantElite = $false
    )

    if ($null -eq $script:ProgressionZone1 -or $script:ProgressionZone1.Count -eq 0) {
        $nextCh = $CurrentEntry.Chapter + 1
        return ($script:Region1Catalog | Where-Object { $_.Chapter -eq $nextCh } | Select-Object -First 1)
    }

    $curEnNorm = if ($null -ne $CurrentEntry.PSObject.Properties['EnNormalized']) { $CurrentEntry.EnNormalized } else { Normalize-OcrVietnamese $CurrentEntry.ViName }
    $foundIdx = -1
    for ($i = 0; $i -lt $script:ProgressionZone1.Count; $i++) {
        $pNorm = Normalize-OcrVietnamese $script:ProgressionZone1[$i]
        if ($pNorm -eq $curEnNorm -or ($null -ne $CurrentEntry.AllAliases -and $CurrentEntry.AllAliases -contains $pNorm)) {
            $foundIdx = $i
            break
        }
    }

    if ($foundIdx -ge 0) {
        $nextIdx = $foundIdx + 1
        if ($nextIdx -lt $script:ProgressionZone1.Count) {
            $nextName = $script:ProgressionZone1[$nextIdx]
            $nextEntry = Resolve-MapCatalogEntry -Query $nextName
            return $nextEntry
        } else {
            # At end of Zone 1 (Dragon Ruins), transition to Zone 2 (Hoenn Region)
            if ($null -ne $script:ProgressionZone2 -and $script:ProgressionZone2.Count -gt 0) {
                $nextName = $script:ProgressionZone2[0]
                $nextEntry = Resolve-MapCatalogEntry -Query $nextName
                if ($null -eq $nextEntry) {
                    Write-Log "[CHAIN STOPPED] Reached end of Zone 1 ($($script:ProgressionZone1[$foundIdx])). Zone 2 ($nextName) is not yet mapped in catalog or Hoenn portal is locked."
                    return $null
                }
                return $nextEntry
            } else {
                Write-Log "[CHAIN STOPPED] Reached end of Zone 1 ($($script:ProgressionZone1[$foundIdx])). Zone 2 is not configured. Stopping cleanly."
                return $null
            }
        }
    }

    # Check if current map is in Zone 2
    $foundZone2Idx = -1
    if ($null -ne $script:ProgressionZone2) {
        for ($j = 0; $j -lt $script:ProgressionZone2.Count; $j++) {
            $pNorm = Normalize-OcrVietnamese $script:ProgressionZone2[$j]
            if ($pNorm -eq $curEnNorm -or ($null -ne $CurrentEntry.AllAliases -and $CurrentEntry.AllAliases -contains $pNorm)) {
                $foundZone2Idx = $j
                break
            }
        }
    }

    if ($foundZone2Idx -ge 0) {
        $nextIdx = $foundZone2Idx + 1
        if ($nextIdx -lt $script:ProgressionZone2.Count) {
            $nextName = $script:ProgressionZone2[$nextIdx]
            $nextEntry = Resolve-MapCatalogEntry -Query $nextName
            if ($null -eq $nextEntry) {
                Write-Log "[CHAIN STOPPED] Next Zone 2 map '$nextName' has no catalog entry. Stopping cleanly."
                return $null
            }
            return $nextEntry
        } else {
            Write-Log "[CHAIN STOPPED] Reached end of Zone 2 ($($script:ProgressionZone2[$foundZone2Idx])). All progression maps completed! Stopping cleanly."
            return $null
        }
    }

    Write-Log "[CHAIN STOPPED] Current map '$($CurrentEntry.ViName)' is unlisted in progression sequence. Stopping cleanly."
    return $null
}

function Get-NextMapCatalogEntry {
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$CurrentEntry,
        [Parameter(Mandatory = $false)][bool]$WantElite = $false
    )
    return (Get-NextProgressionChapterEntry -CurrentEntry $CurrentEntry -WantElite $WantElite)
}

function Resolve-MapCatalogEntry {
    param([AllowNull()][AllowEmptyString()][string]$Query)
    $q = Normalize-OcrVietnamese $Query
    if (-not $q) { return $null }

    # 1. Exact match on any alias (ViName, PtLabel, EnName, or alias)
    foreach ($m in $script:Region1Catalog) {
        if ($null -ne $m.AllAliases -and $m.AllAliases -contains $q) { return $m }
        if ($q -eq $m.Normalized -or $q -eq $m.PtNormalized) { return $m }
        if ($null -ne $m.PSObject.Properties['EnNormalized'] -and $q -eq $m.EnNormalized) { return $m }
    }

    # 2. Unambiguous substring match (minimum 4 chars)
    if ($q.Length -ge 4) {
        $subHits = @($script:Region1Catalog | Where-Object {
            $matches = $false
            if ($null -ne $_.AllAliases) {
                foreach ($al in $_.AllAliases) {
                    if ($al.Contains($q) -or $q.Contains($al)) { $matches = $true; break }
                }
            } else {
                $matches = ($_.Normalized.Contains($q) -or $q.Contains($_.Normalized) -or
                            $_.PtNormalized.Contains($q) -or $q.Contains($_.PtNormalized))
            }
            $matches
        })
        if (@($subHits).Count -eq 1) { return $subHits[0] }
    }

    # 3. Best Levenshtein similarity >= 0.78 across all aliases
    $bestEntry = $null
    $bestSim = 0.0
    foreach ($m in $script:Region1Catalog) {
        $candidates = if ($null -ne $m.AllAliases) { $m.AllAliases } else { @($m.Normalized, $m.PtNormalized) }
        foreach ($c in $candidates) {
            $s = Get-StringSimilarity -A $q -B $c
            if ($s -gt $bestSim) {
                $bestSim = $s
                $bestEntry = $m
            }
        }
    }
    if ($bestSim -ge 0.78) { return $bestEntry }
    return $null
}

function Test-CatalogEntryModalMatch {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [AllowNull()][AllowEmptyString()][string]$OcrBaseName = "",
        [bool]$IsHeaderOccluded = $false,
        [bool]$HasStageIndicators = $true
    )
    if (Test-MapNameMatch -ExpectedMapName $Entry.ViName -OcrText $OcrBaseName) {
        return $true
    }
    if ($null -ne $Entry.PSObject.Properties['EnName'] -and -not [string]::IsNullOrWhiteSpace($Entry.EnName)) {
        if (Test-MapNameMatch -ExpectedMapName $Entry.EnName -OcrText $OcrBaseName) {
            return $true
        }
    }
    if ($null -ne $Entry.AllAliases) {
        $normOcr = Normalize-OcrVietnamese $OcrBaseName
        foreach ($al in $Entry.AllAliases) {
            if ($normOcr.Contains($al) -or $al.Contains($normOcr)) {
                return $true
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($script:VerifiedPlaceholderModalNorm)) {
        if (Test-MapNameMatch -ExpectedMapName $script:VerifiedPlaceholderModalNorm -OcrText $OcrBaseName) {
            return $true
        }
    }
    # Future-proof chapters whose STAGE_MODAL header was not yet live-OCR'd while locked (e.g. Ch 12..14
    # with ModalVerified = $false, or any entry whose ViName is a PT placeholder): accept the opened
    # STAGE_MODAL header provided it is non-occluded, has stage indicators, and does NOT match any other
    # chapter's known Vietnamese name in $script:Region1Catalog.
    $needsUnverifiedFallback = ($Entry.Normalized -eq $Entry.PtNormalized) -or (
        ($null -ne $Entry.PSObject.Properties['ModalVerified']) -and (-not [bool]$Entry.ModalVerified)
    )
    if ($needsUnverifiedFallback -and (-not $IsHeaderOccluded) -and $HasStageIndicators) {
        $ocrNorm = Normalize-OcrVietnamese $OcrBaseName
        if ($ocrNorm.Length -ge 4) {
            foreach ($other in $script:Region1Catalog) {
                if ($other.Chapter -ne $Entry.Chapter -and $other.Normalized -ne $other.PtNormalized) {
                    if (Test-MapNameMatch -ExpectedMapName $other.ViName -OcrText $ocrNorm) {
                        return $false
                    }
                }
            }
            return $true
        }
    }
    return $false
}

function Get-SafeSlug {
    param([string]$Text)
    $s = Clean-MapQueryText $Text
    if (-not $s) { return "current_map" }
    $s = [regex]::Replace($s, '[^a-z0-9]+', '_').Trim('_')
    if (-not $s) { return "current_map" }
    return $s
}

function Test-MapLockPopup {
    param([Parameter(Mandatory = $true)][string]$ImagePath)
    try {
        # Check center dialog area where popup message appears (X: 350, Y: 260, W: 900, H: 380)
        $ocr = Invoke-RegionOcr -ImagePath $ImagePath -X 350 -Y 260 -Width 900 -Height 380
        $text = Normalize-OcrVietnamese $ocr.Text
        $isLock = ($text -match '(khoa|chua mo|yeu cau|cap do|level|vuot qua|unlock|previous|clear|chua dat)')
        return [pscustomobject]@{
            IsLockPopup = $isLock
            OcrText     = $ocr.Text
        }
    } catch {
        return [pscustomobject]@{
            IsLockPopup = $false
            OcrText     = ""
        }
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

$script:LastScreenState = 'UNKNOWN'

function Invoke-AdbTap {
    param(
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $false)][ValidateSet('Default', 'AdventureMap', 'BattleDialogue')][string]$Context = 'Default'
    )
    # Hard safety guardrails (context-aware so legitimate AdventureMap HUD/node taps & BattleDialogue taps never collide):
    # 1. NEVER tap "Tiếp" (1500, 700) on VICTORY_EVAL (replays same stage & wastes stamina); "Tiếp tục" at (1500, 805) is allowed (Y=805 > 735)
    $allowTiepZone = ($Context -eq 'AdventureMap' -and $script:LastScreenState -eq 'ADVENTURE_MAP')
    if ((-not $allowTiepZone) -and $X -ge 1410 -and $X -le 1590 -and $Y -ge 665 -and $Y -le 735) {
        throw "SAFETY BLOCK: Refusing to tap ($X, $Y) inside 'Tiếp' replay button hazard zone (Context=$Context, ScreenState=$script:LastScreenState)!"
    }
    # 2. NEVER tap "Quét 10" / "Quét" sweep buttons on STAGE_MODAL
    $allowQuetZone = (
        ($Context -eq 'AdventureMap' -and $script:LastScreenState -eq 'ADVENTURE_MAP') -or
        ($Context -eq 'BattleDialogue' -and $script:LastScreenState -ne 'STAGE_MODAL')
    )
    if ((-not $allowQuetZone) -and $X -ge 775 -and $X -le 1125 -and $Y -ge 770 -and $Y -le 865) {
        throw "SAFETY BLOCK: Refusing to tap ($X, $Y) inside 'Quét' sweep button hazard zone (Context=$Context, ScreenState=$script:LastScreenState)!"
    }
    # 3. NEVER tap "Vào ải" in -DryRun or -ListMaps mode (unconditional)
    if (($DryRun -or $ListMaps) -and $X -ge 1190 -and $X -le 1475 -and $Y -ge 765 -and $Y -le 870) {
        throw "SAFETY BLOCK: Refusing to tap ($X, $Y) ('Vào ải') while -DryRun or -ListMaps is active!"
    }

    Write-Log "TAP ($X, $Y) - $Reason"
    $res = Invoke-AdbRaw -Arguments @('-s', $Serial, 'shell', 'input', 'tap', "$X", "$Y")
    if ($res.ExitCode -ne 0) {
        throw "ADB tap failed at ($X, $Y) (exit $($res.ExitCode)): $($res.Output)"
    }
}

function Invoke-AdbSwipe {
    param(
        [Parameter(Mandatory = $true)][int]$X1,
        [Parameter(Mandatory = $true)][int]$Y1,
        [Parameter(Mandatory = $true)][int]$X2,
        [Parameter(Mandatory = $true)][int]$Y2,
        [Parameter(Mandatory = $true)][int]$DurationMs,
        [Parameter(Mandatory = $true)][string]$Reason
    )
    Write-Log "SWIPE ($X1,$Y1 -> $X2,$Y2, ${DurationMs}ms) - $Reason"
    $res = Invoke-AdbRaw -Arguments @('-s', $Serial, 'shell', 'input', 'swipe', "$X1", "$Y1", "$X2", "$Y2", "$DurationMs")
    if ($res.ExitCode -ne 0) {
        throw "ADB swipe failed (exit $($res.ExitCode)): $($res.Output)"
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

#region Global Screen State Classifier
function Inspect-GameScreen {
    param([Parameter(Mandatory = $true)][string]$ImagePath)
    Initialize-PokemonOcr

    $gridPoints = @(
        @(200, 150), @(800, 150), @(1400, 150),
        @(300, 400), @(800, 400), @(1300, 400),
        @(400, 650), @(800, 650), @(1200, 650),
        @(800, 780)
    )

    $bmp = $null
    try {
        $bmp = Open-UnlockedBitmap -ImagePath $ImagePath
        if ($bmp.Width -ne 1600 -or $bmp.Height -ne 900) {
            throw "Unexpected BlueStacks resolution $($bmp.Width)x$($bmp.Height); expected 1600x900."
        }

        $p1538 = $bmp.GetPixel(1538, 52)
        $p1553 = $bmp.GetPixel(1553, 52)
        $p1260 = $bmp.GetPixel(1260, 815)
        $p1525 = $bmp.GetPixel(1525, 65)
        $p1545 = $bmp.GetPixel(1545, 55)
        $p50   = $bmp.GetPixel(50, 845)
        $p645  = $bmp.GetPixel(645, 860)
        $p965  = $bmp.GetPixel(965, 860)
        $pL220 = $bmp.GetPixel(40, 220)
        $pL350 = $bmp.GetPixel(40, 350)

        # 1. STAGE_MODAL (works whether stage is unlocked or locked, in both Vietnamese red-X and English teal-X themes)
        $isRedCloseX  = ($p1538.R -ge 140 -and $p1538.G -lt 85 -and $p1538.B -lt 100) -and
                        ($p1553.R -ge 190 -and $p1553.G -ge 190 -and $p1553.B -ge 190)
        $isTealCloseX = ($p1538.B -ge 180 -and $p1538.G -ge 180 -and $p1538.R -le 145) -and
                        ($p1553.R -ge 180 -and $p1553.G -ge 180 -and $p1553.B -ge 180)
        $isStageModal = ($isRedCloseX -or $isTealCloseX)
        $isStageModalDimmedOverlay = $isStageModal -and ($p1553.R -lt 235 -and -not $isTealCloseX)
        $isVaoAiVisible = ($p1260.R -gt 210 -and $p1260.G -gt 140 -and $p1260.B -lt 130)

        # 2. CHAPTER_REWARD_OK ("Bạn đã vượt ải ..." blue OK button at 800, 580 over dimmed Adventure Map)
        $pChOkL = $bmp.GetPixel(745, 580)
        $pChOkR = $bmp.GetPixel(855, 580)
        $isChapterRewardOk = (-not $isStageModal) -and (
            ($pChOkL.B -gt 210 -and $pChOkL.G -gt 120 -and $pChOkL.R -lt 90) -and
            ($pChOkR.B -gt 210 -and $pChOkR.G -gt 120 -and $pChOkR.R -lt 90) -and
            ($p1525.R -lt 165)
        )

        # 3. ADVENTURE_MAP (clean 3D chapter map)
        $isAdventureMap = (-not $isStageModal) -and (-not $isChapterRewardOk) -and (
            ($p1525.R -gt 220 -and $p1525.G -gt 230 -and $p1525.B -gt 230) -and
            ($p1538.R -lt 100 -and $p1538.G -gt 130 -and $p1538.B -gt 160) -and
            ($p50.R -lt 90)
        )
        # Shimmer-invariant button bezel check: inactive button has static bezel (965,860 = 132,52,0 on Normal; 645,860 = 0,40,123 on Hard)
        $isNormalMap = $isAdventureMap -and ($p645.B -ge 165 -and $p965.R -le 155 -and $p965.G -le 75 -and $p965.B -le 20)
        $isHardMap   = $isAdventureMap -and ($p645.R -le 20 -and $p645.G -le 55 -and $p645.B -le 145 -and $p965.R -ge 175 -and $p965.G -ge 85)
        $isAtLeftWall = $isAdventureMap -and (
            ($pL220.R -le 40 -and $pL220.G -le 40 -and $pL220.B -le 95) -and
            ($pL350.R -le 40 -and $pL350.G -le 40 -and $pL350.B -le 95)
        )

        # 4. MAIN_TOWN (clean idle town, both Vietnamese & English layouts)
        $pTownAdv = $bmp.GetPixel(1550, 40)
        $isTownAdvIcon = ($pTownAdv.B -ge 220 -and [int]$pTownAdv.B - [int]$pTownAdv.R -ge 120)
        $isMainTown = (-not $isStageModal) -and (-not $isAdventureMap) -and (
            $isTownAdvIcon -or (
                ($p1545.R -lt 45 -and $p1545.G -gt 165 -and $p1545.B -gt 220) -and
                ($p50.R -gt 200 -and $p50.G -gt 140 -and $p50.B -lt 120)
            )
        )

        # 5. FIRST_CLEAR_OK ("Lần đầu Quà" / "First Clear Rewards" orange/gold OK popup at 800, 705)
        $pOkLeft  = $bmp.GetPixel(745, 705)
        $pOkRight = $bmp.GetPixel(855, 705)
        $isFirstClearOk = (-not $isStageModal) -and (-not $isAdventureMap) -and (-not $isMainTown) -and (
            ($pOkLeft.R -ge 175 -and $pOkLeft.G -ge 110 -and $pOkLeft.B -le 135 -and $pOkLeft.R -ge $pOkLeft.G) -and
            ($pOkRight.R -ge 175 -and $pOkRight.G -ge 110 -and $pOkRight.B -le 135 -and $pOkRight.R -ge $pOkRight.G)
        )

        # 5b. GENERIC_OK_POPUP (Item found / Lair map / Level up / Achievement teal OK dialog centered at 800, 580)
        $pGenOkBezel = $bmp.GetPixel(800, 560)
        $pGenOkBtnL  = $bmp.GetPixel(750, 565)
        $pGenOkBtnR  = $bmp.GetPixel(850, 565)
        $pGenOkBtnC  = $bmp.GetPixel(790, 575)
        $pGenOkDlg   = $bmp.GetPixel(625, 470)
        $pGenOkHdr   = $bmp.GetPixel(800, 240)

        $hasTealBezel = ($pGenOkBezel.G -ge 170 -and $pGenOkBezel.B -ge 170 -and $pGenOkBezel.R -le 160)
        $hasTealWings = ($pGenOkBtnL.G -ge 130 -and $pGenOkBtnL.B -ge 130 -and $pGenOkBtnL.R -le 90) -and
                        ($pGenOkBtnR.G -ge 130 -and $pGenOkBtnR.B -ge 130 -and $pGenOkBtnR.R -le 90)
        $hasButtonCenter = ($pGenOkBtnC.R -ge 180 -and $pGenOkBtnC.G -ge 180 -and $pGenOkBtnC.B -ge 180) -or
                           ($pGenOkBtnC.G -ge 130 -and $pGenOkBtnC.B -ge 130)

        $isTealOkBtn = $hasTealBezel -and $hasTealWings -and $hasButtonCenter
        $isTealDlgBg = ($pGenOkDlg.R -le 40 -and $pGenOkDlg.G -ge 40 -and $pGenOkDlg.B -ge 60) -or
                       ($pGenOkHdr.G -ge 130 -and $pGenOkHdr.B -ge 150 -and $pGenOkHdr.R -le 60)
        $isGenericOkPopup = (-not $isStageModal) -and (-not $isAdventureMap) -and (-not $isMainTown) -and $isTealOkBtn -and $isTealDlgBg

        # 6. VICTORY_EVAL ("Đánh giá" / "Score" victory screen: Back/Về at 1440,595 + Continue/Tiếp tục at 1440,805)
        $pVicVe   = $bmp.GetPixel(1440, 595)
        $pVicTiep = $bmp.GetPixel(1440, 805)
        $isVictoryEval = (-not $isStageModal) -and (-not $isAdventureMap) -and (-not $isMainTown) -and (
            ($pVicVe.B -ge 95 -and $pVicVe.G -ge 75 -and $pVicVe.R -le 90) -and
            ($pVicTiep.R -ge 160 -and $pVicTiep.G -ge 115 -and $pVicTiep.B -le 115 -and $pVicTiep.R -gt $pVicTiep.G)
        )

        # 7. LOADING_SCREEN ("Legends Revolution" / "Map is loading..this costs no data":
        #    dark warm-brown bottom bar y=785..899 + horizontal blue/white progress bar track at y=832..848)
        $loadingBrownPts = @(
            @(45, 800), @(120, 800), @(1485, 800), @(1555, 800),
            @(100, 824), @(450, 824), @(800, 824), @(1150, 824), @(1450, 824),
            @(100, 856), @(450, 856), @(800, 856), @(1150, 856), @(1450, 856)
        )
        $brownHits = 0
        foreach ($lpt in $loadingBrownPts) {
            $lc = $bmp.GetPixel($lpt[0], $lpt[1])
            if ($lc.R -ge 28 -and $lc.R -le 62 -and $lc.G -ge 20 -and $lc.G -le 48 -and $lc.B -ge 14 -and $lc.B -le 38 -and $lc.R -ge $lc.G -and $lc.G -ge $lc.B) {
                $brownHits++
            }
        }
        $barHits = 0
        if ($brownHits -ge 12) {
            for ($bx = 140; $bx -le 1460; $bx += 60) {
                $bc = $bmp.GetPixel($bx, 840)
                $isBlueFill  = ($bc.B -ge 175 -and $bc.G -ge 90 -and ([int]$bc.B - [int]$bc.R) -ge 75 -and ([int]$bc.B - [int]$bc.G) -ge 35)
                $isGrayTrack = ($bc.R -ge 180 -and $bc.G -ge 180 -and $bc.B -ge 180 -and [Math]::Abs([int]$bc.R - [int]$bc.G) -le 16 -and [Math]::Abs([int]$bc.G - [int]$bc.B) -le 16)
                $isSeamBlend = ($bc.B -ge 180 -and $bc.G -ge 130 -and $bc.B -ge $bc.G -and $bc.G -ge $bc.R)
                if ($isBlueFill -or $isGrayTrack -or $isSeamBlend) {
                    $barHits++
                }
            }
        }
        $isLoadingScreen = (-not $isStageModal) -and (-not $isChapterRewardOk) -and (-not $isAdventureMap) -and (-not $isMainTown) -and (-not $isFirstClearOk) -and (-not $isVictoryEval) -and ($brownHits -ge 12) -and ($barHits -ge 21)

        # 8. POPUP_RED_X (Town unlock popup e.g. 'Định Mệnh' or inner modal with genuine circular red X + white ring)
        $redClosePt = New-Object System.Drawing.Point(-1, -1)
        $isPopupRedX = $false
        if (-not $isStageModal -and -not $isAdventureMap -and -not $isMainTown -and -not $isFirstClearOk -and -not $isVictoryEval -and -not $isChapterRewardOk -and -not $isLoadingScreen) {
            $redClosePt = [PokemonStageNative]::FindRedCloseX($bmp, 1000, 5, 1595, 340)
            if ($redClosePt.X -gt 0) {
                $isPopupRedX = $true
            }
        }

        # 9. ADVENTURE_MAP_TOOLTIP (dimmed Adventure Map with Pokémon reward tooltip)
        $isMapTooltip = (-not $isStageModal) -and (-not $isChapterRewardOk) -and (-not $isAdventureMap) -and (-not $isMainTown) -and (-not $isLoadingScreen) -and (-not $isPopupRedX) -and (
            ($p1525.R -ge 90 -and $p1525.R -le 175 -and [Math]::Abs([int]$p1525.R - [int]$p1525.G) -le 15) -and
            ($p1538.G -gt ($p1538.R + 25) -and $p1538.B -gt ($p1538.R + 35) -and $p50.R -lt 50)
        )

        $stateName = if ($isLoadingScreen)       { 'LOADING_SCREEN' }
                     elseif ($isStageModal)      { 'STAGE_MODAL' }
                     elseif ($isChapterRewardOk) { 'CHAPTER_REWARD_OK' }
                     elseif ($isAdventureMap)    { 'ADVENTURE_MAP' }
                     elseif ($isMainTown)        { 'MAIN_TOWN' }
                     elseif ($isFirstClearOk)    { 'FIRST_CLEAR_OK' }
                     elseif ($isGenericOkPopup)  { 'GENERIC_OK_POPUP' }
                     elseif ($isVictoryEval)     { 'VICTORY_EVAL' }
                     elseif ($isPopupRedX)       { 'POPUP_RED_X' }
                     elseif ($isMapTooltip)      { 'ADVENTURE_MAP_TOOLTIP' }
                     else                        { 'UNKNOWN' }

        $script:LastScreenState = $stateName

        $gridValues = New-Object System.Collections.Generic.List[string]
        foreach ($pt in $gridPoints) {
            $c = $bmp.GetPixel($pt[0], $pt[1])
            $gridValues.Add("$($c.R),$($c.G),$($c.B)")
        }

        return [pscustomobject]@{
            State                     = $stateName
            IsLoadingScreen           = $isLoadingScreen
            IsStageModal              = $isStageModal
            IsStageModalDimmedOverlay = $isStageModalDimmedOverlay
            IsVaoAiVisible            = $isVaoAiVisible
            IsChapterRewardOk         = $isChapterRewardOk
            IsAdventureMap            = $isAdventureMap
            IsNormalMap               = $isNormalMap
            IsHardMap                 = $isHardMap
            IsAtLeftMapWall           = $isAtLeftWall
            IsMainTown                = $isMainTown
            IsFirstClearOk            = $isFirstClearOk
            IsGenericOkPopup          = $isGenericOkPopup
            IsVictoryEval             = $isVictoryEval
            IsPopupRedX               = $isPopupRedX
            RedCloseX                 = $redClosePt.X
            RedCloseY                 = $redClosePt.Y
            IsMapTooltip              = $isMapTooltip
            GridSignature             = ($gridValues -join ";")
            VicVeRgb                  = "$($pVicVe.R),$($pVicVe.G),$($pVicVe.B)"
            VicTiepRgb                = "$($pVicTiep.R),$($pVicTiep.G),$($pVicTiep.B)"
        }
    } finally {
        if ($null -ne $bmp) {
            $bmp.Dispose()
        }
    }
}
#endregion

#region Navigation, Mode Switching & Stage Selection Helpers
function Close-StageModal {
    for ($i = 1; $i -le 3; $i++) {
        Invoke-AdbTap -X 1553 -Y 52 -Reason "Close STAGE_MODAL (attempt $i)"
        Start-Sleep -Milliseconds 1100
        Capture-Screen -OutPath $script:LiveScreenPath
        $s = Inspect-GameScreen -ImagePath $script:LiveScreenPath
        if (-not $s.IsStageModal) {
            return $s
        }
    }
    throw "Failed to close STAGE_MODAL after 3 attempts."
}

function Ensure-AdventureMapOpen {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 35) {
        Capture-Screen -OutPath $script:LiveScreenPath
        $s = Inspect-GameScreen -ImagePath $script:LiveScreenPath

        switch ($s.State) {
            'ADVENTURE_MAP' {
                return $s
            }
            'STAGE_MODAL' {
                $null = Close-StageModal
            }
            'CHAPTER_REWARD_OK' {
                Invoke-AdbTap -X 800 -Y 580 -Reason "Dismiss CHAPTER_REWARD_OK (OK)"
                Start-Sleep -Milliseconds 1200
            }
            'ADVENTURE_MAP_TOOLTIP' {
                Invoke-AdbTap -X 800 -Y 885 -Reason "Dismiss Adventure Map tooltip"
                Start-Sleep -Milliseconds 900
            }
            'POPUP_RED_X' {
                Invoke-AdbTap -X $s.RedCloseX -Y $s.RedCloseY -Reason "Close popup red X"
                Start-Sleep -Milliseconds 1200
            }
            'FIRST_CLEAR_OK' {
                Invoke-AdbTap -X 800 -Y 705 -Reason "Dismiss FIRST_CLEAR_OK"
                Start-Sleep -Milliseconds 1500
            }
            'GENERIC_OK_POPUP' {
                Invoke-AdbTap -X 800 -Y 580 -Reason "Dismiss generic teal OK popup (navigation)"
                Start-Sleep -Milliseconds 1200
            }
            'VICTORY_EVAL' {
                Invoke-AdbTap -X 1500 -Y 595 -Reason "Exit VICTORY_EVAL via Ve"
                Start-Sleep -Milliseconds 3500
            }
            'LOADING_SCREEN' {
                Write-Log "Waiting for LOADING_SCREEN to finish ($([math]::Round($sw.Elapsed.TotalSeconds,1))s)..."
                Start-Sleep -Milliseconds 1500
            }
            'MAIN_TOWN' {
                Invoke-AdbTap -X 1545 -Y 55 -Reason "Open Adventure Map from Main Town"
                Start-Sleep -Milliseconds 2600
            }
            default {
                Write-Log "Waiting for UI to settle into Town/Map (state=$($s.State), $([math]::Round($sw.Elapsed.TotalSeconds,1))s)..."
                Start-Sleep -Milliseconds 1500
            }
        }
    }
    $errSnap = Join-Path $script:ResolvedOutputDir "error_cannot_reach_adventure_map.png"
    Copy-Item -LiteralPath $script:LiveScreenPath -Destination $errSnap -Force
    Write-Log "ERROR: Could not reach ADVENTURE_MAP within 35s. Saved '$errSnap'."
    exit 2
}

function Set-AdventureMapMode {
    param([Parameter(Mandatory = $true)][bool]$WantEliteMode)
    $modeLabel = if ($WantEliteMode) { "Hard/Elite (Tinh)" } else { "Normal (Thường)" }

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Capture-Screen -OutPath $script:LiveScreenPath
        $s = Inspect-GameScreen -ImagePath $script:LiveScreenPath
        if ($s.State -ne 'ADVENTURE_MAP') {
            $s = Ensure-AdventureMapOpen
        }

        if ($WantEliteMode -and $s.IsHardMap) {
            Write-Log "Verified Adventure Map mode is Hard/Elite."
            return
        }
        if ((-not $WantEliteMode) -and $s.IsNormalMap) {
            Write-Log "Verified Adventure Map mode is Normal."
            return
        }

        if ($WantEliteMode) {
            Invoke-AdbTap -X 965 -Y 820 -Context 'AdventureMap' -Reason "Switch Adventure Map mode to $modeLabel"
        } else {
            Invoke-AdbTap -X 635 -Y 820 -Context 'AdventureMap' -Reason "Switch Adventure Map mode to $modeLabel"
        }
        Start-Sleep -Milliseconds 1500
    }

    Capture-Screen -OutPath $script:LiveScreenPath
    $finalCheck = Inspect-GameScreen -ImagePath $script:LiveScreenPath
    if (($WantEliteMode -and $finalCheck.IsHardMap) -or ((-not $WantEliteMode) -and $finalCheck.IsNormalMap)) {
        Write-Log "Verified Adventure Map mode is $modeLabel."
        return
    }
    $errSnap = Join-Path $script:ResolvedOutputDir "error_mode_switch_failed.png"
    Copy-Item -LiteralPath $script:LiveScreenPath -Destination $errSnap -Force
    Write-Log "ERROR: Failed to verify mode '$modeLabel' on ADVENTURE_MAP (likely locked or obscured). Saved '$errSnap'."
    exit 2
}

function Move-ToHardLeftWall {
    # Alternate portrait-safe swipe Y rows (745 above bottom HUD, 72 below top frame) so reward portraits never intercept touch-down
    $safeYs = @(745, 72, 500, 745, 72, 500)
    for ($i = 0; $i -lt $safeYs.Count; $i++) {
        $sy = $safeYs[$i]
        Invoke-AdbSwipe -X1 220 -Y1 $sy -X2 1420 -Y2 $sy -DurationMs 350 -Reason "Pan hard-left ($($i + 1)/$($safeYs.Count), Y=$sy)"
        Start-Sleep -Milliseconds 420
        if ($i -ge 2) {
            Capture-Screen -OutPath $script:LiveScreenPath
            $chk = Inspect-GameScreen -ImagePath $script:LiveScreenPath
            if ($chk.IsAtLeftMapWall) {
                Invoke-AdbSwipe -X1 220 -Y1 745 -X2 1420 -Y2 745 -DurationMs 320 -Reason "Flush settle against hard-left wall"
                Start-Sleep -Milliseconds 500
                return
            }
        }
    }
    Start-Sleep -Milliseconds 500
}

function Move-ToMapAnchor {
    param([Parameter(Mandatory = $true)][ValidateSet('Left', 'Mid', 'Right')][string]$Anchor)
    Write-Log "Panning Adventure Map camera to anchor '$Anchor'..."
    switch ($Anchor) {
        'Left' {
            Move-ToHardLeftWall
        }
        'Mid' {
            Move-ToHardLeftWall
            Invoke-AdbSwipe -X1 1250 -Y1 220 -X2 600 -Y2 220 -DurationMs 1000 -Reason "Slow pan to Mid anchor"
            Start-Sleep -Milliseconds 850
        }
        'Right' {
            $safeYs = @(745, 72, 500, 745)
            for ($i = 0; $i -lt $safeYs.Count; $i++) {
                $sy = $safeYs[$i]
                Invoke-AdbSwipe -X1 1380 -Y1 $sy -X2 200 -Y2 $sy -DurationMs 350 -Reason "Pan hard-right ($($i + 1)/4, Y=$sy)"
                Start-Sleep -Milliseconds 420
            }
            Start-Sleep -Milliseconds 550
        }
    }
}

$script:EffectiveMapEntry = $null
$script:EffectiveMapCustomTitle = ""
$script:VerifiedPlaceholderModalNorm = ""

if (-not [string]::IsNullOrWhiteSpace($MapName)) {
    $script:EffectiveMapEntry = Resolve-MapCatalogEntry -Query $MapName
}

function Ensure-StageModalOpen {
    param(
        [bool]$CameFromTiepTuc = $false,
        [int]$ExpectedSelectedStage = 0
    )

    # Wait up to 16s if game is currently on a post-battle loading transition
    $settleSw = [System.Diagnostics.Stopwatch]::StartNew()
    $screen = $null
    while ($settleSw.Elapsed.TotalSeconds -lt 16) {
        Capture-Screen -OutPath $script:LiveScreenPath
        $screen = Inspect-GameScreen -ImagePath $script:LiveScreenPath
        if ($screen.State -notin @('UNKNOWN', 'LOADING_SCREEN')) { break }
        # Bail out early if we see a stable non-transient screen (Dungeon, etc.) - no point waiting
        if ($screen.State -eq 'DUNGEON_SCREEN') { break }
        Write-Log "Waiting for loading/transition screen to settle (state=$($screen.State), $([math]::Round($settleSw.Elapsed.TotalSeconds,1))s)..."
        Start-Sleep -Milliseconds 1500
    }

    # If sitting on post-battle popups (GENERIC_OK_POPUP, FIRST_CLEAR_OK) or VICTORY_EVAL, dismiss popups and exit via Tiếp tục back to modal
    if ($screen.State -in @('GENERIC_OK_POPUP', 'FIRST_CLEAR_OK', 'VICTORY_EVAL')) {
        $recoverSw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($recoverSw.Elapsed.TotalSeconds -lt 25 -and $screen.State -in @('GENERIC_OK_POPUP', 'FIRST_CLEAR_OK', 'VICTORY_EVAL', 'LOADING_SCREEN', 'UNKNOWN')) {
            if ($screen.State -eq 'GENERIC_OK_POPUP') {
                Invoke-AdbTap -X 800 -Y 580 -Reason "Dismiss generic teal OK popup in Ensure-StageModalOpen"
                Start-Sleep -Milliseconds 1500
            } elseif ($screen.State -eq 'FIRST_CLEAR_OK') {
                Invoke-AdbTap -X 800 -Y 705 -Reason "Dismiss FIRST_CLEAR_OK in Ensure-StageModalOpen"
                Start-Sleep -Milliseconds 1500
            } elseif ($screen.State -eq 'VICTORY_EVAL') {
                Invoke-AdbTap -X 1500 -Y 805 -Reason "Exit VICTORY_EVAL via Tiếp tục to STAGE_MODAL (NEVER Tiếp at 1500,700)"
                Start-Sleep -Milliseconds 2500
            } else {
                Start-Sleep -Milliseconds 1500
            }
            Capture-Screen -OutPath $script:LiveScreenPath
            $screen = Inspect-GameScreen -ImagePath $script:LiveScreenPath
        }
    }

    # If a generic teal OK popup or popup red X appeared right over STAGE_MODAL after Tiếp tục, dismiss it in-place first
    if ($CameFromTiepTuc -and $screen.IsGenericOkPopup) {
        Invoke-AdbTap -X 800 -Y 580 -Reason "Dismiss post-Tiếp-tục generic teal OK popup"
        Start-Sleep -Milliseconds 1500
        Capture-Screen -OutPath $script:LiveScreenPath
        $screen = Inspect-GameScreen -ImagePath $script:LiveScreenPath
    }
    if ($CameFromTiepTuc -and $screen.IsPopupRedX) {
        Invoke-AdbTap -X $screen.RedCloseX -Y $screen.RedCloseY -Reason "Dismiss post-Tiếp-tục popup red X"
        Start-Sleep -Milliseconds 1200
        Capture-Screen -OutPath $script:LiveScreenPath
        $screen = Inspect-GameScreen -ImagePath $script:LiveScreenPath
    }

    # Check if already inside STAGE_MODAL
    if ($screen.IsStageModal) {
        if ($screen.IsStageModalDimmedOverlay) {
            Invoke-AdbTap -X 800 -Y 180 -Reason "Dismiss 'Mở ải mới' overlay inside STAGE_MODAL"
            Start-Sleep -Milliseconds 850
            Capture-Screen -OutPath $script:LiveScreenPath
            $screen = Inspect-GameScreen -ImagePath $script:LiveScreenPath
        }

        $maxHeaderRetries = if ([string]::IsNullOrWhiteSpace($MapName)) { 8 } else { 4 }
        $modalInfo = if ($CameFromTiepTuc) {
            Get-StageModalInfo -ImagePath $script:LiveScreenPath
        } else {
            Get-StableStageModalInfo -MaxAttempts $maxHeaderRetries
        }

        # Marquee-resilient fast-path when continuing inside STAGE_MODAL right after Tiếp tục:
        # Note that the server marquee (Y=52..149) covers both ChapterTitle (Y=66..106) and TopBannerStage (Y=44..76),
        # while StageRows (Y>=218) and 'Số lần còn' (Y=248..294) remain 100% unobstructed below Y=149.
        if ($CameFromTiepTuc -and $modalInfo.IsHeaderOccluded) {
            $selRowAfterTiepTuc = @($modalInfo.StageRows) | Where-Object { $_.IsSelected } | Select-Object -First 1
            $stageMatchesExpected = ($ExpectedSelectedStage -gt 0) -and (
                ($modalInfo.SelectedStageBanner -eq $ExpectedSelectedStage) -or
                ($null -ne $selRowAfterTiepTuc -and $selRowAfterTiepTuc.Stage -eq $ExpectedSelectedStage)
            )
            if (($modalInfo.IsElite -eq $script:WantElite) -and $stageMatchesExpected) {
                $fallbackBase = if ($null -ne $script:EffectiveMapEntry) {
                    $script:EffectiveMapEntry.ViName
                } elseif (-not [string]::IsNullOrWhiteSpace($MapName)) {
                    $MapName
                } elseif (-not [string]::IsNullOrWhiteSpace($script:EffectiveMapCustomTitle)) {
                    $script:EffectiveMapCustomTitle
                } else {
                    "Current Chapter"
                }
                $fallbackTitle = if ($script:WantElite -and $fallbackBase -notmatch 'Elite') { "$fallbackBase [Elite]" } else { $fallbackBase }
                $modalInfo.ChapterTitleRaw = $fallbackTitle
                if ($null -ne $script:EffectiveMapEntry) {
                    $modalInfo.MapBaseNameNormalized = $script:EffectiveMapEntry.Normalized
                }
                Write-Log "Continuing inside STAGE_MODAL after Tiếp tục: '$fallbackTitle' (Ải $ExpectedSelectedStage selected, Mode=$script:CanonicalMode verified, Progress=$($modalInfo.StarProgress); header occluded by server marquee)."
                return $modalInfo
            }
            # If ExpectedSelectedStage was not yet visible (e.g. scrolled), retry header stabilization normally
            $modalInfo = Get-StableStageModalInfo -MaxAttempts $maxHeaderRetries
        }

        # If -MapName was omitted, adopt the open modal's map (and mode if -Mode was also omitted)
        if ([string]::IsNullOrWhiteSpace($MapName) -and $null -eq $script:EffectiveMapEntry -and [string]::IsNullOrWhiteSpace($script:EffectiveMapCustomTitle)) {
            $detectedEntry = Resolve-MapCatalogEntry -Query $modalInfo.MapBaseNameNormalized
            if ($null -ne $detectedEntry) {
                $script:EffectiveMapEntry = $detectedEntry
                Write-Log "Adopted open modal map: '$($detectedEntry.ViName)' (OCR='$($modalInfo.ChapterTitleRaw)')."
            } else {
                $script:EffectiveMapCustomTitle = $modalInfo.MapBaseNameNormalized
                Write-Log "Adopted open custom modal map: '$($modalInfo.ChapterTitleRaw)'."
            }
            if (-not $script:ModeExplicitlyBound) {
                $script:WantElite = $modalInfo.IsElite
                $script:CanonicalMode = if ($script:WantElite) { 'Hard' } else { 'Normal' }
                Write-Log "Adopted open modal mode: $script:CanonicalMode."
            }
        }

        $expectedName = if ($null -ne $script:EffectiveMapEntry) {
            $script:EffectiveMapEntry.ViName
        } elseif (-not [string]::IsNullOrWhiteSpace($MapName)) {
            $MapName
        } else {
            $script:EffectiveMapCustomTitle
        }

        $hasStageIndicators = ((@($modalInfo.StageRows).Count -gt 0) -or ($modalInfo.SelectedStageBanner -gt 0))
        $modeMatches = ($modalInfo.IsElite -eq $script:WantElite)
        $mapMatches  = if ($null -ne $script:EffectiveMapEntry) {
            Test-CatalogEntryModalMatch -Entry $script:EffectiveMapEntry -OcrBaseName $modalInfo.MapBaseNameNormalized -IsHeaderOccluded $modalInfo.IsHeaderOccluded -HasStageIndicators $hasStageIndicators
        } else {
            ([string]::IsNullOrWhiteSpace($expectedName)) -or (Test-MapNameMatch -ExpectedMapName $expectedName -OcrText $modalInfo.MapBaseNameNormalized)
        }

        # Secondary marquee guard if header remained occluded across all retries right after Tiếp tục
        if ((-not $mapMatches) -and $CameFromTiepTuc -and $modalInfo.IsHeaderOccluded -and $modeMatches -and $hasStageIndicators) {
            $selRowRetry = @($modalInfo.StageRows) | Where-Object { $_.IsSelected } | Select-Object -First 1
            if ($ExpectedSelectedStage -gt 0 -and ($modalInfo.SelectedStageBanner -eq $ExpectedSelectedStage -or ($null -ne $selRowRetry -and $selRowRetry.Stage -eq $ExpectedSelectedStage))) {
                $fallbackTitle = if ($script:WantElite -and $expectedName -notmatch 'Elite') { "$expectedName [Elite]" } else { $expectedName }
                $modalInfo.ChapterTitleRaw = $fallbackTitle
                if ($null -ne $script:EffectiveMapEntry) {
                    $modalInfo.MapBaseNameNormalized = $script:EffectiveMapEntry.Normalized
                }
                $mapMatches = $true
            }
        }

        if ($modeMatches -and $mapMatches) {
            $isUnverifiedEntry = ($null -ne $script:EffectiveMapEntry) -and (
                ($script:EffectiveMapEntry.Normalized -eq $script:EffectiveMapEntry.PtNormalized) -or
                (($null -ne $script:EffectiveMapEntry.PSObject.Properties['ModalVerified']) -and (-not [bool]$script:EffectiveMapEntry.ModalVerified))
            )
            if ($isUnverifiedEntry -and (-not $modalInfo.IsHeaderOccluded) -and [string]::IsNullOrWhiteSpace($script:VerifiedPlaceholderModalNorm)) {
                $script:VerifiedPlaceholderModalNorm = $modalInfo.MapBaseNameNormalized
            }
            Write-Log "Already inside matching STAGE_MODAL: '$($modalInfo.ChapterTitleRaw)' (Elite=$($modalInfo.IsElite), Progress=$($modalInfo.StarProgress))."
            return $modalInfo
        }

        Write-Log "Current STAGE_MODAL ('$($modalInfo.ChapterTitleRaw)', Elite=$($modalInfo.IsElite)) does not match target ('$expectedName', Elite=$($script:WantElite)); closing modal."
        $screen = Close-StageModal
    }

    # Not in matching STAGE_MODAL: validate we know which map to open on ADVENTURE_MAP
    if ($null -eq $script:EffectiveMapEntry) {
        if ([string]::IsNullOrWhiteSpace($MapName)) {
            $hint = switch ($screen.State) {
                'DUNGEON_SCREEN' { "You are on the DUNGEON screen - this script only works on the ADVENTURE MAP (Story chapters). Please close the Dungeon and go to Adventure Map first, then run again with -MapName '<chapter>' (e.g. -MapName 'Doi Van Menh')." }
                'MAIN_TOWN'     { "You are on the MAIN TOWN screen. Navigate to Adventure Map and open a chapter modal first, then run again (or pass -MapName '<chapter>')." }
                'UNKNOWN'       { "Screen state is UNKNOWN (unrecognized screen). Please go to Adventure Map, open a chapter stage list, then run again. Or pass -MapName '<chapter>' to let the script navigate there automatically." }
                default         { "No Stage Modal is currently open (current state: $($screen.State)). Pass -MapName '<name>' to open it automatically (or run -ListMaps to see all chapters)." }
            }
            Write-Log "ERROR: $hint"
            # Save a screenshot so user can see what screen the script saw
            $errShotPath = Join-Path $script:ResolvedOutputDir "error_unknown_screen.png"
            try { Copy-Item -Path $script:LiveScreenPath -Destination $errShotPath -Force } catch {}
            Write-Log "Screenshot of current screen saved to: $errShotPath"
            exit 1
        } else {
            $avail = ($script:Region1Catalog | ForEach-Object { "$($_.ViName) ($($_.AsciiName))" }) -join ", "
            Write-Log "ERROR: Unknown -MapName '$MapName'. Discoverable maps: $avail"
            exit 1
        }
    }

    $entry = $script:EffectiveMapEntry
    $null = Ensure-AdventureMapOpen
    Set-AdventureMapMode -WantEliteMode $script:WantElite
    Move-ToMapAnchor -Anchor $entry.Anchor

    # Tap chapter landmark node & handle multiple unclaimed chapter reward popups / tooltips cleanly
    $missedNodeTaps = 0
    $tooltipSeen = $false
    for ($iter = 1; $iter -le 10; $iter++) {
        Capture-Screen -OutPath $script:LiveScreenPath
        $preTap = Inspect-GameScreen -ImagePath $script:LiveScreenPath
        if ($preTap.IsChapterRewardOk) {
            Write-Log "Unclaimed chapter completion chest popup present; claiming OK before node tap."
            Invoke-AdbTap -X 800 -Y 580 -Reason "Claim CHAPTER_REWARD_OK (OK)"
            Start-Sleep -Milliseconds 1200
            continue
        }
        if ($preTap.IsMapTooltip) {
            Invoke-AdbTap -X 800 -Y 885 -Reason "Dismiss map reward tooltip"
            Start-Sleep -Milliseconds 900
            continue
        }
        if ($preTap.IsPopupRedX) {
            Invoke-AdbTap -X $preTap.RedCloseX -Y $preTap.RedCloseY -Reason "Dismiss unexpected popup"
            Start-Sleep -Milliseconds 1000
            continue
        }
        if ($preTap.IsGenericOkPopup) {
            Invoke-AdbTap -X 800 -Y 580 -Reason "Dismiss generic teal OK popup before node tap"
            Start-Sleep -Milliseconds 1200
            continue
        }
        if ($preTap.State -ne 'ADVENTURE_MAP') {
            $null = Ensure-AdventureMapOpen
            Set-AdventureMapMode -WantEliteMode $script:WantElite
            Move-ToMapAnchor -Anchor $entry.Anchor
            Capture-Screen -OutPath $script:LiveScreenPath
            $null = Inspect-GameScreen -ImagePath $script:LiveScreenPath
        }

        $tapY = if ($tooltipSeen -and $missedNodeTaps -ge 1) { $entry.TapY + 15 } else { $entry.TapY }
        Invoke-AdbTap -X $entry.TapX -Y $tapY -Context 'AdventureMap' -Reason "Open chapter '$($entry.ViName)' ($script:CanonicalMode) [iter $iter, miss $missedNodeTaps]"
        Start-Sleep -Milliseconds 1500

        Capture-Screen -OutPath $script:LiveScreenPath
        $postTap = Inspect-GameScreen -ImagePath $script:LiveScreenPath

        if ($postTap.IsChapterRewardOk) {
            Write-Log "Unclaimed chapter completion chest popup detected; claiming OK and re-tapping same chapter node."
            Invoke-AdbTap -X 800 -Y 580 -Reason "Claim CHAPTER_REWARD_OK (OK)"
            Start-Sleep -Milliseconds 1200
            continue
        }
        if ($postTap.IsMapTooltip) {
            Write-Log "Adventure map reward tooltip detected; dismissing and retrying node tap."
            $tooltipSeen = $true
            Invoke-AdbTap -X 800 -Y 885 -Reason "Dismiss map reward tooltip"
            Start-Sleep -Milliseconds 900
            continue
        }
        if ($postTap.IsPopupRedX -or $postTap.IsGenericOkPopup) {
            $lockCheck = Test-MapLockPopup -ImagePath $script:LiveScreenPath
            if ($lockCheck.IsLockPopup) {
                Write-Log "In-game lock popup detected after tapping node: '$($lockCheck.OcrText)'."
                if ($postTap.IsGenericOkPopup) {
                    Invoke-AdbTap -X 800 -Y 580 -Reason "Dismiss lock popup OK"
                } else {
                    Invoke-AdbTap -X $postTap.RedCloseX -Y $postTap.RedCloseY -Reason "Dismiss lock popup red X"
                }
                Start-Sleep -Milliseconds 1000
                $missedNodeTaps = 99
                break
            }
        }
        if ($postTap.IsPopupRedX) {
            Invoke-AdbTap -X $postTap.RedCloseX -Y $postTap.RedCloseY -Reason "Dismiss unexpected popup"
            Start-Sleep -Milliseconds 1000
            continue
        }
        if ($postTap.IsGenericOkPopup) {
            Write-Log "Generic teal OK popup detected after node tap; dismissing and retrying."
            Invoke-AdbTap -X 800 -Y 580 -Reason "Dismiss generic teal OK popup after node tap"
            Start-Sleep -Milliseconds 1200
            continue
        }
        if ($postTap.IsStageModal) {
            if ($postTap.IsStageModalDimmedOverlay) {
                Invoke-AdbTap -X 800 -Y 180 -Reason "Dismiss 'Mở ải mới' overlay inside STAGE_MODAL"
                Start-Sleep -Milliseconds 850
                Capture-Screen -OutPath $script:LiveScreenPath
            }
            $modalInfo = Get-StableStageModalInfo -MaxAttempts 4
            if ($modalInfo.IsElite -ne $script:WantElite) {
                $errSnap = Join-Path $script:ResolvedOutputDir "error_wrong_modal_mode.png"
                Copy-Item -LiteralPath $script:LiveScreenPath -Destination $errSnap -Force
                Write-Log "ERROR: Opened STAGE_MODAL '$($modalInfo.ChapterTitleRaw)' with IsElite=$($modalInfo.IsElite), expected $($script:WantElite). Saved '$errSnap'."
                exit 2
            }
            if ($modalInfo.IsHeaderOccluded) {
                $fallbackTitle = if ($script:WantElite) { "$($entry.ViName) [Elite]" } else { $entry.ViName }
                $modalInfo.ChapterTitleRaw = $fallbackTitle
                $modalInfo.MapBaseNameNormalized = $entry.Normalized
                Write-Log "Opened STAGE_MODAL: '$fallbackTitle' (Mode=$script:CanonicalMode verified via attempts='$($modalInfo.TriesRaw)'; header occluded by continuous server marquee)."
                return $modalInfo
            }
            $hasStageIndicators = ((@($modalInfo.StageRows).Count -gt 0) -or ($modalInfo.SelectedStageBanner -gt 0))
            if (-not (Test-CatalogEntryModalMatch -Entry $entry -OcrBaseName $modalInfo.MapBaseNameNormalized -IsHeaderOccluded $modalInfo.IsHeaderOccluded -HasStageIndicators $hasStageIndicators)) {
                $errSnap = Join-Path $script:ResolvedOutputDir "error_wrong_modal_map.png"
                Copy-Item -LiteralPath $script:LiveScreenPath -Destination $errSnap -Force
                Write-Log "ERROR: Opened STAGE_MODAL '$($modalInfo.ChapterTitleRaw)' (norm='$($modalInfo.MapBaseNameNormalized)'), expected '$($entry.ViName)'. Saved '$errSnap'."
                exit 2
            }
            $isUnverifiedOpen = ($entry.Normalized -eq $entry.PtNormalized) -or (
                ($null -ne $entry.PSObject.Properties['ModalVerified']) -and (-not [bool]$entry.ModalVerified)
            )
            if ($isUnverifiedOpen) {
                $script:VerifiedPlaceholderModalNorm = $modalInfo.MapBaseNameNormalized
                Write-Log "Unverified/placeholder map '$($entry.PtLabel)' matched live Vietnamese header '$($modalInfo.ChapterTitleRaw)' (norm='$($modalInfo.MapBaseNameNormalized)')."
            }
            Write-Log "Opened STAGE_MODAL: '$($modalInfo.ChapterTitleRaw)' (Mode=$script:CanonicalMode, Progress=$($modalInfo.StarProgress))."
            return $modalInfo
        }

        $missedNodeTaps++
        if ($missedNodeTaps -ge 3) {
            break
        }
    }

    $lockedSnap = Join-Path $script:ResolvedOutputDir ("error_map_locked_{0}_{1}.png" -f (Get-SafeSlug $entry.AsciiName), $script:CanonicalMode.ToLowerInvariant())
    Copy-Item -LiteralPath $script:LiveScreenPath -Destination $lockedSnap -Force

    if ($Chain) {
        $chainSnap = Join-Path $script:ResolvedOutputDir ("chain_next_map_locked_{0}.png" -f (Get-SafeSlug $entry.AsciiName))
        try { Copy-Item -LiteralPath $script:LiveScreenPath -Destination $chainSnap -Force } catch {}
        Write-Log "========================================================"
        Write-Log "[CHAIN STOPPED] Next map '$($entry.ViName)' ($($entry.EnName)) is LOCKED or not open yet. Halting automation."
        Write-Log "Saved snapshot to '$chainSnap'."
        Write-Log "========================================================"
        return $null
    }

    Write-Log "ERROR: Map '$($entry.ViName)' ($script:CanonicalMode) did not open STAGE_MODAL — chapter/mode is locked or unavailable. Saved '$lockedSnap'."
    exit 2
}

function Select-StageInModal {
    param(
        [Parameter(Mandatory = $true)][int]$TargetStage,
        [switch]$ReuseLastCapture
    )

    $prevMin = -1
    $prevMax = -1
    $stallUp = 0
    $stallDown = 0
    $maxSeenOverall = 0
    $minSeenOverall = 999

    for ($step = 0; $step -lt 20; $step++) {
        if (-not ($step -eq 0 -and $ReuseLastCapture -and (Test-Path -LiteralPath $script:LiveScreenPath))) {
            Capture-Screen -OutPath $script:LiveScreenPath
        }
        $screen = Inspect-GameScreen -ImagePath $script:LiveScreenPath
        if ($screen.IsGenericOkPopup) {
            Write-Log "Generic teal OK popup detected in STAGE_MODAL; tapping OK to dismiss."
            Invoke-AdbTap -X 800 -Y 580 -Reason "Dismiss generic teal OK popup before stage selection"
            Start-Sleep -Milliseconds 1200
            continue
        }
        if (-not $screen.IsStageModal) {
            throw "Expected STAGE_MODAL during stage selection, but screen state is '$($screen.State)'."
        }
        if ($screen.IsStageModalDimmedOverlay) {
            Invoke-AdbTap -X 800 -Y 180 -Reason "Dismiss 'Mở ải mới' overlay before reading stage list"
            Start-Sleep -Milliseconds 800
            Capture-Screen -OutPath $script:LiveScreenPath
            $screen = Inspect-GameScreen -ImagePath $script:LiveScreenPath
        }

        $modalInfo = Get-StageModalInfo -ImagePath $script:LiveScreenPath
        $rows = @($modalInfo.StageRows | Where-Object { $null -ne $_ -and $null -ne $_.Stage })
        if ($rows.Count -eq 0) {
            Invoke-AdbTap -X 800 -Y 180 -Reason "Dismiss possible modal overlay (0 visible rows)"
            Start-Sleep -Milliseconds 800
            continue
        }

        $minVis = ($rows | Measure-Object -Property Stage -Minimum).Minimum
        $maxVis = ($rows | Measure-Object -Property Stage -Maximum).Maximum
        if ($maxVis -gt $maxSeenOverall) { $maxSeenOverall = $maxVis }
        if ($minVis -lt $minSeenOverall) { $minSeenOverall = $minVis }

        $targetRow = $rows | Where-Object { $_.Stage -eq $TargetStage } | Select-Object -First 1
        if ($null -ne $targetRow) {
            # Fast-path: when Tiếp tục (or initial modal open) already selected $TargetStage, skip redundant row tap + sleep!
            if ($targetRow.IsSelected -and ($modalInfo.SelectedStageBanner -eq $TargetStage -or $modalInfo.IsHeaderOccluded)) {
                $isLocked = $targetRow.IsLocked -or (-not $screen.IsVaoAiVisible)
                Write-Log "Fast-path: Ải $TargetStage already selected (Banner=$($modalInfo.SelectedStageBanner), RowY=$($targetRow.CenterY), VaoAiVisible=$($screen.IsVaoAiVisible))."
                return [pscustomobject]@{
                    Found           = $true
                    Reason          = 'AlreadySelected'
                    Stage           = $TargetStage
                    TapY            = $targetRow.CenterY
                    IsLocked        = $isLocked
                    PadlockDetected = $targetRow.IsLocked
                    IsVaoAiVisible  = $screen.IsVaoAiVisible
                    Stars           = $targetRow.Stars
                    ModalInfo       = $modalInfo
                    MaxStageSeen    = $maxSeenOverall
                }
            }

            # Select row and verify top banner shows Ải $TargetStage
            for ($selTry = 1; $selTry -le 3; $selTry++) {
                Invoke-AdbTap -X 200 -Y $targetRow.CenterY -Reason "Select Ải $TargetStage (Y=$($targetRow.CenterY), try $selTry)"
                Start-Sleep -Milliseconds 750
                Capture-Screen -OutPath $script:LiveScreenPath
                $afterScreen = Inspect-GameScreen -ImagePath $script:LiveScreenPath
                $afterInfo   = Get-StageModalInfo -ImagePath $script:LiveScreenPath
                $afterRow    = @($afterInfo.StageRows) | Where-Object { $_.Stage -eq $TargetStage } | Select-Object -First 1

                if ($afterInfo.SelectedStageBanner -eq $TargetStage -or ($null -ne $afterRow -and $afterRow.IsSelected)) {
                    $rowFinal = if ($null -ne $afterRow) { $afterRow } else { $targetRow }
                    $isLocked = $rowFinal.IsLocked -or (-not $afterScreen.IsVaoAiVisible)
                    return [pscustomobject]@{
                        Found           = $true
                        Reason          = 'Selected'
                        Stage           = $TargetStage
                        TapY            = $rowFinal.CenterY
                        IsLocked        = $isLocked
                        PadlockDetected = $rowFinal.IsLocked
                        IsVaoAiVisible  = $afterScreen.IsVaoAiVisible
                        Stars           = $rowFinal.Stars
                        ModalInfo       = $afterInfo
                        MaxStageSeen    = $maxSeenOverall
                    }
                }
                if ($null -ne $afterRow) { $targetRow = $afterRow }
            }
            throw "Tapped Ải $TargetStage three times, but SelectedStageBanner remained $($afterInfo.SelectedStageBanner)."
        }

        if ($TargetStage -lt $minVis) {
            $stallDown = 0
            $diff = $minVis - $TargetStage
            if ($minVis -eq $prevMin) {
                $stallUp++
                if ($stallUp -ge 3 -and $TargetStage -lt $minSeenOverall) {
                    return [pscustomobject]@{
                        Found        = $false
                        Reason       = 'BelowChapterStart'
                        Stage        = $TargetStage
                        ModalInfo    = $modalInfo
                        MaxStageSeen = $maxSeenOverall
                    }
                }
            } else {
                $stallUp = 0
            }
            $prevMin = $minVis
            if ($diff -le 2) {
                Invoke-AdbSwipe -X1 290 -Y1 420 -X2 290 -Y2 580 -DurationMs 950 -Reason "Nudge stage list UP toward Ải $TargetStage (diff=$diff, visible $minVis..$maxVis)"
            } else {
                Invoke-AdbSwipe -X1 290 -Y1 360 -X2 290 -Y2 640 -DurationMs 950 -Reason "Scroll stage list UP toward Ải $TargetStage (diff=$diff, visible $minVis..$maxVis)"
            }
            Start-Sleep -Milliseconds 650
        }
        elseif ($TargetStage -gt $maxVis) {
            $stallUp = 0
            $diff = $TargetStage - $maxVis
            if ($maxVis -eq $prevMax) {
                $stallDown++
                if ($stallDown -ge 3 -and $TargetStage -gt $maxSeenOverall) {
                    return [pscustomobject]@{
                        Found        = $false
                        Reason       = 'EndOfChapter'
                        Stage        = $TargetStage
                        ModalInfo    = $modalInfo
                        MaxStageSeen = $maxSeenOverall
                    }
                }
            } else {
                $stallDown = 0
            }
            $prevMax = $maxVis
            if ($diff -le 2) {
                Invoke-AdbSwipe -X1 290 -Y1 580 -X2 290 -Y2 420 -DurationMs 950 -Reason "Nudge stage list DOWN toward Ải $TargetStage (diff=$diff, visible $minVis..$maxVis)"
            } else {
                Invoke-AdbSwipe -X1 290 -Y1 640 -X2 290 -Y2 360 -DurationMs 950 -Reason "Scroll stage list DOWN toward Ải $TargetStage (diff=$diff, visible $minVis..$maxVis)"
            }
            Start-Sleep -Milliseconds 650
        }
        else {
            Invoke-AdbSwipe -X1 290 -Y1 560 -X2 290 -Y2 420 -DurationMs 600 -Reason "Nudge stage list to unclip Ải $TargetStage"
            Start-Sleep -Milliseconds 600
        }
    }

    return [pscustomobject]@{
        Found        = $false
        Reason       = 'ScrollLimitExceeded'
        Stage        = $TargetStage
        ModalInfo    = (Get-StageModalInfo -ImagePath $script:LiveScreenPath)
        MaxStageSeen = $maxSeenOverall
    }
}

function Test-PostVaoAiBlockedPopup {
    param([Parameter(Mandatory = $true)][string]$ImagePath)
    $bmp = $null
    try {
        $bmp = Open-UnlockedBitmap -ImagePath $ImagePath

        # 1. Check dimmed STAGE_MODAL background signature underneath foreground popup
        $p1538     = $bmp.GetPixel(1538, 52)
        $p1553     = $bmp.GetPixel(1553, 52)
        $p1553Ring = $bmp.GetPixel(1553, 77)
        $p1260     = $bmp.GetPixel(1260, 815)

        $hasDimmedCloseBtn = (
            ($p1538.R -ge 55 -and $p1538.R -le 188 -and $p1538.G -le 75 -and $p1538.B -le 85 -and ([int]$p1538.R - [int]$p1538.G) -ge 35) -and
            ($p1553.R -ge 80 -and $p1553.R -le 235 -and [Math]::Abs([int]$p1553.R - [int]$p1553.G) -le 16 -and [Math]::Abs([int]$p1553.G - [int]$p1553.B) -le 16 -and $p1553.R -gt ($p1538.R + 15)) -and
            ($p1553Ring.R -ge 75 -and $p1553Ring.R -le 235 -and [Math]::Abs([int]$p1553Ring.R - [int]$p1553Ring.G) -le 18 -and [Math]::Abs([int]$p1553Ring.G - [int]$p1553Ring.B) -le 18)
        )
        $hasDimmedVaoAi = (
            $p1260.R -ge 75 -and $p1260.G -ge 45 -and $p1260.B -le 80 -and ([int]$p1260.R - [int]$p1260.B) -ge 40 -and $p1260.R -ge $p1260.G
        )
        $isDimmedStageModal = ($hasDimmedCloseBtn -and $hasDimmedVaoAi)

        # 2. Quick center-popup OCR verification for stamina / tries / VIP / diamond purchase modal text
        $midLight = Invoke-RegionOcr -Bitmap $bmp -X 300 -Y 130 -Width 1000 -Height 620 -Scale 2 -Preprocess LightText
        $midRaw   = Invoke-RegionOcr -Bitmap $bmp -X 300 -Y 130 -Width 1000 -Height 620 -Scale 2 -Preprocess None
        $combined = "$($midLight.NormalizedText) $($midRaw.NormalizedText)".Trim()

        $isNewStageBannerOnly = ($combined -match '\bmo ai moi\b')
        $hasModalOcr = (-not $isNewStageBannerOnly) -and (
            $combined -match '\b(the luc|kim cuong|so lan|het luot|mua luot|them luot|khong du|hoi phuc|bo sung|mua|vip|xac nhan|tui day|balo|vigor|energia|diamante|tentativa|comprar|insuficiente|stamina)\b'
        )

        $innerRedClose = [PokemonStageNative]::FindRedCloseX($bmp, 1000, 85, 1490, 340)

        return [pscustomobject]@{
            IsBlockedPopup     = ($isDimmedStageModal -or $hasModalOcr)
            IsDimmedStageModal = $isDimmedStageModal
            HasModalOcr        = $hasModalOcr
            InnerRedCloseX     = $innerRedClose.X
            InnerRedCloseY     = $innerRedClose.Y
            OcrText            = $combined
        }
    } finally {
        if ($null -ne $bmp) { $bmp.Dispose() }
    }
}

function Test-DefeatScreenOcr {
    param([Parameter(Mandatory = $true)][string]$ImagePath)
    $bmp = $null
    try {
        $bmp = Open-UnlockedBitmap -ImagePath $ImagePath
        $topLight = Invoke-RegionOcr -Bitmap $bmp -X 360 -Y 50 -Width 880 -Height 330 -Scale 2 -Preprocess LightText
        $topRaw   = Invoke-RegionOcr -Bitmap $bmp -X 360 -Y 50 -Width 880 -Height 330 -Scale 2 -Preprocess None
        $botLight = Invoke-RegionOcr -Bitmap $bmp -X 420 -Y 580 -Width 800 -Height 280 -Scale 2 -Preprocess LightText

        $combined = "$($topLight.NormalizedText) $($topRaw.NormalizedText) $($botLight.NormalizedText)"
        $isDefeat = ($combined -match '\b(that bai|thua cuoc|chien bai|derrota|defeat|you lose)\b')
        return [pscustomobject]@{
            IsDefeat = $isDefeat
            OcrText  = $combined.Trim()
            Words    = $botLight.Words
        }
    } finally {
        if ($null -ne $bmp) { $bmp.Dispose() }
    }
}
#endregion

#region Main Execution Flow
Initialize-PokemonOcr
Connect-AdbDevice

# 1. Handle -ListMaps mode (zero battles, zero stamina spent)
if ($ListMaps) {
    $mapState = Ensure-AdventureMapOpen
    if ($script:ModeExplicitlyBound) {
        Set-AdventureMapMode -WantEliteMode $script:WantElite
        Capture-Screen -OutPath $script:LiveScreenPath
        $mapState = Inspect-GameScreen -ImagePath $script:LiveScreenPath
    }
    $listSnap = Join-Path $script:ResolvedOutputDir "list_maps_live.png"
    Copy-Item -LiteralPath $script:LiveScreenPath -Destination $listSnap -Force
    $activeModeStr = if ($mapState.IsHardMap) { "Hard/Elite" } elseif ($mapState.IsNormalMap) { "Normal" } else { "Unknown" }

    Write-Log "=== Discoverable Adventure Maps (Active Map Mode: $activeModeStr) ==="
    Write-Host ("{0,3} | {1,-20} | {2,-18} | {3,-21} | {4,-6} | {5,-12} | {6}" -f "Ch#", "Vietnamese Name", "ASCII -MapName", "Map Ground Label", "Anchor", "Normal Stgs", "Hard/Elite")
    Write-Host ("-" * 105)
    foreach ($m in $script:Region1Catalog) {
        Write-Host ("{0,3} | {1,-20} | {2,-18} | {3,-21} | {4,-6} | {5,-12} | {6}" -f $m.Chapter, $m.ViName, $m.AsciiName, $m.PtLabel, $m.Anchor, $m.NormalStages, $m.HardStages)
    }
    Write-Log "Saved live Adventure Map screenshot: '$listSnap'. Exiting cleanly without fighting."
    exit 0
}

# 2. Handle -DryRun mode (navigates, selects StartStage, logs status, saves preview PNG, NEVER taps Vào ải)
if ($DryRun) {
    $endLabel = if ($EndStage -gt 0) { "$EndStage" } else { "EndOfChapter" }
    Write-Log "=== DRY RUN: Map='$MapName' Mode='$script:CanonicalMode' Stages=$StartStage..$endLabel SkipCleared=$SkipCleared ==="

    $modalInfo = Ensure-StageModalOpen
    $sel = Select-StageInModal -TargetStage $StartStage

    $mapSlug = Get-SafeSlug $(if ($null -ne $script:EffectiveMapEntry) { $script:EffectiveMapEntry.AsciiName } else { $modalInfo.MapBaseNameNormalized })
    $previewPath = Join-Path $script:ResolvedOutputDir ("dryrun_{0}_{1}_stage_{2}.png" -f $mapSlug, $script:CanonicalMode.ToLowerInvariant(), $StartStage)
    Copy-Item -LiteralPath $script:LiveScreenPath -Destination $previewPath -Force

    $headerText = if (-not $sel.ModalInfo.IsHeaderOccluded -and $sel.ModalInfo.ChapterTitleRaw) { $sel.ModalInfo.ChapterTitleRaw } else { $modalInfo.ChapterTitleRaw }
    $eliteFlag  = if (-not $sel.ModalInfo.IsHeaderOccluded) { $sel.ModalInfo.IsElite } else { $modalInfo.IsElite }

    if (-not $sel.Found) {
        Write-Log "ERROR: Stage Ải $StartStage was not found in '$headerText' (reason=$($sel.Reason), maxStageSeen=Ải $($sel.MaxStageSeen)). Preview saved: '$previewPath'."
        exit 2
    }

    $wouldSkip = ($SkipCleared.IsPresent -and $sel.Stars -ge 1)
    Write-Log "DRY RUN STAGE SUMMARY:"
    Write-Log "  Chapter Header  : $headerText"
    Write-Log "  Mode Verified   : $(if ($eliteFlag) { 'Hard/Elite ([Elite])' } else { 'Normal (Thường)' })"
    Write-Log "  Star Progress   : $($sel.ModalInfo.StarProgress)"
    Write-Log "  Selected Stage  : Ải $($sel.Stage) (Banner=$($sel.ModalInfo.SelectedStageBanner), RowTap=(200, $($sel.TapY)))"
    Write-Log "  Stage Status    : $(if ($sel.IsLocked) { 'LOCKED' } else { 'UNLOCKED' }) (Padlock=$($sel.PadlockDetected), VaoAiVisible=$($sel.IsVaoAiVisible), Stars=$($sel.Stars)/4)"
    Write-Log "  Planned Range   : Ải $StartStage -> $(if ($EndStage -gt 0) { "Ải $EndStage" } else { 'End of Chapter' }) (WouldSkipStartStage=$wouldSkip)"
    Write-Log "  Preview Saved   : $previewPath"

    if ($sel.IsLocked) {
        Write-Log "ERROR: Stage Ải $StartStage in '$headerText' is LOCKED (padlock=$($sel.PadlockDetected), VaoAiVisible=$($sel.IsVaoAiVisible)). Exiting without tapping 'Vào ải'."
        exit 2
    }

    Write-Log "DRY RUN PASSED — Stopping cleanly WITHOUT tapping 'Vào ải' (zero stamina spent)."
    exit 0
}

function Save-SettledFinalScreen {
    param([Parameter(Mandatory = $true)][int]$Stage)
    $finalPath = Join-Path $script:ResolvedOutputDir "final_after_stage_${Stage}.png"
    $waitSw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        Capture-Screen -OutPath $finalPath
        $st = Inspect-GameScreen -ImagePath $finalPath
        if ($st.State -notin @('LOADING_SCREEN', 'UNKNOWN') -or $waitSw.Elapsed.TotalSeconds -ge 10) {
            return $finalPath
        }
        Start-Sleep -Milliseconds 1000
    }
}

# 3. Live Stage-Running Loop ($StartStage .. $EndStage or EndOfChapter, with optional -Chain)
$stage = $StartStage
$stagesClearedCount = 0
$chapterMaxStages = 0
$cameFromTiepTuc = $false
$chaptersCompletedCount = 0

while ($true) {
    # Inner stage loop for current chapter
    while ($true) {
    if ($EndStage -gt 0 -and $stage -gt $EndStage) {
        break
    }

    Write-Log "=== Preparing Stage Ải $stage (Mode=$script:CanonicalMode) ==="
    $modalInfo = Ensure-StageModalOpen -CameFromTiepTuc $cameFromTiepTuc -ExpectedSelectedStage $stage
    if ($null -eq $modalInfo) {
        $script:ChainHalted = $true
        break
    }
    $parsedOpenMax = Get-MaxStagesFromStarProgress -StarProgress $modalInfo.StarProgress
    if ($parsedOpenMax -gt 0 -and $parsedOpenMax -ge $stage) {
        $chapterMaxStages = $parsedOpenMax
    }

    $sel = Select-StageInModal -TargetStage $stage -ReuseLastCapture:$cameFromTiepTuc
    $cameFromTiepTuc = $false

    if (-not $sel.Found) {
        if ($sel.Reason -eq 'EndOfChapter' -and $stage -gt $sel.MaxStageSeen -and $stage -gt $StartStage) {
            if ($EndStage -gt 0) {
                Write-Log "Chapter '$($sel.ModalInfo.ChapterTitleRaw)' ends at Ải $($sel.MaxStageSeen) (before requested -EndStage $EndStage). Stopping cleanly."
            } else {
                Write-Log "Reached end of chapter '$($sel.ModalInfo.ChapterTitleRaw)' after Ải $($sel.MaxStageSeen). Stopping cleanly."
            }
            break
        }
        $notFoundSnap = Join-Path $script:ResolvedOutputDir "stage_${stage}_not_found.png"
        Copy-Item -LiteralPath $script:LiveScreenPath -Destination $notFoundSnap -Force
        Write-Log "ERROR: Stage Ải $stage not found in '$($sel.ModalInfo.ChapterTitleRaw)' (reason=$($sel.Reason), maxStageSeen=Ải $($sel.MaxStageSeen)). Saved '$notFoundSnap'."
        exit 2
    }

    $parsedSelMax = Get-MaxStagesFromStarProgress -StarProgress $sel.ModalInfo.StarProgress
    if ($parsedSelMax -gt 0 -and $parsedSelMax -ge $sel.MaxStageSeen -and $parsedSelMax -ge $stage) {
        $chapterMaxStages = $parsedSelMax
    }

    if ($sel.IsLocked) {
        if ($Chain) {
            $chainSnap = Join-Path $script:ResolvedOutputDir ("chain_next_map_locked_{0}.png" -f (Get-SafeSlug $script:EffectiveMapEntry.AsciiName))
            Copy-Item -LiteralPath $script:LiveScreenPath -Destination $chainSnap -Force
            Write-Log "========================================================"
            Write-Log "[CHAIN STOPPED] Stage Ải $stage in '$($sel.ModalInfo.ChapterTitleRaw)' is LOCKED (padlock=$($sel.PadlockDetected)). Halting automation."
            Write-Log "Saved snapshot to '$chainSnap'."
            Write-Log "========================================================"
            $script:ChainHalted = $true
            break
        }
        $lockSnap = Join-Path $script:ResolvedOutputDir "stage_${stage}_locked.png"
        Copy-Item -LiteralPath $script:LiveScreenPath -Destination $lockSnap -Force
        Write-Log "ERROR: Stage Ải $stage in '$($sel.ModalInfo.ChapterTitleRaw)' is LOCKED (padlock=$($sel.PadlockDetected), VaoAiVisible=$($sel.IsVaoAiVisible)). Saved '$lockSnap'."
        exit 2
    }

    $modalSnap = Join-Path $script:ResolvedOutputDir "stage_${stage}_modal.png"
    Copy-Item -LiteralPath $script:LiveScreenPath -Destination $modalSnap -Force
    Write-Log "Selected Ải $stage in '$($sel.ModalInfo.ChapterTitleRaw)' (Stars=$($sel.Stars)/4, TapY=$($sel.TapY), MaxStages=$(if ($chapterMaxStages -gt 0) { $chapterMaxStages } else { '?' }))."

    if ($SkipCleared -and $sel.Stars -ge 1) {
        Write-Log "Stage Ải $stage already has $($sel.Stars) star(s) and -SkipCleared is set; skipping."
        if ($EndStage -gt 0 -and $stage -ge $EndStage) {
            Write-Log "Reached -EndStage $EndStage (skipped cleared stage). Stopping all ADB inputs."
            break
        }
        if ($EndStage -eq 0 -and $chapterMaxStages -gt 0 -and $stage -ge $chapterMaxStages) {
            Write-Log "Reached final stage Ải $stage of chapter (MaxStages=$chapterMaxStages, skipped cleared stage). Stopping all ADB inputs."
            break
        }
        $stage++
        continue
    }

    # Enter battle ("Vào ải")
    Invoke-AdbTap -X 1330 -Y 815 -Reason "Enter Stage Ải $stage (Vào ải)"
    $stageSw = [System.Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Seconds 5

    $prevGrid = $null
    $retriedEnter = $false
    $stageCleared = $false

    while ($stageSw.Elapsed.TotalSeconds -lt $StageTimeoutSec) {
        Capture-Screen -OutPath $script:LiveScreenPath
        $poll = Inspect-GameScreen -ImagePath $script:LiveScreenPath
        $elapsedSec = [math]::Round($stageSw.Elapsed.TotalSeconds, 1)

        if ($poll.IsLoadingScreen) {
            $prevGrid = $null
            Start-Sleep -Seconds 2
            continue
        }
        elseif ($poll.IsStageModal) {
            if ($poll.IsStageModalDimmedOverlay -and $elapsedSec -lt 15) {
                $overlayCheck = Test-PostVaoAiBlockedPopup -ImagePath $script:LiveScreenPath
                if ($overlayCheck.HasModalOcr -and $overlayCheck.InnerRedCloseX -gt 0) {
                    $blockedPath = Join-Path $script:ResolvedOutputDir "stage_${stage}_blocked_popup.png"
                    Copy-Item -LiteralPath $script:LiveScreenPath -Destination $blockedPath -Force
                    Invoke-AdbTap -X $overlayCheck.InnerRedCloseX -Y $overlayCheck.InnerRedCloseY -Reason "Close post-Vào-ải inner popup safely without spending diamonds"
                    Write-Log "ERROR: Stage Ải $stage blocked by modal popup over STAGE_MODAL (OCR='$($overlayCheck.OcrText)'). Saved '$blockedPath'."
                    exit 2
                }
            }
            if ($elapsedSec -lt 15 -and -not $retriedEnter) {
                Write-Log "Stage Ải $stage (${elapsedSec}s): Still on STAGE_MODAL after 'Vào ải'; retrying once."
                $retriedEnter = $true
                Invoke-AdbTap -X 200 -Y $sel.TapY -Reason "Re-select Stage Ải $stage"
                Start-Sleep -Seconds 1
                Invoke-AdbTap -X 1330 -Y 815 -Reason "Retry Enter Stage Ải $stage (Vào ải)"
                Start-Sleep -Seconds 5
                $prevGrid = $null
                continue
            }
            $stuckPath = Join-Path $script:ResolvedOutputDir "stage_${stage}_stuck_modal.png"
            Copy-Item -LiteralPath $script:LiveScreenPath -Destination $stuckPath -Force
            Write-Log "ERROR: Stage Ải $stage (${elapsedSec}s) remained on STAGE_MODAL (possible stamina/attempt limit). Saved '$stuckPath'."
            exit 2
        }
        elseif ($poll.IsPopupRedX -and $elapsedSec -lt 15) {
            $blockCheck = Test-PostVaoAiBlockedPopup -ImagePath $script:LiveScreenPath
            if ($blockCheck.IsBlockedPopup) {
                $blockedPath = Join-Path $script:ResolvedOutputDir "stage_${stage}_blocked_popup.png"
                Copy-Item -LiteralPath $script:LiveScreenPath -Destination $blockedPath -Force
                Invoke-AdbTap -X $poll.RedCloseX -Y $poll.RedCloseY -Reason "Close post-Vào-ải popup safely without spending diamonds"
                Write-Log "ERROR: Stage Ải $stage blocked by verified popup after tapping 'Vào ải' (DimmedModal=$($blockCheck.IsDimmedStageModal), ModalOcr=$($blockCheck.HasModalOcr), OCR='$($blockCheck.OcrText)'). Saved '$blockedPath'."
                exit 2
            }
            Write-Log "Stage Ải $stage (${elapsedSec}s): Ignoring non-blocking RedCloseX candidate at ($($poll.RedCloseX), $($poll.RedCloseY)) (not over dimmed STAGE_MODAL and no blocking modal text)."
            $prevGrid = $poll.GridSignature
            Start-Sleep -Seconds 3
            continue
        }
        elseif ($poll.IsFirstClearOk) {
            Write-Log "Stage Ải $stage (${elapsedSec}s): FIRST_CLEAR_OK ('Lần đầu Quà') detected."
            Invoke-AdbTap -X 800 -Y 705 -Reason "Dismiss FIRST_CLEAR_OK (OK)"
            $prevGrid = $null
            Start-Sleep -Milliseconds 1500
            continue
        }
        elseif ($poll.IsGenericOkPopup) {
            Write-Log "Stage Ải $stage (${elapsedSec}s): GENERIC_OK_POPUP detected (Lair map / Level-up / Reward item) — tapping OK."
            Invoke-AdbTap -X 800 -Y 580 -Reason "Dismiss generic teal OK popup"
            $prevGrid = $null
            Start-Sleep -Milliseconds 1500
            continue
        }
        elseif ($poll.IsVictoryEval) {
            Write-Log "Stage Ải $stage (${elapsedSec}s): VICTORY_EVAL ('Đánh giá') detected (Ve=$($poll.VicVeRgb), TiepTuc=$($poll.VicTiepRgb))."
            $victoryPath = Join-Path $script:ResolvedOutputDir "stage_${stage}_victory.png"
            Copy-Item -LiteralPath $script:LiveScreenPath -Destination $victoryPath -Force
            Write-Log "Saved victory screenshot: '$victoryPath'"
            Start-Sleep -Milliseconds 400
            Invoke-AdbTap -X 1500 -Y 805 -Reason "Tap Tiếp tục (return to STAGE_MODAL; NEVER Tiếp at 1500,700)"
            Start-Sleep -Milliseconds 2500
            $stageCleared = $true
            $cameFromTiepTuc = $true
            $stagesClearedCount++
            break
        }
        elseif (($poll.IsMainTown -or $poll.IsAdventureMap) -and $elapsedSec -gt 15) {
            $unexpPath = Join-Path $script:ResolvedOutputDir "stage_${stage}_unexpected_exit.png"
            Copy-Item -LiteralPath $script:LiveScreenPath -Destination $unexpPath -Force
            Write-Log "ERROR: Stage Ải $stage (${elapsedSec}s) exited to $($poll.State) without VICTORY_EVAL. Saved '$unexpPath'."
            exit 2
        }
        else {
            $isStatic = ($null -ne $prevGrid -and $poll.GridSignature -eq $prevGrid)
            if ($isStatic -and $stageSw.Elapsed.TotalSeconds -gt 10) {
                $defeatCheck = Test-DefeatScreenOcr -ImagePath $script:LiveScreenPath
                if ($defeatCheck.IsDefeat) {
                    $defeatPath = Join-Path $script:ResolvedOutputDir "stage_${stage}_defeat.png"
                    Copy-Item -LiteralPath $script:LiveScreenPath -Destination $defeatPath -Force
                    Write-Log "ERROR: Defeat ('Thất bại') detected on Stage Ải $stage at ${elapsedSec}s (OCR='$($defeatCheck.OcrText)'). Saved '$defeatPath'."
                    exit 3
                }
            }

            if ($isStatic -and $stageSw.Elapsed.TotalSeconds -gt 20) {
                Write-Log "Stage Ải $stage (${elapsedSec}s): Static screen >20s across 10-point grid; tapping (800, 780) to advance dialogue."
                Invoke-AdbTap -X 800 -Y 780 -Context 'BattleDialogue' -Reason "Advance static NPC dialogue"
                $prevGrid = $null
            } else {
                $prevGrid = $poll.GridSignature
            }
            Start-Sleep -Seconds 3
        }
    }

    if (-not $stageCleared) {
        $timeoutPath = Join-Path $script:ResolvedOutputDir "stage_${stage}_timeout.png"
        Copy-Item -LiteralPath $script:LiveScreenPath -Destination $timeoutPath -Force
        Write-Log "ERROR: Stage Ải $stage timed out after ${StageTimeoutSec}s without VICTORY_EVAL. Saved '$timeoutPath'."
        exit 3
    }

    Write-Log "=== Stage Ải $stage completed ==="

    if ($EndStage -gt 0 -and $stage -ge $EndStage) {
        $finalPath = Save-SettledFinalScreen -Stage $stage
        Write-Log "Saved '$finalPath'. Reached -EndStage $EndStage — stopping all ADB inputs immediately."
        break
    }

    if ($EndStage -eq 0 -and $chapterMaxStages -gt 0 -and $stage -ge $chapterMaxStages) {
        $finalPath = Save-SettledFinalScreen -Stage $stage
        Write-Log "Saved '$finalPath'. Completed final stage Ải $stage of chapter (MaxStages=$chapterMaxStages) — stopping all ADB inputs immediately without spilling into next chapter."
        break
    }

    $stage++
    }

    $chaptersCompletedCount++

    if ($script:ChainHalted) {
        break
    }

    if (-not $Chain) {
        break
    }

    if ($null -eq $script:EffectiveMapEntry) {
        Write-Log "[CHAIN STOPPED] Current map has no catalog entry (unrecognized or custom). Cannot determine next map. Stopping cleanly."
        break
    }

    $nextEntry = Get-NextProgressionChapterEntry -CurrentEntry $script:EffectiveMapEntry -WantElite $script:WantElite
    if ($null -eq $nextEntry) {
        Write-Log "[CHAIN STOPPED] No next chapter found in progression sequence. All available chapters completed! Stopping cleanly."
        break
    }

    if (-not (Test-MapIsOpenable -Entry $nextEntry -WantElite $script:WantElite)) {
        $stgStr = if ($script:WantElite) { $nextEntry.HardStages } else { $nextEntry.NormalStages }
        $null = Close-StageModal
        Start-Sleep -Milliseconds 1000
        $null = Ensure-AdventureMapOpen
        Move-ToMapAnchor -Anchor $nextEntry.Anchor
        Capture-Screen -OutPath $script:LiveScreenPath
        $lockedSnap = Join-Path $script:ResolvedOutputDir ("chain_next_map_locked_{0}.png" -f (Get-SafeSlug $nextEntry.AsciiName))
        try { Copy-Item -LiteralPath $script:LiveScreenPath -Destination $lockedSnap -Force } catch {}
        Write-Log "========================================================"
        Write-Log "[CHAIN STOPPED] Next map '$($nextEntry.ViName)' ($($nextEntry.EnName)) is LOCKED ($stgStr) in catalog. Halting automation."
        Write-Log "Saved snapshot to '$lockedSnap'."
        Write-Log "========================================================"
        break
    }

    Write-Log "========================================================"
    Write-Log "[CHAIN] Chapter '$($script:EffectiveMapEntry.ViName)' finished. Advancing to next map: '$($nextEntry.ViName)' ($($nextEntry.EnName))..."
    Write-Log "========================================================"

    # Close current modal to return to Adventure Map
    $null = Close-StageModal
    Start-Sleep -Milliseconds 1200

    # Advance effective map entry and reset stage variables for the new chapter
    $script:EffectiveMapEntry = $nextEntry
    $script:EffectiveMapCustomTitle = ""
    $script:VerifiedPlaceholderModalNorm = ""
    $stage = 1
    $StartStage = 1
    $EndStage = 0
    $chapterMaxStages = 0
    $cameFromTiepTuc = $false

    # Try opening next chapter modal. If it fails or is locked in-game:
    $newModal = Ensure-StageModalOpen
    if ($null -eq $newModal) {
        break
    }
    Write-Log "[CHAIN] Successfully opened '$($newModal.ChapterTitleRaw)'! Starting from Ải 1..."
}

Write-Log "Script finished cleanly ($stagesClearedCount stage(s) cleared across $chaptersCompletedCount chapter(s))."
exit 0
