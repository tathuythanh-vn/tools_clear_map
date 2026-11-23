Add-Type -AssemblyName System.Drawing
$path = 'C:\Users\HT-ASUS\.gemini\antigravity\brain\e7d023a5-ce9c-4b8b-a25d-8a267be3c856\.user_uploaded\media_1795288451129_44d6b914.jpg'
$b = [System.Drawing.Bitmap]::FromFile($path)
$b1600 = New-Object System.Drawing.Bitmap 1600, 900
$g = [System.Drawing.Graphics]::FromImage($b1600)
$g.DrawImage($b, 0, 0, 1600, 900)
$g.Dispose()

$crop = New-Object System.Drawing.Bitmap 400, 600
$gc = [System.Drawing.Graphics]::FromImage($crop)
$gc.DrawImage($b1600, [System.Drawing.Rectangle]::new(0, 0, 400, 600), [System.Drawing.Rectangle]::new(100, 220, 400, 600), [System.Drawing.GraphicsUnit]::Pixel)
$gc.Dispose()
$crop.Save('C:\Users\HT-ASUS\Desktop\leetcode\scratch\crop_stage_list.png', [System.Drawing.Imaging.ImageFormat]::Png)
$crop.Dispose()
$b.Dispose()
$b1600.Dispose()
Write-Host "Saved crop_stage_list.png"
