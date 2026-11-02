param()
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$out=Join-Path $root 'output/extension_v2_6_2'
$result=Get-Content -LiteralPath (Join-Path $out 'build_result.json') -Raw | ConvertFrom-Json
$head=(& git -C $root rev-parse HEAD)
if ($result.version -ne 'v2_6_2' -or $result.git_commit -ne $head) {throw 'Export the current committed v2.6.2 first.'}
foreach ($ext in @('bit','bin')) {
    $file=Join-Path $out ('HX4S20_HDMI_Player_v2_6_2_candidate.'+$ext)
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower() -ne $result.artifact_sha256.$ext) {throw 'Candidate hash mismatch.'}
}
$validation=Join-Path $root 'output/verification/all_suites_manifest.json'
if ((Get-FileHash -LiteralPath $validation -Algorithm SHA256).Hash -ne $result.rtl_validation_sha256) {throw 'Regression evidence changed since export.'}
$manifest=Get-Content -LiteralPath $validation -Raw | ConvertFrom-Json
if (!$manifest.passed -or @($manifest.suites).Count -ne 32) {throw 'All 32 suites required.'}
$evidence=Join-Path $out 'verification'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
Copy-Item -LiteralPath $validation -Destination $evidence
foreach ($suite in $manifest.suites) {
    foreach ($suffix in @('_result.txt','_manifest.json','_elaborate.log')) {
        Copy-Item -LiteralPath (Join-Path $root ('output/verification/'+$suite+$suffix)) -Destination $evidence
    }
}
foreach ($name in @('v262_scope.json','marquee_control_vendor_elaborate.log')) {
    Copy-Item -LiteralPath (Join-Path $root ('output/verification/'+$name)) -Destination $evidence
}
foreach ($name in @('audio_units','marquee_unit','v262_adjust_compare','feedback_text_values','bank_baseline_failure')) {
    Copy-Item -LiteralPath (Join-Path $root ('output/verification/'+$name)) -Destination $evidence -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $root 'tools/marquee_uart.py') -Destination $out
Copy-Item -LiteralPath (Join-Path $root 'doc/v2.6.2_实现方案优化记录.md') -Destination $out
$preview=Join-Path $root 'output/scaling_preview'
if (Test-Path -LiteralPath $preview) {Copy-Item -LiteralPath $preview -Destination $out -Recurse -Force}
Copy-Item -LiteralPath (Join-Path $root 'doc/v2.6.2_架构与约束说明.md') -Destination $out
Copy-Item -LiteralPath (Join-Path $root 'doc/v2.6.2_上板验收清单.md') -Destination $out
$quietReport=Join-Path $root 'doc/v2.6.2_串口静默修正.md'
if (Test-Path -LiteralPath $quietReport) {Copy-Item -LiteralPath $quietReport -Destination $out}
$displayPreview=Join-Path $root 'output/v262_preview'
if (Test-Path -LiteralPath $displayPreview) {
    $previewManifest=Get-Content -LiteralPath (Join-Path $displayPreview 'manifest.json') -Raw | ConvertFrom-Json
    foreach ($property in $previewManifest.rtl_sha256.PSObject.Properties) {
        if ((Get-FileHash -LiteralPath (Join-Path $root $property.Name) -Algorithm SHA256).Hash.ToLower() -ne $property.Value) {throw 'RTL display preview is stale.'}
    }
    $destination=Join-Path $out 'display_preview';New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $previewFiles=@(Get-ChildItem -LiteralPath $displayPreview -File -Filter '*.png')
    $previewFiles+=Get-Item -LiteralPath (Join-Path $displayPreview 'manifest.json')
    foreach ($file in $previewFiles) {
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
}
$archivePath=Join-Path $out ('source_'+$head.Substring(0,7)+'.zip')
& git -C $root archive --format=zip ('--output='+$archivePath) HEAD
if ($LASTEXITCODE -ne 0) {throw 'Source archive failed.'}
$hardware=Join-Path $out 'board_acceptance.json'
if (!(Test-Path -LiteralPath $hardware)) {
    [ordered]@{version='v2_6_2';source_commit=$head;bit_sha256=$result.artifact_sha256.bit;flash_changed=$false;download_mode='SRAM only';hardware_acceptance_complete=$false;pending=@('隐藏HUD调参提示120帧及优先级','三种缓动转场与混合尺寸缩放','HDMI/LCD频谱统一比例','串口字幕右侧入场开关及应急恢复','一小时运行、100次操作','10次上电后临时下载、10次复位及LCD启动观察；新版自主冷启动待后续固化授权');observations=@()} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $hardware -Encoding utf8
}
Copy-Item -LiteralPath (Join-Path $root 'output/baseline_v2_6_2_architecture/baseline_sha256.json') -Destination $out
@((Get-ChildItem -LiteralPath $out -File -Recurse | Where-Object {$_.Name -ne 'delivery_sha256.json'}) | ForEach-Object {
    [ordered]@{path=$_.FullName.Substring($out.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()}
}) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $out 'delivery_sha256.json') -Encoding utf8
Write-Output "Packaged architecture optimization v2.6.2: $out"
