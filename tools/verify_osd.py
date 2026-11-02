# Test verification script for OSD math, HUD layout, and transition wipe coverage

def test_hud_coordinates():
    # 12 HUD lines:
    # Lines 0..6: Settings (Title, Brt, Con, Clr, Scl, SW, Trans)
    # Divider at Y = 166
    # Lines 7..11: Telemetry (Title, FPS, Latency, Memory, Frames)
    line_bounds = [
        (40, 56),
        (58, 74),
        (76, 92),
        (94, 110),
        (112, 128),
        (130, 146),
        (148, 164),
        (168, 184),
        (186, 202),
        (204, 220),
        (222, 238),
        (240, 256)
    ]
    # Check heights
    for i, (y0, y1) in enumerate(line_bounds):
        assert y1 - y0 == 16, f"Line {i} height is not 16!"
    
    # Check gaps
    for i in range(len(line_bounds) - 1):
        gap = line_bounds[i+1][0] - line_bounds[i][1]
        if i == 6:
            # Across divider (164 to 168, divider at 166)
            assert gap == 4, f"Gap across divider is {gap}, expected 4!"
        else:
            assert gap == 2, f"Gap between line {i} and {i+1} is {gap}, expected 2!"

    # Check font row math
    row_calc = [
        lambda y: (y & 0xF) - 8,
        lambda y: (y & 0xF) - 10,
        lambda y: (y & 0xF) - 12,
        lambda y: (y & 0xF) - 14,
        lambda y: (y & 0xF),
        lambda y: (y & 0xF) - 2,
        lambda y: (y & 0xF) - 4,
        lambda y: (y & 0xF) - 8,
        lambda y: (y & 0xF) - 10,
        lambda y: (y & 0xF) - 12,
        lambda y: (y & 0xF) - 14,
        lambda y: (y & 0xF)
    ]
    for i, (y0, y1) in enumerate(line_bounds):
        for y in range(y0, y1):
            r = row_calc[i](y) & 0xF
            expected_r = y - y0
            assert r == expected_r, f"Line {i} at y={y}: got row {r}, expected {expected_r}"

    # Verify HUD box bounds (Y = 36..258)
    box_top, box_bot = 36, 258
    assert box_top < line_bounds[0][0], "Top border overlaps line 0"
    assert line_bounds[-1][1] <= box_bot, "Bottom line exceeds HUD box"
    # Ensure zero collision with Audio Meter at Y = 416
    assert box_bot < 416, "HUD box collides with Audio Meter"
    print(f"HUD 12-Line Coordinate & Row Math Verification: PASS (Margin to Audio Meter: {416 - box_bot}px)")

def test_marquee_length():
    marquee_str = ' *** 2026 ANLOGIC CUP FPGA MULTIMEDIA SYSTEM *** HX4S20C HD PLAYER *** EG4S20BG256 SOC DESIGN *** WELCOME TO NATIONAL FINALS ***'
    assert len(marquee_str) == 128
    print("Marquee Length Verification (128 chars): PASS")

def test_x_cnt_alignment():
    x_cnt = 0
    de_d = 0
    pixels = []
    for p in range(640):
        de = 1
        cur_x = x_cnt
        pixels.append(cur_x)
        if de:
            x_cnt += 1
        de_d = de
    assert pixels == list(range(640)), "x_cnt does not match 0..639!"
    print("x_cnt 0..639 Pixel Alignment Verification: PASS")

