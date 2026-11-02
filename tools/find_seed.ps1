param(
    [string]$BuildRoot = "C:\fpga\HX4S20_全套工程_源码_技术文档_工作记录_20261012(1)\HX4S20_Final_Delivery_Package_20261012\01_工程完整源码\build_ext_20261018_162322",
    [int[]]$Seeds = @(1, 2, 3, 5, 7, 8, 11, 12, 13, 15, 20, 25, 42, 50, 100)
)

$compiler = "C:/fpga/bin/td_commands_prompt.exe"
$runsDir = Join-Path $BuildRoot "prj/HX4S20_HDMI_Player_Runs"
$phyTemplate = Join-Path $runsDir "phy_1"

Write-Output "Starting Placement Seed Search in $BuildRoot..."

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
                
                # Copy golden results to phy_1
                Get-ChildItem $phyDir | ForEach-Object {
                    Copy-Item $_.FullName (Join-Path $phyTemplate $_.Name) -Force
                }
                
                # Copy bitstream to target paths
                $bitFile = Join-Path $phyDir "HX4S20_HDMI_Player.bit"
                if (Test-Path $bitFile) {
                    Copy-Item $bitFile "C:\fpga\board_menu.bit" -Force
                    Copy-Item $bitFile "C:\fpga\HX4S20_HDMI_Player_完整交付包_v2.0\prj\HX4S20_HDMI_Player_Runs\phy_1\HX4S20_HDMI_Player.bit" -Force
                    Write-Output "Golden bitstream copied to C:\fpga\board_menu.bit"
                }
                exit 0
            }
        }
    } else {
        Write-Output "Seed $seed failed to produce route_flow.status"
    }
}

Write-Output "No seed closed timing among tested seeds."
exit 1
