$adb = "C:\Program Files\BlueStacks_nxt\HD-Adb.exe"
& $adb -s 127.0.0.1:5555 shell screencap -p /sdcard/s.png
& $adb -s 127.0.0.1:5555 pull /sdcard/s.png "C:\Users\HT-ASUS\Desktop\leetcode\scratch\current_live.png" | Out-Null
Write-Host "Captured current_live.png"
