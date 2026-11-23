$adb = "C:\Program Files\BlueStacks_nxt\HD-Adb.exe"
Add-Type -AssemblyName System.Drawing

function Tap($x, $y) {
    & $adb -s 127.0.0.1:5555 shell input tap $x $y
    Start-Sleep -Milliseconds 1200
}
function Swipe($x1, $y1, $x2, $y2, $ms=400) {
    & $adb -s 127.0.0.1:5555 shell input swipe $x1 $y1 $x2 $y2 $ms
    Start-Sleep -Milliseconds 900
}
function Shot($name) {
    & $adb -s 127.0.0.1:5555 shell screencap -p /sdcard/s.png
    & $adb -s 127.0.0.1:5555 pull /sdcard/s.png "C:\Users\HT-ASUS\Desktop\leetcode\scratch\$name.png" | Out-Null
}

$lines = Get-Content 'C:\Users\HT-ASUS\Desktop\leetcode\run_pokemon_stages.ps1'
$fnCode = ($lines[0..1558]) -join "`n"
Invoke-Expression $fnCode
Initialize-PokemonOcr

# Reset camera to left wall
for ($i = 0; $i -lt 4; $i++) {
    Swipe 220 745 1420 745 350
}
Start-Sleep -Milliseconds 1000

# Tap each chapter node in Region1Catalog and read modal header
foreach ($m in $script:Region1Catalog) {
    # Move camera to anchor
    switch ($m.Anchor) {
        'Left' {
            # Already left
        }
        'Mid' {
            # From left to mid
            for ($i = 0; $i -lt 4; $i++) { Swipe 220 745 1420 745 350 }
            Swipe 1250 220 600 220 1000
            Start-Sleep -Milliseconds 600
        }
        'Right' {
            for ($i = 0; $i -lt 4; $i++) { Swipe 1380 745 200 745 350 }
            Start-Sleep -Milliseconds 600
        }
    }

    # Tap node
    Tap $m.TapX $m.TapY
    Shot "probe_ch_$($m.Chapter)"
    $s = Inspect-GameScreen -ImagePath "C:\Users\HT-ASUS\Desktop\leetcode\scratch\probe_ch_$($m.Chapter).png"
    if ($s.IsStageModal) {
        $info = Get-StageModalInfo -ImagePath "C:\Users\HT-ASUS\Desktop\leetcode\scratch\probe_ch_$($m.Chapter).png"
        Write-Host ("Ch {0,2}: Modal='{1}' | Progress='{2}' | TopBanner='{3}'" -f $m.Chapter, $info.ChapterTitleRaw, $info.StarProgress, $info.SelectedStageBanner)
        # Close modal
        Tap 1540 85
        Start-Sleep -Milliseconds 800
    } else {
        Write-Host ("Ch {0,2}: State={1} (Not opened/Locked)" -f $m.Chapter, $s.State)
        if ($s.IsPopupRedX) {
            Tap $s.RedCloseX $s.RedCloseY
        }
        if ($s.IsGenericOkPopup) {
            Tap 800 580
        }
    }
}
