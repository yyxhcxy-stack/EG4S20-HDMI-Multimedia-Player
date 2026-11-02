with open('build_ext_20261024_123223/prj/HX4S20_HDMI_Player_Runs/phy_1/final_timing.rpt', 'r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if 'Check Type          : setup' in line:
        # Check the slack above it
        slack_line = lines[i-3]
        if '-' in slack_line:
            print(f"Setup violation at line {i}: {slack_line.strip()}")
            for j in range(max(0, i-4), min(len(lines), i+25)):
                print(f"  {lines[j]}", end='')
            print('\n' + '='*50)
