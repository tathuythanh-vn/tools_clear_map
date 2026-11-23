Add-Type -AssemblyName System.Drawing
$path = 'C:\Users\HT-ASUS\.gemini\antigravity\brain\e7d023a5-ce9c-4b8b-a25d-8a267be3c856\.user_uploaded\media_1795288451129_44d6b914.jpg'
$b = [System.Drawing.Bitmap]::FromFile($path)
$b1600 = New-Object System.Drawing.Bitmap 1600, 900
$g = [System.Drawing.Graphics]::FromImage($b1600)
$g.DrawImage($b, 0, 0, 1600, 900)
$g.Dispose()

# Row 1 (Dungeon 9) is around Y=263
# Row 2 (Dungeon 10) is around Y=382
# Row 3 (Dungeon 11) is around Y=501
Write-Host "Probing Row 3 (Dungeon 11) at Y=500, X=100..350:"
for ($x = 100; $x -le 350; $x += 10) {
    $c = $b1600.GetPixel($x, 500)
    Write-Host ("X={0,3}: R={1,3} G={2,3} B={3,3}" -f $x, $c.R, $c.G, $c.B)
}
$b.Dispose()
$b1600.Dispose()
