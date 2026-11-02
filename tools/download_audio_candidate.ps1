param([string]$TdHome='',[ValidateSet('v2_6','v2_6_1','v2_6_2')][string]$Version='v2_6_2')
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
if ($result.version -ne $Version -or $result.final_timing.Setup.violating_endpoints -ne 0 -or $result.final_timing.Hold.violating_endpoints -ne 0) {throw 'Candidate checks are incomplete.'}
foreach ($check in @('Setup','Hold')) {
    if ($result.final_timing.$check.wns_ps -lt 0 -or $result.final_timing.$check.tns_ps -lt 0) {throw 'Timing not closed.'}
}
if ($Version -eq 'v2_6_2' -and ($result.resources.dsp.used -gt 26 -or $result.resources.bram.used -gt 64 -or $result.resources.bram32k.used -gt 16)) {throw 'Architecture resource budget exceeded.'}
$bit=Join-Path $out ('HX4S20_HDMI_Player_'+$Version+'_candidate.bit')
$sha = [System.Security.Cryptography.SHA256]::Create()
$stream = [System.IO.File]::OpenRead($bit)
$digest = [System.BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLower()
$stream.Close()
if ($digest -ne $result.artifact_sha256.bit) {throw "Candidate bit hash mismatch: $digest vs $($result.artifact_sha256.bit)"}
$boardBit=Join-Path $out 'board_candidate.bit'
Copy-Item -LiteralPath $bit -Destination $boardBit -Force
$stagingBit = 'C:\fpga\board_menu.bit'
Copy-Item -LiteralPath $bit -Destination $stagingBit -Force
$stagingTcl = 'C:\fpga\burn_sram.tcl'
[IO.File]::WriteAllText($stagingTcl,('list_cable'+"`n"+'download -bit "'+$stagingBit.Replace('\','/')+'" -mode jtag'+"`nexit`n"),(New-Object Text.UTF8Encoding($false)))
$tcl=Join-Path $out 'board_sram.tcl'
Copy-Item -LiteralPath $stagingTcl -Destination $tcl -Force
$log=Join-Path $out ('sram_download_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
& (Join-Path $TdHome 'bin/bw_commands_prompt.exe') $stagingTcl.Replace('\','/') > $log 2>&1
if ($LASTEXITCODE -ne 0) {throw "SRAM download failed; inspect $log"}
$content=[IO.File]::ReadAllText($log)
if ($content -notmatch 'RUN-1003 : finish command "download .* -mode jtag"' -or $content -match '(?i)ERROR:|Unknown cable') {throw "No download success evidence; inspect $log"}
[ordered]@{time=(Get-Date -Format o);git_commit=$result.git_commit;bit_sha256=$digest;mode='jtag SRAM';download_log=$log;hardware_acceptance_complete=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'sram_download.json') -Encoding utf8
Write-Output "Temporary SRAM candidate downloaded. SHA256=$digest; log=$log"
