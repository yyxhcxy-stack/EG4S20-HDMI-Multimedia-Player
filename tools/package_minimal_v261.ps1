param()
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$out=Join-Path $root 'output/extension_v2_6_1'
$result=Get-Content -LiteralPath (Join-Path $out 'build_result.json') -Raw | ConvertFrom-Json
$head=(& git -C $root rev-parse HEAD)
if ($result.version -ne 'v2_6_1' -or $result.git_commit -ne $head) {throw 'Export the current committed v2.6.1 first.'}
foreach ($ext in @('bit','bin')) {
    $file=Join-Path $out ('HX4S20_HDMI_Player_v2_6_1_candidate.'+$ext)
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower() -ne $result.artifact_sha256.$ext) {throw 'Candidate hash mismatch.'}
}
$validation=Join-Path $root 'output/verification/all_suites_manifest.json'
if ((Get-FileHash -LiteralPath $validation -Algorithm SHA256).Hash -ne $result.rtl_validation_sha256) {throw 'Regression evidence changed since export.'}
$manifest=Get-Content -LiteralPath $validation -Raw | ConvertFrom-Json
if (!$manifest.passed -or @($manifest.suites).Count -ne 26) {throw 'All 26 suites required.'}
$evidence=Join-Path $out 'verification'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
Copy-Item -LiteralPath $validation -Destination $evidence
foreach ($suite in $manifest.suites) {
    foreach ($suffix in @('_result.txt','_manifest.json','_elaborate.log')) {
        Copy-Item -LiteralPath (Join-Path $root ('output/verification/'+$suite+$suffix)) -Destination $evidence
    }
}
foreach ($name in @('v261_scope.json','marquee_control_vendor_elaborate.log')) {
    Copy-Item -LiteralPath (Join-Path $root ('output/verification/'+$name)) -Destination $evidence
}
foreach ($name in @('audio_units','marquee_unit')) {
    Copy-Item -LiteralPath (Join-Path $root ('output/verification/'+$name)) -Destination $evidence -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $root 'tools/marquee_uart.py') -Destination $out
Copy-Item -LiteralPath (Join-Path $root 'doc/v2.6.1_最小修改与验收.md') -Destination $out
$preview=Join-Path $root 'output/v261_marquee_preview'
if (Test-Path -LiteralPath $preview) {Copy-Item -LiteralPath $preview -Destination $out -Recurse -Force}
$archivePath=Join-Path $out ('source_'+$head.Substring(0,7)+'.zip')
& git -C $root archive --format=zip ('--output='+$archivePath) HEAD
if ($LASTEXITCODE -ne 0) {throw 'Source archive failed.'}
$hardware=Join-Path $out 'board_acceptance.json'
if (!(Test-Path -LiteralPath $hardware)) {
    [ordered]@{version='v2_6_1';source_commit=$head;bit_sha256=$result.artifact_sha256.bit;flash_changed=$false;download_mode='SRAM only';hardware_acceptance_complete=$false;pending=@('开机性能面板隐藏且无闪现','KEY3长按显示和隐藏','串口1/128字符右侧入场向左滚动','重复更新与字幕关闭开启','应急进入退出恢复','HDMI、LCD、声音及原功能');observations=@()} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $hardware -Encoding utf8
}
@((Get-ChildItem -LiteralPath $out -File -Recurse | Where-Object {$_.Name -ne 'delivery_sha256.json'}) | ForEach-Object {
    [ordered]@{path=$_.FullName.Substring($out.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()}
}) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $out 'delivery_sha256.json') -Encoding utf8
Write-Output "Packaged minimal v2.6.1: $out"
