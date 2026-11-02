param([Parameter(Mandatory=$true)][string]$BuildRoot, [string]$TdHome = 'D:/Anlogic/TD6.2.1', [ValidatePattern('^v[0-9]+_[0-9]+(?:_[0-9]+)?$')][string]$Version = 'v2_6')
$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$buildPath = (Resolve-Path -LiteralPath $BuildRoot).Path
$phy = Join-Path $buildPath 'prj/HX4S20_HDMI_Player_Runs/phy_1'
if (!(Test-Path -LiteralPath (Join-Path $phy '.bitgen.end.f'))) { throw 'Build has no bitgen completion marker.' }
$status = [IO.File]::ReadAllText((Join-Path $phy 'route_flow.status'))
$finalTiming = [ordered]@{}
foreach ($check in @('Setup','Hold')) {
    $pattern = $check + '\s*:\s*WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)'
    if ($status -notmatch $pattern) { throw "Missing final $check timing in $phy/route_flow.status" }
    $finalTiming[$check] = [ordered]@{wns_ps=[int]$Matches[1];tns_ps=[int]$Matches[2];violating_endpoints=[int]$Matches[3]}
    if ($finalTiming[$check].wns_ps -lt 0 -or $finalTiming[$check].tns_ps -lt 0 -or $finalTiming[$check].violating_endpoints -ne 0) {
        throw "$check timing is not closed. Candidate export refused; review $phy/route_flow.status"
    }
}

