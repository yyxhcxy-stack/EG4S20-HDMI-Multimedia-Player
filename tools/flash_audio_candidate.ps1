param([string]$TdHome='', [ValidateRange(1,9)][int]$Speed=1, [ValidateSet('v2_6','v2_6_1','v2_6_2')][string]$Version='v2_6')
$ErrorActionPreference='Stop'
if (!$TdHome) {
    if ($env:TD_HOME -and (Test-Path -LiteralPath (Join-Path $env:TD_HOME 'bin/bw_commands_prompt.exe'))) { $TdHome = $env:TD_HOME }
    elseif (Test-Path -LiteralPath 'C:/fpga/bin/bw_commands_prompt.exe') { $TdHome = 'C:/fpga' }
    elseif (Test-Path -LiteralPath 'D:/TD/bin/bw_commands_prompt.exe') { $TdHome = 'D:/TD' }
    elseif (Test-Path -LiteralPath 'C:/Anlogic/TD6.2.1/bin/bw_commands_prompt.exe') { $TdHome = 'C:/Anlogic/TD6.2.1' }
    else { throw "Unable to locate Anlogic BitWriter installation. Please set TD_HOME." }
}
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$out=Join-Path $root ('output/extension_'+$Version)
$result=Get-Content -LiteralPath (Join-Path $out 'build_result.json') -Raw | ConvertFrom-Json
if ($result.version -ne $Version) {throw 'Expected the explicitly selected verified candidate.'}
foreach ($check in @('Setup','Hold')) {
    if ($result.final_timing.$check.wns_ps -lt 0 -or $result.final_timing.$check.tns_ps -ne 0 -or $result.final_timing.$check.violating_endpoints -ne 0) {throw 'Candidate timing checks failed.'}
}
$bit=Join-Path $out ('HX4S20_HDMI_Player_'+$Version+'_candidate.bit')
$digest=(Get-FileHash -LiteralPath $bit -Algorithm SHA256).Hash.ToLower()
if ($digest -ne $result.artifact_sha256.bit) {throw 'Candidate bit hash mismatch.'}
$boardBit=Join-Path $result.build_root 'board_flash_candidate.bit'
Copy-Item -LiteralPath $bit -Destination $boardBit
$tcl=Join-Path $result.build_root 'board_flash_verified.tcl'
[IO.File]::WriteAllText($tcl,('list_cable'+"`n"+'download -bit "'+$boardBit.Replace('\','/')+'" -mode program_spi -spd '+$Speed+' -v'+"`nexit`n"),(New-Object Text.UTF8Encoding($false)))
$log=Join-Path $out ('flash_program_verified_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
'exit' | & (Join-Path $TdHome 'bin/bw_commands_prompt.exe') $tcl.Replace('\','/') > $log 2>&1
$rc=$LASTEXITCODE
$contents=[IO.File]::ReadAllText($log)
if ($rc -ne 0 -or $contents -match '(?i)ERROR:|failed|invalid option|Unknown cable|mismatch|compare error' -or
    $contents -notmatch 'finish command "program_spi ' -or $contents -notmatch '-m verify_spi ' -or
    $contents -notmatch 'finish command "program -cable ' -or $contents -notmatch 'finish command "download ') {
    throw "Flash programming or readback verification did not pass. Inspect $log"
}
[ordered]@{time=(Get-Date -Format o);version=$Version;programming_tool_commit=(& git -C $root rev-parse HEAD);git_commit=$result.git_commit;bit_sha256=$digest;mode='SPI Flash';speed=$Speed;write_and_readback_verified=$true;power_cycle_boot_verified=$false;download_log=$log;download_log_sha256=(Get-FileHash -LiteralPath $log -Algorithm SHA256).Hash.ToLower()} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'flash_program.json') -Encoding utf8
Write-Output "Flash written and readback verified. Git=$($result.git_commit); log=$log"
