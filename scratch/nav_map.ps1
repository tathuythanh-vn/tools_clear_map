$adb = "C:\Program Files\BlueStacks_nxt\HD-Adb.exe"

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
    Write-Host "Saved $name.png"
}

# Step 1: Close any popup by tapping X area
Tap 1130 160
Shot "nav_01_after_close"