$validationPath = Join-Path $sourceRoot 'output/verification/all_suites_manifest.json'
if (!(Test-Path -LiteralPath $validationPath)) { throw 'Run all extension RTL regression suites before exporting.' }
$validation = Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json
$requiredSuites = @('scaling_geometry','frame_boundary','seg_digits','keys','source_fifo','adjust','osd','osd_bram','scaling_system','scaling_core','scaling_pipeline','transition','bmp','frame_reader','frame_writer','frame_writer256','fonts','uart')
if ($Version -in @('v2_6','v2_6_1','v2_6_2')) { $requiredSuites += @('audio_i2s','audio_synth','audio_output','spectrum_dft','audio_system','lcd_snapshot') }
if ($Version -in @('v2_6_1','v2_6_2')) { $requiredSuites += @('marquee_control','marquee_osd') }
if ($Version -eq 'v2_6_2') { $requiredSuites += @('bank_lifecycle','cdc_reset','parameter_feedback','sd_command_equivalence','storage_pressure','enable_equivalence') }
$areaPath = Join-Path $phy 'HX4S20_HDMI_Player_phy.area'
if (!(Test-Path -LiteralPath $areaPath)) { throw 'Missing final physical resource report.' }
$area = [IO.File]::ReadAllText($areaPath)
$resources = [ordered]@{}
foreach ($resource in @('lut','reg','bram','bram32k','dsp','pad','pll','gclk')) {
    $pattern = '(?m)^#' + $resource + '\s+(\d+)\s+out of\s+(\d+)'
    if ($area -notmatch $pattern) { throw "Missing final resource count: $resource" }
    $used = [int]$Matches[1]; $capacity = [int]$Matches[2]
    if ($used -gt $capacity) { throw "Resource capacity exceeded: $resource" }
    $resources[$resource] = [ordered]@{used=$used;capacity=$capacity}
}
if ($Version -in @('v2_6','v2_6_1','v2_6_2') -and ($resources.dsp.used -gt 26 -or $resources.bram.used -gt 64 -or $resources.bram32k.used -gt 16)) {
    throw 'v2.6 DSP/RAM budget exceeded. Candidate export refused.'
}
$physicalLog = [IO.File]::ReadAllText((Join-Path $phy 'build_console.log'))
$sliceMatches = [regex]::Matches($physicalLog, '(\d+) mslices, (\d+) lslices')
if ($sliceMatches.Count -eq 0) { throw 'Missing physical slice utilization.' }
$lastSlices = $sliceMatches[$sliceMatches.Count-1]
foreach ($entry in @(@('mslice',1),@('lslice',2))) {
    $used = [int]$lastSlices.Groups[$entry[1]].Value
    if ($used -gt 4900) { throw 'Physical slice capacity exceeded.' }
    $resources[$entry[0]] = [ordered]@{used=$used;capacity=4900}
}
$routedTiming = [IO.File]::ReadAllText((Join-Path $phy 'HX4S20_HDMI_Player_pr.timing'))
if ($routedTiming -notmatch 'STA coverage\s*:\s*([\d.]+)%') { throw 'Missing STA coverage report.' }
$staCoverage = [double]$Matches[1]
if (!$validation.passed -or @($validation.suites).Count -ne $requiredSuites.Count) { throw 'Incomplete RTL validation evidence.' }
foreach ($suite in $requiredSuites) {
    if (@($validation.suites) -notcontains $suite) { throw "Missing RTL suite: $suite" }
    $record = @($validation.records | Where-Object { $_.suite -eq $suite })
    $resultPath = Join-Path $sourceRoot "output/verification/${suite}_result.txt"
    if ($record.Count -ne 1 -or !(Test-Path -LiteralPath $resultPath) -or
        (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLower() -ne $record[0].result_sha256) {
        throw "RTL result changed or missing: $suite"
    }
}
$rtlFiles = @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'src/rtl') -File -Recurse -Filter '*.v')
if ($rtlFiles.Count -ne @($validation.rtl_sha256.PSObject.Properties).Count) { throw 'RTL source inventory changed; rerun regression.' }
foreach ($file in $rtlFiles) {
    $relative = $file.FullName.Substring($sourceRoot.Length + 1)
    $digest = $validation.rtl_sha256.PSObject.Properties[$relative].Value
    if (!$digest -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower() -ne $digest) {
        throw "RTL validation is stale: $relative"
    }
}
$memoryFiles = @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'src/rtl') -File -Recurse | Where-Object { $_.Extension -in @('.mif','.hex') })
if ($Version -in @('v2_6','v2_6_1','v2_6_2')) {
    if ($memoryFiles.Count -ne @($validation.memory_sha256.PSObject.Properties).Count) { throw 'Memory initialization inventory changed; rerun regression.' }
    foreach ($file in $memoryFiles) {
        $relative = $file.FullName.Substring($sourceRoot.Length+1)
        $digest = $validation.memory_sha256.PSObject.Properties[$relative].Value
        if (!$digest -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower() -ne $digest) { throw "Memory validation is stale: $relative" }
    }
}
if ($Version -in @('v2_6','v2_6_1','v2_6_2')) {
    $speechHex = [IO.File]::ReadAllLines((Join-Path $sourceRoot 'src/rtl/voice_emergency_64kb.hex'))
    $speechMif = [regex]::Matches([IO.File]::ReadAllText((Join-Path $sourceRoot 'voice_emergency_64kb.mif')), '(?m)^\s*([0-9A-Fa-f]{4})\s*:\s*([0-9A-Fa-f]{2})\s*;')
    if ($speechHex.Count -ne 65536 -or $speechMif.Count -ne 65536) { throw 'Incomplete speech ROM initialization.' }
    $speechAddresses = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($word in $speechMif) {
        $address = [Convert]::ToInt32($word.Groups[1].Value,16)
        if (!$speechAddresses.Add($address) -or $speechHex[$address].Trim() -ne $word.Groups[2].Value) { throw 'Hardware speech MIF differs from tested PCM HEX.' }
    }
    $unitEvidence=Join-Path $sourceRoot 'output/verification/audio_units/manifest.json'
    if (!(Test-Path -LiteralPath $unitEvidence)) {throw 'Missing independent audio synthesis evidence.'}
    $units=Get-Content -LiteralPath $unitEvidence -Raw | ConvertFrom-Json
    if (!$units.passed -or @($units.records).Count -ne 2) {throw 'Incomplete audio unit synthesis evidence.'}
    foreach ($module in @('audio_output_stage','audio_spectrum_dft')) {
        if (@($units.records | Where-Object {$_.module -eq $module}).Count -ne 1) {throw 'Missing or duplicate audio synthesis unit.'}
    }
    foreach ($unit in $units.records) {
        $unitSource=Join-Path $sourceRoot ('src/rtl/'+$unit.module+'.v')
        $unitArea=Join-Path $sourceRoot ('output/verification/audio_units/'+$unit.module+'/unit.area')
        if ($unit.dsp -ne 2 -or (Get-FileHash -LiteralPath $unitSource -Algorithm SHA256).Hash.ToLower() -ne $unit.source_sha256 -or
            (Get-FileHash -LiteralPath $unitArea -Algorithm SHA256).Hash.ToLower() -ne $unit.area_sha256) {throw 'Audio synthesis evidence is stale.'}
    }
}
if ($Version -eq 'v2_6_1') {
    & python (Join-Path $sourceRoot 'tools/verify_v261_scope.py')
    if ($LASTEXITCODE -ne 0) {throw 'Unrelated v2.6 baseline source changed.'}
}
if ($Version -in @('v2_6_1','v2_6_2')) {
    $marqueeUnits=Get-Content -LiteralPath (Join-Path $sourceRoot 'output/verification/marquee_unit/manifest.json') -Raw | ConvertFrom-Json
    if (!$marqueeUnits.passed -or @($marqueeUnits.records).Count -ne 2) {throw 'Missing independent marquee/shared UART synthesis evidence.'}
    foreach ($unit in $marqueeUnits.records) {
        $expectedRam=if ($unit.module -eq 'uart_scada_controller') {1} elseif ($unit.module -eq 'marquee_store') {0} else {throw 'Unknown marquee unit.'}
        if ($unit.dsp -ne 0 -or $unit.bram -ne $expectedRam -or $unit.bram32k -ne 0 -or
            (Get-FileHash -LiteralPath (Join-Path $sourceRoot ("src/rtl/"+$unit.module+".v")) -Algorithm SHA256).Hash.ToLower() -ne $unit.source_sha256 -or
            (Get-FileHash -LiteralPath (Join-Path $sourceRoot ("output/verification/marquee_unit/"+$unit.module+"/unit.area")) -Algorithm SHA256).Hash.ToLower() -ne $unit.area_sha256) {throw 'Marquee/shared UART synthesis evidence is stale.'}
        foreach ($property in $unit.dependencies.PSObject.Properties) {
            if ((Get-FileHash -LiteralPath (Join-Path $sourceRoot ("src/rtl/"+$property.Name)) -Algorithm SHA256).Hash.ToLower() -ne $property.Value) {throw 'Shared UART synthesis dependency changed.'}
        }
    }
}
if ($Version -eq 'v2_6_2') {
    & python (Join-Path $sourceRoot 'tools/verify_v262_scope.py')
    if ($LASTEXITCODE -ne 0) {throw 'Architecture optimization scope failed.'}
    $bankProof=Get-Content -LiteralPath (Join-Path $sourceRoot 'output/verification/bank_baseline_failure/manifest.json') -Raw | ConvertFrom-Json
    if (!$bankProof.passed -or !$bankProof.baseline_expected_failure -or
        (Get-FileHash -LiteralPath (Join-Path $sourceRoot 'tools/rtl_tests/bank_lifecycle_test.cpp') -Algorithm SHA256).Hash.ToLower() -ne $bankProof.test_sha256 -or
        (Get-FileHash -LiteralPath (Join-Path $sourceRoot 'tools/rtl_tests/bank_transport_mock.v') -Algorithm SHA256).Hash.ToLower() -ne $bankProof.mock_sha256) {throw 'Missing current baseline failure proof for buffer ownership fix.'}
    $textEvidence=Get-Content -LiteralPath (Join-Path $sourceRoot 'output/verification/feedback_text_values/manifest.json') -Raw | ConvertFrom-Json
    if (!$textEvidence.passed -or
        (Get-FileHash -LiteralPath (Join-Path $sourceRoot 'src/rtl/osd_display.v') -Algorithm SHA256).Hash.ToLower() -ne $textEvidence.source_sha256 -or
        (Get-FileHash -LiteralPath (Join-Path $sourceRoot 'tools/verify_feedback_text_values.py') -Algorithm SHA256).Hash.ToLower() -ne $textEvidence.checker_sha256 -or
        (Get-FileHash -LiteralPath (Join-Path $sourceRoot 'output/verification/feedback_text_values/result.txt') -Algorithm SHA256).Hash.ToLower() -ne $textEvidence.result_sha256) {throw 'Full feedback value evidence is stale.'}
    $adjustUnits=Get-Content -LiteralPath (Join-Path $sourceRoot 'output/verification/v262_adjust_compare/manifest.json') -Raw | ConvertFrom-Json
    $compact=@($adjustUnits.records | Where-Object {$_.variant -eq 'compact_rom'})
    if (!$adjustUnits.passed -or $compact.Count -ne 1 -or $compact[0].resources.dsp -ne 0 -or $compact[0].resources.bram -ne 3 -or
        (Get-FileHash -LiteralPath (Join-Path $sourceRoot 'src/rtl/video_adjust_lut.v') -Algorithm SHA256).Hash.ToLower() -ne $compact[0].source_sha256 -or
        (Get-FileHash -LiteralPath (Join-Path $sourceRoot 'output/verification/v262_adjust_compare/compact_rom/unit.area') -Algorithm SHA256).Hash.ToLower() -ne $compact[0].area_sha256) {throw 'Compact adjustment unit synthesis evidence is stale or incorrect.'}
    if (!$validation.test_sha256 -or !$validation.reference_revisions) {throw 'Missing independent model/test provenance.'}
    foreach ($property in $validation.test_sha256.PSObject.Properties) {
        if ((Get-FileHash -LiteralPath (Join-Path $sourceRoot $property.Name) -Algorithm SHA256).Hash.ToLower() -ne $property.Value) {throw 'Test/reference inputs changed since regression.'}
    }
    foreach ($property in $validation.reference_revisions.PSObject.Properties) {
        if ((& git -C $sourceRoot rev-parse ($property.Name+'^{commit}')) -ne $property.Value) {throw 'Independent reference revision changed.'}
    }
}
$manifest = @()
$inputFiles = @(Get-ChildItem -LiteralPath (Join-Path $buildPath 'src') -File -Recurse)
$inputFiles += @(Get-ChildItem -LiteralPath (Join-Path $buildPath 'prj/al_ip') -File -Recurse)
$inputFiles += Get-Item -LiteralPath (Join-Path $buildPath 'prj/HX4S20_HDMI_Player.al')
$inputFiles += Get-Item -LiteralPath (Join-Path $buildPath 'voice_emergency_64kb.mif')
foreach ($runName in @('syn_1','phy_1')) {
    foreach ($flowFile in @('HX4S20_HDMI_Player.tcl','settings.cfg')) {
        $inputFiles += Get-Item -LiteralPath (Join-Path $buildPath "prj/HX4S20_HDMI_Player_Runs/$runName/$flowFile")
    }
}
foreach ($file in $inputFiles) {
    $relative = $file.FullName.Substring($buildPath.Length + 1)
    $snapshotHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    $currentPath = Join-Path $sourceRoot $relative
    if (!(Test-Path -LiteralPath $currentPath) -or (Get-FileHash -LiteralPath $currentPath -Algorithm SHA256).Hash -ne $snapshotHash) {
        throw "Source changed since build snapshot: $relative. Rebuild before exporting."
    }
    $manifest += [ordered]@{path=$relative;sha256=$snapshotHash}
}
$verifiedCommit = (& git -C $sourceRoot rev-parse HEAD)
$verifiedBranch = (& git -C $sourceRoot branch --show-current)
$verifiedChanges = @(& git -C $sourceRoot status --porcelain --untracked-files=no)
if ($verifiedChanges.Count -ne 0) { throw 'Commit tracked changes before exporting a candidate with an exact Git version.' }
$out = Join-Path $sourceRoot ('output/extension_' + $Version)
New-Item -ItemType Directory -Path $out -Force | Out-Null
$bit = Join-Path $phy 'HX4S20_HDMI_Player.bit'
Copy-Item -LiteralPath $bit -Destination (Join-Path $out ('HX4S20_HDMI_Player_' + $Version + '_candidate.bit'))
foreach ($name in @('HX4S20_HDMI_Player_pr.timing','HX4S20_HDMI_Player_phy.area','route_flow.status','build_console.log')) {
    $path = Join-Path $phy $name
    if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $out }
}
$bw = Join-Path $TdHome 'bin/bw_commands_prompt.exe'
if (Test-Path -LiteralPath $bw) {
    $bin = Join-Path $buildPath 'candidate.bin'
    $tcl = Join-Path $buildPath 'candidate_bin.tcl'
    $commands = 'bit_to_bin -bit "' + $bit.Replace('\','/') + '" -bin "' + $bin.Replace('\','/') + '"' + "`nexit`n"
    [IO.File]::WriteAllText($tcl, $commands, (New-Object Text.UTF8Encoding($false)))
    'exit' | & $bw $tcl.Replace('\','/') > (Join-Path $out 'bin_conversion.log') 2>&1
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $bin)) { throw 'Candidate bin conversion failed.' }
    Copy-Item -LiteralPath $bin -Destination (Join-Path $out ('HX4S20_HDMI_Player_' + $Version + '_candidate.bin'))
}
$status = [IO.File]::ReadAllText((Join-Path $phy 'route_flow.status'))
$gitMetadata = Get-Content -LiteralPath (Join-Path $buildPath 'git_snapshot.json') -Raw | ConvertFrom-Json
$artifactHashes = [ordered]@{}
foreach ($extension in @('bit','bin')) {
    $artifact = Join-Path $out ('HX4S20_HDMI_Player_' + $Version + '_candidate.' + $extension)
    if (!(Test-Path -LiteralPath $artifact)) { throw "Missing candidate artifact: $extension" }
    $artifactHashes[$extension] = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLower()
}
$result = [ordered]@{artifact_sha256=$artifactHashes;version=$Version;build_root=$buildPath;place_seed=$gitMetadata.place_seed;git_commit=$verifiedCommit;git_branch=$verifiedBranch;build_snapshot_git_branch=$gitMetadata.git_branch;git_tracked_changes=$verifiedChanges;build_snapshot_git_commit=$gitMetadata.git_commit;build_snapshot_tracked_changes=$gitMetadata.git_tracked_changes;source_manifest=$manifest;timing_status=$status;final_timing=$finalTiming;sta_coverage_percent=$staCoverage;resources=$resources;rtl_validation_sha256=(Get-FileHash -LiteralPath $validationPath -Algorithm SHA256).Hash;hardware_verified=$false}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'build_result.json') -Encoding utf8
Write-Output "Reviewable candidate and timing reports: $out"
