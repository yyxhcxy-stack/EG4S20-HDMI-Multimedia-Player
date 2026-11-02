param(
    [string]$BuildRoot = "C:\fpga\HX4S20_HDMI_Player_完整交付包_v2.8_方向4全适配\01_工程完整源码\build_ext_20261024_123223",
    [int[]]$Seeds = @(1, 2, 3, 5, 7, 8, 11, 12, 15, 20, 25)
)

$compiler = "C:/fpga/bin/td_commands_prompt.exe"
if (!(Test-Path $compiler)) {
    if (Test-Path "C:/Anlogic/TD6.2.1/bin/td_commands_prompt.exe") {
        $compiler = "C:/Anlogic/TD6.2.1/bin/td_commands_prompt.exe"
    } elseif (Test-Path "D:/TD/bin/td_commands_prompt.exe") {
        $compiler = "D:/TD/bin/td_commands_prompt.exe"
    }
}

$sourceRoot = "C:\fpga\HX4S20_HDMI_Player_完整交付包_v2.8_方向4全适配\01_工程完整源码"
$runsDir = Join-Path $BuildRoot "prj/HX4S20_HDMI_Player_Runs"
$phyTemplate = Join-Path $runsDir "phy_1"

Write-Output "Starting Placement Seed Search in $BuildRoot..."
Write-Output "Compiler: $compiler"

foreach ($seed in $Seeds) {
    $phyDir = Join-Path $runsDir "phy_seed_$seed"
    if (!(Test-Path $phyDir)) { New-Item -ItemType Directory -Path $phyDir -Force | Out-Null }
    
    foreach ($fname in @("settings.cfg", "HX4S20_HDMI_Player.tcl", "HX4S20_HDMI_Player.prj", "voice_emergency_64kb.mif", "font_rom_8x16.mif")) {
        $src = Join-Path $phyTemplate $fname
        $dst = Join-Path $phyDir $fname
        if (Test-Path $src) { Copy-Item $src $dst -Force }
    }
    
    Write-Output "=========================================="
    Write-Output "Testing Place Seed: $seed in $phyDir"
    Write-Output "=========================================="
    
    $env:HX4S20_PLACE_SEED = [string]$seed
    $logFile = Join-Path $phyDir "build_console.log"
    
    Push-Location $phyDir
    try {
        $null | & $compiler 'HX4S20_HDMI_Player.tcl' > $logFile 2>&1
    } finally {
        Pop-Location
    }
    
    $statusFile = Join-Path $phyDir "route_flow.status"
    if (Test-Path $statusFile) {
        $text = [IO.File]::ReadAllText($statusFile)
        $sMatch = [regex]::Match($text, "Setup\s*:\s*WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)")
        $hMatch = [regex]::Match($text, "Hold\s*:\s*WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)")
        
        if ($sMatch.Success -and $hMatch.Success) {
            $s_wns = [int]$sMatch.Groups[1].Value
            $s_feps = [int]$sMatch.Groups[3].Value
            $h_wns = [int]$hMatch.Groups[1].Value
            $h_feps = [int]$hMatch.Groups[3].Value
            
            Write-Output "Seed $seed Result: Setup WNS=${s_wns}ps (FEPS=$s_feps), Hold WNS=${h_wns}ps (FEPS=$h_feps)"
            
            if ($s_wns -ge 0 -and $s_feps -eq 0 -and $h_wns -ge 0 -and $h_feps -eq 0) {
                Write-Output ">>> TIMING CLOSED FOR SEED $seed! <<<"
                
                # Copy golden results back to phy_1
                Get-ChildItem $phyDir | ForEach-Object {
                    Copy-Item $_.FullName (Join-Path $phyTemplate $_.Name) -Force
                }
                
                # Copy bitstream to root for SRAM download
                $bitFile = Join-Path $phyDir "HX4S20_HDMI_Player.bit"
                if (Test-Path $bitFile) {
                    Copy-Item $bitFile (Join-Path $sourceRoot "HX4S20_HDMI_Player.bit") -Force
                    Write-Output "Copied bitstream to $sourceRoot\HX4S20_HDMI_Player.bit"
                }
                
                # Run export collection
                $collectScript = Join-Path $sourceRoot "tools/collect_extension_build.ps1"
                & $collectScript -BuildRoot $BuildRoot -Version "v2_6_2"
                Write-Output "Successfully collected candidate build!"
                exit 0
            }
        }
    } else {
        Write-Output "Seed $seed failed to produce route_flow.status"
    }
}

Write-Output "No seed closed timing among tested seeds."
exit 1
