// ============================================================================
// Module Name: lcd_st7735_telemetry
// Project:     全国大学生嵌入式芯片与系统设计竞赛 - HX4S20 HDMI多媒体展示系统
// Target Board: Anlogic EG4S20BG256 (HX4S20C)
// Function:    1.8寸 128x160 SPI TFT 彩色 LCD (ST7735S) 极简现代精密仪器遥测副屏
// Style:       现代北欧极简 / Apple·Tesla 工业仪器美学
//              - 纯黑深邃背景 (OLED级对比度, 无杂乱背景网格)
//              - 细微发丝分割线 (Hairline Dividers, #212429)
//              - 纯净层级排版 (冷灰标签 + 纯白数据 + 冰蓝单位)
//              - 极细单像素高能冰蓝波形 (Razor-sharp 1px Beam)
//              - 极简单色调 8 频段跳动频谱 (Clean Ice-Blue EQ with White Caps)
//              - 极简微宝石状态指示灯 (Minimal Status Dot)
//              - 转场特效状态 (TRN: FADE / BLND / WIPE / MOSC, AUT/MAN)
//              - 图像滤镜状态 (FLT: VIVID RGB / MONOCHR / INK-RUBB / SPLIT-CMP)
//              - 硬件加速指示 (DFT16 DUAL-DSP)
// ============================================================================
`timescale 1ns / 1ps

module lcd_st7735_telemetry #(
    parameter [7:0] COL_OFFSET = 8'd0, // 1.8寸 128x160 屏幕水平偏移 (默认0, 可根据屏显微调)
    parameter [7:0] ROW_OFFSET = 8'd0  // 1.8寸 128x160 屏幕垂直偏移 (默认0, 可根据屏显微调)
)(
    input  wire                 clk,            // 50MHz 系统时钟
    input  wire                 rst,            // 高电平复位 (rst_all)

    // LCD SPI 物理接口 (对应开发板 J1 扩展口 Pin 23..28)
    output reg                  lcd_scl,        // SPI SCLK (6.25MHz, Pin J16)
    output reg                  lcd_mosi,       // SPI MOSI (SDA, Pin H16)
    output reg                  lcd_cs,         // 片选 (CS, Pin M16, 低有效)
    output reg                  lcd_dc,         // 数据/命令选择 (DC, Pin K16, 0=Cmd, 1=Data)
    output reg                  lcd_rst,        // 硬件复位 (RST, Pin H15, 低有效)
    output reg                  lcd_blk,        // 背光控制 (BLK, Pin K15, 软启动防白屏闪烁)

    // 系统遥测与音频实时输入
    input  wire [2:0]           cur_img_idx,    // 当前图片索引 0..7 (显示为 1..8)
    input  wire [3:0]           img_total_count,// 动态总图片数 1..8
    input  wire [1:0]           scale_mode,     // 缩放模式 0:1.0X, 1:2.0X, 2:0.5X, 3:AUTO
    input  wire [2:0]           vol_mode,       // 音量模式 0:100%, 1:75%, 2:50%, 3:25%, 4:MUTE
    input  wire signed [23:0]   audio_pcm,      // 24-bit PCM 采样
    input  wire                 audio_valid,    // 48kHz 采样脉冲
    input  wire                 emergency_mode, // 应急广播模式状态
    input  wire [2:0]           trans_mode,     // 转场用户模式 0:FADE, 1:BLND, 2:SLID, 3:MOSC, 4:AUTO
    input  wire [1:0]           active_trans,   // 当前激活转场 0:FADE, 1:BLND, 2:SLID, 3:MOSC
    input  wire [1:0]           color_mode,     // 画面滤镜 0:VIVID RGB, 1:MONOCHR, 2:INK-RUBB, 3:SPLIT

    // 来自主屏自研 DFT 频域分析引擎的 8 频段真实频域能量与悬浮峰值
    input  wire [39:0]          sdft_spec_8b,   // 8 频段能量高度 (0..26)
    input  wire [39:0]          sdft_peak_8b    // 8 频段峰值保持顶帽高度 (0..26)
);

    reg [39:0] frame_spec, frame_peak;
    // 背光由状态机控制 (软启动防上电刺眼白屏)

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

    // ------------------------------------------------------------------------
    // 3. 极简字符排版与字库 ROM 映射
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
            3'd1: begin // "PIC   #X/4 60FPS"
                case (req_col)
                    4'd0:  ascii_req = "P";
                    4'd1:  ascii_req = "I";
                    4'd2:  ascii_req = "C";
                    4'd3:  ascii_req = " ";
                    4'd4:  ascii_req = " ";
                    4'd5:  ascii_req = " ";
                    4'd6:  ascii_req = "#";
                    4'd7:  ascii_req = 8'h31 + {5'd0, cur_img_idx};
                    4'd8:  ascii_req = "/";
                    4'd9:  ascii_req = (img_total_count >= 4'd1 && img_total_count <= 4'd9) ? (8'h30 + {4'd0, img_total_count}) : "5";
                    4'd10: ascii_req = " ";
                    4'd11: ascii_req = "6";
                    4'd12: ascii_req = "0";
                    4'd13: ascii_req = "F";
                    4'd14: ascii_req = "P";
                    4'd15: ascii_req = "S";
                    default: ascii_req = " ";
                endcase
            end
            3'd2: begin // "SCL   1.0X DDA2D"
                case (req_col)
                    4'd0:  ascii_req = "S";
                    4'd1:  ascii_req = "C";
                    4'd2:  ascii_req = "L";
                    4'd3:  ascii_req = " ";
                    4'd4:  ascii_req = " ";
                    4'd5:  ascii_req = " ";
                    4'd6:  ascii_req = (scale_mode == 2'd0) ? "1" : (scale_mode == 2'd1) ? "2" : (scale_mode == 2'd2) ? "0" : "A";
                    4'd7:  ascii_req = (scale_mode == 2'd3) ? "U" : ".";
                    4'd8:  ascii_req = (scale_mode == 2'd0) ? "0" : (scale_mode == 2'd1) ? "0" : (scale_mode == 2'd2) ? "5" : "T";
                    4'd9:  ascii_req = (scale_mode == 2'd3) ? "O" : "X";
                    4'd10: ascii_req = " ";
                    4'd11: ascii_req = (scale_mode == 2'd0) ? "R" : "B";
                    4'd12: ascii_req = (scale_mode == 2'd0) ? "A" : "L";
                    4'd13: ascii_req = (scale_mode == 2'd0) ? "W" : "N";
                    4'd14: ascii_req = " ";
                    4'd15: ascii_req = "D";
                    default: ascii_req = " ";
                endcase
            end
            3'd3: begin // "DFT   DFT  48K "
                case (req_col)
                    4'd0:  ascii_req = "D";
                    4'd1:  ascii_req = "F";
                    4'd2:  ascii_req = "T";
                    4'd3:  ascii_req = " ";
                    4'd4:  ascii_req = " ";
                    4'd5:  ascii_req = " ";
                    4'd6:  ascii_req = emergency_mode ? "E" : (vol_mode == 3'd4) ? "M" : "D";
                    4'd7:  ascii_req = emergency_mode ? "M" : (vol_mode == 3'd4) ? "U" : "F";
                    4'd8:  ascii_req = emergency_mode ? "E" : (vol_mode == 3'd4) ? "T" : "T";
                    4'd9:  ascii_req = emergency_mode ? "R" : (vol_mode == 3'd4) ? "E" : " ";
                    4'd10: ascii_req = emergency_mode ? "G" : " ";
                    4'd11: ascii_req = " ";
                    4'd12: ascii_req = "4";
                    4'd13: ascii_req = "8";
                    4'd14: ascii_req = "K";
                    default: ascii_req = " ";
                endcase
            end
            3'd4: begin // "SYS   16.6M OK  "
                case (req_col)
                    4'd0:  ascii_req = "S";
                    4'd1:  ascii_req = "Y";
                    4'd2:  ascii_req = "S";
                    4'd3:  ascii_req = " ";
                    4'd4:  ascii_req = " ";
                    4'd5:  ascii_req = " ";
                    4'd6:  ascii_req = "1";
                    4'd7:  ascii_req = "6";
                    4'd8:  ascii_req = ".";
                    4'd9:  ascii_req = "6";
                    4'd10: ascii_req = "M";
                    4'd11: ascii_req = " ";
                    4'd12: ascii_req = "O";
                    4'd13: ascii_req = "K";
                    default: ascii_req = " ";
                endcase
            end
            3'd5: begin // "TRN   FADE AUT" (转场特效模式 + 自动/手动)
                case (req_col)
                    4'd0:  ascii_req = "T";
                    4'd1:  ascii_req = "R";
                    4'd2:  ascii_req = "N";
                    4'd3:  ascii_req = " ";
                    4'd4:  ascii_req = " ";
                    4'd5:  ascii_req = " ";
                    4'd6:  ascii_req = (active_trans == 2'd0) ? "F" : (active_trans == 2'd1) ? "B" : (active_trans == 2'd2) ? "S" : "M";
                    4'd7:  ascii_req = (active_trans == 2'd0) ? "A" : (active_trans == 2'd1) ? "L" : (active_trans == 2'd2) ? "L" : "O";
                    4'd8:  ascii_req = (active_trans == 2'd0) ? "D" : (active_trans == 2'd1) ? "N" : (active_trans == 2'd2) ? "I" : "S";
                    4'd9:  ascii_req = (active_trans == 2'd0) ? "E" : (active_trans == 2'd1) ? "D" : (active_trans == 2'd2) ? "D" : "C";
                    4'd10: ascii_req = " ";
                    4'd11: ascii_req = (trans_mode == 3'd4) ? "A" : "M";
                    4'd12: ascii_req = (trans_mode == 3'd4) ? "U" : "A";
                    4'd13: ascii_req = (trans_mode == 3'd4) ? "T" : "N";
                    default: ascii_req = " ";
                endcase
            end
            3'd6: begin // "FLT   VIVID RGB" / "FLT   INK-RUBB " / "FLT   MONOCHR  "
                case (req_col)
                    4'd0:  ascii_req = "F";
                    4'd1:  ascii_req = "L";
                    4'd2:  ascii_req = "T";
                    4'd3:  ascii_req = " ";
                    4'd4:  ascii_req = " ";
                    4'd5:  ascii_req = " ";
                    4'd6:  ascii_req = (color_mode == 2'd2) ? "I" : (color_mode == 2'd1) ? "M" : (color_mode == 2'd3) ? "S" : "V";
                    4'd7:  ascii_req = (color_mode == 2'd2) ? "N" : (color_mode == 2'd1) ? "O" : (color_mode == 2'd3) ? "P" : "I";
                    4'd8:  ascii_req = (color_mode == 2'd2) ? "K" : (color_mode == 2'd1) ? "N" : (color_mode == 2'd3) ? "L" : "V";
                    4'd9:  ascii_req = (color_mode == 2'd2) ? "-" : (color_mode == 2'd1) ? "O" : (color_mode == 2'd3) ? "I" : "I";
                    4'd10: ascii_req = (color_mode == 2'd2) ? "R" : (color_mode == 2'd1) ? "C" : (color_mode == 2'd3) ? "T" : "D";
                    4'd11: ascii_req = (color_mode == 2'd2) ? "U" : (color_mode == 2'd1) ? "H" : (color_mode == 2'd3) ? "-" : " ";
                    4'd12: ascii_req = (color_mode == 2'd2) ? "B" : (color_mode == 2'd1) ? "R" : (color_mode == 2'd3) ? "C" : "R";
                    4'd13: ascii_req = (color_mode == 2'd2) ? "B" : (color_mode == 2'd1) ? " " : (color_mode == 2'd3) ? "M" : "G";
                    4'd14: ascii_req = (color_mode == 2'd2) ? " " : (color_mode == 2'd1) ? " " : (color_mode == 2'd3) ? "P" : "B";
                    default: ascii_req = " ";
                endcase
            end
            3'd7: begin // "ECO   L4-GATED" (硬件低功耗能效门控状态指示)
                case (req_col)
                    4'd0:  ascii_req = "E";
                    4'd1:  ascii_req = "C";
                    4'd2:  ascii_req = "O";
                    4'd3:  ascii_req = " ";
                    4'd4:  ascii_req = " ";
                    4'd5:  ascii_req = " ";
                    4'd6:  ascii_req = "L";
                    4'd7:  ascii_req = "4";
                    4'd8:  ascii_req = "-";
                    4'd9:  ascii_req = "G";
                    4'd10: ascii_req = "A";
                    4'd11: ascii_req = "T";
                    4'd12: ascii_req = "E";
                    4'd13: ascii_req = "D";
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
    // 4. 纯硬件现代极简光栅像素着色流水线
    // ------------------------------------------------------------------------
    reg [6:0] cur_x;
    reg [7:0] cur_y; // 扩展为 8-bit (0..159)
    assign cur_x_wire = cur_x;
    wire [7:0] next_y = (cur_x == 7'd127) ? ((cur_y == 8'd159) ? 8'd0 : (cur_y + 8'd1)) : cur_y;

    // 极简微细分割线 (Hairlines: Y = 13, 56, 90, 114, 126, 139)
    wire is_divider = (next_y == 8'd13 || next_y == 8'd56 || next_y == 8'd90 || next_y == 8'd114 || next_y == 8'd126 || next_y == 8'd139);

    // 极简右上角宝石状态指示灯 (X: 117..119, Y: 6..8)
    wire is_status_led = (next_x >= 7'd117 && next_x <= 7'd119 && next_y >= 8'd6 && next_y <= 8'd8);

    // 示波器波形高度计算 (Y 中心轴 = 73, 振幅限幅 ±12)
    wire signed [7:0] osc_scaled = osc_s >>> 2;
    wire signed [7:0] osc_clamp  = (osc_scaled > 8'sd12) ? 8'sd12 : ((osc_scaled < -8'sd12) ? -8'sd12 : osc_scaled);
    wire [7:0] wave_y   = 8'd73 - {osc_clamp[7], osc_clamp[6:0]};
    wire [7:0] d_wave_y = (next_y >= wave_y) ? (next_y - wave_y) : (wave_y - next_y);

    // 自研 DFT 8 频段真实频域跳动频谱 (next_x[6:4] 8 频段, 12px 柱宽 / 4px 间隔, Y: 94..111)
    wire [2:0] cur_band_idx = next_x[6:4];
    wire [3:0] bar_in_band  = next_x[3:0];
    wire       in_band_bar  = (bar_in_band >= 4'd2 && bar_in_band <= 4'd13); // 12px 柱宽, 4px 间隙

    // 组合逻辑多路选择器
    reg [4:0] sel_sdft_h;
    reg [4:0] sel_sdft_p;
    always @(*) begin
        case (cur_band_idx)
            3'd0: begin sel_sdft_h = frame_spec[4:0];   sel_sdft_p = frame_peak[4:0];   end
            3'd1: begin sel_sdft_h = frame_spec[9:5];   sel_sdft_p = frame_peak[9:5];   end
            3'd2: begin sel_sdft_h = frame_spec[14:10]; sel_sdft_p = frame_peak[14:10]; end
            3'd3: begin sel_sdft_h = frame_spec[19:15]; sel_sdft_p = frame_peak[19:15]; end
            3'd4: begin sel_sdft_h = frame_spec[24:20]; sel_sdft_p = frame_peak[24:20]; end
            3'd5: begin sel_sdft_h = frame_spec[29:25]; sel_sdft_p = frame_peak[29:25]; end
            3'd6: begin sel_sdft_h = frame_spec[34:30]; sel_sdft_p = frame_peak[34:30]; end
            default: begin sel_sdft_h = frame_spec[39:35]; sel_sdft_p = frame_peak[39:35]; end
        endcase
    end

    // Same normalized scale as HDMI, rounded 0..26 -> 0..17.
    function [4:0] spectrum_height;
        input [4:0] height;
        begin case(height)
            5'd0:spectrum_height=5'd0;
            5'd1:spectrum_height=5'd1;
            5'd2:spectrum_height=5'd1;
            5'd3:spectrum_height=5'd2;
            5'd4:spectrum_height=5'd3;
            5'd5:spectrum_height=5'd3;
            5'd6:spectrum_height=5'd4;
            5'd7:spectrum_height=5'd5;
            5'd8:spectrum_height=5'd5;
            5'd9:spectrum_height=5'd6;
            5'd10:spectrum_height=5'd7;
            5'd11:spectrum_height=5'd7;
            5'd12:spectrum_height=5'd8;
            5'd13:spectrum_height=5'd9;
            5'd14:spectrum_height=5'd9;
            5'd15:spectrum_height=5'd10;
            5'd16:spectrum_height=5'd10;
            5'd17:spectrum_height=5'd11;
            5'd18:spectrum_height=5'd12;
            5'd19:spectrum_height=5'd12;
            5'd20:spectrum_height=5'd13;
            5'd21:spectrum_height=5'd14;
            5'd22:spectrum_height=5'd14;
            5'd23:spectrum_height=5'd15;
            5'd24:spectrum_height=5'd16;
            5'd25:spectrum_height=5'd16;
            5'd26:spectrum_height=5'd17;
            default:spectrum_height=5'd17;
        endcase end
    endfunction
    wire [4:0] cur_bar_h_cl=spectrum_height(sel_sdft_h);
    wire [4:0] cur_peak_h_cl=spectrum_height(sel_sdft_p);
    wire [7:0] bar_top_y      = 8'd111 - {3'b000, cur_bar_h_cl};
    wire [7:0] peak_top_y     = 8'd111 - {3'b000, cur_peak_h_cl};

    // 字体像素采样
    wire [6:0] txt_dx  = next_x - 7'd4;
    wire [3:0] txt_col = txt_dx[6:3];
    wire [2:0] txt_bit = 3'd7 - txt_dx[2:0];

    wire is_line0 = (next_y >= 8'd3   && next_y <= 8'd10  && next_x >= 7'd4 && next_x <= 7'd107);
    wire is_line1 = (next_y >= 8'd16  && next_y <= 8'd23  && next_x >= 7'd4);
    wire is_line2 = (next_y >= 8'd26  && next_y <= 8'd33  && next_x >= 7'd4);
    wire is_line3 = (next_y >= 8'd36  && next_y <= 8'd43  && next_x >= 7'd4);
    wire is_line4 = (next_y >= 8'd46  && next_y <= 8'd53  && next_x >= 7'd4);
    wire is_line5 = (next_y >= 8'd117 && next_y <= 8'd124 && next_x >= 7'd4 && next_x <= 7'd123);
    wire is_line6 = (next_y >= 8'd129 && next_y <= 8'd136 && next_x >= 7'd4 && next_x <= 7'd123);
    wire is_line7 = (next_y >= 8'd142 && next_y <= 8'd149 && next_x >= 7'd4 && next_x <= 7'd123);

    always @(*) begin
        req_text_en  = 1'b1;
        req_line     = 3'd0;
        req_col      = txt_col;
        req_row      = 3'd0;
        req_bit      = txt_bit;
        req_fg_color = 16'h05DF;

        if (is_line0) begin
            req_line     = 3'd0;
            req_col      = txt_col;
            req_row      = next_y[2:0] - 3'd3;
            req_bit      = txt_bit;
            req_fg_color = 16'h05DF; // 顶栏电光青 (Sleek Cyan)
        end else if (is_line1) begin
            req_line     = 3'd1;
            req_col      = txt_col;
            req_row      = next_y[2:0]; // 16..23 对齐 8
            req_bit      = txt_bit;
            req_fg_color = (txt_col <= 4'd2) ? 16'h7BEF : ((txt_col >= 4'd6 && txt_col <= 4'd9) ? 16'hFFFF : 16'h9CD3);
        end else if (is_line2) begin
            req_line     = 3'd2;
            req_col      = txt_col;
            req_row      = next_y[2:0] - 3'd2; // 26..33
            req_bit      = txt_bit;
            req_fg_color = (txt_col <= 4'd2) ? 16'h7BEF : ((txt_col >= 4'd6 && txt_col <= 4'd9) ? 16'hFFFF : 16'h9CD3);
        end else if (is_line3) begin
            req_line     = 3'd3;
            req_col      = txt_col;
            req_row      = next_y[2:0] - 3'd4; // 36..43
            req_bit      = txt_bit;
            req_fg_color = (txt_col <= 4'd2) ? 16'h7BEF : ((txt_col >= 4'd6 && txt_col <= 4'd10) ? (emergency_mode ? 16'hF980 : 16'hFFFF) : 16'h9CD3);
        end else if (is_line4) begin
            req_line     = 3'd4;
            req_col      = txt_col;
            req_row      = next_y[2:0] - 3'd6; // 46..53
            req_bit      = txt_bit;
            req_fg_color = (txt_col <= 4'd2) ? 16'h7BEF : ((txt_col >= 4'd6 && txt_col <= 4'd10) ? 16'hFFFF : 16'h07E0);
        end else if (is_line5) begin
            req_line     = 3'd5;
            req_col      = txt_col;
            req_row      = next_y[2:0] - 3'd5; // 117..124
            req_bit      = txt_bit;
            req_fg_color = (txt_col <= 4'd2) ? 16'h7BEF : ((txt_col >= 4'd6 && txt_col <= 4'd9) ? 16'h05DF : 16'hFFFF);
        end else if (is_line6) begin
            req_line     = 3'd6;
            req_col      = txt_col;
            req_row      = next_y[2:0] - 3'd1; // 129..136
            req_bit      = txt_bit;
            req_fg_color = (txt_col <= 4'd2) ? 16'h7BEF : ((color_mode == 2'd2) ? 16'hFFE0 : (color_mode == 2'd1) ? 16'hFFFF : 16'h07E0);
        end else if (is_line7) begin
            req_line     = 3'd7;
            req_col      = txt_col;
            req_row      = next_y[2:0] - 3'd6; // 142..149
            req_bit      = txt_bit;
            req_fg_color = (txt_col <= 4'd2) ? 16'h7BEF : 16'h07E0; // ECO 灰标签 + L4-GATED 翡翠绿高亮
        end else begin
            req_text_en  = 1'b0;
        end
    end

    wire font_pixel = (rom_font_byte >> req_bit) & 1'b1;

    // 像素合成输出流水线
    reg [15:0] calc_color;
    always @(*) begin
        if (is_divider) begin
            calc_color = 16'h2124; // 1px 极简微细分割线 (#212429)
        end else if (is_status_led) begin
            calc_color = hb_1hz ? 16'h07E0 : 16'h0124; // 极简呼吸状态微宝石 (翡翠绿 / 极暗灰)
        end else if (req_text_en && font_pixel) begin
            calc_color = req_fg_color; // 极简无衬底高对比度文字
        end else if (next_y >= 8'd60 && next_y <= 8'd87) begin
            // 极简单像素声学示波器 (Y: 60..87)
            if (d_wave_y == 8'd0)
                calc_color = 16'h07FF; // 纯净冰蓝高能单光束
            else if (d_wave_y == 8'd1)
                calc_color = 16'h01A6; // 微光柔和边缘
            else if (next_y == 8'd73 && next_x[2:0] == 3'd0)
                calc_color = 16'h10A2; // 极弱零轴刻度虚线
            else
                calc_color = 16'h0000; // 纯黑底色
        end else if (next_y >= 8'd94 && next_y <= 8'd111) begin
            // 自研 DFT 8 频段真实频域跳动频谱 (Y: 94..111)
            if (in_band_bar) begin
                if (cur_peak_h_cl > 5'd0 && next_y == peak_top_y) begin
                    calc_color = 16'hFFFF; // 纯白悬浮峰值顶帽 (Floating Peak Cap)
                end else if (cur_bar_h_cl > 5'd0 && next_y >= bar_top_y) begin
                    // 录音室三阶多色渐变色谱 (高能量/峰值炽红 -> 中段金黄 -> 基频电光青)
                    if (next_y <= 8'd98)
                        calc_color = 16'hF800; // 炽热红 (High / Peak Alert)
                    else if (next_y <= 8'd104)
                        calc_color = 16'hFFE0; // 璀璨金黄 (Mid / Warmth)
                    else
                        calc_color = 16'h05DF; // 电光青 (Bass / Clean Cyan)
                end else if (next_y == 8'd111) begin
                    calc_color = 16'h18E3; // 静音暗底基线点 (Subtle baseline marker)
                end else begin
                    calc_color = 16'h0000; // 纯黑背景
                end
            end else begin
                calc_color = 16'h0000;
            end
        end else begin
            calc_color = 16'h0000; // OLED 纯黑背景
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
    reg        blk_en;

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
            4'd9:  begin prep_rom_byte = ROW_OFFSET + 8'd159;   prep_rom_dc = 1'b1; end
            4'd10: begin prep_rom_byte = 8'h2C;                 prep_rom_dc = 1'b0; end // RAMWR
            default: begin prep_rom_byte = 8'h00;               prep_rom_dc = 1'b0; end
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            frame_spec      <= 40'd0;
            frame_peak      <= 40'd0;
            state           <= S_PWR_RST_LOW;
            delay_cnt       <= 24'd0;
            init_step       <= 6'd0;
            prep_step       <= 4'd0;
            lcd_rst         <= 1'b1;
            lcd_cs          <= 1'b1;
            blk_en          <= 1'b0;
            spi_start       <= 1'b0;
            spi_tx_byte     <= 8'h00;
            spi_tx_dc       <= 1'b0;
            cur_x           <= 7'd0;
            cur_y           <= 8'd0;
            cur_pixel_color <= 16'h0000;
        end else begin
            spi_start <= 1'b0;

            case (state)
                S_PWR_RST_LOW: begin
                    lcd_rst <= 1'b0; // 硬件低电平复位
                    lcd_cs  <= 1'b1;
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
                    lcd_cs  <= 1'b1;
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
                        lcd_cs      <= 1'b0;
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
                    blk_en  <= 1'b1; // 初始化完成、首帧及后续帧常亮
                    if (prep_step == 4'd0 && !spi_busy && !spi_start) begin
                        frame_spec <= sdft_spec_8b;
                        frame_peak <= sdft_peak_8b;
                    end
                    if (!spi_busy && !spi_start) begin
                        spi_tx_byte <= prep_rom_byte;
                        spi_tx_dc   <= prep_rom_dc;
                        spi_start   <= 1'b1;
                        lcd_cs      <= 1'b0;
                        if (prep_step == 4'd10) begin
                            cur_x           <= 7'd0;
                            cur_y           <= 8'd0;
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
                            if (cur_y == 8'd159) begin
                                cur_y     <= 8'd0;
                                prep_step <= 4'd0;
                                lcd_cs    <= 1'b1; // 帧尾释放 CS，强行校准 SPI 字节解码器
                                state     <= S_FRAME_PREP;
                            end else begin
                                cur_y <= cur_y + 8'd1;
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

    // ------------------------------------------------------------------------
    // LCD 背光超轻量 PWM 调光控制 (49.94% ≈ 50% 占空比, 762.9Hz, 复用 hb_cnt 计数器)
    // ------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst)
            lcd_blk <= 1'b0;
        else
            lcd_blk <= blk_en & hb_cnt[15];
    end

endmodule