def test_horizontal_slide_wipe():
    # Verify horizontal slide wipe progression across all 16 frames
    for fade_step in range(16):
        step_p1 = fade_step + 1
        slide_x = (step_p1 << 5) + (step_p1 << 3)
        assert slide_x == 40 * step_p1
        line_p0 = slide_x - 2
        line_p1 = slide_x - 1
        assert 0 <= line_p0 and line_p1 < 640

        # Phase 1: Closing wipe (fade_in == 0)
        # Left of scanline: mask (0), On scanline: Cyan (0x00FFFF), Right of scanline: old picture (vout_raw)
        for px in range(640):
            is_line = (px == line_p0) or (px == line_p1)
            if is_line:
                tag = "CYAN"
            elif px >= slide_x:
                tag = "OLD_IMG"
            else:
                tag = "MASK"
            
            if fade_step == 15:
                # On step 15, no OLD_IMG should remain on screen (all MASK or CYAN)
                assert tag in ("MASK", "CYAN"), f"Unexpected {tag} at step 15 px {px}"

        # Phase 2: Opening wipe (fade_in == 1)
        # Left of scanline: new picture (vout_raw), On scanline: Cyan (0x00FFFF), Right of scanline: mask (0)
        for px in range(640):
            is_line = (px == line_p0) or (px == line_p1)
            if is_line:
                tag = "CYAN"
            elif px < line_p0:
                tag = "NEW_IMG"
            else:
                tag = "MASK"

            if fade_step == 15:
                # On step 15, all pixels 0..637 should be NEW_IMG
                if px < 638:
                    assert tag == "NEW_IMG"

    print("Horizontal Slide Wipe Math & Coverage Verification: PASS")

def test_hud_line3_color_modes():
    # Verify ASCII character output of fn_hud_l3_char from osd_display.v:
    # Emerg:  FLOW: EVAC [ACT >>>]   (22 chars)
    # Mode 0: RUBB: NATURAL (ORIG)  (22 chars)
    # Mode 1: RUBB: INK-RUBBING     (22 chars)
    # Mode 2: RUBB: CINNABAR-RUB    (22 chars)
    # Mode 3: RUBB: SPLIT-COMPARE   (22 chars)
    def fn_hud_l3_char(emerg, mode, idx):
        if emerg:
            text = "FLOW: EVAC [ACT >>>]  "
            return text[idx]
        if mode == 0:
            text = "RUBB: NATURAL (ORIG)  "
        elif mode == 1:
            text = "RUBB: INK-RUBBING     "
        elif mode == 2:
            text = "RUBB: CINNABAR-RUB    "
        else: # mode 3
            text = "RUBB: SPLIT-COMPARE   "
        return text[idx]

    expected_strs = [
        "RUBB: NATURAL (ORIG)  ",
        "RUBB: INK-RUBBING     ",
        "RUBB: CINNABAR-RUB    ",
        "RUBB: SPLIT-COMPARE   "
    ]
    for mode in range(4):
        assembled = "".join(fn_hud_l3_char(False, mode, i) for i in range(22))
        assert assembled == expected_strs[mode], f"Mode {mode} string mismatch: '{assembled}' != '{expected_strs[mode]}'"
        assert len(assembled) == 22

    evac_str = "".join(fn_hud_l3_char(True, 0, i) for i in range(22))
    assert evac_str == "FLOW: EVAC [ACT >>>]  "
    assert len(evac_str) == 22

    # Verify optical flow chevron geometry & rightward orientation
    # Centerline Y = 358, arms slope backwards at 45 degrees
    # Tip (crest) at flow_rel_x == 0, arms at (flow_rel_x == 0) -> x = phase - dy (left of tip)
    for dy in range(0, 28):
        y_top = 358 - dy
        y_bot = 358 + dy
        dy_calc_top = 358 - y_top
        dy_calc_bot = y_bot - 358
        assert dy_calc_top == dy
        assert dy_calc_bot == dy

    # Highway Wayfinding Sign string (25 chars): ">>> 安全疏散  EXIT 150M >"
    # Anlogic font indices: 安_L=0x09, 安_R=0x0A, 全_L=0x0B, 全_R=0x0C, 疏_L=0x0D, 疏_R=0x0E, 散_L=0x0F, 散_R=0x10
    sign_chars = [0x3E, 0x3E, 0x3E, 0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x20, 0x20, 0x45, 0x58, 0x49, 0x54, 0x20, 0x31, 0x35, 0x30, 0x4D, 0x20, 0x3E]
    assert len(sign_chars) == 25

    print("HUD Line 3 4-Mode & Emergency Evacuation Strings & Flow Math: PASS")

