# Test fn_top_mode_char logic
def fn_top_mode_char(state_code, fail_mode, auto_mode, idx):
    if fail_mode:
        s = "[FAIL  ]"
    elif state_code == 2:
        s = "[2:SEEK]"
    elif state_code == 3:
        s = "[3:RAM_W]"
    elif state_code == 1 and not auto_mode:
        s = "[1:IDLE]"
    elif auto_mode:
        s = "[4:AUTO]"
    else:
        s = "[4:MANU]"
    return s[idx]

states = [
    (1, False, False, "State 1 Idle Manual"),
    (2, False, False, "State 2 Seek Manual"),
    (3, False, False, "State 3 Write RAM"),
    (4, False, False, "State 4 OSD Manual"),
    (4, False, True,  "State 4 OSD Auto"),
    (1, True,  False, "Fail Mode"),
]

for st, fail, auto, desc in states:
    text = "".join([fn_top_mode_char(st, fail, auto, i) for i in range(8)])
    print(f"{desc:<25}: '{text}' (len={len(text)})")
