`timescale 1ns / 1ps
// ============================================================================
// Module Name: video_transition
// Description: Multi-mode video transition engine in output coordinates (640x480).
//              Modes:
//                2'd0: Smoothstep Alpha Cross-Fade (平滑透明度渐变)
//                2'd1: Venetian Blinds Wipe (百叶窗百叶开合)
//                2'd2: Horizontal Laser Slide / Wipe (激光横向推进扫描)
//                2'd3: Digital Mosaic / Checkerboard Dissolve (数字马赛克方块消融)
// ============================================================================
module video_transition (
    input wire clk,
    input wire rst,
    input wire de,
    input wire [23:0] rgb_in,
    input wire active,
    input wire opening,
    input wire [1:0] mode,
    input wire [3:0] step,
    output wire [23:0] rgb_out
);
    reg [9:0] x;
    reg [9:0] y;
    reg [9:0] de_blank_cnt;
    reg       de_d;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x            <= 10'd0;
            y            <= 10'd0;
            de_blank_cnt <= 10'd0;
            de_d         <= 1'b0;
        end else begin
            de_d <= de;
            if (de) begin
                x            <= x + 10'd1;
                de_blank_cnt <= 10'd0;
            end else begin
                x <= 10'd0;
                if (de_blank_cnt < 10'd1000)
                    de_blank_cnt <= de_blank_cnt + 10'd1;

                // Line end detection: increment line count y
                if (de_d) begin
                    if (y >= 10'd479)
                        y <= 10'd0;
                    else
                        y <= y + 10'd1;
                end

                // VBLANK detection: blanking > 300 cycles resets y to top
                if (de_blank_cnt >= 10'd300) begin
                    y <= 10'd0;
                end
            end
        end
    end

    // Include both exact endpoints: an unchanged old frame and a completely
    // black frame, followed by a fully visible new frame.
    // Smoothstep endpoints, round(256*(3*t*t-2*t*t*t)), t=step/15.
    function [8:0] ease;
        input [3:0] phase;
        begin case(phase)
            4'd0:ease=9'd0;
            4'd1:ease=9'd3;
            4'd2:ease=9'd12;
            4'd3:ease=9'd27;
            4'd4:ease=9'd45;
            4'd5:ease=9'd66;
            4'd6:ease=9'd90;
            4'd7:ease=9'd115;
            4'd8:ease=9'd141;
            4'd9:ease=9'd166;
            4'd10:ease=9'd190;
            4'd11:ease=9'd211;
            4'd12:ease=9'd229;
            4'd13:ease=9'd244;
            4'd14:ease=9'd253;
            4'd15:ease=9'd256;
        endcase end
    endfunction
    wire [8:0] progress = ease(step);
    // Low-Power Operand Isolation:
    // Clamp fade_gain to 0 when transition is inactive or not in fade mode.
    // When fade_gain is 0, all multiplier partial products evaluate to 0 (zero toggling)
    // without requiring expensive 24-bit data path multiplexers!
    wire [8:0] gain = opening ? progress : 9'd256-progress;
    wire [8:0] fade_gain = (active && (mode == 2'd0)) ? gain : 9'd0;

    function [7:0] scale_channel;
        input [7:0] channel;
        input [8:0] weight;
        reg [16:0] product;
        begin
            product = channel * weight;
            scale_channel = (product + 17'd128) >> 8;
        end
    endfunction

    // Mode 0: Smoothstep Alpha Fade
    wire [23:0] faded = {scale_channel(rgb_in[23:16], fade_gain),
                         scale_channel(rgb_in[15:8],  fade_gain),
                         scale_channel(rgb_in[7:0],   fade_gain)};

    // Mode 1: Venetian Blinds
    wire [5:0] slit = (gain + 9'd4) >> 3;
    wire [23:0] blinds = ({1'b0, x[4:0]} < slit) ? rgb_in : 24'd0;

    // Mode 2: Horizontal Laser Slide / Wipe
    // 0..640 with 16 states. Endpoint overrides avoid a residual scanline
    // after closing and a cut at the first/last column after opening.
    wire [18:0] edge_product = ({10'd0,progress} << 9) + ({10'd0,progress} << 7) + 19'd128;
    wire [9:0] edge_x = edge_product >> 8;
    wire core = (x == edge_x - 10'd1) || (x == edge_x - 10'd2);
    wire halo = (x == edge_x - 10'd3) || (x == edge_x);
    wire visible = opening ? (x < edge_x) : (x >= edge_x);
    wire [23:0] wipe = (step == 4'd0) ? (opening ? 24'd0 : rgb_in) :
                       (step == 4'd15) ? (opening ? rgb_in : 24'd0) :
                       core ? 24'hFFFFFF : halo ? 24'h00FFFF :
                       visible ? rgb_in : 24'd0;

    // Mode 3: Digital Mosaic / Checkerboard Dissolve (16x16 pixel blocks)
    wire [5:0] bx = x[9:4];
    wire [4:0] by = y[8:4];
    wire [5:0] by_x3 = {by, 1'b0} + {1'b0, by};
    wire [5:0] hash_sum = (bx ^ by_x3) + {1'b0, bx[5:1]} + {2'b0, by[4:1]};
    wire [3:0] mosaic_val = hash_sum[3:0];
    wire mosaic_visible = opening ? (mosaic_val <= step) : (mosaic_val > step);
    wire [23:0] mosaic = (step == 4'd0)  ? (opening ? 24'd0 : rgb_in) :
                         (step == 4'd15) ? (opening ? rgb_in : 24'd0) :
                         mosaic_visible  ? rgb_in : 24'd0;

    assign rgb_out = !active        ? rgb_in :
                     (mode == 2'd1) ? blinds :
                     (mode == 2'd2) ? wipe :
                     (mode == 2'd3) ? mosaic : faded;
endmodule
