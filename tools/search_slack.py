with open('build_ext_20261024_123223/prj/HX4S20_HDMI_Player_Runs/phy_1/final_timing.rpt', 'r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if 'Slack' in line or 'slack' in line:
        print(f"Line {i}: {line.strip()}")
        for j in range(max(0, i-2), min(len(lines), i+25)):
            print(f"  {lines[j]}", end='')
        break
