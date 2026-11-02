# Patch src/rtl/font_rom_8x16.v to make rom_data and cjk_rom_data clocked registers, inferring BRAM
with open("src/rtl/font_rom_8x16.v", "r", encoding="utf-8") as f:
    content = f.read()

# Replace always @(*) with always @(posedge clk) for both ROMs
p1 = "    reg [7:0] rom_data;\n    always @(*) begin"
r1 = "    reg [7:0] rom_data;\n    always @(posedge clk) begin"
assert p1 in content, "p1 not found"
content = content.replace(p1, r1)

p2 = "    reg [7:0] cjk_rom_data;\n    always @(*) begin"
r2 = "    reg [7:0] cjk_rom_data;\n    always @(posedge clk) begin"
assert p2 in content, "p2 not found"
content = content.replace(p2, r2)

p3 = """    always @(posedge clk) begin
        font_data <= is_cjk ? cjk_rom_data : rom_data;
    end"""

r3 = """    reg is_cjk_d;
    always @(posedge clk) begin
        is_cjk_d <= is_cjk;
    end
    always @(*) begin
        font_data = is_cjk_d ? cjk_rom_data : rom_data;
    end"""
assert p3 in content, "p3 not found"
content = content.replace(p3, r3)

with open("src/rtl/font_rom_8x16.v", "w", encoding="utf-8") as f:
    f.write(content)

print("Successfully patched src/rtl/font_rom_8x16.v to clocked BRAM inference!")
