module video_scroll_osd (
    input             video_clk,
    input             rst,
	    input             vs,
	    input             frame_vs,
	    input             de,
	    input      [23:0] rgb_in,
	    input      [2:0]  img_idx,
	    input      [7:0]  play_pos,
	    input             auto_play,
	    input             card_hold,
	    input      [5:0]  sec_count,
	    output reg [23:0] rgb_out
	);

    localparam [8:0] BAND_Y0 = 9'd452;
    localparam [8:0] BAND_Y1 = 9'd467;
	    localparam integer TEXT_CHARS = 13;
	    localparam [9:0] TEXT_W = 10'd104;
	    localparam [9:0] SCROLL_LAST = 10'd639 + TEXT_W;

	    reg       de_d;
	    reg       vs_d;
	    reg       frame_vs_d;
    reg [9:0] x_cnt;
    reg [8:0] y_cnt;
    reg [9:0] scroll;

	    wire [9:0] slot_x = {4'd0, img_idx, 3'd0} + 10'd8;
	    wire in_slot = de && (y_cnt >= 9'd438) && (y_cnt <= 9'd443) &&
	                   (x_cnt >= slot_x) && (x_cnt < slot_x + 10'd6);
	    wire in_prog = de && auto_play && (y_cnt >= 9'd446) && (y_cnt <= 9'd448) &&
	                   (x_cnt >= 10'd8) && (x_cnt < 10'd8 + {2'd0, play_pos});
	    wire in_hold = de && card_hold && (y_cnt >= 9'd438) && (y_cnt <= 9'd448) &&
	                   (x_cnt >= 10'd56) && (x_cnt <= 10'd60);
	    wire [3:0] sec_tens = (sec_count >= 6'd50) ? 4'd5 :
	                          (sec_count >= 6'd40) ? 4'd4 :
	                          (sec_count >= 6'd30) ? 4'd3 :
	                          (sec_count >= 6'd20) ? 4'd2 :
	                          (sec_count >= 6'd10) ? 4'd1 : 4'd0;
	    wire [3:0] sec_ones = sec_count - {sec_tens, 3'd0} - {1'b0, sec_tens, 1'b0};
	    wire [3:0] min_tens = 4'd0;
	    wire [3:0] min_ones = (sec_count == 6'd0) ? 4'd0 : 4'd0;
	    wire in_time = de && (y_cnt <= 9'd6) && (x_cnt >= 10'd600) && (x_cnt <= 10'd636);
	    wire [9:0] time_x = x_cnt - 10'd600;
	    wire [3:0] time_digit = (time_x < 10'd8) ? min_tens :
	                            (time_x < 10'd16) ? min_ones :
	                            (time_x < 10'd24) ? 4'd10 :
	                            (time_x < 10'd32) ? sec_tens : sec_ones;
	    wire [9:0] time_glyph_x = time_x - {time_x[9:3], 3'd0};
	    wire time_on = in_time && (time_glyph_x < 10'd5) && font5(time_digit, time_glyph_x[2:0], y_cnt[2:0]);
	    wire in_band = de && (y_cnt >= BAND_Y0) && (y_cnt <= BAND_Y1);
	    wire [10:0] text_pos = {1'b0, x_cnt} + {1'b0, scroll};
	    wire        text_visible = text_pos >= 11'd640;
	    wire [9:0]  local_x = text_pos - 11'd640;
	    wire [9:0]  glyph_x = local_x - {local_x[9:3], 3'd0};
	    wire [3:0]  glyph_i = local_x[6:3];
    wire [2:0] glyph_y = y_cnt - BAND_Y0;
	    wire glyph_hit = in_band && text_visible && (local_x < TEXT_W) && (glyph_x < 10'd5) &&
                     font_on(glyph_code(glyph_i[3:0]), glyph_x, glyph_y);

	    function font5;
	        input [3:0] digit;
	        input [2:0] x;
	        input [2:0] y;
	        reg [4:0] row;
	        begin
	            case (digit)
	                4'd0: row = row5(y, 5'b01110, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b01110);
	                4'd1: row = row5(y, 5'b00100, 5'b01100, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b01110);
	                4'd2: row = row5(y, 5'b01110, 5'b10001, 5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b11111);
	                4'd3: row = row5(y, 5'b11110, 5'b00001, 5'b00001, 5'b01110, 5'b00001, 5'b00001, 5'b11110);
	                4'd4: row = row5(y, 5'b00010, 5'b00110, 5'b01010, 5'b10010, 5'b11111, 5'b00010, 5'b00010);
	                4'd5: row = row5(y, 5'b11111, 5'b10000, 5'b10000, 5'b11110, 5'b00001, 5'b00001, 5'b11110);
	                4'd6: row = row5(y, 5'b01110, 5'b10000, 5'b10000, 5'b11110, 5'b10001, 5'b10001, 5'b01110);
	                4'd7: row = row5(y, 5'b11111, 5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b01000, 5'b01000);
	                4'd8: row = row5(y, 5'b01110, 5'b10001, 5'b10001, 5'b01110, 5'b10001, 5'b10001, 5'b01110);
	                4'd9: row = row5(y, 5'b01110, 5'b10001, 5'b10001, 5'b01111, 5'b00001, 5'b00001, 5'b01110);
	                default: row = row5(y, 5'b00000, 5'b00100, 5'b00100, 5'b00000, 5'b00100, 5'b00100, 5'b00000);
	            endcase
	            font5 = row[3'd4 - x];
	        end
	    endfunction

	    function [4:0] glyph_code;
        input [3:0] idx;
        begin
	            case (idx)
	                4'd0:  glyph_code = 5'd22; // W
	                4'd1:  glyph_code = 5'd18; // E
	                4'd2:  glyph_code = 5'd11; // L
	                4'd3:  glyph_code = 5'd12; // C
	                4'd4:  glyph_code = 5'd14; // O
	                4'd5:  glyph_code = 5'd21; // M
	                4'd6:  glyph_code = 5'd18; // E
	                4'd7:  glyph_code = 5'd31; // space
	                4'd8:  glyph_code = 5'd19; // V
	                4'd9:  glyph_code = 5'd17; // I
	                4'd10: glyph_code = 5'd23; // S
	                4'd11: glyph_code = 5'd17; // I
	                4'd12: glyph_code = 5'd24; // T
	                default: glyph_code = 5'd31;
	            endcase
        end
    endfunction

    function font_on;
        input [4:0] glyph;
        input [9:0] x;
        input [2:0] y;
        reg [4:0] row;
        begin
            row = font_row(glyph, y);
            font_on = row[4'd4 - x[2:0]];
        end
    endfunction

    function [4:0] font_row;
        input [4:0] glyph;
        input [2:0] y;
        begin
            case (glyph)
                5'd10: font_row = row5(y, 5'b01110, 5'b10001, 5'b10001, 5'b11111, 5'b10001, 5'b10001, 5'b10001);
                5'd11: font_row = row5(y, 5'b10000, 5'b10000, 5'b10000, 5'b10000, 5'b10000, 5'b10000, 5'b11111);
                5'd12: font_row = row5(y, 5'b01110, 5'b10001, 5'b10000, 5'b10000, 5'b10000, 5'b10001, 5'b01110);
                5'd13: font_row = row5(y, 5'b10001, 5'b11001, 5'b10101, 5'b10011, 5'b10001, 5'b10001, 5'b10001);
                5'd14: font_row = row5(y, 5'b01110, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b01110);
                5'd15: font_row = row5(y, 5'b11111, 5'b10000, 5'b10000, 5'b11110, 5'b10000, 5'b10000, 5'b10000);
                5'd16: font_row = row5(y, 5'b01110, 5'b10001, 5'b10000, 5'b10111, 5'b10001, 5'b10001, 5'b01110);
	                5'd17: font_row = row5(y, 5'b01110, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b01110);
	                5'd18: font_row = row5(y, 5'b11111, 5'b10000, 5'b10000, 5'b11110, 5'b10000, 5'b10000, 5'b11111);
	                5'd19: font_row = row5(y, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b01010, 5'b00100);
	                5'd20: font_row = row5(y, 5'b11110, 5'b10001, 5'b10001, 5'b11110, 5'b10000, 5'b10000, 5'b10000);
	                5'd21: font_row = row5(y, 5'b10001, 5'b11011, 5'b10101, 5'b10001, 5'b10001, 5'b10001, 5'b10001);
	                5'd22: font_row = row5(y, 5'b10001, 5'b10001, 5'b10001, 5'b10101, 5'b10101, 5'b01010, 5'b01010);
	                5'd23: font_row = row5(y, 5'b01111, 5'b10000, 5'b10000, 5'b01110, 5'b00001, 5'b00001, 5'b11110);
	                5'd24: font_row = row5(y, 5'b11111, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b00100);
	                default: font_row = 5'b00000;
            endcase
        end
    endfunction

    function [4:0] row5;
        input [2:0] y;
        input [4:0] r0;
        input [4:0] r1;
        input [4:0] r2;
        input [4:0] r3;
        input [4:0] r4;
        input [4:0] r5;
        input [4:0] r6;
        begin
            case (y)
                3'd0: row5 = r0;
                3'd1: row5 = r1;
                3'd2: row5 = r2;
                3'd3: row5 = r3;
                3'd4: row5 = r4;
                3'd5: row5 = r5;
                3'd6: row5 = r6;
                default: row5 = 5'b00000;
            endcase
        end
    endfunction

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
	            de_d       <= 1'b0;
	            vs_d       <= 1'b0;
	            frame_vs_d <= 1'b0;
            x_cnt   <= 10'd0;
            y_cnt   <= 9'd0;
            scroll  <= 10'd0;
            rgb_out <= 24'd0;
        end else begin
	            de_d <= de;
	            vs_d <= vs;
	            frame_vs_d <= frame_vs;

	            if (!frame_vs_d && frame_vs) begin
	                if (scroll == SCROLL_LAST)
	                    scroll <= 10'd0;
	                else
	                    scroll <= scroll + 10'd1;
	            end

	            if (!vs_d && vs) begin
	                x_cnt <= 10'd0;
	                y_cnt <= 9'd0;
	            end else if (!de_d && de) begin
                x_cnt <= 10'd0;
            end else if (de) begin
                x_cnt <= x_cnt + 10'd1;
            end else if (de_d && !de) begin
                y_cnt <= y_cnt + 9'd1;
            end

	            if (time_on)
	                rgb_out <= 24'hFFFFFF;
	            else if (glyph_hit)
	                rgb_out <= {(rgb_in[23:17] + 7'd127), (rgb_in[15:9] + 7'd127), rgb_in[7:1]};
	            else if (in_hold)
	                rgb_out <= 24'hFF4040;
	            else if (in_slot)
	                rgb_out <= 24'hFFFF00;
	            else if (in_prog)
	                rgb_out <= 24'h40FF80;
	            else
	                rgb_out <= rgb_in;
        end
    end

endmodule
