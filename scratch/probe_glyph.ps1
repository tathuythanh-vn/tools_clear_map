Add-Type -AssemblyName System.Drawing
$crop = [System.Drawing.Bitmap]::FromFile('C:\Users\HT-ASUS\Desktop\leetcode\scratch\crop_stage_list.png')
# Row 2 (Dungeon 10) Y_crop is around 382 - 220 = 162
Write-Host "Row 2 (Dungeon 10, unselected) at Y=162, X=40..250:"
for ($x = 40; $x -le 250; $x += 10) {
    $c = $crop.GetPixel($x, 162)
    Write-Host ("X_game={0,3} (xc={1,3}): R={2,3} G={3,3} B={4,3}" -f ($x + 100), $x, $c.R, $c.G, $c.B)
}
Write-Host ""
# Row 3 (Dungeon 11) Y_crop is around 501 - 220 = 281
Write-Host "Row 3 (Dungeon 11, selected) at Y=281, X=40..250:"
for ($x = 40; $x -le 250; $x += 10) {
    $c = $crop.GetPixel($x, 281)
    Write-Host ("X_game={0,3} (xc={1,3}): R={2,3} G={3,3} B={4,3}" -f ($x + 100), $x, $c.R, $c.G, $c.B)
}
$crop.Dispose()
