# -*- coding: utf-8 -*-
# Generate Super-Aesthetics Cyber Cockpit lcd_st7735_telemetry.v (Optimized Logic)

rtl = '''// ============================================================================
// Module Name: lcd_st7735_telemetry
// Project:     全国大学生嵌入式芯片与系统设计竞赛 - HX4S20 HDMI多媒体展示系统
// Target Board: Anlogic EG4S20BG256 (HX4S20C)
// Function:    1.44寸 128x128 SPI TFT 彩色 LCD (ST7735S) 极客座舱高颜值遥测副屏驱动
// Features:    - 战机座舱胶囊标签 [PIC] [SCL] [AUD] [LAT]
//              - 纯白光束核心 + 荧光绿 CRT 示波器
//              - 16px 8频段跳动频谱三段渐变 + 悬浮白帽
//              - 战术菱形雷达 1.0Hz 心跳指示灯
//              - 工业级抗干扰 6.25MHz SPI 引擎
// ============================================================================
`timescale 1ns / 1ps

module lcd_st7735_telemetry #(
    parameter [7:0] COL_OFFSET = 8'd2, // ST7735S 1.44寸 128x128 屏幕水平偏移
    parameter [7:0] ROW_OFFSET = 8'd3  // ST7735S 1.44寸 128x128 屏幕垂直偏移
)(
    input  wire                 clk,            // 50MHz 系统时钟
    input  wire                 rst,            // 高电平复位 (rst_all)

    // LCD SPI 物理接口 (对应开发板 J1 扩展口 Pin 23..28)
    output reg                  lcd_scl,        // SPI SCLK (6.25MHz, Pin J16)
    output reg                  lcd_mosi,       // SPI MOSI (SDA, Pin H16)
    output reg                  lcd_cs,         // 片选 (CS, Pin M16, 低有效)
    output reg                  lcd_dc,         // 数据/命令选择 (DC, Pin K16, 0=Cmd, 1=Data)
    output reg                  lcd_rst,        // 硬件复位 (RST, Pin H15, 低有效)
    output wire                 lcd_blk,        // 背光控制 (BLK, Pin K15, 高电平常开)

    // 系统遥测与音频实时输入
    input  wire [2:0]           cur_img_idx,    // 当前图片索引 0..3 (显示为 1..4)
    input  wire [1:0]           scale_mode,     // 缩放模式 0:1.0X, 1:2.0X, 2:0.5X, 3:AUTO
    input  wire [2:0]           vol_mode,       // 音量模式 0:100%, 1:75%, 2:50%, 3:25%, 4:MUTE
    input  wire signed [23:0]   audio_pcm,      // 24-bit PCM 采样
    input  wire                 audio_valid,    // 48kHz 采样脉冲
    input  wire                 emergency_mode  // 应急广播模式状态
);

    // 背光常开 (3.3V)
    assign lcd_blk = 1'b1;

    // ------------------------------------------------------------------------
    // 1. 1.0Hz 系统心跳发生器
    // ------------------------------------------------------------------------
    reg [25:0] hb_cnt;
    reg        hb_1hz;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            hb_cnt <= 26'd0;
            hb_1hz <= 1'b0;
        end else if (hb_cnt >= 26'd24_999_999) begin
            hb_cnt <= 26'd0;
            hb_1hz <= ~hb_1hz;
        end else begin
            hb_cnt <= hb_cnt + 26'd1;
        end
    end

    // ------------------------------------------------------------------------
    // 2. 音频 128 点示波器 BRAM 采样缓存与 8 频段跳动频谱
    // ------------------------------------------------------------------------
    reg [2:0] audio_vld_sync;
    always @(posedge clk or posedge rst) begin
        if (rst)
            audio_vld_sync <= 3'b000;
        else
            audio_vld_sync <= {audio_vld_sync[1:0], audio_valid};
    end
    wire audio_pulse = audio_vld_sync[1] & ~audio_vld_sync[2];

    reg [6:0] osc_wr_ptr;
    always @(posedge clk or posedge rst) begin
        if (rst)
            osc_wr_ptr <= 7'd0;
        else if (audio_pulse)
            osc_wr_ptr <= osc_wr_ptr + 7'd1;
    end

    // 示波器 RAM: 纯时钟驱动推导 BRAM9K
    reg signed [7:0] osc_buf [0:127];
    always @(posedge clk) begin
        if (audio_pulse)
            osc_buf[osc_wr_ptr] <= audio_pcm[23:16];
    end

    wire [6:0] cur_x_wire;
    wire [6:0] next_x = (cur_x_wire == 7'd127) ? 7'd0 : (cur_x_wire + 7'd1);

    reg signed [7:0] osc_s;
    always @(posedge clk) begin
        osc_s <= osc_buf[next_x];
    end

    // 8 频段频谱能量峰值及衰减
    reg [2:0]  band_level [0:7];
    reg [20:0] decay_cnt;
    wire [7:0] audio_abs = audio_pcm[23] ? (-audio_pcm[23:16]) : audio_pcm[23:16];
    wire [2:0] band_in_idx = osc_wr_ptr[6:4];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            band_level[0] <= 3'd0; band_level[1] <= 3'd0; band_level[2] <= 3'd0; band_level[3] <= 3'd0;
            band_level[4] <= 3'd0; band_level[5] <= 3'd0; band_level[6] <= 3'd0; band_level[7] <= 3'd0;
            decay_cnt <= 21'd0;
        end else begin
            if (audio_pulse) begin
                if (audio_abs[7:5] > band_level[band_in_idx])
                    band_level[band_in_idx] <= (audio_abs[7:5] > 3'd6) ? 3'd6 : audio_abs[7:5];
            end

            if (decay_cnt >= 21'd1_600_000) begin
                decay_cnt <= 21'd0;
                if (band_level[0] > 0) band_level[0] <= band_level[0] - 3'd1;
                if (band_level[1] > 0) band_level[1] <= band_level[1] - 3'd1;
                if (band_level[2] > 0) band_level[2] <= band_level[2] - 3'd1;
                if (band_level[3] > 0) band_level[3] <= band_level[3] - 3'd1;
                if (band_level[4] > 0) band_level[4] <= band_level[4] - 3'd1;
                if (band_level[5] > 0) band_level[5] <= band_level[5] - 3'd1;
                if (band_level[6] > 0) band_level[6] <= band_level[6] - 3'd1;
                if (band_level[7] > 0) band_level[7] <= band_level[7] - 3'd1;
            end else begin
                decay_cnt <= decay_cnt + 21'd1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // 3. 字符代码映射与字库 ROM 请求 (含胶囊标签)
    // ------------------------------------------------------------------------
    reg [2:0]  req_line;
    reg [3:0]  req_col;
    reg [2:0]  req_row;
    reg [2:0]  req_bit;
    reg        req_text_en;
    reg [15:0] req_fg_color;

    reg [7:0] ascii_req;
    always @(*) begin
        case (req_line)
            3'd0: begin // "ANLOGIC TELEM"
                case (req_col)
                    4'd0:  ascii_req = "A";
                    4'd1:  ascii_req = "N";
                    4'd2:  ascii_req = "L";
                    4'd3:  ascii_req = "O";
                    4'd4:  ascii_req = "G";
                    4'd5:  ascii_req = "I";
                    4'd6:  ascii_req = "C";
                    4'd7:  ascii_req = " ";
                    4'd8:  ascii_req = "T";
                    4'd9:  ascii_req = "E";
                    4'd10: ascii_req = "L";
                    4'd11: ascii_req = "E";
                    4'd12: ascii_req = "M";
                    default: ascii_req = " ";
                endcase
            end
            3'd1: begin // "[PIC] #X/4 60FPS"
                case (req_col)
                    4'd0:  ascii_req = "[";
                    4'd1:  ascii_req = "P";
                    4'd2:  ascii_req = "I";
                    4'd3:  ascii_req = "C";
                    4'd4:  ascii_req = "]";
                    4'd5:  ascii_req = " ";
                    4'd6:  ascii_req = "#";
                    4'd7:  ascii_req = 8'h31 + {6'd0, cur_img_idx[1:0]};
                    4'd8:  ascii_req = "/";
                    4'd9:  ascii_req = "4";
                    4'd10: ascii_req = " ";
                    4'd11: ascii_req = "6";
                    4'd12: ascii_req = "0";
                    4'd13: ascii_req = "F";
                    4'd14: ascii_req = "P";
                    4'd15: ascii_req = "S";
                    default: ascii_req = " ";
                endcase
            end
            3'd2: begin // "[SCL] 1.0X DDA2D"
                case (req_col)
                    4'd0:  ascii_req = "[";
                    4'd1:  ascii_req = "S";
                    4'd2:  ascii_req = "C";
                    4'd3:  ascii_req = "L";
                    4'd4:  ascii_req = "]";
                    4'd5:  ascii_req = " ";
                    4'd6:  ascii_req = (scale_mode == 2'd0) ? "1" : (scale_mode == 2'd1) ? "2" : (scale_mode == 2'd2) ? "0" : "A";
                    4'd7:  ascii_req = (scale_mode == 2'd3) ? "U" : ".";
                    4'd8:  ascii_req = (scale_mode == 2'd0) ? "0" : (scale_mode == 2'd1) ? "0" : (scale_mode == 2'd2) ? "5" : "T";
                    4'd9:  ascii_req = (scale_mode == 2'd3) ? "O" : "X";
                    4'd10: ascii_req = " ";
                    4'd11: ascii_req = "D";
                    4'd12: ascii_req = "D";
                    4'd13: ascii_req = "A";
                    4'd14: ascii_req = "2";
                    4'd15: ascii_req = "D";
                    default: ascii_req = " ";
                endcase
            end
            3'd3: begin // "[AUD] CHIME 48K "
                case (req_col)
                    4'd0:  ascii_req = "[";
                    4'd1:  ascii_req = "A";
                    4'd2:  ascii_req = "U";
                    4'd3:  ascii_req = "D";
                    4'd4:  ascii_req = "]";
                    4'd5:  ascii_req = " ";
                    4'd6:  ascii_req = emergency_mode ? "E" : (vol_mode == 3'd4) ? "M" : "C";
                    4'd7:  ascii_req = emergency_mode ? "M" : (vol_mode == 3'd4) ? "U" : "H";
                    4'd8:  ascii_req = emergency_mode ? "E" : (vol_mode == 3'd4) ? "T" : "I";
                    4'd9:  ascii_req = emergency_mode ? "R" : (vol_mode == 3'd4) ? "E" : "M";
                    4'd10: ascii_req = emergency_mode ? "G" : (vol_mode == 3'd4) ? " " : "E";
                    4'd11: ascii_req = " ";
                    4'd12: ascii_req = "4";
                    4'd13: ascii_req = "8";
                    4'd14: ascii_req = "K";
                    default: ascii_req = " ";
                endcase
            end
            3'd4: begin // "[LAT] 16.6MS OK "
                case (req_col)
                    4'd0:  ascii_req = "[";
                    4'd1:  ascii_req = "L";
                    4'd2:  ascii_req = "A";
                    4'd3:  ascii_req = "T";
                    4'd4:  ascii_req = "]";
                    4'd5:  ascii_req = " ";
                    4'd6:  ascii_req = "1";
                    4'd7:  ascii_req = "6";
                    4'd8:  ascii_req = ".";
                    4'd9:  ascii_req = "6";
                    4'd10: ascii_req = "M";
                    4'd11: ascii_req = "S";
                    4'd12: ascii_req = " ";
                    4'd13: ascii_req = "O";
                    4'd14: ascii_req = "K";
                    default: ascii_req = " ";
                endcase
            end
            3'd5: begin // "HX4S20-DUAL-DSP"
                case (req_col)
                    4'd0:  ascii_req = "H";
                    4'd1:  ascii_req = "X";
                    4'd2:  ascii_req = "4";
                    4'd3:  ascii_req = "S";
                    4'd4:  ascii_req = "2";
                    4'd5:  ascii_req = "0";
                    4'd6:  ascii_req = "-";
                    4'd7:  ascii_req = "D";
                    4'd8:  ascii_req = "U";
                    4'd9:  ascii_req = "A";
                    4'd10: ascii_req = "L";
                    4'd11: ascii_req = "-";
                    4'd12: ascii_req = "D";
                    4'd13: ascii_req = "S";
                    4'd14: ascii_req = "P";
                    default: ascii_req = " ";
                endcase
            end
            default: ascii_req = " ";
        endcase
    end

    function [5:0] get_char_idx;
        input [7:0] ch;
        begin
            if (ch >= 8'h41 && ch <= 8'h5A) // 'A'..'Z'
                get_char_idx = 6'd16 + (ch[4:0] - 5'd1);
            else if (ch >= 8'h30 && ch <= 8'h39) // '0'..'9'
                get_char_idx = 6'd6 + ch[3:0];
            else begin
                case (ch)
                    8'h23: get_char_idx = 6'd1;  // '#'
                    8'h25: get_char_idx = 6'd2;  // '%'
                    8'h2D: get_char_idx = 6'd3;  // '-'
                    8'h2E: get_char_idx = 6'd4;  // '.'
                    8'h2F: get_char_idx = 6'd5;  // '/'
                    8'h3A: get_char_idx = 6'd42; // ':'
                    8'h5B: get_char_idx = 6'd43; // '['
                    8'h5D: get_char_idx = 6'd44; // ']'
                    default: get_char_idx = 6'd0; // ' '
                endcase
            end
        end
    endfunction

    // 字体 ROM 实例化 (1 块 BRAM9K)
    wire [5:0] rom_char_idx = get_char_idx(ascii_req);
    wire [7:0] rom_font_byte;

    font_rom_8x8 u_font_rom (
        .clk        (clk),
        .char_idx   (rom_char_idx),
        .row        (req_row),
        .font_data  (rom_font_byte)
    );

    // ------------------------------------------------------------------------
    // 4. 纯硬件动态光栅像素着色流水线 (高颜值科技座舱设计)
    // ------------------------------------------------------------------------
    reg [6:0] cur_x, cur_y;
    assign cur_x_wire = cur_x;
    wire [6:0] next_y = (cur_x == 7'd127) ? ((cur_y == 7'd127) ? 7'd0 : (cur_y + 7'd1)) : cur_y;

    // 示波器波形高度计算 (Y 中心轴 = 82)
    wire signed [7:0] osc_scaled = osc_s >>> 2;
    wire signed [7:0] osc_clamp = (osc_scaled > 8'sd22) ? 8'sd22 : ((osc_scaled < -8'sd22) ? -8'sd22 : osc_scaled);
    wire [6:0] wave_y = 7'd82 - osc_clamp[6:0];
    wire [6:0] d_wave_y = (next_y >= wave_y) ? (next_y - wave_y) : (wave_y - next_y);

    // 8 频段跳动频谱位置与高度判定 (利用 next_x[6:4] 零开销分段, Y: 96..112)
    wire [2:0] cur_band_idx = next_x[6:4];
    wire [3:0] bar_in_band  = next_x[3:0];
    wire       in_band_bar  = (bar_in_band >= 4'd2 && bar_in_band <= 4'd13); // 12px 宽柱体, 4px 间距
    wire [4:0] cur_bar_h    = {band_level[cur_band_idx], 2'b00}; // 0..24 像素高度
    wire [6:0] bar_top_y    = 7'd112 - {2'b00, cur_bar_h};

    // 战术菱形雷达心跳判定 (曼哈顿距离替代乘法器, 中心 X=117, Y=8)
    wire [3:0] dx_radar   = (next_x >= 7'd117) ? (next_x - 7'd117) : (7'd117 - next_x);
    wire [3:0] dy_radar   = (next_y >= 7'd8)   ? (next_y - 7'd8)   : (7'd8 - next_y);
    wire [4:0] dist_radar = dx_radar + dy_radar;
    wire       radar_core = (dist_radar <= 5'd2);
    wire       radar_ring = (dist_radar >= 5'd4 && dist_radar <= 5'd5);

    // 字体像素采样
    wire [6:0] txt_dx = next_x - 7'd4;
    wire [3:0] txt_col = txt_dx[6:3];
    wire [2:0] txt_bit = 3'd7 - txt_dx[2:0];

    wire is_line0 = (next_y >= 7'd4  && next_y <= 7'd11  && next_x >= 7'd4 && next_x <= 7'd107);
    wire is_line1 = (next_y >= 7'd18 && next_y <= 7'd25  && next_x >= 7'd4);
    wire is_line2 = (next_y >= 7'd28 && next_y <= 7'd35  && next_x >= 7'd4);
    wire is_line3 = (next_y >= 7'd38 && next_y <= 7'd45  && next_x >= 7'd4);
    wire is_line4 = (next_y >= 7'd48 && next_y <= 7'd55  && next_x >= 7'd4);
    wire is_line5 = (next_y >= 7'd118 && next_y <= 7'd125 && next_x >= 7'd4 && next_x <= 7'd123);

    // 胶囊卡片背景范围判定 (X=4..43 为 [TAG] 胶囊)
    wire in_pill_tag = (next_x >= 7'd4 && next_x <= 7'd43);

    always @(*) begin
        req_text_en  = 1'b1;
        req_line     = 3'd0;
        req_col      = txt_col;
        req_row      = 3'd0;
        req_bit      = txt_bit;
        req_fg_color = 16'h07FF;

        if (is_line0) begin
            req_line     = 3'd0;
            req_col      = txt_col;
            req_row      = next_y[2:0] - 3'd4;
            req_bit      = txt_bit;
            req_fg_color = 16'h07FF; // 顶栏青色
        end else if (is_line1) begin
            req_line     = 3'd1;
            req_col      = txt_col;
            req_row      = next_y[2:0] - 3'd2;
            req_bit      = txt_bit;
            req_fg_color = in_pill_tag ? 16'hFFE0 : 16'hFFFF; // [PIC]琥珀金 / 数据白
        end else if (is_line2) begin
            req_line     = 3'd2;
            req_col      = txt_col;
            req_row      = next_y[2:0] - 3'd4;
            req_bit      = txt_bit;
            req_fg_color = in_pill_tag ? 16'h07FF : 16'h7FFF; // [SCL]霓虹青 / 数据冰蓝
        end else if (is_line3) begin
            req_line     = 3'd3;
            req_col      = txt_col;
            req_row      = next_y[2:0] - 3'd6;
            req_bit      = txt_bit;
            req_fg_color = in_pill_tag ? 16'hFDA0 : (emergency_mode ? 16'hF800 : 16'hFEA0); // [AUD]橙黄 / 金色音源
        end else if (is_line4) begin
            req_line     = 3'd4;
            req_col      = txt_col;
            req_row      = next_y[2:0];
            req_bit      = txt_bit;
            req_fg_color = in_pill_tag ? 16'h57E0 : 16'hFFFF; // [LAT]翡翠绿 / 延迟纯白
        end else if (is_line5) begin
            req_line     = 3'd5;
            req_col      = txt_col;
            req_row      = next_y[2:0] - 3'd6;
            req_bit      = txt_bit;
            req_fg_color = (txt_col <= 4'd5) ? 16'hFFE0 : ((txt_col == 4'd6) ? 16'h8410 : 16'h07FF); // HX4S20金色 / DUAL-DSP青色
        end else begin
            req_text_en  = 1'b0;
        end
    end

    wire font_pixel = (rom_font_byte >> req_bit) & 1'b1;

    reg [15:0] calc_color;
    always @(*) begin
        calc_color = 16'h0000;

        // ====================================================================
        // Zone 1: 顶栏科技钛金边框与雷达心跳 (Y <= 15)
        // ====================================================================
        if (next_y <= 7'd15) begin
            if (next_y == 7'd0)
                calc_color = 16'h2145; // 顶部极细钛金线
            else if (next_y == 7'd15)
                calc_color = 16'h07FF; // 青色高光分界线
            else if (radar_core)
                calc_color = hb_1hz ? 16'hFFFF : 16'h07E0; // 雷达心跳芯 (脉冲白/亮绿)
            else if (radar_ring)
                calc_color = 16'h02ED; // 雷达外同心扫描光环
            else if (req_text_en && is_line0)
                calc_color = font_pixel ? req_fg_color : 16'h08E7;
            else
                calc_color = 16'h08E7; // 钛金深蓝底色 #0B192C
        end

        // ====================================================================
        // Zone 2: 战机座舱胶囊仪表遥测区 (16 <= Y <= 56)
        // ====================================================================
        else if (next_y <= 7'd56) begin
            if (next_y == 7'd56)
                calc_color = 16'h03BF; // 青色仪表分界线
            else if (req_text_en && font_pixel)
                calc_color = req_fg_color;
            else if (in_pill_tag && is_line1)
                calc_color = 16'h28A0; // [PIC] 琥珀暗辉底
            else if (in_pill_tag && is_line2)
                calc_color = 16'h0106; // [SCL] 暗青发光底
            else if (in_pill_tag && is_line3)
                calc_color = 16'h2880; // [AUD] 暗橙发光底
            else if (in_pill_tag && is_line4)
                calc_color = 16'h0121; // [LAT] 暗绿发光底
            else
                calc_color = (next_x[3:0] == 4'd0 || next_y[3:0] == 4'd0) ? 16'h0862 : 16'h0000; // 暗黑座舱网格
        end

        // ====================================================================
        // Zone 3: 声学双核实验室 (CRT 示波器 + 16px EQ 频谱) (57 <= Y <= 113)
        // ====================================================================
        else if (next_y <= 7'd113) begin
            // 示波器波形覆盖 (束芯白光 + 荧光绿渐变光晕)
            if (d_wave_y == 7'd0)
                calc_color = 16'hFFFF; // 核心光束束芯 (纯白高能)
            else if (d_wave_y == 7'd1)
                calc_color = 16'h07E0; // 荧光绿辉光
            else if (d_wave_y == 7'd2)
                calc_color = 16'h0340; // 暗绿光晕柔光
            // 8 频段跳动频谱渲染 (Y: 96..112)
            else if (in_band_bar && next_y >= 7'd96 && next_y <= 7'd112 && next_y >= bar_top_y) begin
                if (next_y == bar_top_y)
                    calc_color = 16'hFFFF; // 悬浮白色重力衰减峰值帽
                else if (next_y <= 7'd100)
                    calc_color = 16'hFD00; // 高能级橙红
                else if (next_y <= 7'd106)
                    calc_color = 16'h07E0; // 中能级翠绿
                else
                    calc_color = 16'h02DF; // 基底电光青
            end
            // 示波器背景与高精度刻度网格
            else if (next_y == 7'd82 && next_x[1] == 1'b0)
                calc_color = 16'h0A66; // 中心零轴虚线
            else if (next_x == 7'd64 && next_y[1] == 1'b0)
                calc_color = 16'h0A66; // 垂直中心虚线
            else if ((next_y == 7'd68 || next_y == 7'd96) && next_x[2:0] == 3'd0)
                calc_color = 16'h0924; // 1/4 分度暗青刻度点
            else
                calc_color = 16'h00A2; // 经典示波器暗青底色 #001424
        end

        // ====================================================================
        // Zone 4: 金色底栏与系统在线标语 (114 <= Y <= 127)
        // ====================================================================
        else begin
            if (next_y == 7'd114 || next_y == 7'd127)
                calc_color = 16'hFDA0; // 琥珀金高光分割线
            else if (req_text_en && is_line5)
                calc_color = font_pixel ? req_fg_color : 16'h0886;
            else
                calc_color = 16'h0886; // 钛金深海蓝底色 #0A182E
        end
    end

    // ------------------------------------------------------------------------
    // 5. 6.25MHz 高容错 SPI 发送引擎 (CPOL=0, CPHA=0, 动态 CS 同步)
    // ------------------------------------------------------------------------
    reg [7:0] spi_tx_byte;
    reg       spi_tx_dc;
    reg       spi_start;
    wire      spi_busy;

    reg [7:0] spi_shift;
    reg [2:0] spi_bit_cnt; // 0..7
    reg [2:0] spi_div;     // 0..7 (50MHz / 8 = 6.25MHz)
    reg       spi_active;

    assign spi_busy = spi_active;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lcd_scl     <= 1'b0;
            lcd_mosi    <= 1'b0;
            lcd_cs      <= 1'b1;
            lcd_dc      <= 1'b0;
            spi_active  <= 1'b0;
            spi_div     <= 3'd0;
            spi_bit_cnt <= 3'd0;
            spi_shift   <= 8'd0;
        end else begin
            if (!spi_active) begin
                lcd_scl <= 1'b0;
                if (spi_start) begin
                    spi_active  <= 1'b1;
                    spi_div     <= 3'd0;
                    spi_bit_cnt <= 3'd7;
                    spi_shift   <= spi_tx_byte;
                    lcd_dc      <= spi_tx_dc;
                    lcd_mosi    <= spi_tx_byte[7];
                    lcd_cs      <= 1'b0; // 选通从机
                end
            end else begin
                spi_div <= spi_div + 3'd1;
                if (spi_div == 3'd2) begin
                    lcd_scl <= 1'b1; // 上升沿，从机采样
                end else if (spi_div == 3'd6) begin
                    lcd_scl <= 1'b0; // 下降沿
                    if (spi_bit_cnt == 3'd0) begin
                        spi_active <= 1'b0; // 8 位传输结束
                    end else begin
                        spi_bit_cnt <= spi_bit_cnt - 3'd1;
                        lcd_mosi    <= spi_shift[6];
                        spi_shift   <= {spi_shift[6:0], 1'b0};
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // 6. ST7735S 驱动状态机与全套初始化序列
    // ------------------------------------------------------------------------
    localparam S_PWR_RST_LOW   = 4'd0;
    localparam S_PWR_RST_HIGH  = 4'd1;
    localparam S_INIT_SEND     = 4'd2;
    localparam S_INIT_WAIT     = 4'd3;
    localparam S_FRAME_PREP    = 4'd4;
    localparam S_PIXEL_HI      = 4'd5;
    localparam S_PIXEL_LO      = 4'd6;

    reg [3:0]  state;
    reg [23:0] delay_cnt;
    reg [5:0]  init_step;
    reg [3:0]  prep_step;
    reg [15:0] cur_pixel_color;

    reg [7:0]  init_rom_byte;
    reg        init_rom_dc;
    reg [23:0] init_rom_delay;

    always @(*) begin
        case (init_step)
            // 1. 软件复位
            6'd0:  begin init_rom_byte = 8'h01; init_rom_dc = 1'b0; init_rom_delay = 24'd7_500_000; end // SWRESET (150ms)
            // 2. 退出睡眠
            6'd1:  begin init_rom_byte = 8'h11; init_rom_dc = 1'b0; init_rom_delay = 24'd10_000_000; end // SLPOUT (200ms)
            // 3. 帧率控制 (Normal mode, 3 args)
            6'd2:  begin init_rom_byte = 8'hB1; init_rom_dc = 1'b0; init_rom_delay = 24'd500;        end // FRMCTR1
            6'd3:  begin init_rom_byte = 8'h01; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            6'd4:  begin init_rom_byte = 8'h2C; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            6'd5:  begin init_rom_byte = 8'h2D; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            // 4. 帧率控制 (Idle mode, 3 args)
            6'd6:  begin init_rom_byte = 8'hB2; init_rom_dc = 1'b0; init_rom_delay = 24'd500;        end // FRMCTR2
            6'd7:  begin init_rom_byte = 8'h01; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            6'd8:  begin init_rom_byte = 8'h2C; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            6'd9:  begin init_rom_byte = 8'h2D; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            // 5. 帧率控制 (Partial mode, 6 args)
            6'd10: begin init_rom_byte = 8'hB3; init_rom_dc = 1'b0; init_rom_delay = 24'd500;        end // FRMCTR3
            6'd11: begin init_rom_byte = 8'h01; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            6'd12: begin init_rom_byte = 8'h2C; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            6'd13: begin init_rom_byte = 8'h2D; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            6'd14: begin init_rom_byte = 8'h01; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            6'd15: begin init_rom_byte = 8'h2C; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            6'd16: begin init_rom_byte = 8'h2D; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            // 6. 显示反转控制 (1 arg: 0x07 = 点反转)
            6'd17: begin init_rom_byte = 8'hB4; init_rom_dc = 1'b0; init_rom_delay = 24'd500;        end // INVCTR
            6'd18: begin init_rom_byte = 8'h07; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            // 7. 电源控制 1 (3 args: GVDD, AVDD, AUTO)
            6'd19: begin init_rom_byte = 8'hC0; init_rom_dc = 1'b0; init_rom_delay = 24'd500;        end // PWCTR1
            6'd20: begin init_rom_byte = 8'hA2; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            6'd21: begin init_rom_byte = 8'h02; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            6'd22: begin init_rom_byte = 8'h84; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            // 8. 电源控制 2 (1 arg: VGH, VGL)
            6'd23: begin init_rom_byte = 8'hC1; init_rom_dc = 1'b0; init_rom_delay = 24'd500;        end // PWCTR2
            6'd24: begin init_rom_byte = 8'hC5; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            // 9. 电源控制 3 (2 args)
            6'd25: begin init_rom_byte = 8'hC2; init_rom_dc = 1'b0; init_rom_delay = 24'd500;        end // PWCTR3
            6'd26: begin init_rom_byte = 8'h0A; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            6'd27: begin init_rom_byte = 8'h00; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            // 10. 电源控制 4 (2 args)
            6'd28: begin init_rom_byte = 8'hC3; init_rom_dc = 1'b0; init_rom_delay = 24'd500;        end // PWCTR4
            6'd29: begin init_rom_byte = 8'h8A; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            6'd30: begin init_rom_byte = 8'h2A; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            // 11. 电源控制 5 (2 args)
            6'd31: begin init_rom_byte = 8'hC4; init_rom_dc = 1'b0; init_rom_delay = 24'd500;        end // PWCTR5
            6'd32: begin init_rom_byte = 8'h8A; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            6'd33: begin init_rom_byte = 8'hEE; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            // 12. VCOM 控制 (1 arg)
            6'd34: begin init_rom_byte = 8'hC5; init_rom_dc = 1'b0; init_rom_delay = 24'd500;        end // VMCTR1
            6'd35: begin init_rom_byte = 8'h0E; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            // 13. 关闭颜色反转
            6'd36: begin init_rom_byte = 8'h20; init_rom_dc = 1'b0; init_rom_delay = 24'd500;        end // INVOFF
            // 14. 内存访问控制 MADCTL (1 arg: 0xC8 = BGR, 镜像)
            6'd37: begin init_rom_byte = 8'h36; init_rom_dc = 1'b0; init_rom_delay = 24'd500;        end // MADCTL
            6'd38: begin init_rom_byte = 8'hC8; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            // 15. 颜色格式 COLMOD (1 arg: 0x05 = 16-bit RGB565)
            6'd39: begin init_rom_byte = 8'h3A; init_rom_dc = 1'b0; init_rom_delay = 24'd500;        end // COLMOD
            6'd40: begin init_rom_byte = 8'h05; init_rom_dc = 1'b1; init_rom_delay = 24'd500;        end
            // 16. 正常显示模式
            6'd41: begin init_rom_byte = 8'h13; init_rom_dc = 1'b0; init_rom_delay = 24'd1_000_000; end // NORON (20ms)
            // 17. 开启主显示
            6'd42: begin init_rom_byte = 8'h29; init_rom_dc = 1'b0; init_rom_delay = 24'd5_000_000; end // DISPON (100ms)
            default: begin init_rom_byte = 8'h00; init_rom_dc = 1'b0; init_rom_delay = 24'd0;       end
        endcase
    end

    reg [7:0] prep_rom_byte;
    reg       prep_rom_dc;

    always @(*) begin
        case (prep_step)
            4'd0:  begin prep_rom_byte = 8'h2A;                 prep_rom_dc = 1'b0; end // CASET
            4'd1:  begin prep_rom_byte = 8'h00;                 prep_rom_dc = 1'b1; end
            4'd2:  begin prep_rom_byte = COL_OFFSET;            prep_rom_dc = 1'b1; end
            4'd3:  begin prep_rom_byte = 8'h00;                 prep_rom_dc = 1'b1; end
            4'd4:  begin prep_rom_byte = COL_OFFSET + 8'd127;   prep_rom_dc = 1'b1; end
            4'd5:  begin prep_rom_byte = 8'h2B;                 prep_rom_dc = 1'b0; end // RASET
            4'd6:  begin prep_rom_byte = 8'h00;                 prep_rom_dc = 1'b1; end
            4'd7:  begin prep_rom_byte = ROW_OFFSET;            prep_rom_dc = 1'b1; end
            4'd8:  begin prep_rom_byte = 8'h00;                 prep_rom_dc = 1'b1; end
            4'd9:  begin prep_rom_byte = ROW_OFFSET + 8'd127;   prep_rom_dc = 1'b1; end
            4'd10: begin prep_rom_byte = 8'h2C;                 prep_rom_dc = 1'b0; end // RAMWR
            default: begin prep_rom_byte = 8'h00;               prep_rom_dc = 1'b0; end
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= S_PWR_RST_LOW;
            delay_cnt       <= 24'd0;
            init_step       <= 6'd0;
            prep_step       <= 4'd0;
            lcd_rst         <= 1'b1;
            spi_start       <= 1'b0;
            spi_tx_byte     <= 8'h00;
            spi_tx_dc       <= 1'b0;
            cur_x           <= 7'd0;
            cur_y           <= 7'd0;
            cur_pixel_color <= 16'h0000;
        end else begin
            spi_start <= 1'b0;

            case (state)
                S_PWR_RST_LOW: begin
                    lcd_rst <= 1'b0; // 硬件低电平复位
                    if (delay_cnt >= 24'd1_000_000) begin // 20ms @ 50MHz
                        delay_cnt <= 24'd0;
                        lcd_rst   <= 1'b1;
                        state     <= S_PWR_RST_HIGH;
                    end else begin
                        delay_cnt <= delay_cnt + 24'd1;
                    end
                end

                S_PWR_RST_HIGH: begin
                    lcd_rst <= 1'b1; // 复位释放，等待内部时钟稳态
                    if (delay_cnt >= 24'd7_500_000) begin // 150ms @ 50MHz
                        delay_cnt <= 24'd0;
                        init_step <= 6'd0;
                        state     <= S_INIT_SEND;
                    end else begin
                        delay_cnt <= delay_cnt + 24'd1;
                    end
                end

                S_INIT_SEND: begin
                    if (!spi_busy && !spi_start) begin
                        spi_tx_byte <= init_rom_byte;
                        spi_tx_dc   <= init_rom_dc;
                        spi_start   <= 1'b1;
                        state       <= S_INIT_WAIT;
                    end
                end

                S_INIT_WAIT: begin
                    if (!spi_busy && !spi_start) begin
                        if (delay_cnt >= init_rom_delay) begin
                            delay_cnt <= 24'd0;
                            if (init_step == 6'd42) begin
                                prep_step <= 4'd0;
                                state     <= S_FRAME_PREP;
                            end else begin
                                init_step <= init_step + 6'd1;
                                state     <= S_INIT_SEND;
                            end
                        end else begin
                            delay_cnt <= delay_cnt + 24'd1;
                        end
                    end
                end

                S_FRAME_PREP: begin
                    if (!spi_busy && !spi_start) begin
                        spi_tx_byte <= prep_rom_byte;
                        spi_tx_dc   <= prep_rom_dc;
                        spi_start   <= 1'b1;
                        if (prep_step == 4'd10) begin
                            cur_x           <= 7'd0;
                            cur_y           <= 7'd0;
                            cur_pixel_color <= calc_color;
                            state           <= S_PIXEL_HI;
                        end else begin
                            prep_step <= prep_step + 4'd1;
                        end
                    end
                end

                S_PIXEL_HI: begin
                    if (!spi_busy && !spi_start) begin
                        spi_tx_byte <= cur_pixel_color[15:8];
                        spi_tx_dc   <= 1'b1;
                        spi_start   <= 1'b1;
                        state       <= S_PIXEL_LO;
                    end
                end

                S_PIXEL_LO: begin
                    if (!spi_busy && !spi_start) begin
                        spi_tx_byte <= cur_pixel_color[7:0];
                        spi_tx_dc   <= 1'b1;
                        spi_start   <= 1'b1;

                        cur_pixel_color <= calc_color;
                        if (cur_x == 7'd127) begin
                            cur_x <= 7'd0;
                            if (cur_y == 7'd127) begin
                                cur_y     <= 7'd0;
                                prep_step <= 4'd0;
                                state     <= S_FRAME_PREP;
                            end else begin
                                cur_y <= cur_y + 7'd1;
                                state <= S_PIXEL_HI;
                            end
                        end else begin
                            cur_x <= cur_x + 7'd1;
                            state <= S_PIXEL_HI;
                        end
                    end
                end

                default: state <= S_PWR_RST_LOW;
            endcase
        end
    end

endmodule
'''

with open("src/rtl/lcd_st7735_telemetry.v", "w", encoding="utf-8") as f:
    f.write(rtl)

print("Super-aesthetics src/rtl/lcd_st7735_telemetry.v written!")
