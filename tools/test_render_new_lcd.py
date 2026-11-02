import os
import math
from PIL import Image

def get_char_idx(ch):
    if 'a' <= ch <= 'z':
        ch = ch.upper()
    if 'A' <= ch <= 'Z':
        return 16 + (ord(ch) - ord('A'))
    if '0' <= ch <= '9':
        return 6 + (ord(ch) - ord('0'))
    mapping = {' ': 0, '#': 1, '%': 2, '-': 3, '.': 4, '/': 5, ':': 42}
    return mapping.get(ch, 0)

# Load font ROM from font_rom_8x8.v
font_rom = [0] * 512
with open("src/rtl/font_rom_8x8.v", "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line.startswith("glyph_rom[") and "8'h" in line:
            idx_part = line.split("]")[0].split("[")[1].strip()
            val_part = line.split("8'h")[1].split(";")[0].strip()
            font_rom[int(idx_part)] = int(val_part, 16)

def get_font_byte(char_idx, row):
    return font_rom[(char_idx << 3) | row]

def render_preview(filename="sim_lcd_1_8inch_preview.png"):
    width, height = 128, 160
    img = Image.new("RGB", (width, height), (0, 0, 0))
    pixels = img.load()

    # Telemetry state
    cur_img_idx = 0 # PIC #1/4
    scale_mode = 0  # 1.0X
    vol_mode = 0    # 100%
    emergency_mode = False
    trans_mode = 3  # AUTO
    active_trans = 3 # MOSAIC
    color_mode = 2  # INK-RUBB

    # Waveform mock
    osc_buf = [int(10 * math.sin(2 * math.pi * x / 32)) for x in range(128)]

    # SDFT mock
    sdft_h = [12, 16, 20, 24, 18, 14, 10, 6]
    sdft_p = [15, 18, 22, 25, 20, 16, 12, 8]

    for y in range(height):
        for x in range(width):
            # 1. Dividers
            if y in [13, 56, 90, 114, 126, 139]:
                pixels[x, y] = (0x21, 0x24, 0x29)
                continue

            # 2. Status LED (X: 117..119, Y: 6..8)
            if 117 <= x <= 119 and 6 <= y <= 8:
                pixels[x, y] = (0x00, 0xFF, 0x7F) # Emerald breathing dot
                continue

            # 3. Text Lines
            is_text = False
            char_ch = " "
            fg_color = (255, 255, 255)

            txt_dx = x - 4
            txt_col = txt_dx >> 3
            txt_bit = 7 - (txt_dx & 7)

            if 3 <= y <= 10 and 4 <= x <= 107: # Line 0: ANLOGIC TELEM
                is_text = True
                s = "ANLOGIC TELEM"
                char_ch = s[txt_col] if txt_col < len(s) else " "
                fg_color = (0, 220, 255) # Cyan
                req_row = (y - 3) & 7
            elif 16 <= y <= 23 and x >= 4: # Line 1: PIC   #1/4 60FPS
                is_text = True
                s = f"PIC   #{cur_img_idx+1}/4 60FPS"
                char_ch = s[txt_col] if txt_col < len(s) else " "
                fg_color = (180, 190, 200) if txt_col <= 2 else ((255, 255, 255) if 6 <= txt_col <= 9 else (140, 180, 220))
                req_row = y & 7
            elif 26 <= y <= 33 and x >= 4: # Line 2: SCL   1.0X DDA2D
                is_text = True
                s = "SCL   1.0X DDA2D"
                char_ch = s[txt_col] if txt_col < len(s) else " "
                fg_color = (180, 190, 200) if txt_col <= 2 else ((255, 255, 255) if 6 <= txt_col <= 9 else (140, 180, 220))
                req_row = (y - 26) & 7
            elif 36 <= y <= 43 and x >= 4: # Line 3: DFT   DFT  48K
                is_text = True
                s = "DFT   DFT  48K "
                char_ch = s[txt_col] if txt_col < len(s) else " "
                fg_color = (180, 190, 200) if txt_col <= 2 else ((255, 255, 255) if 6 <= txt_col <= 10 else (140, 180, 220))
                req_row = (y - 36) & 7
            elif 46 <= y <= 53 and x >= 4: # Line 4: SYS   16.6M OK
                is_text = True
                s = "SYS   16.6M OK  "
                char_ch = s[txt_col] if txt_col < len(s) else " "
                fg_color = (180, 190, 200) if txt_col <= 2 else ((255, 255, 255) if 6 <= txt_col <= 10 else (0, 255, 128))
                req_row = (y - 46) & 7
            elif 117 <= y <= 124 and 4 <= x <= 123: # Line 5: TRN   MOSC AUT
                is_text = True
                tname = ["FADE", "BLND", "WIPE", "MOSC"][active_trans]
                tmode = "AUT" if trans_mode == 3 else "MAN"
                s = f"TRN   {tname} {tmode}"
                char_ch = s[txt_col] if txt_col < len(s) else " "
                fg_color = (180, 190, 200) if txt_col <= 2 else ((0, 220, 255) if 6 <= txt_col <= 9 else (255, 255, 255))
                req_row = (y - 117) & 7
            elif 129 <= y <= 136 and 4 <= x <= 123: # Line 6: FLT   INK-RUBB
                is_text = True
                cname = ["VIVID RGB", "MONOCHR  ", "INK-RUBB ", "SPLIT-CMP"][color_mode]
                s = f"FLT   {cname}"
                char_ch = s[txt_col] if txt_col < len(s) else " "
                fg_color = (180, 190, 200) if txt_col <= 2 else ((255, 220, 0) if color_mode == 2 else (0, 255, 128))
                req_row = (y - 129) & 7
            elif 142 <= y <= 149 and 4 <= x <= 123: # Line 7: DFT16 DUAL-DSP
                is_text = True
                s = "DFT16 DUAL-DSP"
                char_ch = s[txt_col] if txt_col < len(s) else " "
                fg_color = (0, 220, 255) if txt_col <= 4 else (160, 170, 200)
                req_row = (y - 142) & 7

            if is_text:
                cidx = get_char_idx(char_ch)
                font_byte = get_font_byte(cidx, req_row)
                if (font_byte >> txt_bit) & 1:
                    pixels[x, y] = fg_color
                    continue

            # 4. Waveform (Y: 60..87, center 73)
            if 60 <= y <= 87:
                wave_y = 73 - osc_buf[x]
                dy = abs(y - wave_y)
                if dy == 0:
                    pixels[x, y] = (0, 255, 255) # Razor-sharp cyan beam
                elif dy == 1:
                    pixels[x, y] = (0, 60, 100) # Soft glow edge
                elif y == 73 and (x & 7) == 0:
                    pixels[x, y] = (30, 40, 50) # Subtle zero-axis ticks
                continue

            # 5. Equalizer (Y: 94..111)
            if 94 <= y <= 111:
                band_idx = x >> 4 # 8 bands
                bar_x = x & 15
                if 2 <= bar_x <= 13: # 12px width, 4px spacing
                    h = sdft_h[band_idx]
                    p = sdft_p[band_idx]
                    bar_top = 111 - h
                    peak_top = 111 - p
                    if y == peak_top and p > 0:
                        pixels[x, y] = (255, 255, 255) # Floating white cap
                    elif y >= bar_top and h > 0:
                        if y <= 98:
                            pixels[x, y] = (255, 50, 50) # Red
                        elif y <= 104:
                            pixels[x, y] = (255, 220, 0) # Amber
                        else:
                            pixels[x, y] = (0, 220, 255) # Cyan
                    elif y == 111:
                        pixels[x, y] = (40, 50, 60)
                continue

    img.save(filename)
    img_4x = img.resize((width * 4, height * 4), Image.NEAREST)
    img_4x.save(filename.replace(".png", "_4x.png"))
    print(f"Rendered: {filename} and {filename.replace('.png', '_4x.png')}")

if __name__ == "__main__":
    render_preview()
