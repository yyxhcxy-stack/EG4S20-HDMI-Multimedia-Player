import re

file_path = 'src/rtl/osd_display.v'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update fn_logo_pixel
old_fn = """    // -------------------------------------------------------------
    // 8. Anlogic Logo 16x16 ROM
    // -------------------------------------------------------------
    function fn_logo_pixel;
        input [3:0] y;
        input [3:0] x;
        reg [15:0] row;
        begin
            case (y)
                4'd0:  row = 16'b0000000000000000;
                4'd1:  row = 16'b0011000000110000;
                4'd2:  row = 16'b0011100000111000;
                4'd3:  row = 16'b0001110000011100;
                4'd4:  row = 16'b0001110000011100;
                4'd5:  row = 16'b0000111000001110;
                4'd6:  row = 16'b0000111000001110;
                4'd7:  row = 16'b0000011100000111;
                4'd8:  row = 16'b0000011100000111;
                4'd9:  row = 16'b0000001110000011;
                4'd10: row = 16'b0000001110000011;
                4'd11: row = 16'b0000000111000001;
                4'd12: row = 16'b0000000111000001;
                4'd13: row = 16'b0000000011000000;
                4'd14: row = 16'b0000000000000000;
                default: row = 16'b0000000000000000;
            endcase
            fn_logo_pixel = row[4'd15 - x];
        end
    endfunction"""

new_fn = """    // -------------------------------------------------------------
    // 8. Anlogic Dual-Color Corporate Logo 16x16 ROM (Official Anlogic Identity)
    //    2'b00: Transparent / Glass Background
    //    2'b01: Corporate Tech Navy Blue ('A' glyph)
    //    2'b10: Anlogic Crimson Red (8 horizontal stripes)
    // -------------------------------------------------------------
    function [1:0] fn_logo_pixel;
        input [3:0] y;
        input [3:0] x;
        reg [15:0] row_b;
        reg [15:0] row_r;
        begin
            case (y)
                4'd0:  begin row_b = 16'b0000_0000_0000_0000; row_r = 16'b0000_0011_1111_1111; end // ......RRRRRRRRRR (Stripe 0)
                4'd1:  begin row_b = 16'b0000_1100_0000_0000; row_r = 16'b0000_0000_0000_0000; end // ....BB.......... (Apex of 'A')
                4'd2:  begin row_b = 16'b0000_1100_0000_0000; row_r = 16'b0000_0001_1111_1110; end // ....BB.RRRRRRRR. (Stripe 1)
                4'd3:  begin row_b = 16'b0001_1100_0000_0000; row_r = 16'b0000_0000_0000_0000; end // ...BBB.......... ('A')
                4'd4:  begin row_b = 16'b0001_1100_0000_0000; row_r = 16'b0000_0000_1111_1110; end // ...BBB..RRRRRRR. (Stripe 2)
                4'd5:  begin row_b = 16'b0001_1110_0000_0000; row_r = 16'b0000_0000_0000_0000; end // ...BBBB......... ('A')
                4'd6:  begin row_b = 16'b0001_1110_0000_0000; row_r = 16'b0000_0000_1111_1100; end // ...BBBB.RRRRRR.. (Stripe 3)
                4'd7:  begin row_b = 16'b0011_1110_0000_0000; row_r = 16'b0000_0000_0000_0000; end // ..BBBBB......... ('A')
                4'd8:  begin row_b = 16'b0011_0110_0000_0000; row_r = 16'b0000_0000_0111_1100; end // ..BB.BB..RRRRR.. (Stripe 4 + Cutout)
                4'd9:  begin row_b = 16'b0011_0011_0000_0000; row_r = 16'b0000_0000_0000_0000; end // ..BB..BB........ ('A' Cutout)
                4'd10: begin row_b = 16'b0110_0011_0000_0000; row_r = 16'b0000_0000_0111_1000; end // .BB...BB.RRRR... (Stripe 5 + Cutout)
                4'd11: begin row_b = 16'b0110_0011_0000_0000; row_r = 16'b0000_0000_0000_0000; end // .BB...BB........ ('A' Cutout)
                4'd12: begin row_b = 16'b0110_0001_1000_0000; row_r = 16'b0000_0000_0011_1000; end // .BB....BB.RRR... (Stripe 6 + Cutout)
                4'd13: begin row_b = 16'b1100_0001_1000_0000; row_r = 16'b0000_0000_0000_0000; end // BB.....BB....... ('A' Cutout)
                4'd14: begin row_b = 16'b1111_1100_1100_0000; row_r = 16'b0000_0000_0001_1000; end // BBBBBB..BB.RR... (Stripe 7 + 'A' Base)
                4'd15: begin row_b = 16'b1111_1100_1100_0000; row_r = 16'b0000_0000_0000_0000; end // BBBBBB..BB...... ('A' Base)
                default: begin row_b = 16'h0000; row_r = 16'h0000; end
            endcase
            fn_logo_pixel = row_b[4'd15 - x] ? 2'b01 :
                            row_r[4'd15 - x] ? 2'b10 : 2'b00;
        end
    endfunction"""

assert old_fn in content, "old_fn not found in content!"
content = content.replace(old_fn, new_fn)

# 2. Update reg logo_pix_p1 declaration
old_decl = "    reg        logo_pix_p1;"
new_decl = "    reg [1:0]  logo_pix_p1;"
assert old_decl in content, "old_decl not found!"
content = content.replace(old_decl, new_decl)

# 3. Update reset assignment
old_rst = "            logo_pix_p1   <= 1'b0;"
new_rst = "            logo_pix_p1   <= 2'b00;"
assert old_rst in content, "old_rst not found!"
content = content.replace(old_rst, new_rst)

# 4. Update output stage mux
old_mux = """            end else if (is_logo_p1 && logo_pix_p1) begin
                rgb_out <= 24'hEE1818; // Anlogic Red Logo"""

new_mux = """            end else if (is_logo_p1 && (logo_pix_p1 != 2'b00)) begin
                rgb_out <= (logo_pix_p1 == 2'b01) ? 24'h204888 : 24'hEE1818; // Dual-Color Anlogic Logo: Navy Blue 'A' + Crimson Red Stripes"""

assert old_mux in content, "old_mux not found!"
content = content.replace(old_mux, new_mux)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Successfully updated src/rtl/osd_display.v!")
