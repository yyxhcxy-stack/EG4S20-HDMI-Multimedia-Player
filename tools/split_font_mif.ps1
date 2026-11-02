$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$sourceRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
$sourceMif = Join-Path $sourceRoot 'src/rtl/font_rom_8x16.mif'
$loMif = Join-Path $sourceRoot 'src/rtl/font_rom_8x16_lo.mif'
$hiMif = Join-Path $sourceRoot 'src/rtl/font_rom_8x16_hi.mif'

$lines = Get-Content -LiteralPath $sourceMif
$dataLines = $lines | Where-Object { $_ -match '^[0-9A-Fa-f]{4}\s*:\s*[0-9A-Fa-f]{2};' }
Write-Output "Total data lines: $($dataLines.Length)"

$header = @(
    "DEPTH = 1024;",
    "WIDTH = 8;",
    "ADDRESS_RADIX = HEX;",
    "DATA_RADIX = HEX;",
    "CONTENT",
    "BEGIN"
)

$loContent = [System.Collections.Generic.List[string]]::new()
foreach ($h in $header) { $loContent.Add($h) }
for ($i = 0; $i -lt 1024; $i++) {
    $val = ($dataLines[$i] -split ':')[1].Trim()
    $addr = '{0:X4}' -f $i
    $loContent.Add("$addr : $val")
}
$loContent.Add("END;")

$hiContent = [System.Collections.Generic.List[string]]::new()
foreach ($h in $header) { $hiContent.Add($h) }
for ($i = 0; $i -lt 1024; $i++) {
    $val = ($dataLines[$i + 1024] -split ':')[1].Trim()
    $addr = '{0:X4}' -f $i
    $hiContent.Add("$addr : $val")
}
$hiContent.Add("END;")

[System.IO.File]::WriteAllLines($loMif, $loContent)
[System.IO.File]::WriteAllLines($hiMif, $hiContent)

Write-Output "Successfully generated font_rom_8x16_lo.mif ($($loContent.Count) lines) and font_rom_8x16_hi.mif ($($hiContent.Count) lines)."
