param([string]$BitPath = "D:/FPGA/HX4S20_v2.6.2_d5faf4c_handoff/project/build_ext_20261011_004303/prj/HX4S20_HDMI_Player_Runs/phy_1/HX4S20_HDMI_Player.bit")

$ErrorActionPreference = "Stop"
$tcl = "D:/FPGA/HX4S20_v2.6.2_d5faf4c_handoff/project/download_direct.tcl"
$tclContent = @"
list_cable
download -bit "$BitPath" -mode jtag
exit
"@

Set-Content -LiteralPath $tcl -Value $tclContent -Encoding Ascii
Write-Host "Running bw_commands_prompt.exe on $BitPath..."
& "D:/TD/bin/bw_commands_prompt.exe" $tcl
Write-Host "Done downloading to SRAM!"
