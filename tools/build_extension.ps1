param([string]$BuildRoot = '', [string]$TdHome = '', [ValidatePattern('^v[0-9]+_[0-9]+(?:_[0-9]+)?$')][string]$Version = 'v2_6_2', [ValidateRange(0,255)][int]$PlaceSeed = 10, [switch]$NoExport)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::ASCII
if (!$TdHome) {
    if ($env:TD_HOME -and (Test-Path -LiteralPath (Join-Path $env:TD_HOME 'bin/td_commands_prompt.exe'))) { $TdHome = $env:TD_HOME }
    elseif (Test-Path -LiteralPath 'C:/fpga/bin/td_commands_prompt.exe') { $TdHome = 'C:/fpga' }
    elseif (Test-Path -LiteralPath 'D:/TD/bin/td_commands_prompt.exe') { $TdHome = 'D:/TD' }
    elseif (Test-Path -LiteralPath 'C:/Anlogic/TD6.2.1/bin/td_commands_prompt.exe') { $TdHome = 'C:/Anlogic/TD6.2.1' }
    else { throw "Unable to locate Anlogic Tang Dynasty installation. Please set TD_HOME." }
}
$sourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (!$BuildRoot) { $BuildRoot = Join-Path $sourceRoot ('build_ext_' + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
if (Test-Path -LiteralPath $BuildRoot) { throw "Build directory already exists: $BuildRoot" }
$compiler = Join-Path $TdHome 'bin/td_commands_prompt.exe'
if (!(Test-Path -LiteralPath $compiler)) { throw "TD compiler not found: $compiler" }
New-Item -ItemType Directory -Path $BuildRoot | Out-Null
$gitMetadata = [ordered]@{
    place_seed = $PlaceSeed
    git_commit = $(try { & git -C $sourceRoot rev-parse HEAD 2>$null } catch { 'd5faf4c' })
    git_branch = $(try { & git -C $sourceRoot branch --show-current 2>$null } catch { 'main' })
    git_tracked_changes = $(try { @(& git -C $sourceRoot status --porcelain --untracked-files=no 2>$null) } catch { @() })
}
$env:HX4S20_PLACE_SEED = [string]$PlaceSeed
$gitMetadata | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $BuildRoot 'git_snapshot.json') -Encoding utf8
Copy-Item -LiteralPath (Join-Path $sourceRoot 'src') -Destination $BuildRoot -Recurse
New-Item -ItemType Directory -Path (Join-Path $BuildRoot 'prj') | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceRoot 'prj/al_ip') -Destination (Join-Path $BuildRoot 'prj') -Recurse
Copy-Item -LiteralPath (Join-Path $sourceRoot 'prj/HX4S20_HDMI_Player.al') -Destination (Join-Path $BuildRoot 'prj')
Copy-Item -LiteralPath (Join-Path $sourceRoot 'voice_emergency_64kb.mif') -Destination $BuildRoot
if (Test-Path -LiteralPath (Join-Path $sourceRoot 'src/rtl/font_rom_8x16_lo.mif')) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'src/rtl/font_rom_8x16_lo.mif') -Destination $BuildRoot
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'src/rtl/font_rom_8x16_hi.mif') -Destination $BuildRoot
}
$projectText = [IO.File]::ReadAllText((Join-Path $sourceRoot 'prj/HX4S20_HDMI_Player.al'))
$projectText = $projectText.Replace('Path="../', 'Path="../../../').Replace('Path="al_ip/', 'Path="../../al_ip/')
$utf8 = New-Object Text.UTF8Encoding($false)
foreach ($runName in @('syn_1','phy_1')) {
    $runPath = Join-Path $BuildRoot "prj/HX4S20_HDMI_Player_Runs/$runName"
    New-Item -ItemType Directory -Path $runPath -Force | Out-Null
    $oldRun = Join-Path $sourceRoot "prj/HX4S20_HDMI_Player_Runs/$runName"
    Copy-Item -LiteralPath (Join-Path $oldRun 'settings.cfg') -Destination $runPath
    Copy-Item -LiteralPath (Join-Path $oldRun 'HX4S20_HDMI_Player.tcl') -Destination $runPath
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'voice_emergency_64kb.mif') -Destination $runPath
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'src/rtl/font_rom_8x16.mif') -Destination $runPath
    if (Test-Path -LiteralPath (Join-Path $sourceRoot 'src/rtl/font_rom_8x16_lo.mif')) {
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'src/rtl/font_rom_8x16_lo.mif') -Destination $runPath
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'src/rtl/font_rom_8x16_hi.mif') -Destination $runPath
    }
    [IO.File]::WriteAllText((Join-Path $runPath 'HX4S20_HDMI_Player.prj'), $projectText, $utf8)
    $tclFile = Join-Path $runPath 'HX4S20_HDMI_Player.tcl'
    $tclContent = [IO.File]::ReadAllText($tclFile)
    $tclContent = $tclContent.Replace('return -code error $RESULT', "puts `"TD_STEP_FAILED: `$s - `$RESULT`"`r`n    exit 1")
    [IO.File]::WriteAllText($tclFile, $tclContent + "`nexit 0`n", $utf8)
    Push-Location -LiteralPath $runPath
    try {
        $null | & $compiler 'HX4S20_HDMI_Player.tcl' > (Join-Path $runPath 'build_console.log') 2>&1
        if ($LASTEXITCODE -ne 0) { throw "TD $runName failed. See $runPath/build_console.log" }
        $marker = if ($runName -eq 'syn_1') { '.opt_gate.end.f' } else { '.bitgen.end.f' }
        if (!(Test-Path -LiteralPath $marker)) { throw "TD $runName did not complete. See $runPath/build_console.log" }
    } finally { Pop-Location }
    Write-Output "Completed $runName in $runPath"
}
Write-Output "Build completed: $BuildRoot"
Write-Output 'Check final timing before using this candidate on hardware.'
if (!$NoExport) { & (Join-Path $PSScriptRoot 'collect_extension_build.ps1') -BuildRoot $BuildRoot -TdHome $TdHome -Version $Version }
