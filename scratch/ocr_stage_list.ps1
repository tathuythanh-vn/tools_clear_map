Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$lines = Get-Content 'C:\Users\HT-ASUS\Desktop\leetcode\run_pokemon_stages.ps1'
$fnCode = ($lines[0..1558]) -join "`n"
Invoke-Expression $fnCode
Initialize-PokemonOcr

$crop = [System.Drawing.Bitmap]::FromFile('C:\Users\HT-ASUS\Desktop\leetcode\scratch\crop_stage_list.png')
$ocr = Invoke-RegionOcr -Bitmap $crop -X 0 -Y 0 -Width 400 -Height 600 -Scale 2 -Preprocess None
Write-Host "OCR text on stage list:"
foreach ($l in $ocr.Lines) {
    Write-Host ("  Line: '{0}' at Y={1}" -f $l.Text, $l.CenterY)
}
$crop.Dispose()
