import math
from PIL import Image

# Import the font definition from build_lcd_font
from build_lcd_font import FONT_8X8, CHARS_ORDER

def get_char_idx(ch):
    if 'a' <= ch <= 'z':
        ch = ch.upper()
    if 'A' <= ch <= 'Z':
        return 16 + (ord(ch) - ord('A'))
    if '0' <= ch <= '9':
        return 6 + (ord(ch) - ord('0'))
    mapping = {' ': 0, '#': 1, '%': 2, '-': 3, '.': 4, '/': 5, ':': 42}
    return mapping.get(ch, 0)

def get_font_byte(char_idx, row):
    ch = CHARS_ORDER[char_idx]
    return FONT_8X8[ch][row]

def get_line_char(line_id, col, cur_img_idx=1, scale_mode=3, vol_mode=0, emergency_mode=False):
    # line 0: "ANLOGIC TELEM"
    # line 1: "IMG:#%d/4 60HZ"
    # line 2: "SCL:AUTO DDA "
    # line 3: "AUD:CHIME 48K"
    # line 4: "LAT:16.6MS OK"
    # line 5: "HX4S20 DUAL-DSP"
    if line_id == 0:
        s = "ANLOGIC TELEM"
    elif line_id == 1:
        s = f"IMG:#{cur_img_idx+1}/4 60HZ"
    elif line_id == 2:
        scl_str = ["1.0X", "2.0X", "0.5X", "AUTO"][scale_mode]
        s = f"SCL:{scl_str} DDA "
    elif line_id == 3:
        aud_str = "EMERG" if emergency_mode else ("MUTE " if vol_mode == 4 else "CHIME")
        s = f"AUD:{aud_str} 48K"
    elif line_id == 4:
        s = "LAT:16.6MS OK"
    elif line_id == 5:
        s = "HX4S20 DUAL-DSP"
    else:
        s = " " * 16
    
    if col < len(s):
        return s[col]
    return " "

def rgb565_to_rgb888(rgb565):
    r = ((rgb565 >> 11) & 0x1F) * 255 // 31
    g = ((rgb565 >> 5) & 0x3F) * 255 // 63
    b = (rgb565 & 0x1F) * 255 // 31
    return (r, g, b)

