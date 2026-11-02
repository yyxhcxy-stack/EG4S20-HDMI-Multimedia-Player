# Generate src/rtl/font_rom_8x8.v
from build_lcd_font import FONT_8X8, CHARS_ORDER

lines = []
lines.append("// ============================================================================")
lines.append("// 8x8 Dot Matrix Font ROM (43 glyphs, 344 entries)")
lines.append("// Dedicated clocked ROM for ST7735S telemetry LCD")
lines.append("// ============================================================================")
lines.append("`timescale 1ns / 1ps")
lines.append("")
lines.append("module font_rom_8x8 (")
lines.append("    input  wire       clk,")
lines.append("    input  wire [5:0] char_idx, // 0..42")
lines.append("    input  wire [2:0] row,      // 0..7")
lines.append("    output reg  [7:0] font_data // MSB = leftmost pixel")
lines.append(");")
lines.append("")
lines.append("    wire [8:0] addr = {char_idx, row};")
lines.append("")
lines.append("    always @(posedge clk) begin")
lines.append("        case (addr)")

for idx, ch in enumerate(CHARS_ORDER):
    rows = FONT_8X8[ch]
    for r, val in enumerate(rows):
        addr = (idx << 3) | r
        ch_esc = ch if ch not in ['\\', "'", '"'] else f"\\{ch}"
        lines.append(f"            9'd{addr:3d}: font_data <= 8'h{val:02X}; // '{ch_esc}' row {r}")

lines.append("            default: font_data <= 8'h00;")
lines.append("        endcase")
lines.append("    end")
lines.append("")
lines.append("endmodule")
lines.append("")

with open("src/rtl/font_rom_8x8.v", "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

print("Successfully generated src/rtl/font_rom_8x8.v!")
