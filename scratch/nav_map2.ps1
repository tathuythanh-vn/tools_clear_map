$adb = "C:\Program Files\BlueStacks_nxt\HD-Adb.exe"

function Swipe($x1, $y1, $x2, $y2, $ms=400) {
    & $adb -s 127.0.0.1:5555 shell input swipe $x1 $y1 $x2 $y2 $ms
    Start-Sleep -Milliseconds 1200
}
function Shot($name) {
    & $adb -s 127.0.0.1:5555 shell screencap -p /sdcard/s.png
    & $adb -s 127.0.0.1:5555 pull /sdcard/s.png "C:\Users\HT-ASUS\Desktop\leetcode\scratch\$name.png" | Out-Null
    Write-Host "Saved $name.png"
}

# Pan right (drag from right to left)
Swipe 1200 450 300 450 600
Shot "nav_02_pan_right1"

Swipe 1200 450 300 450 600
Shot "nav_03_pan_right2"

Swipe 1200 450 300 450 600
Shot "nav_04_pan_right3"
