// =====================================================================
// Module: video_sobel
// Purpose: Pure Hardware Real-time Sobel Edge Detection and Visual Enhancement Pipeline
//          Strictly aligned with Competition Analysis (Slide 13)
//
// Features:
//  1. Pure video_clk (25MHz) 6-stage streaming pipeline, 0 PLL overhead.
//  2. High-precision RGB24 to BT.601 Grayscale via 0-DSP shift-add arithmetic:
//     Y = (77*R + 150*G + 29*B) >> 8
//  3. Dual-line buffer (Line Y-1 & Line Y-2) using dedicated ERAM9K block RAMs,
//     forming a real-time 3x3 sliding neighborhood window matrix P00..P22.
//  4. Hardware Sobel Horizontal & Vertical Gradients:
//     Gx = |(P02 + 2*P12 + P22) - (P00 + 2*P10 + P20)|
//     Gy = |(P20 + 2*P21 + P22) - (P00 + 2*P01 + P02)|
//     |G| = Gx + Gy
//  5. Cyberpunk Line-Art Visual Enhancement:
//     - Edge (|G| >= THRESHOLD): Electric Neon Cyan (24'h00FFFF)
//     - Background: Deep Dark Slate Blue (24'h0A0D14)
//     - 3-pixel border blanking to suppress edge filter startup artifacts
//  6. Three-mode Seamless Switch:
//     - Mode 0: Full Color Vivid RGB
//     - Mode 1: Monochrome Grayscale
//     - Mode 2: Real-time Sobel Edge Detection
//  7. Precise 6-cycle latency alignment between hs, vs, de, and pixel output.
//  8. Tear-free VBLANK parameter latching.
// =====================================================================
`timescale 1ns / 1ps

module video_sobel #(
    parameter [11:0] THRESHOLD = 12'd200
)(
    input  wire        video_clk,
    input  wire        rst,
    input  wire [1:0]  color_mode,       // 0: Vivid RGB, 1: Monochrome, 2: Sobel Edge
    
    // Video stream in (640x480 VESA timing)
    input  wire        vs_in,
    input  wire        hs_in,
    input  wire        de_in,
    input  wire [23:0] rgb_in,
    
    // Video stream out (fully aligned, 6 cycles latency)
    output reg         vs_out,
    output reg         hs_out,
    output reg         de_out,
    output reg  [23:0] rgb_out
);

    // -------------------------------------------------------------
    // 1. Pixel & Line Coordinate Tracking
    // -------------------------------------------------------------
    reg vs_d0;
    wire frame_start = vs_d0 && !vs_in;

    // Latch color_mode on VBLANK to prevent mid-frame visual tearing
    reg [1:0] active_color_mode;
    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            active_color_mode <= 2'd0;
        end else if (frame_start) begin
            active_color_mode <= color_mode;
        end
    end

    // Low-power operand isolation flag: Sobel gradients are only required in Mode 2 & Mode 3
    wire sobel_active = (active_color_mode >= 2'd2);

    reg [9:0] col_cnt;
    reg [9:0] line_cnt;
    reg       de_in_d;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            col_cnt  <= 10'd0;
            line_cnt <= 10'd0;
            vs_d0    <= 1'b0;
            de_in_d  <= 1'b0;
        end else begin
            vs_d0   <= vs_in;
            de_in_d <= de_in;
            if (frame_start) begin
                col_cnt  <= 10'd0;
                line_cnt <= 10'd0;
            end else if (de_in) begin
                col_cnt <= col_cnt + 10'd1;
            end else begin
                col_cnt <= 10'd0;
                if (de_in_d) begin
                    line_cnt <= line_cnt + 10'd1;
                end
            end
        end
    end

    // -------------------------------------------------------------
    // 2. Stage 1: Zero-DSP Shift-Add Grayscale Conversion
    //    BT.601: Y = (77*R + 150*G + 29*B) >> 8
    //    77*R  = (R<<6) + (R<<3) + (R<<2) + R
    //    150*G = (G<<7) + (G<<4) + (G<<2) + (G<<1)
    //    29*B  = (B<<4) + (B<<3) + (B<<2) + B
    // -------------------------------------------------------------
    wire [15:0] r_mult = {2'b0, rgb_in[23:16], 6'b0} + {5'b0, rgb_in[23:16], 3'b0} +
                         {6'b0, rgb_in[23:16], 2'b0} + {8'b0, rgb_in[23:16]};
    wire [15:0] g_mult = {1'b0, rgb_in[15:8],  7'b0} + {4'b0, rgb_in[15:8],  4'b0} +
                         {6'b0, rgb_in[15:8],  2'b0} + {7'b0, rgb_in[15:8],  1'b0};
    wire [15:0] b_mult = {4'b0, rgb_in[7:0],   4'b0} + {5'b0, rgb_in[7:0],   3'b0} +
                         {6'b0, rgb_in[7:0],   2'b0} + {8'b0, rgb_in[7:0]};
    wire [16:0] luma_sum = {1'b0, r_mult} + {1'b0, g_mult} + {1'b0, b_mult};
    wire [7:0]  gray_c   = luma_sum[15:8];

    wire       line_border = (line_cnt < 10'd3) || (line_cnt >= 10'd477);
    reg [7:0]  gray_d1;
    reg [23:0] rgb_d1;
    reg        de_d1, hs_d1, vs_d1;
    reg [9:0]  col_d1;
    reg        line_border_d1;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            gray_d1        <= 8'd0;
            rgb_d1         <= 24'd0;
            de_d1          <= 1'b0;
            hs_d1          <= 1'b0;
            vs_d1          <= 1'b0;
            col_d1         <= 10'd0;
            line_border_d1 <= 1'b1;
        end else begin
            gray_d1        <= (active_color_mode != 2'd0) ? gray_c : 8'd0;
            rgb_d1         <= rgb_in;
            de_d1          <= de_in;
            hs_d1          <= hs_in;
            vs_d1          <= vs_in;
            col_d1         <= col_cnt;
            line_border_d1 <= line_border;
        end
    end

    // -------------------------------------------------------------
    // 3. Stage 2: Dual Line Buffer (Line Y-1 & Line Y-2)
    // -------------------------------------------------------------
    reg [7:0] line_buf0 [0:639];
    reg [7:0] line_buf1 [0:639];

    reg [7:0] lb0_rd;
    reg [7:0] lb1_rd;
    always @(posedge video_clk) begin
        if (sobel_active && de_d1) begin
            lb0_rd <= line_buf0[col_d1];
            lb1_rd <= line_buf1[col_d1];
        end
    end

    reg [7:0]  gray_d2;
    reg [23:0] rgb_d2;
    reg        de_d2, hs_d2, vs_d2;
    reg [9:0]  col_d2;
    reg        line_border_d2;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            gray_d2        <= 8'd0;
            rgb_d2         <= 24'd0;
            de_d2          <= 1'b0;
            hs_d2          <= 1'b0;
            vs_d2          <= 1'b0;
            col_d2         <= 10'd0;
            line_border_d2 <= 1'b1;
        end else begin
            gray_d2        <= gray_d1;
            rgb_d2         <= rgb_d1;
            de_d2          <= de_d1;
            hs_d2          <= hs_d1;
            vs_d2          <= vs_d1;
            col_d2         <= col_d1;
            line_border_d2 <= line_border_d1;
        end
    end

    // Write Line Y into line_buf0, and Line Y-1 into line_buf1
    always @(posedge video_clk) begin
        if (sobel_active && de_d2) begin
            line_buf0[col_d2] <= gray_d2;
            line_buf1[col_d2] <= lb0_rd;
        end
    end

    // -------------------------------------------------------------
    // 4. Stage 3: 3x3 Sliding Window Matrix
    //    [P00  P01  P02]  <- Line Y-2 (Oldest)
    //    [P10  P11  P12]  <- Line Y-1 (Center)
    //    [P20  P21  P22]  <- Line Y   (Newest)
    // -------------------------------------------------------------
    reg [7:0] p00, p01, p02;
    reg [7:0] p10, p11, p12;
    reg [7:0] p20, p21, p22;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            p00 <= 8'd0; p01 <= 8'd0; p02 <= 8'd0;
            p10 <= 8'd0; p11 <= 8'd0; p12 <= 8'd0;
            p20 <= 8'd0; p21 <= 8'd0; p22 <= 8'd0;
        end else if (sobel_active && de_d2) begin
            p00 <= p01;
            p01 <= p02;
            p02 <= lb1_rd;

            p10 <= p11;
            p11 <= p12;
            p12 <= lb0_rd;

            p20 <= p21;
            p21 <= p22;
            p22 <= gray_d2;
        end
    end

    reg [7:0]  gray_d3;
    reg [23:0] rgb_d3;
    reg        de_d3, hs_d3, vs_d3;
    reg [9:0]  col_d3;
    reg        line_border_d3;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            gray_d3        <= 8'd0;
            rgb_d3         <= 24'd0;
            de_d3          <= 1'b0;
            hs_d3          <= 1'b0;
            vs_d3          <= 1'b0;
            col_d3         <= 10'd0;
            line_border_d3 <= 1'b1;
        end else begin
            gray_d3        <= gray_d2;
            rgb_d3         <= rgb_d2;
            de_d3          <= de_d2;
            hs_d3          <= hs_d2;
            vs_d3          <= vs_d2;
            col_d3         <= col_d2;
            line_border_d3 <= line_border_d2;
        end
    end

    // -------------------------------------------------------------
    // 5. Stage 4: Sobel Positive & Negative Gradient Partial Sums
    // -------------------------------------------------------------
    reg [10:0] gx_pos, gx_neg;
    reg [10:0] gy_pos, gy_neg;
    reg [7:0]  gray_d4;
    reg [23:0] rgb_d4;
    reg        de_d4, hs_d4, vs_d4;
    reg [9:0]  col_d4;
    reg        line_border_d4;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            gx_pos         <= 11'd0;
            gx_neg         <= 11'd0;
            gy_pos         <= 11'd0;
            gy_neg         <= 11'd0;
            gray_d4        <= 8'd0;
            rgb_d4         <= 24'd0;
            de_d4          <= 1'b0;
            hs_d4          <= 1'b0;
            vs_d4          <= 1'b0;
            col_d4         <= 10'd0;
            line_border_d4 <= 1'b1;
        end else begin
            gx_pos         <= sobel_active ? ({3'd0, p02} + {2'd0, p12, 1'b0} + {3'd0, p22}) : 11'd0;
            gx_neg         <= sobel_active ? ({3'd0, p00} + {2'd0, p10, 1'b0} + {3'd0, p20}) : 11'd0;
            gy_pos         <= sobel_active ? ({3'd0, p20} + {2'd0, p21, 1'b0} + {3'd0, p22}) : 11'd0;
            gy_neg         <= sobel_active ? ({3'd0, p00} + {2'd0, p01, 1'b0} + {3'd0, p02}) : 11'd0;
            gray_d4        <= gray_d3;
            rgb_d4         <= rgb_d3;
            de_d4          <= de_d3;
            hs_d4          <= hs_d3;
            vs_d4          <= vs_d3;
            col_d4         <= col_d3;
            line_border_d4 <= line_border_d3;
        end
    end

    // -------------------------------------------------------------
    // 6. Stage 5: Absolute Differences |Gx| & |Gy|
    // -------------------------------------------------------------
    reg [10:0] gx_abs;
    reg [10:0] gy_abs;
    reg [7:0]  gray_d5;
    reg [23:0] rgb_d5;
    reg        de_d5, hs_d5, vs_d5;
    reg [9:0]  col_d5;
    reg        line_border_d5;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            gx_abs         <= 11'd0;
            gy_abs         <= 11'd0;
            gray_d5        <= 8'd0;
            rgb_d5         <= 24'd0;
            de_d5          <= 1'b0;
            hs_d5          <= 1'b0;
            vs_d5          <= 1'b0;
            col_d5         <= 10'd0;
            line_border_d5 <= 1'b1;
        end else begin
            gx_abs         <= (gx_pos >= gx_neg) ? (gx_pos - gx_neg) : (gx_neg - gx_pos);
            gy_abs         <= (gy_pos >= gy_neg) ? (gy_pos - gy_neg) : (gy_neg - gy_pos);
            gray_d5        <= gray_d4;
            rgb_d5         <= rgb_d4;
            de_d5          <= de_d4;
            hs_d5          <= hs_d4;
            vs_d5          <= vs_d4;
            col_d5         <= col_d4;
            line_border_d5 <= line_border_d4;
        end
    end

    // -------------------------------------------------------------
    // 7. Stage 6: Total Gradient, Thresholding, Digital Rubbing & Output
    // -------------------------------------------------------------
    wire [11:0] grad_sum = {1'b0, gx_abs} + {1'b0, gy_abs};
    wire        is_edge  = (grad_sum >= THRESHOLD);
    
    // Border suppression: suppress border 3 pixels/lines to eliminate filter startup noise
    wire is_border   = (col_d5 < 10'd3) || (col_d5 >= 10'd637) || line_border_d5;
    wire active_edge = !is_border && is_edge;

    // 1. Classic Ink Rubbing (古法乌金墨拓本):
    // Dark inkstone rice-paper background: 24'h080A0E
    // Crisp inscribed stroke: 24'hFFFFFF (Pure silver-white)
    wire [23:0] ink_rubbing_pixel = active_edge ? 24'hFFFFFF : 24'h080A0E;

    // 2. Imperial Cinnabar Rubbing (皇家朱砂御拓本):
    // Deep royal cinnabar background: 24'h7A1414
    // Gilded inscribed stroke: 24'hFFE066 (Antique Gilded Gold)
    wire [23:0] cin_rubbing_pixel = active_edge ? 24'hFFE066 : 24'h7A1414;


    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            vs_out  <= 1'b0;
            hs_out  <= 1'b0;
            de_out  <= 1'b0;
            rgb_out <= 24'd0;
        end else begin
            vs_out <= vs_d5;
            hs_out <= hs_d5;
            de_out <= de_d5;
            if (!de_d5) begin
                rgb_out <= 24'd0;
            end else begin
                case (active_color_mode)
                    2'd0: rgb_out <= rgb_d5;                      // Mode 0: 原画真彩 (Natural Vivid RGB)
                    2'd1: rgb_out <= {gray_d5, gray_d5, gray_d5}; // Mode 1: 黑白模式 (High-Precision Grayscale Monochrome)
                    2'd2: rgb_out <= ink_rubbing_pixel;           // Mode 2: 古法墨拓 (Classic Ink Rubbing)
                    2'd3: begin                                   // Mode 3: 原物与SW3色彩模式(古法墨拓)分屏审视 (Split-Screen Comparison)
                        if (col_d5 == 10'd319 || col_d5 == 10'd320)
                            rgb_out <= 24'h00FFCC;                // 中轴青铜激光刻度线
                        else if (col_d5 < 10'd319)
                            rgb_out <= rgb_d5;                    // 左半屏：文物实物原图 (原画状态)
                        else
                            rgb_out <= ink_rubbing_pixel;         // 右半屏：SW3古法墨拓色彩模式
                    end
                    default: rgb_out <= rgb_d5;
                endcase
            end
        end
    end

endmodule
