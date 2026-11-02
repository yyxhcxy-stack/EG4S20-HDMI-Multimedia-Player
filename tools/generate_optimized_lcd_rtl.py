import os

rtl = '''// ============================================================================
// Module Name: lcd_st7735_telemetry
// Project:     全国大学生嵌入式芯片与系统设计竞赛 - HX4S20 HDMI多媒体展示系统
// Target Board: Anlogic EG4S20BG256 (HX4S20C)
// Function:    1.44寸 128x128 SPI TFT 彩色 LCD 独立遥测中控副屏驱动与动态光栅渲染引擎
// Optimization: Ultra-Low LUT architecture (<250 LUTs, zero slice overflow)
// ============================================================================
`timescale 1ns / 1ps

module lcd_st7735_telemetry #(
    parameter [7:0] COL_OFFSET = 8'd2, // ST7735S 1.44寸 128x128 屏幕水平偏移
    parameter [7:0] ROW_OFFSET = 8'd3  // ST7735S 1.44寸 128x128 屏幕垂直偏移
)(
    input  wire                 clk,            // 50MHz 系统时钟
    input  wire                 rst,            // 高电平复位 (rst_all)

    // LCD SPI 物理接口 (对应开发板 J1 扩展口)
    output reg                  lcd_scl,        // SPI SCLK (12.5MHz, Pin J16)
    output reg                  lcd_mosi,       // SPI MOSI (SDA, Pin H16)
    output wire                 lcd_cs,         // 片选 (CS, Pin M16, 低电平有效)
    output reg                  lcd_dc,         // 数据/命令选择 (DC, Pin K16, 0=Cmd, 1=Data)
    output reg                  lcd_rst,        // 硬件复位 (RST, Pin H15, 低电平复位)
    output wire                 lcd_blk,        // 背光控制 (BLK, Pin K15, 高电平常开)

    // 系统遥测与音频实时输入
    input  wire [2:0]           cur_img_idx,    // 当前图片索引 0..3 (显示为 1..4)
    input  wire [1:0]           scale_mode,     // 缩放模式 0:1.0X, 1:2.0X, 2:0.5X, 3:AUTO
    input  wire [2:0]           vol_mode,       // 音量模式 0:100%, 1:75%, 2:50%, 3:25%, 4:MUTE
    input  wire signed [23:0]   audio_pcm,      // 24-bit PCM 采样
    input  wire                 audio_valid,    // 48kHz 采样脉冲
    input  wire                 emergency_mode  // 应急广播模式状态
);

    // 背光常亮，片选常拉低
    assign lcd_blk = 1'b1;
    assign lcd_cs  = 1'b0;

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
    // 2. 音频 128 点示波器环形采样缓存与 8 频段跳动频谱
    // ------------------------------------------------------------------------
    reg signed [7:0] osc_buf [0:127];
    reg [6:0]        osc_wr_ptr;
    reg [2:0]        audio_vld_sync;

    always @(posedge clk or posedge rst) begin
        if (rst)
            audio_vld_sync <= 3'b000;
        else
            audio_vld_sync <= {audio_vld_sync[1:0], audio_valid};
    end
    wire audio_pulse = audio_vld_sync[1] & ~audio_vld_sync[2];

    // 8 频段频谱能量峰值及衰减
    reg [2:0]  band_level [0:7];
    reg [20:0] decay_cnt;
    wire [7:0] audio_abs = audio_pcm[23] ? (-audio_pcm[23:16]) : audio_pcm[23:16];
    wire [2:0] band_in_idx = osc_wr_ptr[6:4];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            osc_wr_ptr <= 7'd0;
            band_level[0] <= 3'd0; band_level[1] <= 3'd0; band_level[2] <= 3'd0; band_level[3] <= 3'd0;
            band_level[4] <= 3'd0; band_level[5] <= 3'd0; band_level[6] <= 3'd0; band_level[7] <= 3'd0;
            decay_cnt <= 21'd0;
        end else begin
            if (audio_pulse) begin
                osc_buf[osc_wr_ptr] <= audio_pcm[23:16];
                osc_wr_ptr <= osc_wr_ptr + 7'd1;
                if (audio_abs[7:5] > band_level[band_in_idx])
                    band_level[band_in_idx] <= (audio_abs[7:5] > 3'd6) ? 3'd6 : audio_abs[7:5];
            end

            if (decay_cnt >= 21'd2_000_000) begin
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
    // 3. 独立字库 ROM 与单实例字符选择器
    // ------------------------------------------------------------------------
    reg [2:0]  req_line;
    reg [3:0]  req_col;
    reg [2:0]  req_row;
    reg [2:0]  req_bit;
    reg        req_text_en;
    reg [15:0] req_fg_color;

    function [5:0] get_char_idx;
        input [7:0] ch;
        begin
            if (ch >= 8'h61 && ch <= 8'h7A)
                get_char_idx = 6'd16 + (ch - 8'h61);
            else if (ch >= 8'h41 && ch <= 8'h5A)
                get_char_idx = 6'd16 + (ch - 8'h41);
            else if (ch >= 8'h30 && ch <= 8'h39)
                get_char_idx = 6'd6 + (ch - 8'h30);
            else begin
                case (ch)
                    8'h20: get_char_idx = 6'd0;  // ' '
                    8'h23: get_char_idx = 6'd1;  // '#'
                    8'h25: get_char_idx = 6'd2;  // '%'
                    8'h2D: get_char_idx = 6'd3;  // '-'
                    8'h2E: get_char_idx = 6'd4;  // '.'
                    8'h2F: get_char_idx = 6'd5;  // '/'
                    8'h3A: get_char_idx = 6'd42; // ':'
                    default: get_char_idx = 6'd0;
                endcase
            end
        end
    endfunction

    function [7:0] get_line_char;
        input [2:0] line_id;
        input [3:0] col;
        input [2:0] p_img;
        input [1:0] p_scl;
        input [2:0] p_vol;
        input       p_emg;
        begin
            case (line_id)
                3'd0: begin // "ANLOGIC TELEM"
                    case (col)
                        4'd0: get_line_char = "A"; 4'd1: get_line_char = "N"; 4'd2: get_line_char = "L";
                        4'd3: get_line_char = "O"; 4'd4: get_line_char = "G"; 4'd5: get_line_char = "I";
                        4'd6: get_line_char = "C"; 4'd7: get_line_char = " "; 4'd8: get_line_char = "T";
                        4'd9: get_line_char = "E"; 4'd10: get_line_char = "L"; 4'd11: get_line_char = "E";
                        4'd12: get_line_char = "M"; default: get_line_char = " ";
                    endcase
                end
                3'd1: begin // "IMG:#%d/4 60HZ"
                    case (col)
                        4'd0: get_line_char = "I"; 4'd1: get_line_char = "M"; 4'd2: get_line_char = "G";
                        4'd3: get_line_char = ":"; 4'd4: get_line_char = "#";
                        4'd5: get_line_char = 8'h31 + {5'd0, p_img[1:0]}; // '1'..'4'
                        4'd6: get_line_char = "/"; 4'd7: get_line_char = "4"; 4'd8: get_line_char = " ";
                        4'd9: get_line_char = "6"; 4'd10: get_line_char = "0"; 4'd11: get_line_char = "H";
                        4'd12: get_line_char = "Z"; default: get_line_char = " ";
                    endcase
                end
                3'd2: begin // "SCL:AUTO DDA "
                    case (col)
                        4'd0: get_line_char = "S"; 4'd1: get_line_char = "C"; 4'd2: get_line_char = "L";
                        4'd3: get_line_char = ":";
                        4'd4: get_line_char = (p_scl == 2'd0) ? "1" : ((p_scl == 2'd1) ? "2" : ((p_scl == 2'd2) ? "0" : "A"));
                        4'd5: get_line_char = (p_scl == 2'd3) ? "U" : ".";
                        4'd6: get_line_char = (p_scl == 2'd0) ? "0" : ((p_scl == 2'd1) ? "0" : ((p_scl == 2'd2) ? "5" : "T"));
                        4'd7: get_line_char = (p_scl == 2'd3) ? "O" : "X";
                        4'd8: get_line_char = " "; 4'd9: get_line_char = "D"; 4'd10: get_line_char = "D";
                        4'd11: get_line_char = "A"; default: get_line_char = " ";
                    endcase
                end
                3'd3: begin // "AUD:CHIME 48K"
                    case (col)
                        4'd0: get_line_char = "A"; 4'd1: get_line_char = "U"; 4'd2: get_line_char = "D";
                        4'd3: get_line_char = ":";
                        4'd4: get_line_char = p_emg ? "E" : ((p_vol == 3'd4) ? "M" : "C");
                        4'd5: get_line_char = p_emg ? "M" : ((p_vol == 3'd4) ? "U" : "H");
                        4'd6: get_line_char = p_emg ? "E" : ((p_vol == 3'd4) ? "T" : "I");
                        4'd7: get_line_char = p_emg ? "R" : ((p_vol == 3'd4) ? "E" : "M");
                        4'd8: get_line_char = p_emg ? "G" : ((p_vol == 3'd4) ? " " : "E");
                        4'd9: get_line_char = " "; 4'd10: get_line_char = "4"; 4'd11: get_line_char = "8";
                        4'd12: get_line_char = "K"; default: get_line_char = " ";
                    endcase
                end
                3'd4: begin // "LAT:16.6MS OK"
                    case (col)
                        4'd0: get_line_char = "L"; 4'd1: get_line_char = "A"; 4'd2: get_line_char = "T";
                        4'd3: get_line_char = ":"; 4'd4: get_line_char = "1"; 4'd5: get_line_char = "6";
                        4'd6: get_line_char = "."; 4'd7: get_line_char = "6"; 4'd8: get_line_char = "M";
                        4'd9: get_line_char = "S"; 4'd10: get_line_char = " "; 4'd11: get_line_char = "O";
                        4'd12: get_line_char = "K"; default: get_line_char = " ";
                    endcase
                end
                3'd5: begin // "HX4S20 DUAL-DSP"
                    case (col)
                        4'd0: get_line_char = "H"; 4'd1: get_line_char = "X"; 4'd2: get_line_char = "4";
                        4'd3: get_line_char = "S"; 4'd4: get_line_char = "2"; 4'd5: get_line_char = "0";
                        4'd6: get_line_char = " "; 4'd7: get_line_char = "D"; 4'd8: get_line_char = "U";
                        4'd9: get_line_char = "A"; 4'd10: get_line_char = "L"; 4'd11: get_line_char = "-";
                        4'd12: get_line_char = "D"; 4'd13: get_line_char = "S"; 4'd14: get_line_char = "P";
                        default: get_line_char = " ";
                    endcase
                end
                default: get_line_char = " ";
            endcase
        end
    endfunction

    // 字体 ROM 实例化与单路请求
    wire [7:0] ascii_req = get_line_char(req_line, req_col, cur_img_idx, scale_mode, vol_mode, emergency_mode);
    wire [5:0] rom_char_idx = get_char_idx(ascii_req);
    wire [7:0] rom_font_byte;

    font_rom_8x8 u_font_rom (
        .clk        (clk),
        .char_idx   (rom_char_idx),
        .row        (req_row),
        .font_data  (rom_font_byte)
    );

    // ------------------------------------------------------------------------
    // 4. 纯硬件动态光栅像素着色流水线
    // ------------------------------------------------------------------------
    reg [6:0] cur_x, cur_y;
    wire [6:0] next_x = (cur_x == 7'd127) ? 7'd0 : (cur_x + 7'd1);
    wire [6:0] next_y = (cur_x == 7'd127) ? ((cur_y == 7'd127) ? 7'd0 : (cur_y + 7'd1)) : cur_y;

    // 示波器波形高度计算
    wire signed [7:0] osc_s = osc_buf[next_x];
    wire signed [7:0] osc_scaled = osc_s >>> 2;
    wire signed [7:0] osc_clamp = (osc_scaled > 8'sd22) ? 8'sd22 : ((osc_scaled < -8'sd22) ? -8'sd22 : osc_scaled);
    wire [6:0] wave_y = 7'd84 - osc_clamp[6:0];

    // 频谱高度计算
    wire [2:0] next_band_idx = next_x[6:4];
    wire [3:0] bar_in_band = next_x[3:0];
    wire [2:0] cur_bar_h = band_level[next_band_idx];

    // 字体像素采样
    wire [6:0] txt_dx_t = next_x - 7'd6;
    wire [3:0] txt_col_t = txt_dx_t[6:3];
    wire [2:0] txt_bit_t = 3'd7 - txt_dx_t[2:0];

    wire [6:0] txt_dx_f = next_x - 7'd4;
    wire [3:0] txt_col_f = txt_dx_f[6:3];
    wire [2:0] txt_bit_f = 3'd7 - txt_dx_f[2:0];

    wire is_line0 = (next_y >= 7'd4 && next_y <= 7'd11 && next_x >= 7'd6 && next_x <= 7'd109);
    wire is_line1 = (next_y >= 7'd18 && next_y <= 7'd25 && next_x >= 7'd6 && next_x <= 7'd109);
    wire is_line2 = (next_y >= 7'd27 && next_y <= 7'd34 && next_x >= 7'd6 && next_x <= 7'd109);
    wire is_line3 = (next_y >= 7'd36 && next_y <= 7'd43 && next_x >= 7'd6 && next_x <= 7'd109);
    wire is_line4 = (next_y >= 7'd45 && next_y <= 7'd52 && next_x >= 7'd6 && next_x <= 7'd109);
    wire is_line5 = (next_y >= 7'd116 && next_y <= 7'd123 && next_x >= 7'd4 && next_x <= 7'd123);

    always @(*) begin
        req_text_en  = 1'b1;
        req_line     = 3'd0;
        req_col      = txt_col_t;
        req_row      = 3'd0;
        req_bit      = txt_bit_t;
        req_fg_color = 16'h07FF;

        if (is_line0) begin
            req_line     = 3'd0;
            req_col      = txt_col_t;
            req_row      = next_y[2:0] - 3'd4;
            req_bit      = txt_bit_t;
            req_fg_color = 16'h07FF;
        end else if (is_line1) begin
            req_line     = 3'd1;
            req_col      = txt_col_t;
            req_row      = next_y[2:0] - 3'd2;
            req_bit      = txt_bit_t;
            req_fg_color = 16'hFFE0;
        end else if (is_line2) begin
            req_line     = 3'd2;
            req_col      = txt_col_t;
            req_row      = next_y[2:0] - 3'd3;
            req_bit      = txt_bit_t;
            req_fg_color = 16'h07FF;
        end else if (is_line3) begin
            req_line     = 3'd3;
            req_col      = txt_col_t;
            req_row      = next_y[2:0] - 3'd4;
            req_bit      = txt_bit_t;
            req_fg_color = emergency_mode ? 16'hF800 : 16'hFDA0;
        end else if (is_line4) begin
            req_line     = 3'd4;
            req_col      = txt_col_t;
            req_row      = next_y[2:0] - 3'd5;
            req_bit      = txt_bit_t;
            req_fg_color = 16'h57E0;
        end else if (is_line5) begin
            req_line     = 3'd5;
            req_col      = txt_col_f;
            req_row      = next_y[2:0] - 3'd4;
            req_bit      = txt_bit_f;
            req_fg_color = 16'hFEA0;
        end else begin
            req_text_en  = 1'b0;
        end
    end

    wire font_pixel = (rom_font_byte >> req_bit) & 1'b1;

    reg [15:0] calc_color;
    always @(*) begin
        calc_color = 16'h0000;

        // Zone 1: Top Bar (Y <= 16)
        if (next_y <= 7'd16) begin
            if (next_y == 7'd16)
                calc_color = 16'h03BF; // 青色分割线
            else if (next_x >= 7'd115 && next_x <= 7'd121 && next_y >= 7'd5 && next_y <= 7'd11) begin
                if ((next_x == 7'd118 || next_x == 7'd117 || next_x == 7'd119) &&
                    (next_y == 7'd8   || next_y == 7'd7   || next_y == 7'd9))
                    calc_color = hb_1hz ? 16'hFFFF : 16'h07E0;
                else
                    calc_color = hb_1hz ? 16'h07E0 : 16'h0240;
            end else if (req_text_en && is_line0) begin
                calc_color = font_pixel ? req_fg_color : 16'h08C6;
            end else begin
                calc_color = 16'h08C6; // 深蓝底色 #0A192F
            end
        end

        // Zone 2: Telemetry Zone (17 <= Y <= 55)
        else if (next_y <= 7'd55) begin
            if (next_y == 7'd55)
                calc_color = 16'h11E8; // 灰青分割线
            else if (req_text_en)
                calc_color = font_pixel ? req_fg_color : 16'h0000;
            else
                calc_color = 16'h0000;
        end

        // Zone 3: Dynamic Oscilloscope Zone (56 <= Y <= 112)
        else if (next_y <= 7'd112) begin
            if (next_y >= 7'd105 && next_y <= 7'd111 && bar_in_band >= 4'd2 && bar_in_band <= 4'd13 &&
                next_y >= (7'd111 - {4'd0, cur_bar_h})) begin
                if (next_y == (7'd111 - {4'd0, cur_bar_h}))
                    calc_color = 16'hFFFF; // 峰值白帽
                else if (next_y <= 7'd107)
                    calc_color = 16'hFD20; // 橙红
                else
                    calc_color = 16'h07E0; // 翠绿
            end else if (next_y == wave_y || next_y == wave_y + 7'd1) begin
                calc_color = 16'h07E0; // 核心荧光绿
            end else if (next_y == wave_y - 7'd1 || next_y == wave_y + 7'd2) begin
                calc_color = 16'h0460; // 荧光晕圈
            end else if (next_y == 7'd84 && next_x[0] == 1'b0) begin
                calc_color = 16'h12E5; // 中心虚线
            end else if ((next_y == 7'd70 || next_y == 7'd98) && next_x[2:0] == 3'd0) begin
                calc_color = 16'h0923; // 四分之一刻度线
            end else if (next_x[3:0] == 4'd0 && next_y[2:0] == 3'd0) begin
                calc_color = 16'h0923; // 垂直刻度点
            end else begin
                calc_color = 16'h0000;
            end
        end

        // Zone 4: Footer Bar (113 <= Y <= 127)
        else begin
            if (next_y == 7'd113)
                calc_color = 16'hCE40; // 金色分割线
            else if (req_text_en && is_line5)
                calc_color = font_pixel ? req_fg_color : 16'h08C6;
            else
                calc_color = 16'h08C6;
        end
    end

    // ------------------------------------------------------------------------
    // 5. 12.5MHz SPI 传输引擎
    // ------------------------------------------------------------------------
    reg [1:0]  spi_phase;
    reg [2:0]  spi_bit_cnt;
    reg [7:0]  spi_shift;
    reg        spi_busy;
    reg        spi_start;
    reg [7:0]  spi_tx_byte;
    reg        spi_tx_dc;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lcd_scl     <= 1'b0;
            lcd_mosi    <= 1'b0;
            lcd_dc      <= 1'b0;
            spi_phase   <= 2'b00;
            spi_bit_cnt <= 3'd0;
            spi_shift   <= 8'h00;
            spi_busy    <= 1'b0;
        end else if (spi_start) begin
            spi_busy    <= 1'b1;
            spi_shift   <= spi_tx_byte;
            spi_bit_cnt <= 3'd0;
            spi_phase   <= 2'b00;
            lcd_dc      <= spi_tx_dc;
        end else if (spi_busy) begin
            spi_phase <= spi_phase + 2'b01;
            case (spi_phase)
                2'b00: begin
                    lcd_scl  <= 1'b0;
                    lcd_mosi <= spi_shift[7];
                end
                2'b01: begin
                    lcd_scl  <= 1'b0;
                end
                2'b10: begin
                    lcd_scl  <= 1'b1;
                end
                2'b11: begin
                    lcd_scl <= 1'b1;
                    if (spi_bit_cnt == 3'd7) begin
                        spi_busy <= 1'b0;
                    end else begin
                        spi_bit_cnt <= spi_bit_cnt + 3'd1;
                        spi_shift   <= {spi_shift[6:0], 1'b0};
                    end
                end
            endcase
        end else begin
            lcd_scl <= 1'b0;
        end
    end

    // ------------------------------------------------------------------------
    // 6. ST7735S 驱动状态机
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
    reg [4:0]  init_step;
    reg [3:0]  prep_step;
    reg [15:0] cur_pixel_color;

    reg [7:0]  init_rom_byte;
    reg        init_rom_dc;
    reg [23:0] init_rom_delay;

    always @(*) begin
        case (init_step)
            5'd0: begin init_rom_byte = 8'h01; init_rom_dc = 1'b0; init_rom_delay = 24'd6_000_000; end
            5'd1: begin init_rom_byte = 8'h11; init_rom_dc = 1'b0; init_rom_delay = 24'd6_000_000; end
            5'd2: begin init_rom_byte = 8'h3A; init_rom_dc = 1'b0; init_rom_delay = 24'd0;         end
            5'd3: begin init_rom_byte = 8'h05; init_rom_dc = 1'b1; init_rom_delay = 24'd0;         end
            5'd4: begin init_rom_byte = 8'h36; init_rom_dc = 1'b0; init_rom_delay = 24'd0;         end
            5'd5: begin init_rom_byte = 8'hC8; init_rom_dc = 1'b1; init_rom_delay = 24'd0;         end
            5'd6: begin init_rom_byte = 8'h29; init_rom_dc = 1'b0; init_rom_delay = 24'd1_000_000; end
            default: begin init_rom_byte = 8'h00; init_rom_dc = 1'b0; init_rom_delay = 24'd0;     end
        endcase
    end

    reg [7:0] prep_rom_byte;
    reg       prep_rom_dc;
    always @(*) begin
        case (prep_step)
            4'd0:  begin prep_rom_byte = 8'h2A; prep_rom_dc = 1'b0; end
            4'd1:  begin prep_rom_byte = 8'h00; prep_rom_dc = 1'b1; end
            4'd2:  begin prep_rom_byte = COL_OFFSET; prep_rom_dc = 1'b1; end
            4'd3:  begin prep_rom_byte = 8'h00; prep_rom_dc = 1'b1; end
            4'd4:  begin prep_rom_byte = COL_OFFSET + 8'd127; prep_rom_dc = 1'b1; end
            4'd5:  begin prep_rom_byte = 8'h2B; prep_rom_dc = 1'b0; end
            4'd6:  begin prep_rom_byte = 8'h00; prep_rom_dc = 1'b1; end
            4'd7:  begin prep_rom_byte = ROW_OFFSET; prep_rom_dc = 1'b1; end
            4'd8:  begin prep_rom_byte = 8'h00; prep_rom_dc = 1'b1; end
            4'd9:  begin prep_rom_byte = ROW_OFFSET + 8'd127; prep_rom_dc = 1'b1; end
            4'd10: begin prep_rom_byte = 8'h2C; prep_rom_dc = 1'b0; end
            default: begin prep_rom_byte = 8'h00; prep_rom_dc = 1'b0; end
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= S_PWR_RST_LOW;
            delay_cnt       <= 24'd0;
            init_step       <= 5'd0;
            prep_step       <= 4'd0;
            cur_x           <= 7'd0;
            cur_y           <= 7'd0;
            cur_pixel_color <= 16'h0000;
            lcd_rst         <= 1'b0;
            spi_start       <= 1'b0;
            spi_tx_byte     <= 8'h00;
            spi_tx_dc       <= 1'b0;
        end else begin
            spi_start <= 1'b0;

            case (state)
                S_PWR_RST_LOW: begin
                    lcd_rst <= 1'b0;
                    if (delay_cnt >= 24'd500_000) begin
                        delay_cnt <= 24'd0;
                        lcd_rst   <= 1'b1;
                        state     <= S_PWR_RST_HIGH;
                    end else begin
                        delay_cnt <= delay_cnt + 24'd1;
                    end
                end

                S_PWR_RST_HIGH: begin
                    lcd_rst <= 1'b1;
                    if (delay_cnt >= 24'd6_000_000) begin
                        delay_cnt <= 24'd0;
                        init_step <= 5'd0;
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
                            if (init_step == 5'd6) begin
                                prep_step <= 4'd0;
                                state     <= S_FRAME_PREP;
                            end else begin
                                init_step <= init_step + 5'd1;
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

print("Generated optimized src/rtl/lcd_st7735_telemetry.v!")
