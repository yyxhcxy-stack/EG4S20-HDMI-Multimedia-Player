import os
from PIL import Image, ImageDraw, ImageFont

font = ImageFont.truetype('C:/Windows/Fonts/lucon.ttf', 13)

# 0x20 to 0x5F (64 chars)
chars_str = ' !"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_'

lines = []
lines.append("// =====================================================================")
lines.append("// 8x16 Dot Matrix Font ROM (ASCII 0x20 - 0x5F, 64 characters)")
lines.append("// Auto-generated for Anlogic EG4S20 HDMI Display OSD")
lines.append("// =====================================================================")
lines.append("`timescale 1ns / 1ps")
lines.append("")
lines.append("module font_rom_8x16 (")
lines.append("    input  wire       clk,")
lines.append("    input  wire [6:0] ascii_code, // Supports 0x20-0x7E (auto converts a-z)")
lines.append("    input  wire [3:0] row,        // 0..15 scanlines")
lines.append("    output reg  [7:0] font_data   // 8 bits per scanline (MSB=left)")
lines.append(");")
lines.append("")
lines.append("    // Auto-map lowercase a-z (0x61-0x7A) to uppercase A-Z (0x41-0x5A)")
lines.append("    wire [6:0] norm_ascii = (ascii_code >= 7'h61 && ascii_code <= 7'h7A) ?")
lines.append("                            (ascii_code - 7'h20) : ascii_code;")
lines.append("    wire [5:0] char_idx   = (norm_ascii >= 7'h20 && norm_ascii <= 7'h5F) ?")
lines.append("                            (norm_ascii[5:0] - 6'h20) : 6'd0;")
lines.append("")
lines.append("    reg [7:0] rom_data;")
lines.append("    always @(*) begin")
lines.append("        case ({char_idx, row})")

count = 0
for i, ch in enumerate(chars_str):
    im = Image.new('1', (8, 16), 0)
    draw = ImageDraw.Draw(im)
    draw.text((0, 1), ch, font=font, fill=1)
    
    for y in range(16):
        b = 0
        for x in range(8):
            if im.getpixel((x, y)):
                b |= (1 << (7 - x))
        addr = (i << 4) | y
        ch_esc = ch if ch not in ['\\', '\'', '"'] else f'\\{ch}'
        lines.append(f"            10'h{addr:03X}: rom_data = 8'h{b:02X}; // '{ch_esc}' row {y}")
        count += 1

lines.append("            default: rom_data = 8'h00;")
lines.append("        endcase")
lines.append("    end")
lines.append("")
lines.append("    always @(posedge clk) begin")
lines.append("        font_data <= rom_data;")
lines.append("    end")
lines.append("")
lines.append("endmodule")
lines.append("")

output_path = "D:/fpga/src/rtl/font_rom_8x16.v"
with open(output_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

print(f"Generated {count} scanlines in {output_path}")
