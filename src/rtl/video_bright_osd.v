module video_bright_osd (
    input             video_clk,
    input             rst,
    input             vs,
    input             de,
    input      [23:0] rgb_in,
	    input      [3:0]  sw_level_async,
	    input             contrast_on,
	    output     [3:0]  bright_level,
    output reg [23:0] rgb_out
);

    reg [3:0] sw_s0;
    reg [3:0] sw_s1;
    reg [3:0] level_hold;
    reg       de_d;
    reg       vs_d;
    reg [9:0] x_cnt;
    reg [8:0] y_cnt;

    // 64/128 = 50%，每一级 +12.5%，第 4 级为 100%，再往上开始加亮并限幅。
    wire [8:0] gain = 9'd64 + {1'd0, sw_s1, 4'd0};
    wire [7:0] pix_r = scale_ch(rgb_in[23:16], gain);
    wire [7:0] pix_g = scale_ch(rgb_in[15:8], gain);
    wire [7:0] pix_b = scale_ch(rgb_in[7:0], gain);

	    wire        in_tag  = de && (y_cnt <= 9'd10) && (x_cnt >= 10'd28) && (x_cnt <= 10'd32);
	    wire        in_tagv = de && (y_cnt <= 9'd10) && (x_cnt >= 10'd36) && (x_cnt <= 10'd40);
	    wire        in_mark = de && (y_cnt <= 9'd10) && (x_cnt >= 10'd4) && (x_cnt <= 10'd8);
    wire        in_tens = de && (y_cnt <= 9'd10) && (x_cnt >= 10'd12) && (x_cnt <= 10'd16);
    wire        in_ones = de && (y_cnt <= 9'd10) && (x_cnt >= 10'd20) && (x_cnt <= 10'd24);
    wire        in_bar  = de && (y_cnt >= 9'd12) && (y_cnt <= 9'd15) && (x_cnt >= 10'd4) && (x_cnt <= 10'd67);
    wire [3:0]  tens    = (sw_s1 >= 4'd10) ? 4'd1 : 4'd0;
    wire [3:0]  ones    = (sw_s1 >= 4'd10) ? (sw_s1 - 4'd10) : sw_s1;
	    wire        tag_on  = in_tag && font_on(4'd12, x_cnt - 10'd28, y_cnt[2:0]);
	    wire        tagv_on = in_tagv && font_on(contrast_on ? 4'd1 : 4'd0, x_cnt - 10'd36, y_cnt[2:0]);
	    wire        mark_on = in_mark && font_on(4'd11, x_cnt - 10'd4, y_cnt[2:0]);
    wire        tens_on = in_tens && font_on(tens, x_cnt - 10'd12, y_cnt[2:0]);
    wire        ones_on = in_ones && font_on(ones, x_cnt - 10'd20, y_cnt[2:0]);
    wire        bar_on  = in_bar && ((x_cnt - 10'd4) < {4'd0, sw_s1, 2'd0});
	    wire        text_on = mark_on || tens_on || ones_on || bar_on || tag_on || tagv_on;

    assign bright_level = level_hold;

    function [7:0] scale_ch;
        input [7:0] ch;
        input [8:0] g;
        reg [16:0] prod;
        begin
            prod = ch * g;
            scale_ch = (prod[16:7] > 10'd255) ? 8'hff : prod[14:7];
        end
    endfunction

    function font_on;
        input [3:0] glyph;
        input [9:0] x;
        input [2:0] y;
        reg [4:0] row;
        begin
            row = font_row(glyph, y);
            font_on = (x <= 10'd4) && row[4'd4 - x[2:0]];
        end
    endfunction

    function [4:0] font_row;
        input [3:0] glyph;
        input [2:0] y;
        begin
            case (glyph)
                4'd0: font_row = row5(y, 5'b01110, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b01110);
                4'd1: font_row = row5(y, 5'b00100, 5'b01100, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b01110);
                4'd2: font_row = row5(y, 5'b01110, 5'b10001, 5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b11111);
                4'd3: font_row = row5(y, 5'b11110, 5'b00001, 5'b00001, 5'b01110, 5'b00001, 5'b00001, 5'b11110);
                4'd4: font_row = row5(y, 5'b00010, 5'b00110, 5'b01010, 5'b10010, 5'b11111, 5'b00010, 5'b00010);
                4'd5: font_row = row5(y, 5'b11111, 5'b10000, 5'b10000, 5'b11110, 5'b00001, 5'b00001, 5'b11110);
                4'd6: font_row = row5(y, 5'b01110, 5'b10000, 5'b10000, 5'b11110, 5'b10001, 5'b10001, 5'b01110);
                4'd7: font_row = row5(y, 5'b11111, 5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b01000, 5'b01000);
                4'd8: font_row = row5(y, 5'b01110, 5'b10001, 5'b10001, 5'b01110, 5'b10001, 5'b10001, 5'b01110);
	                4'd9: font_row = row5(y, 5'b01110, 5'b10001, 5'b10001, 5'b01111, 5'b00001, 5'b00001, 5'b01110);
	                4'd12: font_row = row5(y, 5'b01110, 5'b10001, 5'b10000, 5'b10000, 5'b10000, 5'b10001, 5'b01110);
	                default: font_row = row5(y, 5'b11110, 5'b10001, 5'b10001, 5'b11110, 5'b10001, 5'b10001, 5'b11110);
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
            sw_s0      <= 4'd4;
            sw_s1      <= 4'd4;
            level_hold <= 4'd4;
            de_d       <= 1'b0;
            vs_d       <= 1'b0;
            x_cnt      <= 10'd0;
            y_cnt      <= 9'd0;
            rgb_out    <= 24'd0;
        end else begin
            sw_s0 <= sw_level_async;
            sw_s1 <= sw_s0;
            de_d  <= de;
            vs_d  <= vs;

            if (!vs)
                level_hold <= sw_s1;

            if (vs && !vs_d) begin
                x_cnt <= 10'd0;
                y_cnt <= 9'd0;
            end else if (de) begin
                x_cnt <= de_d ? (x_cnt + 10'd1) : 10'd0;
            end else if (de_d) begin
                x_cnt <= 10'd0;
                y_cnt <= y_cnt + 9'd1;
            end

            if (!de)
                rgb_out <= 24'd0;
            else if (text_on)
                rgb_out <= 24'hFFFF00;
            else
                rgb_out <= {pix_r, pix_g, pix_b};
        end
    end

endmodule
