file_path = 'src/rtl/osd_display.v'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace fn_logo_pixel with fn_logo_is_blue and fn_logo_is_red
old_fn_block = """    // -------------------------------------------------------------
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

new_fn_block = """    // -------------------------------------------------------------
    // 8. Anlogic Dual-Color Corporate Logo 16x16 ROM (Official Anlogic Identity)
    //    Split into 1-bit boolean maps to minimize LUT/MSlice logic complexity
    // -------------------------------------------------------------
    function fn_logo_is_red;
        input [3:0] y;
        input [3:0] x;
        reg [15:0] row;
        begin
            if (y[0]) begin
                fn_logo_is_red = 1'b0; // Red stripes only exist on even rows
            end else begin
                case (y[3:1])
                    3'd0: row = 16'b0000_0011_1111_1111; // Row 0
                    3'd1: row = 16'b0000_0001_1111_1110; // Row 2
                    3'd2: row = 16'b0000_0000_1111_1110; // Row 4
                    3'd3: row = 16'b0000_0000_1111_1100; // Row 6
                    3'd4: row = 16'b0000_0000_0111_1100; // Row 8
                    3'd5: row = 16'b0000_0000_0111_1000; // Row 10
                    3'd6: row = 16'b0000_0000_0011_1000; // Row 12
                    3'd7: row = 16'b0000_0000_0001_1000; // Row 14
                endcase
                fn_logo_is_red = row[4'd15 - x];
            end
        end
    endfunction

    function fn_logo_is_blue;
        input [3:0] y;
        input [3:0] x;
        reg [15:0] row;
        begin
            case (y)
                4'd0:        row = 16'b0000_0000_0000_0000;
                4'd1, 4'd2:  row = 16'b0000_1100_0000_0000;
                4'd3, 4'd4:  row = 16'b0001_1100_0000_0000;
                4'd5, 4'd6:  row = 16'b0001_1110_0000_0000;
                4'd7:        row = 16'b0011_1110_0000_0000;
                4'd8:        row = 16'b0011_0110_0000_0000;
                4'd9:        row = 16'b0011_0011_0000_0000;
                4'd10, 4'd11: row = 16'b0110_0011_0000_0000;
                4'd12:       row = 16'b0110_0001_1000_0000;
                4'd13:       row = 16'b1100_0001_1000_0000;
                4'd14, 4'd15: row = 16'b1111_1100_1100_0000;
                default:     row = 16'h0000;
            endcase
            fn_logo_is_blue = row[4'd15 - x];
        end
    endfunction"""

assert old_fn_block in content, "old_fn_block not found!"
content = content.replace(old_fn_block, new_fn_block)

# Replace register declaration:
old_decl = """    reg        is_logo_p1;
    reg [1:0]  logo_pix_p1;"""
new_decl = """    reg        logo_blue_p1;
    reg        logo_red_p1;"""
assert old_decl in content, "old_decl not found!"
content = content.replace(old_decl, new_decl)

# Replace reset block:
old_rst = """            is_logo_p1    <= 1'b0;
            logo_pix_p1   <= 2'b00;"""
new_rst = """            logo_blue_p1  <= 1'b0;
            logo_red_p1   <= 1'b0;"""
assert old_rst in content, "old_rst not found!"
content = content.replace(old_rst, new_rst)

# Replace assignment:
old_assign = """            // Logo check
            is_logo_p1    <= in_top_logo;
            logo_pix_p1   <= fn_logo_pixel(active_emergency ? (y_cnt[3:0] - 4'd2) : (y_cnt[3:0] - 4'd10),
                                         active_emergency ? (x_cnt - 10'd20) : (x_cnt - 10'd12));"""
new_assign = """            // Logo check (Dual-Color Anlogic Corporate Identity)
            logo_blue_p1  <= in_top_logo && fn_logo_is_blue(active_emergency ? (y_cnt[3:0] - 4'd2) : (y_cnt[3:0] - 4'd10),
                                                            active_emergency ? (x_cnt - 10'd20) : (x_cnt - 10'd12));
            logo_red_p1   <= in_top_logo && fn_logo_is_red(active_emergency ? (y_cnt[3:0] - 4'd2) : (y_cnt[3:0] - 4'd10),
                                                           active_emergency ? (x_cnt - 10'd20) : (x_cnt - 10'd12));"""
assert old_assign in content, "old_assign not found!"
content = content.replace(old_assign, new_assign)

# Replace Stage 2 mux:
old_stage2 = """            end else if (is_logo_p1 && (logo_pix_p1 != 2'b00)) begin
                rgb_out <= (logo_pix_p1 == 2'b01) ? 24'h204888 : 24'hEE1818; // Dual-Color Anlogic Logo: Navy Blue 'A' + Crimson Red Stripes"""

new_stage2 = """            end else if (logo_blue_p1) begin
                rgb_out <= 24'h204888; // Anlogic Tech Navy Blue Logo ('A')
            end else if (logo_red_p1) begin
                rgb_out <= 24'hEE1818; // Anlogic Crimson Red Logo (8 Stripes)"""

assert old_stage2 in content, "old_stage2 not found!"
content = content.replace(old_stage2, new_stage2)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Successfully replaced with optimized boolean maps!")