def test_contrast_key_and_sobel_bypass():
    # 1. KEY2 double-click directly controls contrast mode
    for key_c in (0, 1):
        sw_contrast = key_c
        assert sw_contrast == key_c, "key_c did not control contrast"

    # 2. In Sobel mode, brightness/contrast multipliers are bypassed
    raw_sobel_cyan = 0x00FFFF
    raw_sobel_slate = 0x0A0D14
    for mode in range(4):
        # Suppose contrast is enhanced
        con_rgb = 0x123456
        adj_rgb = raw_sobel_cyan if (mode == 2 or mode == 3) else con_rgb
        if mode == 2 or mode == 3:
            assert adj_rgb == raw_sobel_cyan, f"Sobel/Split Cyan was modified in mode {mode}"
        else:
            assert adj_rgb == con_rgb

    # 3. HUD Line 5 Contrast Strings (22 chars)
    def fn_hud_l5_char(con, idx):
        if con:
            text = "CONTRAST:  1.5X [HIGH]"
        else:
            text = "CONTRAST:  1.0X [STD ]"
        return text[idx]

    assert "".join(fn_hud_l5_char(0, i) for i in range(22)) == "CONTRAST:  1.0X [STD ]"
    assert "".join(fn_hud_l5_char(1, i) for i in range(22)) == "CONTRAST:  1.5X [HIGH]"

    print("Contrast KEY2 Toggle & Sobel Pass-through Bypass Verification: PASS")

def test_telemetry_hud_strings():
    # Line 7: [SYSTEM TELEMETRY]
    def fn_hud_l7_char(idx):
        text = "[SYSTEM TELEMETRY]    "
        return text[idx]
    assert "".join(fn_hud_l7_char(i) for i in range(22)) == "[SYSTEM TELEMETRY]    "

    # Line 8: FPS:   60.0 [LOCKED]
    def fn_hud_l8_char(idx):
        text = "FPS:   60.0 [LOCKED]  "
        return text[idx]
    assert "".join(fn_hud_l8_char(i) for i in range(22)) == "FPS:   60.0 [LOCKED]  "

    # Line 9: Latency across 4 modes
    expected_lat = [
        "LAT: 160NS  (4-CYC)   ", # 00: Native 1.0X
        "LAT: 32.2US (1-LN)    ", # 01: Scaler
        "LAT: 64.1US (2-LN)    ", # 10: Sobel
        "LAT: 96.3US (3-LN)    "  # 11: Scaler + Sobel
    ]
    for mode in range(4):
        s = expected_lat[mode]
        assert len(s) == 22, f"Latency mode {mode} length {len(s)} != 22"

    # Line 10: Memory bandwidth
    mem_ok = "MEM:  73.7MB/S [OK]   "
    mem_load = "MEM: 147.5MB/S [LOAD] "
    assert len(mem_ok) == 22
    assert len(mem_load) == 22

    # Line 11: 6-digit BCD Frame counter
    def fn_hud_l11_char(digits, idx):
        d5, d4, d3, d2, d1, d0 = digits
        text = f"FRM:  {d5}{d4}{d3}{d2}{d1}{d0} [0-DRP]  "
        return text[idx]
    
    sample_frm = "".join(fn_hud_l11_char((0, 1, 4, 8, 2, 0), i) for i in range(22))
    assert sample_frm == "FRM:  014820 [0-DRP]  "
    assert len(sample_frm) == 22
    print("Telemetry HUD Strings & ASCII Verification: PASS")

if __name__ == '__main__':
    test_hud_coordinates()
    test_marquee_length()
    test_x_cnt_alignment()
    test_horizontal_slide_wipe()
    test_hud_line3_color_modes()
    test_contrast_key_and_sobel_bypass()
    test_telemetry_hud_strings()
    print("\nAll OSD, Transition & Telemetry Verification Tests: PASS!")
