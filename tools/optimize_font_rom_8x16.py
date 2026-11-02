import re

with open("src/rtl/font_rom_8x16.v", "r", encoding="utf-8") as f:
    text = f.read()

# Match ascii entries: 10'h000: rom_data = 8'h00; // ' ' row 0
ascii_pattern = re.compile(r"(10'h[0-9A-Fa-f]{3}):\s*rom_data\s*=\s*(8'h[0-9A-Fa-f]{2});(.*)")
ascii_entries = []
for line in text.splitlines():
    m = ascii_pattern.search(line)
    if m:
        addr_hex = m.group(1).split("h")[1]
        addr_int = int(addr_hex, 16)
        val = m.group(2)
        comment = m.group(3)
        ascii_entries.append((addr_int, val, comment))

print("Ascii entries matched:", len(ascii_entries))

# Match cjk entries: 9'h010: cjk_rom_data = 8'h04;
cjk_pattern = re.compile(r"(9'h[0-9A-Fa-f]{3}):\s*cjk_rom_data\s*=\s*(8'h[0-9A-Fa-f]{2});(.*)")
cjk_entries = []
for line in text.splitlines():
    m = cjk_pattern.search(line)
    if m:
        addr_hex = m.group(1).split("h")[1]
        raw_val = int(addr_hex, 16)
        # raw_val was {ascii_code[4:0], row[3:0]}
        # where ascii_code was 1..16
        code = (raw_val >> 4) & 0x1F
        row = raw_val & 0xF
        cjk_idx = code - 1
        addr_int = 1024 + cjk_idx * 16 + row
        val = m.group(2)
        comment = m.group(3)
        cjk_entries.append((addr_int, val, comment))

print("Cjk entries matched:", len(cjk_entries))

# Build unified module
out_lines = [
    "// =====================================================================",
    "// 8x16 Dot Matrix Font ROM (ASCII 64 + CJK 16 glyphs = 1280 entries)",
    "// Unified Single-Clocked BRAM Inference (0 LUTs, 2 BRAM9K)",
    "// =====================================================================",
    "`timescale 1ns / 1ps",
    "",
    "module font_rom_8x16 (",
    "    input  wire       clk,",
    "    input  wire [6:0] ascii_code, // Supports 0x01-0x10 (CJK) & 0x20-0x7E (ASCII)",
    "    input  wire [3:0] row,        // 0..15 scanlines",
    "    output reg  [7:0] font_data   // 8 bits per scanline (MSB=left)",
    ");",
    "",
    "    // Normalize lowercase to uppercase",
    "    wire [6:0] norm_ascii = (ascii_code >= 7'h61 && ascii_code <= 7'h7A) ?",
    "                            (ascii_code - 7'h20) : ascii_code;",
    "",
    "    // Unified 7-bit character index (0..63 for ASCII, 64..79 for CJK)",
    "    wire [6:0] char_idx = (ascii_code >= 7'h01 && ascii_code <= 7'h10) ?",
    "                          (7'd64 + (ascii_code[4:0] - 5'd1)) :",
    "                          ((norm_ascii >= 7'h20 && norm_ascii <= 7'h5F) ?",
    "                           (norm_ascii - 7'h20) : 7'd0);",
    "",
    "    wire [10:0] addr = {char_idx, row};",
    "",
    "    always @(posedge clk) begin",
    "        case (addr)"
]

# Write ASCII entries
for addr_int, val, comment in ascii_entries:
    out_lines.append(f"            11'd{addr_int:4d}: font_data <= {val};{comment}")

# Write CJK entries
for addr_int, val, comment in cjk_entries:
    out_lines.append(f"            11'd{addr_int:4d}: font_data <= {val};{comment}")

out_lines.extend([
    "            default: font_data <= 8'h00;",
    "        endcase",
    "    end",
    "",
    "endmodule",
    ""
])

with open("src/rtl/font_rom_8x16.v", "w", encoding="utf-8") as f:
    f.write("\n".join(out_lines))

print("Successfully generated unified src/rtl/font_rom_8x16.v!")
