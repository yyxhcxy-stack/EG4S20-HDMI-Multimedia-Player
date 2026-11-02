with open('build_ext_20261024_123223/prj/HX4S20_HDMI_Player_Runs/phy_1/final_timing.rpt', 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

# Find the section starting with "Path 1" or where slack is negative
idx = text.find('Slack: -0.019')
if idx == -1:
    idx = text.find('-0.019ns')
if idx != -1:
    print(text[max(0, idx-200):idx+1200])
else:
    print("Not found directly, searching for 'Slack:'")
    import re
    for m in re.finditer(r'Slack:\s*-', text):
        print('=== NEGATIVE SLACK ===')
        print(text[m.start()-100:m.start()+1000])
