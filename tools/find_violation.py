with open('build_ext_20261024_123223/prj/HX4S20_HDMI_Player_Runs/phy_1/final_timing.rpt', 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

import re
matches = [m.start() for m in re.finditer(r'clk2', text)]
print('Matches for clk2:', len(matches))
for idx in matches[:5]:
    print('==============================')
    print(text[max(0, idx-50):idx+500])