def render_frame(cur_img_idx=1, scale_mode=3, vol_mode=0, emergency_mode=False, hb_1hz=True):
    # Synthesize bronze chime acoustic oscillation waveform (fundamental 440Hz + decay)
    osc_buf = []
    for x in range(128):
        # 128 samples: 440Hz bronze chime with bell harmonics
        t = x / 128.0
        wave = 0.65 * math.sin(2 * math.pi * 2.5 * t) + 0.25 * math.sin(2 * math.pi * 5.0 * t)
        val = int(wave * 90) # signed 8-bit (-128..127)
        val = max(-128, min(127, val))
        osc_buf.append(val)

    # 8-band spectrum levels (0..6)
    band_disp = [4, 6, 5, 3, 2, 3, 1, 1]

    img = Image.new('RGB', (128, 128))
    pixels = img.load()

    for py in range(128):
        for px in range(128):
            color565 = 0x0000

            # 1. Top Bar (py <= 16)
            if py <= 16:
                if py == 16:
                    color565 = 0x03BF # Cyan separator line
                elif 115 <= px <= 121 and 5 <= py <= 11:
                    dx = abs(px - 118)
                    dy = abs(py - 8)
                    if dx + dy <= 4:
                        if hb_1hz:
                            if dx <= 1 and dy <= 1:
                                color565 = 0xFFFF # White core
                            elif dx + dy <= 3:
                                color565 = 0x07E0 # Bright green
                            else:
                                color565 = 0x04A0
                        else:
                            color565 = 0x01A0 # Dim green
                    else:
                        color565 = 0x08C6 # Deep tech blue #0A192F
                elif 4 <= py <= 11 and 6 <= px <= 109:
                    char_col = (px - 6) >> 3
                    char_row = py - 4
                    char_bit = 7 - ((px - 6) & 0x07)
                    ch = get_line_char(0, char_col)
                    f_byte = get_font_byte(get_char_idx(ch), char_row)
                    if (f_byte >> char_bit) & 1:
                        color565 = 0x07FF # Cyan text
                    else:
                        color565 = 0x08C6 # Deep tech blue #0A192F
                else:
                    color565 = 0x08C6 # Deep tech blue #0A192F

            # 2. Telemetry Zone (17 <= py <= 55)
            elif 17 <= py <= 55:
                if py == 55:
                    color565 = 0x11E8 # Slate cyan line
                elif 6 <= px <= 109:
                    char_col = (px - 6) >> 3
                    char_bit = 7 - ((px - 6) & 0x07)
                    if 18 <= py <= 25:
                        char_row = py - 18
                        ch = get_line_char(1, char_col, cur_img_idx, scale_mode, vol_mode, emergency_mode)
                        f_byte = get_font_byte(get_char_idx(ch), char_row)
                        color565 = 0xFFE0 if ((f_byte >> char_bit) & 1) else 0x0000 # Yellow
                    elif 27 <= py <= 34:
                        char_row = py - 27
                        ch = get_line_char(2, char_col, cur_img_idx, scale_mode, vol_mode, emergency_mode)
                        f_byte = get_font_byte(get_char_idx(ch), char_row)
                        color565 = 0x07FF if ((f_byte >> char_bit) & 1) else 0x0000 # Cyan
                    elif 36 <= py <= 43:
                        char_row = py - 36
                        ch = get_line_char(3, char_col, cur_img_idx, scale_mode, vol_mode, emergency_mode)
                        f_byte = get_font_byte(get_char_idx(ch), char_row)
                        txt_col = 0xF800 if emergency_mode else 0xFDA0
                        color565 = txt_col if ((f_byte >> char_bit) & 1) else 0x0000 # Orange / Red
                    elif 45 <= py <= 52:
                        char_row = py - 45
                        ch = get_line_char(4, char_col, cur_img_idx, scale_mode, vol_mode, emergency_mode)
                        f_byte = get_font_byte(get_char_idx(ch), char_row)
                        color565 = 0x57E0 if ((f_byte >> char_bit) & 1) else 0x0000 # Lime green
                    else:
                        color565 = 0x0000
                else:
                    color565 = 0x0000

            # 3. Dynamic Oscilloscope Zone (56 <= py <= 112)
            elif 56 <= py <= 112:
                # Oscilloscope waveform mapping
                s = osc_buf[px]
                s_scaled = s >> 2 # divide by 4
                s_clamped = max(-22, min(22, s_scaled))
                wave_y = 84 - s_clamped

                # Spectrum bar check at bottom
                is_spectrum = False
                if 105 <= py <= 111:
                    band_id = px >> 4 # 0..7
                    bar_in_band = px & 0x0F
                    if 2 <= bar_in_band <= 13:
                        bar_h = band_disp[band_id]
                        if py >= (111 - bar_h):
                            is_spectrum = True
                            if py == (111 - bar_h):
                                color565 = 0xFFFF # Peak cap
                            elif py <= 107:
                                color565 = 0xFD20 # Orange
                            else:
                                color565 = 0x07E0 # Green

                if is_spectrum:
                    pass
                elif py == wave_y or py == wave_y + 1:
                    color565 = 0x07E0 # Core neon green
                elif py == wave_y - 1 or py == wave_y + 2:
                    color565 = 0x0460 # Phosphor halo
                else:
                    # Grids
                    if py == 84 and (px % 2 == 0):
                        color565 = 0x12E5 # Center dotted cyan
                    elif (py == 70 or py == 98) and (px % 8 == 0):
                        color565 = 0x0923 # Sub-grid tick
                    elif (px % 16 == 0) and (py % 8 == 0):
                        color565 = 0x0923 # Vertical tick
                    else:
                        color565 = 0x0000

            # 4. Footer Bar (113 <= py <= 127)
            else:
                if py == 113:
                    color565 = 0xCE40 # Gold separator line
                elif 116 <= py <= 123 and 4 <= px <= 123:
                    char_col = (px - 4) >> 3
                    char_row = py - 116
                    char_bit = 7 - ((px - 4) & 0x07)
                    ch = get_line_char(5, char_col)
                    f_byte = get_font_byte(get_char_idx(ch), char_row)
                    if (f_byte >> char_bit) & 1:
                        color565 = 0xFEA0 # Brilliant gold
                    else:
                        color565 = 0x08C6
                else:
                    color565 = 0x08C6

            pixels[px, py] = rgb565_to_rgb888(color565)

    return img

img = render_frame()
img.save("tools/sim_lcd_preview.png")
# Scale up 4x for easier inspection
img_scaled = img.resize((512, 512), Image.NEAREST)
img_scaled.save("tools/sim_lcd_preview_4x.png")
print("Rendered tools/sim_lcd_preview.png (128x128) and tools/sim_lcd_preview_4x.png (512x512) successfully.")
