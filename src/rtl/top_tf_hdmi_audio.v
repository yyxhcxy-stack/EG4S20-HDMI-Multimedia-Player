
module top(
    input                       clk,
    input                       rst_n,
	    input                       key1,           // 手动下一�?
	    input                       key2,           // 自动播放 开/�?
	    input                       key3,           // KEY3: 单击(切缩�? / 双击(调音�? / 长按1�?切换右上角性能模板HUD)
	    input  [3:0]                sw_bright,      // SW1..SW4，亮�?0..15

    output [5:0]                seg_sel,
    output [7:0]                seg_data,
    output [3:0]                led,            // 板载 LED0..LED3 (A4, A3, C10, B12)
    output                      buzz,           // 板载蜂鸣�?(H11)

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso,

    // Innovation 3: Tunnel SCADA Industrial Bus & Telemetry (CH340 USB Bridge)
    input                       uart_rx,        // RXD (Pin F12)
    output                      uart_tx,        // TXD (Pin D12)

    // Innovation 4: Wireless BLE HC-08D Transparent Telemetry (J1 Pin 4 F13, Pin 8 J13)
    input                       ble_rx,         // Pin F13 (J1 Pin 4, from HC-08D TXD)
    output                      ble_tx,         // Pin J13 (J1 Pin 8, to HC-08D RXD)

    // ST7735S 1.44�?SPI TFT LCD 遥测中控副屏 (J1 Pins 23..28)
    output                      lcd_scl,
    output                      lcd_mosi,
    output                      lcd_cs,
    output                      lcd_dc,
    output                      lcd_rst,
    output                      lcd_blk
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = 24'd1_048_576; // 1M words per frame buffer (supports up to 1024x768)

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
		wire        display_valid;
		wire        load_fail_hold;
	wire [7:0]  play_pos;
	reg  [1:0]  key3_sync;
	reg  [3:0]  key3_state;
	reg  [25:0] key3_timer;
    reg k3_debounce_early,k3_long_early,k3_click_early,k3_cool_early;
    wire k3_timer_running=|key3_timer;
	reg  [1:0]  scale_mode; // 0: 1.0X, 1: 2.0X, 2: 0.5X, 3: AUTO
	reg  [2:0]  vol_mode;   // 0: 100%, 1: 75%, 2: 50%, 3: 25%, 4: MUTE
	wire        hud_en = menu_active; // 菜单激活时开�?HUD，菜单关闭时淡出隐藏
	reg  [1:0]  alpha_mode; // 0: 25% Crystal, 1: 50% Frosted Glass, 2: 75% Dark Mask
	reg  [1:0]  key2_sync;
	reg  [3:0]  key2_state;
	reg  [25:0] key2_timer;
	reg  [2:0]  trans_user_mode; // 0: Fade, 1: Blinds, 2: Slide, 3: Mosaic, 4: AUTO (Double click KEY4 to cycle)
	reg         emergency_mode;
	reg         key2_auto_out;
	reg  [1:0]  key1_sync;
	reg  [3:0]  key1_state;
	reg  [25:0] key1_timer;
	reg  [2:0]  contrast_mode; // 0: 1.00X, 1: 1.25X, 2: 1.50X, 3: 2.00X, 4: 0.75X
	reg  [1:0]  tone_mode;     // Direction 3: 0: STD, 1: WARM, 2: COOL, 3: EYE
	reg  [1:0]  seg_disp_mode; // 0: PIC, 1: SP1 (Equalizer), 2: SP2 (Waveform), 3: AUT (Auto-cycle)
	reg         key1_next_active_low;
	reg  [6:0]  vu_amp;

wire [3:0]  state_code;
wire [2:0]  cur_img_idx;
wire        auto_play_status;
wire [3:0]  cur_img_num;
wire [3:0]  img_found_total;
wire [6:0]  seg_img_data;

assign cur_img_num = display_valid ? ({1'b0, cur_img_idx} + 4'd1) : 4'd0;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;
reg  [1:0]  disp_buf_idx_v;
reg  [2:0]  vs_blank_sync;

wire [15:0] buf0_w_sd, buf0_h_sd;
wire [15:0] buf1_w_sd, buf1_h_sd;
wire [2:0]  buf0_idx_sd, buf1_idx_sd;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_pll_lock;
wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire audio_raw_valid;
wire signed [23:0] audio_left_data;
wire signed [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：三�?PLL 都锁定后再保持约 20 ms，避免上电时钟未稳就启动
wire sys_pll_lock;
wire video_pll_lock;
wire pll_locked = sys_pll_lock & video_pll_lock & audio_pll_lock;

reg [19:0] por_cnt;
reg        rst_all_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        por_cnt   <= 20'd0;
        rst_all_r <= 1'b1;
    end else if (!pll_locked) begin
        por_cnt   <= 20'd0;
        rst_all_r <= 1'b1;
    end else if (por_cnt < 20'd1_000_000) begin
        por_cnt   <= por_cnt + 20'd1;
        rst_all_r <= 1'b1;
    end else begin
        rst_all_r <= 1'b0;
    end
end

	wire rst_all = rst_all_r;

	// System Heartbeat Counter & 50Hz Tick Generator
	reg [25:0] hb_cnt;
	reg        last_hb24;
	always @(posedge clk or posedge rst_all) begin
	    if (rst_all) begin
	        hb_cnt    <= 26'd0;
	        last_hb24 <= 1'b0;
	    end else begin
	        hb_cnt    <= hb_cnt + 26'd1;
	        last_hb24 <= hb_cnt[24];
	    end
	end
	wire hb_tick_50hz = (hb_cnt[19:0] == 20'd0); // ~47.7Hz (~21ms per tick)
	wire hb_tick_1hz  = (hb_cnt[24] && !last_hb24); // ~1.49Hz edge tick

	// 0.67秒上电按键保护门 (防抖与电压建立保护，复用 hb_cnt[25]，上电期间屏蔽按键误触发)
	reg        boot_ready;
	always @(posedge clk or posedge rst_all) begin
	    if (rst_all)        boot_ready <= 1'b0;
	    else if (hb_cnt[25]) boot_ready <= 1'b1;
	end

	wire key1_gated = boot_ready ? key1 : 1'b1;
	wire key2_gated = boot_ready ? key2 : 1'b1;
	wire key3_gated = boot_ready ? key3 : 1'b1;

	// SCADA Controller interconnect wires (declared prior to usage to prevent implicit 1-bit truncation)
	wire        cmd_emerg_set;
	wire        cmd_emerg_clr;
	wire        cmd_next_pulse;
	wire        cmd_auto_set;
	wire        cmd_auto_clr;
	wire        cmd_scale_vld;
	wire [1:0]  cmd_scale_val;
	wire        cmd_vol_vld;
	wire [2:0]  cmd_vol_val;
	wire        cmd_trans_vld;
	wire [2:0]  cmd_trans_val;
	wire        cmd_alpha_vld;
	wire [1:0]  cmd_alpha_val;
	wire        scada_active;
	wire        scada_rx_pulse;

	// KEY3 early timing comparator registers (CE=1, optimal BLE packing)
	always @(posedge clk or posedge rst_all) begin
	    if (rst_all) begin
	        k3_debounce_early <= 1'b0;
	        k3_long_early     <= 1'b0;
	        k3_click_early    <= 1'b0;
	        k3_cool_early     <= 1'b0;
	    end else begin
	        k3_debounce_early <= key3_timer >= 26'd1_000_000 - 2;
	        k3_long_early     <= key3_timer >= 26'd30_000_000 - 2; // 0.60 second
	        k3_click_early    <= key3_timer >= 26'd17_500_000 - 2;
	        k3_cool_early     <= key3_timer >= 26'd1_500_000 - 2;
	    end
	end

	// Direction 1: OSD Interactive Virtual Menu Controller Signals
	reg        menu_active;
	reg [2:0]  menu_cursor;     // 0: Brightness, 1: Volume, 2: Color, 3: Scale, 4: Contrast, 5: Transition, 6: Exit
	reg [1:0]  menu_bright;     // Brightness (0..3)
	reg [1:0]  menu_color_mode; // Color filter mode (0..3)
	reg [3:0]  menu_idle_cnt;   // 16-second auto-exit inactivity timer (16 ticks of hb_tick_1hz)

	reg k3_menu_open_pulse;
	reg k3_menu_close_pulse;
	reg k3_menu_sel_pulse;
	reg k1_menu_inc_pulse;
	reg k2_menu_dec_pulse;

	wire menu_open_pulse  = k3_menu_open_pulse;
	wire menu_close_pulse = k3_menu_close_pulse;
	wire menu_sel_pulse   = k3_menu_sel_pulse;
	wire menu_inc_pulse   = k1_menu_inc_pulse;
	wire menu_dec_pulse   = k2_menu_dec_pulse;

	// Direction 1 & 3: OSD Interactive Virtual Menu Central Controller
	always @(posedge clk or posedge rst_all) begin
	    if (rst_all) begin
	        menu_active     <= 1'b0;
	        menu_cursor     <= 3'd0;
	        menu_bright     <= 2'd0;
	        menu_color_mode <= 2'd0;
	        tone_mode       <= 2'd0;
	        menu_idle_cnt   <= 4'd0;
	    end else begin
	        if (menu_open_pulse) begin
	            menu_active   <= 1'b1;
	            menu_cursor   <= 3'd0;
	            menu_idle_cnt <= 4'd0;
	        end else if (menu_close_pulse) begin
	            menu_active   <= 1'b0;
	            menu_idle_cnt <= 4'd0;
	        end else if (menu_active) begin
	            // 16 seconds auto-exit timeout
	            if (menu_sel_pulse || menu_inc_pulse || menu_dec_pulse) begin
	                menu_idle_cnt <= 4'd0;
	            end else if (hb_tick_1hz) begin
	                if (menu_idle_cnt == 4'd15) begin
	                    menu_active   <= 1'b0;
	                    menu_idle_cnt <= 4'd0;
	                end else begin
	                    menu_idle_cnt <= menu_idle_cnt + 4'd1;
	                end
	            end

	            // Cursor navigation down (0..7 cyclic)
	            if (menu_sel_pulse) begin
	                if (menu_cursor >= 3'd7) begin
	                    menu_active <= 1'b0; // If on Item 7 (Exit), clicking SEL exits menu!
	                    menu_cursor <= 3'd0;
	                end else begin
	                    menu_cursor <= menu_cursor + 3'd1;
	                end
	            end

	            // If on Item 7 (Exit), clicking + or - also exits menu!
	            if (menu_cursor == 3'd7) begin
	                if (menu_inc_pulse || menu_dec_pulse) begin
	                    menu_active <= 1'b0;
	                    menu_cursor <= 3'd0;
	                end
	            end

	            // Menu Item 0: Brightness adjust (0..3)
	            if (menu_cursor == 3'd0) begin
	                if (menu_inc_pulse) menu_bright <= menu_bright + 2'd1;
	                else if (menu_dec_pulse) menu_bright <= menu_bright - 2'd1;
	            end

	            // Menu Item 2: Color filter mode adjust (0..3)
	            if (menu_cursor == 3'd2) begin
	                if (menu_inc_pulse) menu_color_mode <= menu_color_mode + 2'd1;
	                else if (menu_dec_pulse) menu_color_mode <= menu_color_mode - 2'd1;
	            end

	            // Menu Item 6: Tone mode adjust (0..3: STD, WARM, COOL, EYE)
	            if (menu_cursor == 3'd6) begin
	                if (menu_inc_pulse) tone_mode <= tone_mode + 2'd1;
	                else if (menu_dec_pulse) tone_mode <= tone_mode - 2'd1;
	            end
	        end else begin
	            menu_idle_cnt   <= 4'd0;
	            menu_bright     <= sw_bright[1:0];
	            menu_color_mode <= (sw_bright[3] && !sw_bright[2]) ? 2'd1 :
	                               (!sw_bright[3] && sw_bright[2]) ? 2'd2 :
	                               (sw_bright[3] && sw_bright[2])  ? 2'd3 : 2'd0;
	        end
	    end
	end

	// =============================================================
	// KEY3 (引脚 B1, 板载丝印 KEY3, 端口 key3_gated)
	// 单击(切缩�?、双�?调音�?、三�?切换Alpha透明�?、长�?�?切换右上角性能模板HUD平滑呼吸显隐) 硬件状态机 (FSM)
	// - 单击 (<1s 松开�?350ms 内无�?次按�?: 切换图像缩放模式 (1.0X -> 2.0X -> 0.5X -> AUTO)
	// - 双击 (350ms 内第2次按下且 350ms 内无�?次按�?: 切换音量 (100% -> 75% -> 50% -> 25% -> MUTE)
	// - 三击 (350ms 内第3次按�?: 切换 Alpha 透明度模�?(25% -> 50% -> 75% -> 25%)
	// - 长按 (持续按下�?1.0 �?= 50,000,000周期): 翻转 hud_en (右上角性能模板 16 帧平滑呼吸淡入淡�?
	// =============================================================
	localparam K3_IDLE          = 4'd0; // 空闲待机 (等待�?1 次按�?
	localparam K3_PRESS1_DEB    = 4'd1; // �?1 次按下消�?(20ms)
	localparam K3_HELD          = 4'd2; // 按下保持计时 (0.6s 长按判定)
	localparam K3_REL1_DEB      = 4'd3; // �?1 次短按松开消抖 (20ms)
	localparam K3_WAIT_CLICK2   = 4'd4; // 判定等待�?(350ms): 等待�?2 次按下，超时则判定为单击
	localparam K3_PRESS2_DEB    = 4'd5; // �?2 次按下消�?(20ms)，确认双击！
	localparam K3_WAIT2_REL     = 4'd6; // 等待�?2 次松开
	localparam K3_REL2_DEB      = 4'd7; // �?2 次松开消抖 (30ms 冷却)，返回空�?
	localparam K3_WAIT_LONG_REL = 4'd8; // 确认长按，等待松开按键
	localparam K3_REL_LONG_DEB  = 4'd9; // 长按松开消抖 (30ms 冷却)，返回空�?

	always @(posedge clk or posedge rst_all) begin
	    if (rst_all) begin
	        key3_sync           <= 2'b11;
	        key3_state          <= K3_IDLE;
	        key3_timer          <= 26'd0;
	        scale_mode          <= 2'b11;
	        vol_mode            <= 3'd0;
	        alpha_mode          <= 2'd1; // 默认 50% 磨砂玻璃
	        k3_menu_open_pulse  <= 1'b0;
	        k3_menu_close_pulse <= 1'b0;
	        k3_menu_sel_pulse   <= 1'b0;
	    end else begin
	        key3_sync           <= {key3_sync[0], key3_gated};
	        k3_menu_open_pulse  <= 1'b0;
	        k3_menu_close_pulse <= 1'b0;
	        k3_menu_sel_pulse   <= 1'b0;

	        // SCADA remote scale, volume, and alpha control overrides
	        if (cmd_scale_vld) begin
	            scale_mode <= cmd_scale_val;
	            key3_state <= K3_IDLE;
	            key3_timer <= 26'd0;
	        end
	        if (cmd_vol_vld) begin
	            vol_mode   <= cmd_vol_val;
	            key3_state <= K3_IDLE;
	            key3_timer <= 26'd0;
	        end
	        if (cmd_alpha_vld) begin
	            alpha_mode <= cmd_alpha_val;
	            key3_state <= K3_IDLE;
	            key3_timer <= 26'd0;
	        end

	        case (key3_state)
	            K3_IDLE: begin
	                key3_timer <= 26'd0;
	                if (!key3_sync[1]) begin
	                    key3_state <= K3_PRESS1_DEB;
	                end
	            end

	            K3_PRESS1_DEB: begin
	                if (key3_sync[1]) begin
	                    // 前沿毛刺/抖动，返回空�?
	                    key3_state <= K3_IDLE;
	                    key3_timer <= 26'd0;
	                end else if (k3_debounce_early && k3_timer_running) begin
	                    // 持续按下稳定 20ms，确认为有效按下，转入长�?短按保持判定
	                    key3_state <= K3_HELD;
	                    key3_timer <= 26'd1_000_000;
	                end else begin
	                    key3_timer <= key3_timer + 26'd1;
	                end
	            end

	            K3_HELD: begin
	                if (k3_long_early && k3_timer_running) begin
	                    // 持续按下超过 0.6 �?-> 【长�?0.6s 切换菜单开/关！�?
	                    if (menu_active) begin
	                        k3_menu_close_pulse <= 1'b1; // 菜单内长按：立即关闭菜单�?
	                    end else begin
	                        k3_menu_open_pulse  <= 1'b1; // 正常模式长按：打开菜单�?
	                    end
	                    key3_state <= K3_WAIT_LONG_REL;
	                    key3_timer <= 26'd0;
	                end else if (key3_sync[1]) begin
	                    // �?0.6 秒前松开按键 -> 进入短按松开消抖
	                    key3_state <= K3_REL1_DEB;
	                    key3_timer <= 26'd0;
	                end else begin
	                    key3_timer <= key3_timer + 26'd1;
	                end
	            end

	            K3_REL1_DEB: begin
	                if (!key3_sync[1]) begin
	                    // 松开过程中有回弹杂波，返回保持计�?
	                    key3_state <= K3_HELD;
	                    key3_timer <= 26'd1_000_000;
	                end else if (k3_debounce_early && k3_timer_running) begin
	                    if (menu_active) begin
	                        // 菜单模式：短按松开消抖�?20ms 即触发光标循环下�?(0..5)，直接返回空闲！
	                        k3_menu_sel_pulse <= 1'b1;
	                        key3_state        <= K3_IDLE;
	                        key3_timer        <= 26'd0;
	                    end else begin
	                        // 正常模式：稳定松开�?20ms，开�?350ms 双击判定窗口
	                        key3_state <= K3_WAIT_CLICK2;
	                        key3_timer <= 26'd0;
	                    end
	                end else begin
	                    key3_timer <= key3_timer + 26'd1;
	                end
	            end

	            K3_WAIT_CLICK2: begin
	                if (!key3_sync[1]) begin
	                    // �?350ms 窗口内检测到�?2 次按�?-> 进入�?2 次按下消�?
	                    key3_state <= K3_PRESS2_DEB;
	                    key3_timer <= 26'd0;
	                end else if (k3_click_early && k3_timer_running) begin
	                    // 350ms 窗口超时未等到第 2 次按�?-> 【确定为单击 Single-Click！�?
	                    // 正常模式：切换图像缩放模�?(1.0X -> 2.0X -> 0.5X -> AUTO)
	                    scale_mode <= (scale_mode >= 2'd3) ? 2'd0 : (scale_mode + 2'd1);
	                    key3_state <= K3_IDLE;
	                    key3_timer <= 26'd0;
	                end else begin
	                    key3_timer <= key3_timer + 26'd1;
	                end
	            end

	            K3_PRESS2_DEB: begin
	                if (key3_sync[1]) begin
	                    // �?2 次按下的微小毛刺，退回判定窗�?
	                    key3_state <= K3_WAIT_CLICK2;
	                    key3_timer <= 26'd0;
	                end else if (k3_debounce_early && k3_timer_running) begin
	                    // 持续按下�?20ms -> 【确定为双击 Double-Click！�?
	                    // 切换音量 (100% -> 75% -> 50% -> 25% -> MUTE)
	                    vol_mode   <= (vol_mode >= 3'd4) ? 3'd0 : (vol_mode + 3'd1);
	                    key3_state <= K3_WAIT2_REL;
	                    key3_timer <= 26'd0;
	                end else begin
	                    key3_timer <= key3_timer + 26'd1;
	                end
	            end

	            K3_WAIT2_REL: begin
	                key3_timer <= 26'd0;
	                if (key3_sync[1]) begin
	                    // 检测到�?2 次松开
	                    key3_state <= K3_REL2_DEB;
	                end
	            end

	            K3_REL2_DEB: begin
	                if (!key3_sync[1]) begin
	                    // 回弹防抖
	                    key3_state <= K3_WAIT2_REL;
	                    key3_timer <= 26'd0;
	                end else if (k3_cool_early && k3_timer_running) begin
	                    // 稳定松开�?30ms，彻底平息机械回弹，返回空闲待命
	                    key3_state <= K3_IDLE;
	                    key3_timer <= 26'd0;
	                end else begin
	                    key3_timer <= key3_timer + 26'd1;
	                end
	            end

	            K3_WAIT_LONG_REL: begin
	                key3_timer <= 26'd0;
	                if (key3_sync[1]) begin
	                    // 长按触发后，检测到松开
	                    key3_state <= K3_REL_LONG_DEB;
	                end
	            end

	            K3_REL_LONG_DEB: begin
	                if (!key3_sync[1]) begin
	                    // 回弹防抖，重新等待松开
	                    key3_state <= K3_WAIT_LONG_REL;
	                    key3_timer <= 26'd0;
	                end else if (k3_cool_early && k3_timer_running) begin
	                    // 稳定松开�?30ms，平息机械回弹，返回空闲待命
	                    key3_state <= K3_IDLE;
	                    key3_timer <= 26'd0;
	                end else begin
	                    key3_timer <= key3_timer + 26'd1;
	                end
	            end

	            default: begin
	                key3_state <= K3_IDLE;
	                key3_timer <= 26'd0;
	            end
	        endcase

	        // Direction 1: Menu item adjustments for Volume and Scaling
	        if (menu_active) begin
	            if (menu_cursor == 3'd1) begin // Item 1: Volume
	                if (menu_inc_pulse)      vol_mode <= (vol_mode >= 3'd4) ? 3'd0 : (vol_mode + 3'd1);
	                else if (menu_dec_pulse) vol_mode <= (vol_mode == 3'd0) ? 3'd4 : (vol_mode - 3'd1);
	            end else if (menu_cursor == 3'd3) begin // Item 3: Scale
	                if (menu_inc_pulse)      scale_mode <= scale_mode + 2'd1;
	                else if (menu_dec_pulse) scale_mode <= scale_mode - 2'd1;
	            end
	        end
	    end
	end

	// =============================================================
	// =============================================================
	// KEY4 (key2_gated, 引脚 C1) 单击(自动轮播)、双�?切换转场特效)、长�?应急广播模�? 硬件状态机 (FSM)
	// - 单击 (< 1.5s �?350ms 内无�?2 次按�?: 产生 30ms 有效低电平脉冲切换自动轮�?
	// - 双击 (350ms 窗口内第 2 次按�?: 切换转场特效模式 (0: FADE -> 1: BLND -> 2: SLID -> 3: AUTO)
	// - 长按 (持续按下 >= 1.5s，满 75,000,000 周期): 翻转 emergency_mode，松开时屏蔽短按防误触
	// =============================================================
	localparam K2_IDLE          = 4'd0; // 空闲待机
	localparam K2_PRESS1_DEB    = 4'd1; // �?1 次按下消�?(20ms)
	localparam K2_HELD          = 4'd2; // 按下保持计时 (1.5s 长按阈值判�?
	localparam K2_REL1_DEB      = 4'd3; // �?1 次松开消抖 (20ms)
	localparam K2_WAIT_CLICK2   = 4'd4; // 判定等待�?(350ms): 等待�?2 次按下，超时则判定为单击
	localparam K2_SINGLE_ACT    = 4'd5; // 确认单击：产�?30ms 脉冲触发轮播
	localparam K2_PRESS2_DEB    = 4'd6; // �?2 次按下消�?(20ms)，确认双击！
	localparam K2_WAIT2_REL     = 4'd7; // 等待�?2 次松开 (30ms 冷却)，返回空�?
	localparam K2_WAIT_LONG_REL = 4'd8; // 确认长按：翻转应急模式，等待松开
	localparam K2_REL_LONG_DEB  = 4'd9; // 长按松开消抖 (30ms 冷却)

	wire scada_toggle_auto = (cmd_auto_set && !auto_play_status) ||
	                         (cmd_auto_clr &&  auto_play_status);

	always @(posedge clk or posedge rst_all) begin
	    if (rst_all) begin
	        key2_sync         <= 2'b11;
	        key2_state        <= K2_IDLE;
	        key2_timer        <= 27'd0;
	        trans_user_mode   <= 3'd4; // 默认 AUTO 自动循环交替 (Fade -> Blinds -> Slide)
	        emergency_mode    <= 1'b0;
	        key2_auto_out     <= 1'b1;
	        k2_menu_dec_pulse <= 1'b0;
	    end else begin
	        key2_sync         <= {key2_sync[0], key2_gated};
	        k2_menu_dec_pulse <= 1'b0;

	        // SCADA 远程应急模式与转场特效控制超驰
	        if (cmd_emerg_set) begin
	            emergency_mode <= 1'b1;
	        end else if (cmd_emerg_clr) begin
	            emergency_mode <= 1'b0;
	        end
	        if (cmd_trans_vld) begin
	            trans_user_mode <= cmd_trans_val;
	        end

	        case (key2_state)
	            K2_IDLE: begin
	                key2_timer    <= 27'd0;
	                key2_auto_out <= 1'b1;
	                if (scada_toggle_auto) begin
	                    key2_state <= K2_SINGLE_ACT;
	                end else if (!key2_sync[1]) begin
	                    key2_state <= K2_PRESS1_DEB;
	                end
	            end

	            K2_PRESS1_DEB: begin
	                if (key2_sync[1]) begin
	                    key2_state <= K2_IDLE;
	                    key2_timer <= 26'd0;
	                end else if (key2_timer >= 26'd1_000_000 - 1) begin
	                    // 持续按下稳定�?20ms，确认为真实按键动作
	                    if (menu_active) k2_menu_dec_pulse <= 1'b1; // 菜单模式：立即响�?VALUE - (0延迟)
	                    key2_state <= K2_HELD;
	                    key2_timer <= 26'd1_000_000;
	                end else begin
	                    key2_timer <= key2_timer + 26'd1;
	                end
	            end

	            K2_HELD: begin
	                if (!menu_active && (key2_timer >= 26'd50_000_000 - 1)) begin
	                    // 持续按下超过 1.0 �?-> 【仅在正常模式下翻转应急模式�?
	                    emergency_mode <= ~emergency_mode;
	                    key2_state     <= K2_WAIT_LONG_REL;
	                    key2_timer     <= 26'd0;
	                end else if (key2_sync[1]) begin
	                    // �?1.0 秒前松开按键 -> 进入松开消抖以准备判定单击或双击
	                    key2_state <= K2_REL1_DEB;
	                    key2_timer <= 26'd0;
	                end else begin
	                    key2_timer <= key2_timer + 26'd1;
	                end
	            end

	            K2_REL1_DEB: begin
	                if (!key2_sync[1]) begin
	                    // 松开过程中有抖动回弹，恢复保持计�?
	                    key2_state <= K2_HELD;
	                    key2_timer <= menu_active ? 26'd0 : 26'd1_000_000;
	                end else if (key2_timer >= 26'd1_000_000 - 1) begin
	                    if (menu_active) begin
	                        // 菜单模式：松开消抖�?20ms 直接返回空闲�?
	                        key2_state <= K2_IDLE;
	                        key2_timer <= 26'd0;
	                    end else begin
	                        // 稳定松开�?20ms，开�?350ms 双击判定窗口
	                        key2_state <= K2_WAIT_CLICK2;
	                        key2_timer <= 26'd0;
	                    end
	                end else begin
	                    key2_timer <= key2_timer + 26'd1;
	                end
	            end

	            K2_WAIT_CLICK2: begin
	                if (!key2_sync[1]) begin
	                    // �?350ms 窗口内检测到�?2 次按�?-> 进入�?2 次按下消�?
	                    key2_state <= K2_PRESS2_DEB;
	                    key2_timer <= 26'd0;
	                end else if (key2_timer >= 26'd17_500_000 - 1) begin
	                    // 350ms 窗口超时未等到第 2 次按�?-> 【确定为单击 Single-Click！�?
	                    key2_state <= K2_SINGLE_ACT;
	                    key2_timer <= 26'd0;
	                end else begin
	                    key2_timer <= key2_timer + 26'd1;
	                end
	            end

	            K2_SINGLE_ACT: begin
	                // 输出 30ms 有效低电平脉冲，驱动 sd_card_bmp 切换自动播放
	                key2_auto_out <= 1'b0;
	                if (key2_timer >= 26'd1_500_000 - 1) begin
	                    key2_auto_out <= 1'b1;
	                    key2_state    <= K2_IDLE;
	                    key2_timer    <= 26'd0;
	                end else begin
	                    key2_timer <= key2_timer + 26'd1;
	                end
	            end

	            K2_PRESS2_DEB: begin
	                if (key2_sync[1]) begin
	                    // �?2 次按下的微小毛刺，退回判定窗�?
	                    key2_state <= K2_WAIT_CLICK2;
	                    key2_timer <= 26'd0;
	                end else if (key2_timer >= 26'd1_000_000 - 1) begin
	                    // 持续按下�?20ms -> 【确定为双击 Double-Click！�?
	                    // 循环切换转场特效模式: 0 (Fade) -> 1 (Blinds) -> 2 (Slide) -> 3 (Auto) -> 0...
	                    trans_user_mode <= (trans_user_mode >= 3'd4) ? 3'd0 : (trans_user_mode + 3'd1);
	                    key2_state      <= K2_WAIT2_REL;
	                    key2_timer      <= 26'd0;
	                end else begin
	                    key2_timer <= key2_timer + 26'd1;
	                end
	            end

	            K2_WAIT2_REL: begin
	                if (!key2_sync[1]) begin
	                    key2_timer <= 26'd0;
	                end else if (key2_timer >= 26'd1_500_000 - 1) begin
	                    // 稳定松开�?30ms，彻底消除按键杂波，返回空闲待命
	                    key2_state <= K2_IDLE;
	                    key2_timer <= 26'd0;
	                end else begin
	                    key2_timer <= key2_timer + 26'd1;
	                end
	            end

	            K2_WAIT_LONG_REL: begin
	                // 长按触发后屏蔽任何短按输出，静候按键松开
	                key2_auto_out <= 1'b1;
	                key2_timer    <= 26'd0;
	                if (key2_sync[1]) begin
	                    key2_state <= K2_REL_LONG_DEB;
	                end
	            end

	            K2_REL_LONG_DEB: begin
	                key2_auto_out <= 1'b1;
	                if (!key2_sync[1]) begin
	                    key2_state <= K2_WAIT_LONG_REL;
	                    key2_timer <= 26'd0;
	                end else if (key2_timer >= 26'd1_500_000 - 1) begin
	                    // 稳定松开�?30ms，彻底消除按键杂波，返回空闲待命
	                    key2_state <= K2_IDLE;
	                    key2_timer <= 26'd0;
	                end else begin
	                    key2_timer <= key2_timer + 26'd1;
	                end
	            end

	            default: begin
	                key2_state    <= K2_IDLE;
	                key2_timer    <= 26'd0;
	                key2_auto_out <= 1'b1;
	            end
	        endcase

	        // Direction 1: Menu item adjustment for Transition Mode
	        if (menu_active && menu_cursor == 3'd5) begin
	            if (menu_inc_pulse)      trans_user_mode <= (trans_user_mode >= 3'd4) ? 3'd0 : (trans_user_mode + 3'd1);
	            else if (menu_dec_pulse) trans_user_mode <= (trans_user_mode == 3'd0) ? 3'd4 : (trans_user_mode - 3'd1);
	        end
	    end
	end

	// =============================================================
	// 创新 3: 隧道监控中心 SCADA 工业总线�?1Hz 环境遥测回传控制�?
	// =============================================================
	wire marq_frame_pulse,marq_hidden,marq_custom_valid,marq_normal_reset;
	wire [6:0] marq_read_addr,marq_read_data;
	uart_scada_controller u_uart_scada (
        .video_clk(video_clk),.marq_frame_pulse(marq_frame_pulse),.marq_read_addr(marq_read_addr),
        .marq_read_data(marq_read_data),.marq_custom_valid(marq_custom_valid),.marq_hidden(marq_hidden),.marq_normal_reset(marq_normal_reset),
	    .clk             (clk),
	    .rst             (rst_all),
	    .uart_rx         (uart_rx),
	    .uart_tx         (uart_tx),
	    .ble_rx          (ble_rx),
	    .ble_tx          (ble_tx),
	    .emergency_mode  (emergency_mode),
	    .auto_play_status(auto_play_status),
	    .scale_mode_in   (scale_mode),
	    .vol_mode_in     (vol_mode),
	    .cmd_emerg_set   (cmd_emerg_set),
	    .cmd_emerg_clr   (cmd_emerg_clr),
	    .cmd_next_pulse  (cmd_next_pulse),
	    .cmd_auto_set    (cmd_auto_set),
	    .cmd_auto_clr    (cmd_auto_clr),
	    .cmd_scale_vld   (cmd_scale_vld),
	    .cmd_scale_val   (cmd_scale_val),
	    .cmd_vol_vld     (cmd_vol_vld),
	    .cmd_vol_val     (cmd_vol_val),
	    .cmd_trans_vld   (cmd_trans_vld),
	    .cmd_trans_val   (cmd_trans_val),
	    .cmd_alpha_vld   (cmd_alpha_vld),
	    .cmd_alpha_val   (cmd_alpha_val),
	    .scada_active    (scada_active),
	    .scada_rx_pulse  (scada_rx_pulse)
	);

	// =============================================================
	// 创新 2: ST7735S 1.44�?128x128 SPI TFT 彩色 LCD 独立遥测中控副屏
	// =============================================================
	// SDFT Multi-Screen Synergy Cross-Clock Domain Synchronizers (video_clk 25MHz -> clk 50MHz)
	wire [39:0] osd_sdft_spec_8b;
	wire [39:0] osd_sdft_peak_8b;
    wire [79:0] lcd_audio_snapshot;
    wire [39:0] sdft_spec_sync2=lcd_audio_snapshot[39:0];
    wire [39:0] sdft_peak_sync2=lcd_audio_snapshot[79:40];
    reg [18:0] lcd_snapshot_counter;
    always @(posedge video_clk or posedge rst_all)
      if(rst_all) lcd_snapshot_counter<=0;
      else lcd_snapshot_counter<=lcd_snapshot_counter==19'd416666 ? 19'd0 : lcd_snapshot_counter+1'b1;
    audio_snapshot_cdc lcd_audio_cdc(.src_clk(video_clk),.dst_clk(clk),.rst(rst_all),
      .data_in({osd_sdft_peak_8b,osd_sdft_spec_8b}),.send(lcd_snapshot_counter==0),.data_out(lcd_audio_snapshot),.received());

    // Color filter mode definition (dynamically controlled by OSD menu with initial DIP switch defaults)
    wire [1:0] color_mode = menu_color_mode;

    // Synchronize active transition step to clk domain for secondary screen telemetry
    reg [1:0] trans_auto_step_s0, trans_auto_step_s1;
    always @(posedge clk or posedge rst_all) begin
        if (rst_all) begin
            trans_auto_step_s0 <= 2'd0;
            trans_auto_step_s1 <= 2'd0;
        end else begin
            trans_auto_step_s0 <= trans_auto_step;
            trans_auto_step_s1 <= trans_auto_step_s0;
        end
    end
    wire [1:0] active_trans_for_lcd = (trans_user_mode == 3'd4) ? trans_auto_step_s1 : trans_user_mode[1:0];

    reg [3:0] img_found_total_50m_d0, img_found_total_50m;
    always @(posedge clk or posedge rst_all) begin
        if (rst_all) begin
            img_found_total_50m_d0 <= 4'd4;
            img_found_total_50m    <= 4'd4;
        end else begin
            img_found_total_50m_d0 <= (img_found_total != 4'd0) ? img_found_total : 4'd4;
            img_found_total_50m    <= img_found_total_50m_d0;
        end
    end

	lcd_st7735_telemetry #(
	    .COL_OFFSET     (8'd0), // 1.8�?128x160 默认水平偏移 0
	    .ROW_OFFSET     (8'd0)  // 1.8�?128x160 默认垂直偏移 0
	) u_lcd_telemetry (
	    .clk            (clk),
	    .rst            (rst_all),
	    .lcd_scl        (lcd_scl),
	    .lcd_mosi       (lcd_mosi),
	    .lcd_cs         (lcd_cs),
	    .lcd_dc         (lcd_dc),
	    .lcd_rst        (lcd_rst),
	    .lcd_blk        (lcd_blk),
	    .cur_img_idx    (cur_img_idx),
	    .img_total_count(img_found_total_50m),
	    .scale_mode     (scale_mode),
	    .vol_mode       (vol_mode),
	    .audio_pcm      (audio_left_data),
	    .audio_valid    (audio_valid),
	    .emergency_mode (emergency_mode),
	    .trans_mode     (trans_user_mode),
	    .active_trans   (active_trans_for_lcd),
	    .color_mode     (color_mode),
	    .sdft_spec_8b   (sdft_spec_sync2),
	    .sdft_peak_8b   (sdft_peak_sync2)
	);



	// SCADA 远程切图脉冲展宽: 2 ticks (~42ms) 有效低电�?+ 1 tick (~21ms) 释放冷却 (复用 hb_tick_50hz)
	reg [1:0] cmd_next_state;
	reg [1:0] cmd_next_cnt;
	reg       cmd_next_active_low;

	always @(posedge clk or posedge rst_all) begin
	    if (rst_all) begin
	        cmd_next_state      <= 2'd0;
	        cmd_next_cnt        <= 2'd0;
	        cmd_next_active_low <= 1'b1;
	    end else begin
	        case (cmd_next_state)
	            2'd0: begin // IDLE
	                cmd_next_active_low <= 1'b1;
	                cmd_next_cnt        <= 2'd0;
	                if (cmd_next_pulse) begin
	                    cmd_next_state      <= 2'd1;
	                    cmd_next_active_low <= 1'b0;
	                end
	            end
	            2'd1: begin // ACTIVE LOW (~42ms)
	                cmd_next_active_low <= 1'b0;
	                if (hb_tick_50hz) begin
	                    if (cmd_next_cnt == 2'd1) begin
	                        cmd_next_state      <= 2'd2;
	                        cmd_next_cnt        <= 2'd0;
	                        cmd_next_active_low <= 1'b1;
	                    end else begin
	                        cmd_next_cnt <= cmd_next_cnt + 2'd1;
	                    end
	                end
	            end
	            2'd2: begin // COOLDOWN HIGH (~21ms)
	                cmd_next_active_low <= 1'b1;
	                if (hb_tick_50hz) begin
	                    cmd_next_state <= 2'd0;
	                    cmd_next_cnt   <= 2'd0;
	                end
	            end
	            default: cmd_next_state <= 2'd0;
	        endcase
	    end
	end

	// =============================================================
	// KEY2 (引脚 B2, 板载丝印 KEY2, 端口 key1_gated)
	// 单击 (切下一张图�? �?双击 (切换对比�?1.0X / 1.5X) 硬件级有限状态机 (FSM)
	// 单击：松开并在 350ms 窗口超时后，产生 30ms 有效低电平脉冲触发切�?
	// 双击：在 350ms 窗口内检测到�?2 次有效按下，翻转 contrast_mode，完全屏蔽切图脉�?
	// =============================================================
	localparam K1_IDLE          = 4'd0; // 空闲待机 (等待�?1 次按�?
	localparam K1_PRESS1_DEB    = 4'd1; // �?1 次按下消�?(20ms)
	localparam K1_WAIT1_REL     = 4'd2; // 等待�?1 次松开或长按判�?
	localparam K1_REL1_DEB      = 4'd3; // �?1 次松开消抖 (20ms)
	localparam K1_WAIT_CLICK2   = 4'd4; // 判定等待�?(350ms): 等待�?2 次按下，超时判定为单�?
	localparam K1_SINGLE_ACT    = 4'd5; // 确认单击：输�?30ms 脉冲触发切图
	localparam K1_PRESS2_DEB    = 4'd6; // �?2 次按下消�?(20ms)，确认双击！
	localparam K1_WAIT2_REL     = 4'd7; // 等待�?2 次松开 (30ms 冷却)，返回空�?
	localparam K1_LONG_ACT      = 4'd8; // 确认长按�?1.0s：切换数码管显示模式 (PIC -> SP1 -> SP2 -> AUT)
	localparam K1_WAIT_LONG_REL = 4'd9; // 等待长按松开
	localparam K1_REL_LONG_DEB  = 4'd10;// 长按松开消抖 (20ms)

	always @(posedge clk or posedge rst_all) begin
	    if (rst_all) begin
	        key1_sync            <= 2'b11;
	        key1_state           <= K1_IDLE;
	        key1_timer           <= 26'd0;
	        contrast_mode        <= 3'd0; // 默认 1.00X 标准对比�?
	        seg_disp_mode        <= 2'd0; // 默认图片状态模�?(P-01-A)
	        key1_next_active_low <= 1'b1;
	        k1_menu_inc_pulse    <= 1'b0;
	    end else begin
	        key1_sync         <= {key1_sync[0], key1_gated};
	        k1_menu_inc_pulse <= 1'b0;

	        case (key1_state)
	            K1_IDLE: begin
	                key1_timer           <= 26'd0;
	                key1_next_active_low <= 1'b1;
	                if (!key1_sync[1]) begin
	                    key1_state <= K1_PRESS1_DEB;
	                end
	            end

	            K1_PRESS1_DEB: begin
	                if (key1_sync[1]) begin
	                    // 前沿抖动/毛刺，退回空�?
	                    key1_state <= K1_IDLE;
	                    key1_timer <= 26'd0;
	                end else if (key1_timer >= 26'd500_000 - 1) begin
	                    // 持续按下稳定 20ms，确认为有效�?1 次按�?
	                    if (menu_active) k1_menu_inc_pulse <= 1'b1; // 菜单模式：立即触�?VALUE + (0延迟)
	                    key1_state <= K1_WAIT1_REL;
	                    key1_timer <= 26'd0;
	                end else begin
	                    key1_timer <= key1_timer + 26'd1;
	                end
	            end

	            K1_WAIT1_REL: begin
	                if (key1_sync[1]) begin
	                    // 持续按下未达 1.0s 即松开 -> 判定为短按候选，进入松开消抖以判决单击或双击
	                    key1_state <= K1_REL1_DEB;
	                    key1_timer <= 26'd0;
	                end else if (!menu_active && (key1_timer >= 26'd49_000_000 - 1)) begin
	                    // 持续按住�?1.0s -> 【仅在正常模式下确认为长按�?
	                    key1_state <= K1_LONG_ACT;
	                    key1_timer <= 26'd0;
	                end else begin
	                    key1_timer <= key1_timer + 26'd1;
	                end
	            end

	            K1_LONG_ACT: begin
	                // 切换数码管显示模�?(PIC -> SP1 -> SP2 -> AUT)
	                seg_disp_mode <= (seg_disp_mode >= 2'd3) ? 2'd0 : (seg_disp_mode + 2'd1);
	                key1_state    <= K1_WAIT_LONG_REL;
	                key1_timer    <= 26'd0;
	            end

	            K1_WAIT_LONG_REL: begin
	                key1_timer <= 26'd0;
	                if (key1_sync[1]) begin
	                    // 长按触发后，检测到按键松开
	                    key1_state <= K1_REL_LONG_DEB;
	                end
	            end

	            K1_REL_LONG_DEB: begin
	                if (!key1_sync[1]) begin
	                    // 回弹防抖，重新等待松开
	                    key1_state <= K1_WAIT_LONG_REL;
	                    key1_timer <= 26'd0;
	                end else if (key1_timer >= 26'd1_000_000 - 1) begin
	                    // 稳定松开�?20ms，平息机械回弹，返回空闲待命
	                    key1_state <= K1_IDLE;
	                    key1_timer <= 26'd0;
	                end else begin
	                    key1_timer <= key1_timer + 26'd1;
	                end
	            end

	            K1_REL1_DEB: begin
	                if (!key1_sync[1]) begin
	                    // 松开过程中有回弹杂波，重新等待松开
	                    key1_state <= K1_WAIT1_REL;
	                    key1_timer <= 26'd0;
	                end else if (key1_timer >= 26'd500_000 - 1) begin
	                    if (menu_active) begin
	                        // 菜单模式：松开消抖 10ms 直接返回空闲
	                        key1_state <= K1_IDLE;
	                        key1_timer <= 26'd0;
	                    end else begin
	                        // 正常模式：短按松开满 10ms 立即确认单击切图！彻底消灭 350ms 双击等待滞后！
	                        key1_state <= K1_SINGLE_ACT;
	                        key1_timer <= 26'd0;
	                    end
	                end else begin
	                    key1_timer <= key1_timer + 26'd1;
	                end
	            end

	            K1_WAIT_CLICK2: begin
	                if (!key1_sync[1]) begin
	                    // �?350ms 窗口内检测到�?2 次按�?-> 进入�?2 次按下消�?
	                    key1_state <= K1_PRESS2_DEB;
	                    key1_timer <= 26'd0;
	                end else if (key1_timer >= 26'd17_500_000 - 1) begin
	                    // 350ms 窗口超时未等到第 2 次按�?-> 【确定为单击 Single-Click！�?
	                    // 正常模式：转入脉冲输出状态，产生 30ms 有效低电平脉冲触发切�?
	                    key1_state <= K1_SINGLE_ACT;
	                    key1_timer <= 26'd0;
	                end else begin
	                    key1_timer <= key1_timer + 26'd1;
	                end
	            end

	            K1_SINGLE_ACT: begin
	                // 输出 30ms 有效低电平脉冲驱�?TF 切图
	                key1_next_active_low <= 1'b0;
	                if (key1_timer >= 26'd500_000 - 1) begin
	                    key1_next_active_low <= 1'b1;
	                    key1_state           <= K1_IDLE;
	                    key1_timer           <= 26'd0;
	                end else begin
	                    key1_timer <= key1_timer + 26'd1;
	                end
	            end

	            K1_PRESS2_DEB: begin
	                if (key1_sync[1]) begin
	                    // �?2 次按下的微小毛刺，退回判定窗�?
	                    key1_state <= K1_WAIT_CLICK2;
	                    key1_timer <= 26'd0;
	                end else if (key1_timer >= 26'd1_000_000 - 1) begin
	                    // 持续按下�?20ms -> 【确定为双击 Double-Click！�?
	                    // 切换对比度模�?(0: 1.00X, 1: 1.25X, 2: 1.50X, 3: 2.00X, 4: 0.75X)
	                    contrast_mode <= (contrast_mode >= 3'd4) ? 3'd0 : (contrast_mode + 3'd1);
	                    key1_state    <= K1_WAIT2_REL;
	                    key1_timer    <= 26'd0;
	                end else begin
	                    key1_timer <= key1_timer + 26'd1;
	                end
	            end

	            K1_WAIT2_REL: begin
	                if (!key1_sync[1]) begin
	                    // 还在按着，重置计时器等待彻底松开
	                    key1_timer <= 26'd0;
	                end else if (key1_timer >= 26'd1_500_000 - 1) begin
	                    // 稳定松开�?30ms，彻底平息机械回弹，返回空闲待命
	                    key1_state <= K1_IDLE;
	                    key1_timer <= 26'd0;
	                end else begin
	                    key1_timer <= key1_timer + 26'd1;
	                end
	            end

	            default: begin
	                key1_state           <= K1_IDLE;
	                key1_timer           <= 26'd0;
	                key1_next_active_low <= 1'b1;
	            end
	        endcase

	        // Direction 1: Menu item adjustment for Contrast Mode
	        if (menu_active && menu_cursor == 3'd4) begin
	            if (menu_inc_pulse)      contrast_mode <= (contrast_mode == 3'd4) ? 3'd0 : (contrast_mode + 3'd1);
	            else if (menu_dec_pulse) contrast_mode <= (contrast_mode == 3'd0) ? 3'd4 : (contrast_mode - 3'd1);
	        end
	    end
	end

	wire final_key_next = key1_next_active_low & cmd_next_active_low;

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .extlock    (sys_pll_lock),
    .reset      (1'b0)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .extlock    (video_pll_lock),
    .reset      (1'b0)
);

// 复用�?I2S->HDMI 工程里的 PLL，只�?12.288MHz 音频主时�?
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同�?
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// 同步 Sdr_init_done �?sd_card_clk 域，确保 SDRAM 初始化彻底完成后再启�?TF/BMP 控制�?
reg [1:0] sdr_init_done_sd_sync;
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all)
        sdr_init_done_sd_sync <= 2'b00;
    else
        sdr_init_done_sd_sync <= {sdr_init_done_sd_sync[0], Sdr_init_done};
end
wire sd_bmp_rst = rst_all | (~sdr_init_done_sd_sync[1]);

// ===================== TF 多图扫描与缓存（双缓冲） =====================
wire [15:0] bmp_orig_width;
wire [15:0] bmp_orig_height;
wire [15:0] disp_bmp_width;
wire [15:0] disp_bmp_height;

reg [20:0] cur_write_len;
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all)
        cur_write_len <= 21'd307200;
    else
        cur_write_len <= (bmp_orig_width == 16'd0) ? 21'd307200 : (bmp_orig_width * bmp_orig_height);
end

wire [2:0] reader_owner_sd;
sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .AUTO_PLAY_SEC     (3),
    .SCAN_START_SECTOR (32'd16384),
    .SCAN_MAX_SECTOR   (32'd1048576),
    .SCAN_TARGET_COUNT (4'd5)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (sd_bmp_rst),
    .key_next          (final_key_next),
    .key_auto          (key2_auto_out),
    .cur_img_idx       (cur_img_idx),
    .auto_play_status  (auto_play_status),
    .state_code        (state_code),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .bmp_orig_width    (bmp_orig_width),
    .bmp_orig_height   (bmp_orig_height),
    .disp_bmp_width    (disp_bmp_width),
    .disp_bmp_height   (disp_bmp_height),
    .buf0_w_out        (buf0_w_sd),
    .buf0_h_out        (buf0_h_sd),
    .buf1_w_out        (buf1_w_sd),
    .buf1_h_out        (buf1_h_sd),
    .buf0_idx_out      (buf0_idx_sd),
    .buf1_idx_out      (buf1_idx_sd),
    .display_valid     (display_valid),
    .load_fail_hold    (load_fail_hold),
    .play_pos          (play_pos),
    .img_count_out     (img_found_total),

    .reader_bank       (reader_owner_sd[1:0]),
    .reader_valid      (reader_owner_sd[2]),
    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

seg_decoder seg_decoder_m0(
    .bin_data          (cur_img_num),
    .seg_data          (seg_img_data)
);

// -------------------------------------------------------------
// 参数调节数码管临时悬浮显�?(2.5秒倒计�? �?模式切换悬浮提示 (1.5�?
// -------------------------------------------------------------


reg [3:0]  sw_bright_d0, sw_bright_d1;
reg [1:0]  scale_mode_d0, scale_mode_d1;
reg [2:0]  vol_mode_d0, vol_mode_d1;
reg [1:0]  alpha_mode_d0, alpha_mode_d1;
reg [2:0]  contrast_mode_d0, contrast_mode_d1;
reg [1:0]  seg_disp_mode_d0, seg_disp_mode_d1;
reg [2:0]  trans_user_mode_d0, trans_user_mode_d1;
reg        auto_play_d0, auto_play_d1;
reg [7:0]  seg_override_timer; // 50Hz tick: 120 * 21ms = 2.5s
reg [7:0]  seg_prompt_timer;   // 50Hz tick: 72 * 21ms = 1.5s
reg [3:0]  override_mode;      // 0: bright, 1: contrast, 2: color, 3: scale, 4: volume, 5: hud, 6: trans, 7: play_mode, 8: alpha

always @(posedge clk or posedge rst_all) begin
    if (rst_all) begin
        sw_bright_d0       <= 4'd0;
        sw_bright_d1       <= 4'd0;
        contrast_mode_d0   <= 3'd0;
        contrast_mode_d1   <= 3'd0;
        scale_mode_d0      <= 2'b11;
        scale_mode_d1      <= 2'b11;
        vol_mode_d0        <= 3'd0;
        vol_mode_d1        <= 3'd0;
        alpha_mode_d0      <= 2'd1;
        alpha_mode_d1      <= 2'd1;
        seg_disp_mode_d0   <= 2'd0;
        seg_disp_mode_d1   <= 2'd0;
        trans_user_mode_d0 <= 3'd4;
        trans_user_mode_d1 <= 3'd4;
        auto_play_d0       <= 1'b0;
        auto_play_d1       <= 1'b0;
        seg_override_timer <= 8'd0;
        seg_prompt_timer   <= 8'd0;
        override_mode      <= 4'd0;
    end else begin
        sw_bright_d0       <= sw_bright;
        sw_bright_d1       <= sw_bright_d0;
        contrast_mode_d0   <= contrast_mode;
        contrast_mode_d1   <= contrast_mode_d0;
        scale_mode_d0      <= scale_mode;
        scale_mode_d1      <= scale_mode_d0;
        vol_mode_d0        <= vol_mode;
        vol_mode_d1        <= vol_mode_d0;
        alpha_mode_d0      <= alpha_mode;
        alpha_mode_d1      <= alpha_mode_d0;
        seg_disp_mode_d0   <= seg_disp_mode;
        seg_disp_mode_d1   <= seg_disp_mode_d0;
        trans_user_mode_d0 <= trans_user_mode;
        trans_user_mode_d1 <= trans_user_mode_d0;
        auto_play_d0       <= auto_play_status;
        auto_play_d1       <= auto_play_d0;

        if (seg_disp_mode_d0 != seg_disp_mode_d1) begin
            seg_prompt_timer   <= 8'd72; // 1.5s 模式提示 (d-PIC / d-SP1 / d-SP2 / d-AUt)
            seg_override_timer <= 8'd0;
        end else if (alpha_mode_d0 != alpha_mode_d1) begin
            seg_override_timer <= 8'd120;
            override_mode      <= 4'd8; // Alpha 模式 (2.5s)
        end else if (trans_user_mode_d0 != trans_user_mode_d1) begin
            seg_override_timer <= 8'd120;
            override_mode      <= 4'd6; // 转场特效模式 (2.5s)
        end else if (auto_play_d0 != auto_play_d1) begin
            seg_override_timer <= 8'd120;
            override_mode      <= 4'd7; // 播放切图模式 (2.5s)
        end else if (contrast_mode_d0 != contrast_mode_d1) begin
            seg_override_timer <= 8'd120;
            override_mode      <= 4'd1; // Contrast Mode
        end else if (sw_bright_d0[1:0] != sw_bright_d1[1:0]) begin
            seg_override_timer <= 8'd120;
            override_mode      <= 4'd0; // Brightness
        end else if (sw_bright_d0[3:2] != sw_bright_d1[3:2]) begin
            seg_override_timer <= 8'd120;
            override_mode      <= 4'd2; // Color Mode
        end else if (scale_mode_d0 != scale_mode_d1) begin
            seg_override_timer <= 8'd120;
            override_mode      <= 4'd3; // Scale
        end else if (vol_mode_d0 != vol_mode_d1) begin
            seg_override_timer <= 8'd120;
            override_mode      <= 4'd4; // Volume
        end else if (hb_tick_50hz) begin
            if (seg_override_timer > 8'd0)
                seg_override_timer <= seg_override_timer - 8'd1;
            if (seg_prompt_timer > 8'd0)
                seg_prompt_timer <= seg_prompt_timer - 8'd1;
        end
    end
end

// 计算参数覆盖段码
reg [7:0] seg_param_0, seg_param_1, seg_param_2, seg_param_3, seg_param_4, seg_param_5;
always @(*) begin
    if (menu_active) begin
        seg_param_0 = 8'hab; // 'n'
        seg_param_1 = 8'h86; // 'E'
        seg_param_2 = 8'hab; // 'n'
        seg_param_3 = 8'hc1; // 'U'
        seg_param_4 = 8'hbf; // '-'
        case (menu_cursor)
            3'd0: seg_param_5 = 8'hf9; // '1'
            3'd1: seg_param_5 = 8'ha4; // '2'
            3'd2: seg_param_5 = 8'hb0; // '3'
            3'd3: seg_param_5 = 8'h99; // '4'
            3'd4: seg_param_5 = 8'h92; // '5'
            3'd5: seg_param_5 = 8'h82; // '6'
            3'd6: seg_param_5 = 8'hf8; // '7'
            default: seg_param_5 = 8'h80; // '8'
        endcase
    end else begin
        case (override_mode)
        3'd0: begin // 亮度: b - 100 / b - 125 / b - 075 / b - 150
            seg_param_0 = 8'h83; // 'b'
            seg_param_1 = 8'hbf; // '-'
            case (sw_bright[1:0])
                2'b00: begin seg_param_2 = 8'hf9; seg_param_3 = 8'hc0; seg_param_4 = 8'hc0; end // 100
                2'b01: begin seg_param_2 = 8'hf9; seg_param_3 = 8'ha4; seg_param_4 = 8'h92; end // 125
                2'b10: begin seg_param_2 = 8'hc0; seg_param_3 = 8'hf8; seg_param_4 = 8'h92; end // 075
                2'b11: begin seg_param_2 = 8'hf9; seg_param_3 = 8'h92; seg_param_4 = 8'hc0; end // 150
            endcase
            seg_param_5 = 8'hff; // blank
        end
        3'd1: begin // 对比�? C - 1 . 0 0 / C - 1 . 2 5 / C - 1 . 5 0 / C - 2 . 0 0 / C - 0 . 7 5
            seg_param_0 = 8'hc6; // 'C'
            seg_param_1 = 8'hbf; // '-'
            case (contrast_mode)
                3'd0: begin seg_param_2 = 8'h79; seg_param_3 = 8'hc0; seg_param_4 = 8'hc0; end // '1.00'
                3'd1: begin seg_param_2 = 8'h79; seg_param_3 = 8'ha4; seg_param_4 = 8'h92; end // '1.25'
                3'd2: begin seg_param_2 = 8'h79; seg_param_3 = 8'h92; seg_param_4 = 8'hc0; end // '1.50'
                3'd3: begin seg_param_2 = 8'h24; seg_param_3 = 8'hc0; seg_param_4 = 8'hc0; end // '2.00'
                3'd4: begin seg_param_2 = 8'h40; seg_param_3 = 8'hf8; seg_param_4 = 8'h92; end // '0.75'
                default: begin seg_param_2 = 8'h79; seg_param_3 = 8'hc0; seg_param_4 = 8'hc0; end
            endcase
            seg_param_5 = 8'hff;
        end
        3'd2: begin // 色彩模式: C L - r G b / C L - b n - / C L - S o b / C L - S P L
            seg_param_0 = 8'hc6; // 'C'
            seg_param_1 = 8'hc7; // 'L'
            seg_param_2 = 8'hbf; // '-'
            case (color_mode)
                2'b00: begin seg_param_3 = 8'haf; seg_param_4 = 8'h82; seg_param_5 = 8'h83; end // 'rGb' (Vivid 彩色)
                2'b01: begin seg_param_3 = 8'h83; seg_param_4 = 8'hab; seg_param_5 = 8'hbf; end // 'bn-' (Mono 黑白)
                2'b10: begin seg_param_3 = 8'h92; seg_param_4 = 8'ha3; seg_param_5 = 8'h83; end // 'Sob' (Rubbing 墨拓)
                2'b11: begin seg_param_3 = 8'h92; seg_param_4 = 8'h8c; seg_param_5 = 8'hc7; end // 'SPL' (Split 分屏)
            endcase
        end
        3'd3: begin // 缩放模式: S - 1 . 0 / S - 2 . 0 / S - 0 . 5 / S - A u t
            seg_param_0 = 8'h92; // 'S'
            seg_param_1 = 8'ha7; // 'c'
            seg_param_2 = 8'hbf; // '-'
            case (scale_mode)
                2'b00: begin seg_param_3 = 8'h79; seg_param_4 = 8'hc0; seg_param_5 = 8'hff; end // '1.' '0' blank -> "Sc-1.0"
                2'b01: begin seg_param_3 = 8'h24; seg_param_4 = 8'hc0; seg_param_5 = 8'hff; end // '2.' '0' blank -> "Sc-2.0"
                2'b10: begin seg_param_3 = 8'h40; seg_param_4 = 8'h92; seg_param_5 = 8'hff; end // '0.' '5' blank -> "Sc-0.5"
                2'b11: begin seg_param_3 = 8'h83; seg_param_4 = 8'hc7; seg_param_5 = 8'hab; end // 'b'  'L'  'n'  -> "Sc-bLn" (Bilinear)
                default: begin seg_param_3 = 8'h88; seg_param_4 = 8'he3; seg_param_5 = 8'h87; end
            endcase
        end
        3'd4: begin // 音量: U - 1 0 0 / U - 0 7 5 / U - 0 5 0 / U - 0 2 5 / U - O F F
            seg_param_0 = 8'hc1; // 'U'
            seg_param_1 = 8'hbf; // '-'
            case (vol_mode)
                3'd0: begin seg_param_2 = 8'hf9; seg_param_3 = 8'hc0; seg_param_4 = 8'hc0; end // 100
                3'd1: begin seg_param_2 = 8'hc0; seg_param_3 = 8'hf8; seg_param_4 = 8'h92; end // 075
                3'd2: begin seg_param_2 = 8'hc0; seg_param_3 = 8'h92; seg_param_4 = 8'hc0; end // 050
                3'd3: begin seg_param_2 = 8'hc0; seg_param_3 = 8'ha4; seg_param_4 = 8'h92; end // 025
                default: begin seg_param_2 = 8'hc0; seg_param_3 = 8'h8e; seg_param_4 = 8'h8e; end // OFF
            endcase
            seg_param_5 = 8'hff; // blank
        end
        3'd5: begin // HUD开�? H u d - O n / H u d - O F
            seg_param_0 = 8'h89; // 'H'
            seg_param_1 = 8'he3; // 'u'
            seg_param_2 = 8'ha1; // 'd'
            seg_param_3 = 8'hbf; // '-'
            if (hud_en) begin
                seg_param_4 = 8'hc0; // 'O'
                seg_param_5 = 8'hab; // 'n'
            end else begin
                seg_param_4 = 8'hc0; // 'O'
                seg_param_5 = 8'h8e; // 'F'
            end
        end
        3'd6: begin // 转场特效模式: t r - F A d / t r - b L d / t r - S L d / t r - A u t
            seg_param_0 = 8'h87; // 't'
            seg_param_1 = 8'haf; // 'r'
            seg_param_2 = 8'hbf; // '-'
            case (trans_user_mode)
                3'd0: begin seg_param_3 = 8'h8e; seg_param_4 = 8'h88; seg_param_5 = 8'ha1; end // 'FAd' (Fade)
                3'd1: begin seg_param_3 = 8'h83; seg_param_4 = 8'hc7; seg_param_5 = 8'ha1; end // 'bLd' (Blinds)
                3'd2: begin seg_param_3 = 8'h92; seg_param_4 = 8'hc7; seg_param_5 = 8'ha1; end // 'SLd' (Slide)
                3'd3: begin seg_param_3 = 8'hab; seg_param_4 = 8'hc0; seg_param_5 = 8'h92; end // 'nOS' (Mosaic)
                3'd4: begin seg_param_3 = 8'h88; seg_param_4 = 8'he3; seg_param_5 = 8'h87; end // 'Aut' (Auto)
                default: begin seg_param_3 = 8'h88; seg_param_4 = 8'he3; seg_param_5 = 8'h87; end
            endcase
        end
        4'd7: begin // 播放切图模式: P L - A u t / P L - H A n
            seg_param_0 = 8'h8c; // 'P'
            seg_param_1 = 8'hc7; // 'L'
            seg_param_2 = 8'hbf; // '-'
            if (auto_play_status) begin
                seg_param_3 = 8'h88; // 'A'
                seg_param_4 = 8'he3; // 'u'
                seg_param_5 = 8'h87; // 't'
            end else begin
                seg_param_3 = 8'h89; // 'H'
                seg_param_4 = 8'h88; // 'A'
                seg_param_5 = 8'hab; // 'n'
            end
        end
        4'd8: begin // Alpha透明�? AL - 25P / AL - 50P / AL - 75P
            seg_param_0 = 8'h88; // 'A'
            seg_param_1 = 8'hc7; // 'L'
            seg_param_2 = 8'hbf; // '-'
            case (alpha_mode)
                2'd0: begin seg_param_3 = 8'ha4; seg_param_4 = 8'h92; seg_param_5 = 8'h8c; end // '2' '5' 'P' (25%)
                2'd2: begin seg_param_3 = 8'hf8; seg_param_4 = 8'h92; seg_param_5 = 8'h8c; end // '7' '5' 'P' (75%)
                default: begin seg_param_3 = 8'h92; seg_param_4 = 8'hc0; seg_param_5 = 8'h8c; end // '5' '0' 'P' (50%)
            endcase
        end
        default: begin
            seg_param_0 = 8'hff;
            seg_param_1 = 8'hff;
            seg_param_2 = 8'hff;
            seg_param_3 = 8'hff;
            seg_param_4 = 8'hff;
            seg_param_5 = 8'hff;
        end
        endcase
    end
end

// ===================== 板载 LED �?蜂鸣�?(Beep & VU) =====================

// 应急模式数码管爆闪显示 "A L - E r r" (�?6Hz 爆闪)
wire emerg_seg_flash = hb_cnt[22];
wire [7:0] emerg_seg_0 = emerg_seg_flash ? 8'h88 : 8'hff; // 'A'
wire [7:0] emerg_seg_1 = emerg_seg_flash ? 8'hc7 : 8'hff; // 'L'
wire [7:0] emerg_seg_2 = emerg_seg_flash ? 8'hbf : 8'hff; // '-'
wire [7:0] emerg_seg_3 = emerg_seg_flash ? 8'h86 : 8'hff; // 'E'
wire [7:0] emerg_seg_4 = emerg_seg_flash ? 8'haf : 8'hff; // 'r'
wire [7:0] emerg_seg_5 = emerg_seg_flash ? 8'haf : 8'hff; // 'r'

// ========================================================================
// 扩展要求5 方向一：数码管 状态显示——频谱模�?幅�?& 自动轮显引擎
// 赛题要求：板�?6 位数码管实时指示当前音频可视化模�?(SP1/SP2) �?00~99 动态音频幅�?
// ========================================================================
// 1. 模式切换提示段码 (1.5s 倒计时悬浮显�? d-PIC / d-SP1 / d-SP2 / d-AUt)
reg [7:0] seg_prompt_0, seg_prompt_1, seg_prompt_2, seg_prompt_3, seg_prompt_4, seg_prompt_5;
always @(*) begin
    case (seg_disp_mode)
        2'd0: begin // d - P I C
            seg_prompt_0 = 8'ha1; // 'd'
            seg_prompt_1 = 8'hbf; // '-'
            seg_prompt_2 = 8'h8c; // 'P'
            seg_prompt_3 = 8'hcf; // 'I'
            seg_prompt_4 = 8'hc6; // 'C'
            seg_prompt_5 = 8'hff; // blank
        end
        2'd1: begin // d - S P 1
            seg_prompt_0 = 8'ha1; // 'd'
            seg_prompt_1 = 8'hbf; // '-'
            seg_prompt_2 = 8'h92; // 'S'
            seg_prompt_3 = 8'h8c; // 'P'
            seg_prompt_4 = 8'hf9; // '1'
            seg_prompt_5 = 8'hff; // blank
        end
        2'd2: begin // d - S P 2
            seg_prompt_0 = 8'ha1; // 'd'
            seg_prompt_1 = 8'hbf; // '-'
            seg_prompt_2 = 8'h92; // 'S'
            seg_prompt_3 = 8'h8c; // 'P'
            seg_prompt_4 = 8'ha4; // '2'
            seg_prompt_5 = 8'hff; // blank
        end
        2'd3: begin // d - A u t
            seg_prompt_0 = 8'ha1; // 'd'
            seg_prompt_1 = 8'hbf; // '-'
            seg_prompt_2 = 8'h88; // 'A'
            seg_prompt_3 = 8'he3; // 'u'
            seg_prompt_4 = 8'h87; // 't'
            seg_prompt_5 = 8'hff; // blank
        end
        default: begin
            seg_prompt_0 = 8'hff;
            seg_prompt_1 = 8'hff;
            seg_prompt_2 = 8'hff;
            seg_prompt_3 = 8'hff;
            seg_prompt_4 = 8'hff;
            seg_prompt_5 = 8'hff;
        end
    endcase
end

// 2. 自动交替轮显定时�?(AUT 模式下基�?1Hz 脉冲�?3 秒交替一次图片状态与音频幅�?
reg [1:0]  auto_sec_cnt;
reg        auto_cycle_phase;
always @(posedge clk or posedge rst_all) begin
    if (rst_all) begin
        auto_sec_cnt     <= 2'd0;
        auto_cycle_phase <= 1'b0;
    end else if (hb_tick_1hz) begin
        if (auto_sec_cnt >= 2'd2) begin
            auto_sec_cnt     <= 2'd0;
            auto_cycle_phase <= ~auto_cycle_phase;
        end else begin
            auto_sec_cnt <= auto_sec_cnt + 2'd1;
        end
    end
end
wire [1:0] effective_disp_mode = (seg_disp_mode == 2'd3) ? (auto_cycle_phase ? 2'd1 : 2'd0) : seg_disp_mode;

// 3. 48kHz 音频有效脉冲同步与瞬态包络检波器 (Instant Attack, 20ms Smooth Decay)
reg [2:0] audio_vld_sync;
always @(posedge clk or posedge rst_all) begin
    if (rst_all)
        audio_vld_sync <= 3'b000;
    else
        audio_vld_sync <= {audio_vld_sync[1:0], audio_valid};
end
wire audio_vld_pulse = (audio_vld_sync[1] && !audio_vld_sync[2]);

wire [23:0] audio_abs    = audio_left_data[23] ? (-audio_left_data) : audio_left_data;
wire [15:0] amp_mult     = audio_abs[22:15] * 7'd100;
wire [7:0]  amp_raw      = amp_mult[15:8];
wire [6:0]  amp_peak     = (amp_raw > 8'd99) ? 7'd99 : amp_raw[6:0];

always @(posedge clk or posedge rst_all) begin
    if (rst_all) begin
        vu_amp <= 7'd0;
    end else begin
        // 瞬时峰值跃�?(Instant Attack)
        if (audio_vld_pulse) begin
            if (amp_peak > vu_amp)
                vu_amp <= amp_peak;
        end

        // 20ms 平滑阻尼回落 (Smooth Decay 50Hz, 复用 hb_tick_50hz)
        if (hb_tick_50hz && (vu_amp > 7'd0)) begin
            if (vu_amp >= 7'd30)
                vu_amp <= vu_amp - 7'd2;
            else
                vu_amp <= vu_amp - 7'd1;
        end
    end
end

// 4. 纯组合逻辑无除�?BCD 拆分 (00 ~ 99)
// Constant BCD lookup preserves all 128 possible input codes.
function [7:0] fn_vu_bcd;
    input [6:0] amp;
    begin
        case(amp)
            7'd0: fn_vu_bcd=8'h00;
            7'd1: fn_vu_bcd=8'h01;
            7'd2: fn_vu_bcd=8'h02;
            7'd3: fn_vu_bcd=8'h03;
            7'd4: fn_vu_bcd=8'h04;
            7'd5: fn_vu_bcd=8'h05;
            7'd6: fn_vu_bcd=8'h06;
            7'd7: fn_vu_bcd=8'h07;
            7'd8: fn_vu_bcd=8'h08;
            7'd9: fn_vu_bcd=8'h09;
            7'd10: fn_vu_bcd=8'h10;
            7'd11: fn_vu_bcd=8'h11;
            7'd12: fn_vu_bcd=8'h12;
            7'd13: fn_vu_bcd=8'h13;
            7'd14: fn_vu_bcd=8'h14;
            7'd15: fn_vu_bcd=8'h15;
            7'd16: fn_vu_bcd=8'h16;
            7'd17: fn_vu_bcd=8'h17;
            7'd18: fn_vu_bcd=8'h18;
            7'd19: fn_vu_bcd=8'h19;
            7'd20: fn_vu_bcd=8'h20;
            7'd21: fn_vu_bcd=8'h21;
            7'd22: fn_vu_bcd=8'h22;
            7'd23: fn_vu_bcd=8'h23;
            7'd24: fn_vu_bcd=8'h24;
            7'd25: fn_vu_bcd=8'h25;
            7'd26: fn_vu_bcd=8'h26;
            7'd27: fn_vu_bcd=8'h27;
            7'd28: fn_vu_bcd=8'h28;
            7'd29: fn_vu_bcd=8'h29;
            7'd30: fn_vu_bcd=8'h30;
            7'd31: fn_vu_bcd=8'h31;
            7'd32: fn_vu_bcd=8'h32;
            7'd33: fn_vu_bcd=8'h33;
            7'd34: fn_vu_bcd=8'h34;
            7'd35: fn_vu_bcd=8'h35;
            7'd36: fn_vu_bcd=8'h36;
            7'd37: fn_vu_bcd=8'h37;
            7'd38: fn_vu_bcd=8'h38;
            7'd39: fn_vu_bcd=8'h39;
            7'd40: fn_vu_bcd=8'h40;
            7'd41: fn_vu_bcd=8'h41;
            7'd42: fn_vu_bcd=8'h42;
            7'd43: fn_vu_bcd=8'h43;
            7'd44: fn_vu_bcd=8'h44;
            7'd45: fn_vu_bcd=8'h45;
            7'd46: fn_vu_bcd=8'h46;
            7'd47: fn_vu_bcd=8'h47;
            7'd48: fn_vu_bcd=8'h48;
            7'd49: fn_vu_bcd=8'h49;
            7'd50: fn_vu_bcd=8'h50;
            7'd51: fn_vu_bcd=8'h51;
            7'd52: fn_vu_bcd=8'h52;
            7'd53: fn_vu_bcd=8'h53;
            7'd54: fn_vu_bcd=8'h54;
            7'd55: fn_vu_bcd=8'h55;
            7'd56: fn_vu_bcd=8'h56;
            7'd57: fn_vu_bcd=8'h57;
            7'd58: fn_vu_bcd=8'h58;
            7'd59: fn_vu_bcd=8'h59;
            7'd60: fn_vu_bcd=8'h60;
            7'd61: fn_vu_bcd=8'h61;
            7'd62: fn_vu_bcd=8'h62;
            7'd63: fn_vu_bcd=8'h63;
            7'd64: fn_vu_bcd=8'h64;
            7'd65: fn_vu_bcd=8'h65;
            7'd66: fn_vu_bcd=8'h66;
            7'd67: fn_vu_bcd=8'h67;
            7'd68: fn_vu_bcd=8'h68;
            7'd69: fn_vu_bcd=8'h69;
            7'd70: fn_vu_bcd=8'h70;
            7'd71: fn_vu_bcd=8'h71;
            7'd72: fn_vu_bcd=8'h72;
            7'd73: fn_vu_bcd=8'h73;
            7'd74: fn_vu_bcd=8'h74;
            7'd75: fn_vu_bcd=8'h75;
            7'd76: fn_vu_bcd=8'h76;
            7'd77: fn_vu_bcd=8'h77;
            7'd78: fn_vu_bcd=8'h78;
            7'd79: fn_vu_bcd=8'h79;
            7'd80: fn_vu_bcd=8'h80;
            7'd81: fn_vu_bcd=8'h81;
            7'd82: fn_vu_bcd=8'h82;
            7'd83: fn_vu_bcd=8'h83;
            7'd84: fn_vu_bcd=8'h84;
            7'd85: fn_vu_bcd=8'h85;
            7'd86: fn_vu_bcd=8'h86;
            7'd87: fn_vu_bcd=8'h87;
            7'd88: fn_vu_bcd=8'h88;
            7'd89: fn_vu_bcd=8'h89;
            7'd90: fn_vu_bcd=8'h90;
            7'd91: fn_vu_bcd=8'h91;
            7'd92: fn_vu_bcd=8'h92;
            7'd93: fn_vu_bcd=8'h93;
            7'd94: fn_vu_bcd=8'h94;
            7'd95: fn_vu_bcd=8'h95;
            7'd96: fn_vu_bcd=8'h96;
            7'd97: fn_vu_bcd=8'h97;
            7'd98: fn_vu_bcd=8'h98;
            7'd99: fn_vu_bcd=8'h99;
            7'd100: fn_vu_bcd=8'h9a;
            7'd101: fn_vu_bcd=8'h9b;
            7'd102: fn_vu_bcd=8'h9c;
            7'd103: fn_vu_bcd=8'h9d;
            7'd104: fn_vu_bcd=8'h9e;
            7'd105: fn_vu_bcd=8'h9f;
            7'd106: fn_vu_bcd=8'h90;
            7'd107: fn_vu_bcd=8'h91;
            7'd108: fn_vu_bcd=8'h92;
            7'd109: fn_vu_bcd=8'h93;
            7'd110: fn_vu_bcd=8'h94;
            7'd111: fn_vu_bcd=8'h95;
            7'd112: fn_vu_bcd=8'h96;
            7'd113: fn_vu_bcd=8'h97;
            7'd114: fn_vu_bcd=8'h98;
            7'd115: fn_vu_bcd=8'h99;
            7'd116: fn_vu_bcd=8'h9a;
            7'd117: fn_vu_bcd=8'h9b;
            7'd118: fn_vu_bcd=8'h9c;
            7'd119: fn_vu_bcd=8'h9d;
            7'd120: fn_vu_bcd=8'h9e;
            7'd121: fn_vu_bcd=8'h9f;
            7'd122: fn_vu_bcd=8'h90;
            7'd123: fn_vu_bcd=8'h91;
            7'd124: fn_vu_bcd=8'h92;
            7'd125: fn_vu_bcd=8'h93;
            7'd126: fn_vu_bcd=8'h94;
            7'd127: fn_vu_bcd=8'h95;
        endcase
    end
endfunction
wire [7:0] vu_bcd=fn_vu_bcd(vu_amp);
wire [3:0] vu_tens=vu_bcd[7:4];
wire [3:0] vu_ones=vu_bcd[3:0];

function [7:0] fn_seg_code;
    input [3:0] hex;
    begin
        case (hex)
            4'd0: fn_seg_code = 8'hc0;
            4'd1: fn_seg_code = 8'hf9;
            4'd2: fn_seg_code = 8'ha4;
            4'd3: fn_seg_code = 8'hb0;
            4'd4: fn_seg_code = 8'h99;
            4'd5: fn_seg_code = 8'h92;
            4'd6: fn_seg_code = 8'h82;
            4'd7: fn_seg_code = 8'hf8;
            4'd8: fn_seg_code = 8'h80;
            4'd9: fn_seg_code = 8'h90;
            default: fn_seg_code = 8'hff;
        endcase
    end
endfunction

// 5. 多模式稳态段码综�?
// Mode 0: P - 0 x - A/H
// Mode 1: S P 1 - x x (Equalizer 频段柱状图模式，右侧两联显示 00~99 动态幅�?
// Mode 2: S P 2 - x x (Waveform 波形图模式，右侧两联显示 00~99 动态幅�?
wire [7:0] mode_seg_0 = (effective_disp_mode == 2'd0) ? 8'h8c : 8'h92; // 'P' or 'S'
wire [7:0] mode_seg_1 = (effective_disp_mode == 2'd0) ? 8'hbf : 8'h8c; // '-' or 'P'
wire [7:0] mode_seg_2 = (effective_disp_mode == 2'd0) ? 8'hc0 : ((effective_disp_mode == 2'd1) ? 8'hf9 : 8'ha4); // '0' or '1' or '2'
wire [7:0] mode_seg_3 = (effective_disp_mode == 2'd0) ? (display_valid ? {1'b1, seg_img_data} : 8'hbf) : 8'hbf; // img_num or '-'
wire [7:0] mode_seg_4 = (effective_disp_mode == 2'd0) ? 8'hbf : fn_seg_code(vu_tens); // '-' or tens
wire [7:0] mode_seg_5 = (effective_disp_mode == 2'd0) ? (load_fail_hold ? 8'h86 : (auto_play_status ? 8'h88 : 8'h89)) : fn_seg_code(vu_ones); // 'A'/'H' or ones

// 6. 全局显示仲裁：应急模�?> 菜单/参数调节覆盖 > 模式切换提示 > 稳态显示模�?
wire is_emerg_active   = emergency_mode;
wire is_param_override = menu_active || (seg_override_timer > 8'd0);
wire is_prompt_active  = (seg_prompt_timer > 8'd0);

wire [7:0] final_seg_0 = is_emerg_active ? emerg_seg_0 : (is_param_override ? seg_param_0 : (is_prompt_active ? seg_prompt_0 : mode_seg_0));
wire [7:0] final_seg_1 = is_emerg_active ? emerg_seg_1 : (is_param_override ? seg_param_1 : (is_prompt_active ? seg_prompt_1 : mode_seg_1));
wire [7:0] final_seg_2 = is_emerg_active ? emerg_seg_2 : (is_param_override ? seg_param_2 : (is_prompt_active ? seg_prompt_2 : mode_seg_2));
wire [7:0] final_seg_3 = is_emerg_active ? emerg_seg_3 : (is_param_override ? seg_param_3 : (is_prompt_active ? seg_prompt_3 : mode_seg_3));
wire [7:0] final_seg_4 = is_emerg_active ? emerg_seg_4 : (is_param_override ? seg_param_4 : (is_prompt_active ? seg_prompt_4 : mode_seg_4));
wire [7:0] final_seg_5 = is_emerg_active ? emerg_seg_5 : (is_param_override ? seg_param_5 : (is_prompt_active ? seg_prompt_5 : mode_seg_5));

// Register display arbitration before the scan mux (uniform CE=1, enables optimal BLE packing and stops logic duplication into seg_scan)
reg [7:0] scan_seg_0,scan_seg_1,scan_seg_2,scan_seg_3,scan_seg_4,scan_seg_5;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scan_seg_0 <= 8'hff; scan_seg_1 <= 8'hff; scan_seg_2 <= 8'hff;
        scan_seg_3 <= 8'hff; scan_seg_4 <= 8'hff; scan_seg_5 <= 8'hff;
    end else begin
        scan_seg_0 <= final_seg_0; scan_seg_1 <= final_seg_1; scan_seg_2 <= final_seg_2;
        scan_seg_3 <= final_seg_3; scan_seg_4 <= final_seg_4; scan_seg_5 <= final_seg_5;
    end
end

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        (scan_seg_0),
    .seg_data_1        (scan_seg_1),
    .seg_data_2        (scan_seg_2),
    .seg_data_3        (scan_seg_3),
    .seg_data_4        (scan_seg_4),
    .seg_data_5        (scan_seg_5)
);

// 4个板载独�?LED (A4, A3, C10, B12)
// 常态显示：系统心跳、TF状态、自动轮播、音频能量跳�?
wire [3:0] led_normal = {
    (audio_left_data[21:18] > 4'd2),
    auto_play_status ? 1'b1 : hb_cnt[23],
    ~play_pos[0],
    hb_cnt[24]
};

// 警车红蓝交替高频爆闪模式：基于系统心跳的分频信号实现左右双灯交替闪烁
wire strobe_side  = hb_cnt[23];                     // 0.75Hz 左右交替
wire strobe_pulse = hb_cnt[21] & hb_cnt[20];       // 6Hz 爆闪脉冲
wire [3:0] led_emergency = strobe_side ? {strobe_pulse, strobe_pulse, 2'b00}
                                       : {2'b00, strobe_pulse, strobe_pulse};

assign led = emergency_mode ? led_emergency : led_normal;

// =============================================================
// 板载蜂鸣�?(管脚 H11) 硬件驱动修复与防空警报发生器
// 低电平导通，高电平截止。常态恒定输出高电平 1'b1 禁鸣�?
// 应急广播开启时，输�?1.2kHz ~ 2.4kHz 往复平滑扫频防空警报方波�?
// =============================================================
reg [15:0] buzz_half_period; // 10417 (2.4kHz) ~ 20833 (1.2kHz)
reg [15:0] buzz_cnt;
reg        buzz_sq;
reg        buzz_sweep_dir;   // 0: 升频, 1: 降频
reg [12:0] buzz_step_cnt;    // 4800 周期步进 (~96us, 单程 1.0s)

always @(posedge clk or posedge rst_all) begin
    if (rst_all) begin
        buzz_half_period <= 16'd20833;
        buzz_cnt         <= 16'd0;
        buzz_sq          <= 1'b1;
        buzz_sweep_dir   <= 1'b0;
        buzz_step_cnt    <= 13'd0;
    end else if (!emergency_mode) begin
        // 常态彻底截止静�?
        buzz_half_period <= 16'd20833;
        buzz_cnt         <= 16'd0;
        buzz_sq          <= 1'b1;
        buzz_sweep_dir   <= 1'b0;
        buzz_step_cnt    <= 13'd0;
    end else begin
        // 扫频步进发生器：1.0s 内完�?1.2kHz <-> 2.4kHz 平滑扫频
        if (buzz_step_cnt >= 13'd4799) begin
            buzz_step_cnt <= 13'd0;
            if (!buzz_sweep_dir) begin
                if (buzz_half_period <= 16'd10417)
                    buzz_sweep_dir <= 1'b1;
                else
                    buzz_half_period <= buzz_half_period - 16'd1;
            end else begin
                if (buzz_half_period >= 16'd20833)
                    buzz_sweep_dir <= 1'b0;
                else
                    buzz_half_period <= buzz_half_period + 16'd1;
            end
        end else begin
            buzz_step_cnt <= buzz_step_cnt + 13'd1;
        end

        // 方波翻转发生�?
        if (buzz_cnt >= buzz_half_period - 16'd1) begin
            buzz_cnt <= 16'd0;
            buzz_sq  <= ~buzz_sq;
        end else begin
            buzz_cnt <= buzz_cnt + 16'd1;
        end
    end
end

assign buzz = emergency_mode ? buzz_sq : 1'b1;

	// -------------------------------------------------------------
	// 跨时钟域信号同步�?video_clk (彻底杜绝亚稳态与跨域时序违例)
	// -------------------------------------------------------------
	reg [1:0]  emergency_mode_v_sync;
	reg [1:0]  emergency_mode_a_sync;
	reg [1:0]  display_valid_a_sync;
	reg [1:0]  scada_active_v_sync;
	always @(posedge video_clk or posedge rst_all) begin
	    if (rst_all) begin
	        emergency_mode_v_sync <= 2'b00;
	        scada_active_v_sync   <= 2'b00;
	    end else begin
	        emergency_mode_v_sync <= {emergency_mode_v_sync[0], emergency_mode};
	        scada_active_v_sync   <= {scada_active_v_sync[0], scada_active};
	    end
	end
	wire emergency_mode_v = emergency_mode_v_sync[1];
	wire scada_active_v   = scada_active_v_sync[1];

	always @(posedge audio_mclk or posedge rst_all) begin
	    if (rst_all) begin
	        emergency_mode_a_sync <= 2'b00;
	        display_valid_a_sync  <= 2'b00;
	    end else begin
	        emergency_mode_a_sync <= {emergency_mode_a_sync[0], emergency_mode};
	        display_valid_a_sync  <= {display_valid_a_sync[0], display_valid};
	    end
	end
	wire emergency_mode_a = emergency_mode_a_sync[1];
	wire display_valid_a  = display_valid_a_sync[1];

	reg [2:0]  contrast_mode_v0, contrast_mode_v1;
	reg [1:0]  hud_en_v_sync;
	reg [1:0]  display_valid_v_sync;
	reg [1:0]  load_fail_v_sync;
	reg [1:0]  sdram_loading_v_sync;
	reg [2:0]  cur_img_idx_v0, cur_img_idx_v1;
	reg [3:0]  img_total_v0, img_total_v1;
	reg        auto_play_v0, auto_play_v1;
	reg [1:0]  disp_buf_idx_v0, disp_buf_idx_v1;
	reg [1:0]  scale_mode_v0, scale_mode_v1;
	reg [1:0]  alpha_mode_v0, alpha_mode_v1;
	reg [1:0]  color_mode_v0, color_mode_v1;
	reg [2:0]  vol_mode_v0, vol_mode_v1;
	reg [15:0] buf0_w_v0, buf0_w_v1;
	reg [15:0] buf0_h_v0, buf0_h_v1;
	reg [15:0] buf1_w_v0, buf1_w_v1;
	reg [15:0] buf1_h_v0, buf1_h_v1;
	reg [2:0]  buf0_idx_v0, buf0_idx_v1;
	reg [2:0]  buf1_idx_v0, buf1_idx_v1;
	reg [2:0]  trans_user_mode_v0, trans_user_mode_v1;
	reg        menu_active_v0, menu_active_v1;
	reg [2:0]  menu_cursor_v0, menu_cursor_v1;
	reg [1:0]  menu_bright_v0, menu_bright_v1;
	reg [1:0]  tone_mode_v0, tone_mode_v1;
	reg [3:0]  state_code_v0, state_code_v1;

	// color_mode is declared earlier above for u_lcd_telemetry

	always @(posedge video_clk or posedge rst_all) begin
	    if (rst_all) begin
	        contrast_mode_v0     <= 3'd0;
	        contrast_mode_v1     <= 3'd0;
	        hud_en_v_sync        <= 2'b00;
	        display_valid_v_sync <= 2'b00;
	        load_fail_v_sync     <= 2'b00;
	        sdram_loading_v_sync <= 2'b00;
	        cur_img_idx_v0       <= 3'd0;
	        cur_img_idx_v1       <= 3'd0;
	        img_total_v0         <= 4'd4;
	        img_total_v1         <= 4'd4;
	        auto_play_v0         <= 1'b0;
	        auto_play_v1         <= 1'b0;
	        disp_buf_idx_v0      <= 2'd0;
	        disp_buf_idx_v1      <= 2'd0;
	        scale_mode_v0        <= 2'b11;
	        scale_mode_v1        <= 2'b11;
	        alpha_mode_v0        <= 2'd1;
	        alpha_mode_v1        <= 2'd1;
	        color_mode_v0        <= 2'b00;
	        color_mode_v1        <= 2'b00;
	        vol_mode_v0          <= 3'd0;
	        vol_mode_v1          <= 3'd0;
	        buf0_w_v0            <= 16'd640;
	        buf0_w_v1            <= 16'd640;
	        buf0_h_v0            <= 16'd480;
	        buf0_h_v1            <= 16'd480;
	        buf1_w_v0            <= 16'd640;
	        buf1_w_v1            <= 16'd640;
	        buf1_h_v0            <= 16'd480;
	        buf1_h_v1            <= 16'd480;
	        buf0_idx_v0          <= 3'd0;
	        buf0_idx_v1          <= 3'd0;
	        buf1_idx_v0          <= 3'd0;
	        buf1_idx_v1          <= 3'd0;
	        trans_user_mode_v0   <= 3'd4;
	        trans_user_mode_v1   <= 3'd4;
	        menu_active_v0       <= 1'b0;
	        menu_active_v1       <= 1'b0;
	        menu_cursor_v0       <= 3'd0;
	        menu_cursor_v1       <= 3'd0;
	        menu_bright_v0       <= 2'b00;
	        menu_bright_v1       <= 2'b00;
	        tone_mode_v0         <= 2'b00;
	        tone_mode_v1         <= 2'b00;
	        state_code_v0        <= 4'd1;
	        state_code_v1        <= 4'd1;
	    end else begin
	        contrast_mode_v0     <= contrast_mode;
	        contrast_mode_v1     <= contrast_mode_v0;
	        hud_en_v_sync        <= {hud_en_v_sync[0], hud_en};
	        display_valid_v_sync <= {display_valid_v_sync[0], display_valid};
	        load_fail_v_sync     <= {load_fail_v_sync[0], load_fail_hold};
	        sdram_loading_v_sync <= {sdram_loading_v_sync[0], sd_card_write_en};
	        cur_img_idx_v0       <= cur_img_idx;
	        cur_img_idx_v1       <= cur_img_idx_v0;
	        img_total_v0         <= img_found_total;
	        img_total_v1         <= img_total_v0;
	        auto_play_v0         <= auto_play_status;
	        auto_play_v1         <= auto_play_v0;
	        disp_buf_idx_v0      <= disp_buf_idx;
	        disp_buf_idx_v1      <= disp_buf_idx_v0;
	        scale_mode_v0        <= scale_mode;
	        scale_mode_v1        <= scale_mode_v0;
	        alpha_mode_v0        <= alpha_mode;
	        alpha_mode_v1        <= alpha_mode_v0;
	        color_mode_v0        <= color_mode;
	        color_mode_v1        <= color_mode_v0;
	        vol_mode_v0          <= vol_mode;
	        vol_mode_v1          <= vol_mode_v0;
	        trans_user_mode_v0   <= trans_user_mode;
	        trans_user_mode_v1   <= trans_user_mode_v0;
	        buf0_w_v0            <= buf0_w_sd;
	        buf0_w_v1            <= buf0_w_v0;
	        buf0_h_v0            <= buf0_h_sd;
	        buf0_h_v1            <= buf0_h_v0;
	        buf1_w_v0            <= buf1_w_sd;
	        buf1_w_v1            <= buf1_w_v0;
	        buf1_h_v0            <= buf1_h_sd;
	        buf1_h_v1            <= buf1_h_v0;
	        buf0_idx_v0          <= buf0_idx_sd;
	        buf0_idx_v1          <= buf0_idx_v0;
	        buf1_idx_v0          <= buf1_idx_sd;
	        buf1_idx_v1          <= buf1_idx_v0;
	        menu_active_v0       <= menu_active;
	        menu_active_v1       <= menu_active_v0;
	        menu_cursor_v0       <= menu_cursor;
	        menu_cursor_v1       <= menu_cursor_v0;
	        menu_bright_v0       <= menu_bright;
	        menu_bright_v1       <= menu_bright_v0;
	        tone_mode_v0         <= tone_mode;
	        tone_mode_v1         <= tone_mode_v0;
	        state_code_v0        <= state_code;
	        state_code_v1        <= state_code_v0;
	    end
	end

	wire [2:0]  contrast_mode_v     = contrast_mode_v1;
	wire        hud_en_v            = hud_en_v_sync[1];
	wire [1:0]  alpha_mode_v        = alpha_mode_v1;
	wire        display_valid_v     = display_valid_v_sync[1];
	wire        load_fail_hold_v    = load_fail_v_sync[1];
	wire        sdram_loading_v     = sdram_loading_v_sync[1];
	wire [2:0]  cur_img_idx_v       = (disp_buf_idx_v == 2'd0) ? buf0_idx_v1 : buf1_idx_v1;
	wire [3:0]  img_total_count_v   = (img_total_v1 != 4'd0) ? img_total_v1 : 4'd4;
	wire        auto_play_status_v  = auto_play_v1;
	wire [1:0]  disp_buf_idx_target = disp_buf_idx_v1;
	// Apply a requested scale mode atomically at a frame boundary. Hold it
	// through both halves of a transition so FIFO consumption stays consistent.
	reg [1:0] scale_mode_frame;
	wire [1:0] scale_mode_v = scale_mode_frame;
	always @(posedge video_clk or posedge rst_all) begin
	    if (rst_all) scale_mode_frame <= 2'd3;
	    else if (vs_fall_pulse && !fade_active) scale_mode_frame <= scale_mode_v1;
	end
	wire [1:0]  color_mode_v        = color_mode_v1;
	wire [2:0]  vol_mode_v          = vol_mode_v1;
	wire [2:0]  trans_user_mode_v   = trans_user_mode_v1;
	wire        menu_active_v       = menu_active_v1;
	wire [2:0]  menu_cursor_v       = menu_cursor_v1;
	wire [1:0]  menu_bright_v       = menu_bright_v1;
	wire [1:0]  tone_mode_v         = tone_mode_v1;
	wire [3:0]  disp_state_code     = load_fail_hold_v                                            ? 4'd5 : // 5: FAIL
	                                  (state_code_v1 == 4'd2)                                     ? 4'd2 : // 2: SEEK BMP
	                                  (sdram_loading_v || state_code_v1 == 4'd3 || state_code_v1 == 4'd4) ? 4'd3 : // 3: WRITE SDRAM
	                                  display_valid_v                                             ? 4'd4 : // 4: OSD OVERLAY
	                                  4'd1;                                                                // 1: IDLE
	wire [15:0] disp_bmp_width_v    = (disp_buf_idx_v == 2'd0) ? buf0_w_v1 : buf1_w_v1;
	wire [15:0] disp_bmp_height_v   = (disp_buf_idx_v == 2'd0) ? buf0_h_v1 : buf1_h_v1;
	wire [20:0] cur_disp_buf_base = (disp_buf_idx_v == 2'd0) ? BUF0_ADDR : BUF1_ADDR;
    wire scaler_read_req, scaler_read_ack, source_empty;
    wire [20:0] scaler_read_base, scaler_read_len;
    reg scaler_ack_previous;
    reg [2:0] reader_owner_mem;
    always @(posedge ext_mem_clk or posedge rst_all) begin
        if (rst_all) begin scaler_ack_previous <= 0; reader_owner_mem <= 0; end
        else begin
            scaler_ack_previous <= scaler_read_ack;
            if (scaler_read_ack && !scaler_ack_previous)
                reader_owner_mem <= {1'b1, (scaler_read_base >= BUF1_ADDR) ? 2'd1 : 2'd0};
        end
    end
    audio_snapshot_cdc #(.WIDTH(3)) reader_owner_cdc(
        .src_clk(ext_mem_clk), .dst_clk(sd_card_clk), .rst(rst_all),
        .data_in(reader_owner_mem), .send(scaler_read_ack && !scaler_ack_previous), .data_out(reader_owner_sd), .received());
    wire [9:0] scaled_width, scaled_height;
    wire scaling_underflow;

// ===================== 原图像时序与帧缓�?=====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);


	// -------------------------------------------------------------
	// 转场特效引擎：支持用户锁定【淡入淡�?Fade】、【百叶窗 Venetian Blinds】、【水平推挤滑�?Slide Wipe】或【自动循环交�?Auto�?
	// -------------------------------------------------------------
	reg       fade_active;
	reg       fade_in;
	reg [3:0] fade_step;
	reg [1:0] fade_hold_cnt;
	reg [1:0] trans_auto_step; // 0: Smooth Alpha Fade, 1: Venetian Blinds Wipe, 2: Horizontal Slide Wipe (自动交替)
	reg [1:0] active_trans_mode; // 当前进行中转场所锁定的特效模�?

	// 单周期场同步脉冲 (VS 下降沿，严格一帧一个时钟脉冲，彻底消除 3 周期多步�?bug)
	reg vs_v_d;
	always @(posedge video_clk or posedge rst_all) begin
	    if (rst_all) vs_v_d <= 1'b1;
	    else         vs_v_d <= vs_0;
	end
	wire vs_fall_pulse = vs_v_d & ~vs_0;

	always @(posedge video_clk or posedge rst_all) begin
	    if (rst_all) begin
	        disp_buf_idx_v    <= 2'd0;
	        fade_active       <= 1'b0;
	        fade_in           <= 1'b0;
	        fade_step         <= 4'd0;
	        fade_hold_cnt     <= 2'd0;
	        trans_auto_step   <= 2'd0;
	        active_trans_mode <= 2'd0;
	    end else if (vs_fall_pulse) begin
	        if (!fade_active) begin
	            // 只要检测到目标图像缓冲区切换，严格触发转场�?
	            if (display_valid_v && (disp_buf_idx_target != disp_buf_idx_v)) begin
	                fade_active       <= 1'b1;
	                fade_in           <= 1'b0;
	                fade_step         <= 4'd0;
	                fade_hold_cnt     <= 2'd0;
	                active_trans_mode <= (trans_user_mode_v == 3'd4) ? trans_auto_step : trans_user_mode_v[1:0];
	            end
	        end else begin
	            if (!fade_in) begin
	                // 阶段一：画面闭合遮�?/ 淡出至全�?
	                if (fade_step == 4'd15) begin
	                    disp_buf_idx_v <= disp_buf_idx_target; // 在全黑遮挡瞬间切�?SDRAM 读图通道
	                    fade_in        <= 1'b1;
	                    fade_step      <= 4'd0; // 全黑保持帧：确保通道切换瞬间处于100%全黑遮盖，流水线与FIFO充分预充水，杜绝任何撕裂与毛刺
	                    fade_hold_cnt  <= 2'd2; // Hold 2 black frames for SDRAM stride switch & FIFO prefill
	                end else begin
	                    fade_step      <= fade_step + 4'd1;
	                end
	            end else begin
	                // 阶段二：新画面百叶窗/滑动展开 / 淡入至全�?
	                if (fade_hold_cnt != 2'd0) begin
	                    fade_hold_cnt <= fade_hold_cnt - 2'd1;
	                    fade_step     <= 4'd0;
	                end else if (fade_step == 4'd15) begin
	                    fade_active     <= 1'b0; // 转场完美结束
	                    fade_in         <= 1'b0;
	                    fade_step       <= 4'd0;
	                    trans_auto_step <= (trans_auto_step >= 2'd3) ? 2'd0 : (trans_auto_step + 2'd1); // 自动轮转下一个特�?(0:Fade, 1:Blinds, 2:Slide, 3:Mosaic)
	                end else begin
	                    fade_step       <= fade_step + 4'd1;
	                end
	            end
	        end
	    end
	end

	// -------------------------------------------------------------
	// 图像缩放适配与双线性插值引�?(video_scaler)
	// -------------------------------------------------------------
	wire        scaler_vs;
	wire        scaler_hs;
	wire        scaler_de;
	wire [23:0] scaler_rgb;

    scaling_pipeline u_scaling_pipeline (
        .mem_clk(ext_mem_clk), .video_clk(video_clk), .rst(rst_all),
        .frame_req(video_read_req), .frame_ack(video_read_req_ack),
        .frame_base(cur_disp_buf_base), .width(disp_bmp_width_v), .height(disp_bmp_height_v), .mode(scale_mode_v),
        .read_req(scaler_read_req), .read_ack(scaler_read_ack),
        .read_base(scaler_read_base), .read_len(scaler_read_len),
        .src_empty(source_empty), .src_data(video_read_data[31:8]), .src_read(video_read_en),
        .hs(hs_0), .vs(vs_0), .de(de_0), .display_valid(display_valid_v),
        .hs_out(scaler_hs), .vs_out(scaler_vs), .de_out(scaler_de), .rgb_out(scaler_rgb),
        .display_w(scaled_width), .display_h(scaled_height), .underflow(scaling_underflow)
    );
    // Keep legacy raw timing aliases for frame-boundary transition control.
    assign hs = hs_0;
    assign vs = vs_0;
    assign de = de_0;
    assign vout_data_raw = scaler_rgb;

	// Transitions follow scaling: their masks always span the 640x480 output.
	wire [23:0] transition_rgb;
	video_transition u_video_transition (
	    .clk(video_clk), .rst(rst_all), .de(scaler_de),
	    .rgb_in(scaler_rgb), .active(fade_active), .opening(fade_in),
	    .mode(active_trans_mode), .step(fade_step), .rgb_out(transition_rgb)
	);

	// -------------------------------------------------------------
	// 纯硬件实�?Sobel 边缘检测流水线引擎 (video_sobel)
	// -------------------------------------------------------------
	wire        sobel_vs;
	wire        sobel_hs;
	wire        sobel_de;
	wire [23:0] sobel_rgb;

	video_sobel #(
	    .THRESHOLD  (12'd200)
	) u_video_sobel (
	    .video_clk  (video_clk),
	    .rst        (rst_all),
	    .color_mode (color_mode_v),
	    .vs_in      (scaler_vs),
	    .hs_in      (scaler_hs),
	    .de_in      (scaler_de),
	    .rgb_in     (transition_rgb),
	    .vs_out     (sobel_vs),
	    .hs_out     (sobel_hs),
	    .de_out     (sobel_de),
	    .rgb_out    (sobel_rgb)
	);

	// -------------------------------------------------------------
	// 统一流式 OSD 与画面参数调节引�?(osd_display)
	// -------------------------------------------------------------
	wire        osd_vs;
	wire        osd_hs;
	wire        osd_de;
	wire [23:0] osd_rgb;

	osd_display u_osd_display (
        .marq_frame_pulse(marq_frame_pulse),.marq_read_addr(marq_read_addr),
        .marq_read_data(marq_read_data),.marq_custom_valid(marq_custom_valid),.marq_hidden(marq_hidden),.marq_normal_reset(marq_normal_reset),
        .clk50           (clk),
	    .video_clk        (video_clk),
	    .rst              (rst_all),
	    .vs_in            (sobel_vs),
	    .hs_in            (sobel_hs),
	    .de_in            (sobel_de),
	    .rgb_in           (sobel_rgb),
	    .sw_in            (sw_bright),
	    .contrast_lvl_in  (contrast_mode_v),
	    .hud_en           (hud_en_v),
	    .alpha_mode       (alpha_mode_v),
	    .scale_mode       (scale_mode_v),
	    .color_mode       (color_mode_v),
	    .trans_mode       (trans_user_mode_v),
	    .trans_effect     (active_trans_mode),
	    .bmp_width        (disp_bmp_width_v),
	    .bmp_height       (disp_bmp_height_v),
        .scaled_width     (scaled_width), .scaled_height(scaled_height),
	    .auto_play_status (auto_play_status_v),
	    .cur_img_idx      (cur_img_idx_v),
	    .display_valid    (display_valid_v),
	    .load_fail_hold   (load_fail_hold_v),
	    .audio_valid      (audio_valid),
	    .audio_left       (audio_left_data),
	    .sdram_loading    (sdram_loading_v),
	    .fade_active      (fade_active),
	    .img_total_count  (img_total_count_v),
	    .vol_mode         (vol_mode_v),
	    .emergency_mode   (emergency_mode_v),
	    .scada_active     (scada_active_v),
	    .vs_out           (osd_vs),
	    .hs_out           (osd_hs),
	    .de_out           (osd_de),
	    .rgb_out          (osd_rgb),
	    .sdft_spec_8b     (osd_sdft_spec_8b),
	    .sdft_peak_8b     (osd_sdft_peak_8b),
	    .menu_active      (menu_active_v),
	    .menu_cursor      (menu_cursor_v),
	    .menu_bright      (menu_bright_v),
	    .tone_mode        (tone_mode_v),
	    .disp_state_code  (disp_state_code)
	);

	assign vout_data = osd_rgb;

frame_read_write #(
    .SAME_CLOCK_READ  (1),
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (ext_mem_clk),
    .read_req          (scaler_read_req),
    .read_req_ack      (scaler_read_ack),
    .read_finish       (),
    .read_addr_0       (scaler_read_base),
    .read_addr_1       (scaler_read_base),
    .read_addr_2       (24'd0),
    .read_addr_3       (24'd0),
    .read_addr_index   (2'd0),
    .read_len          (scaler_read_len),
    .read_stride_2x    (1'b0),
    .read_line_width   (disp_bmp_width_v),
    .read_en           (video_read_en),
    .read_data         (video_read_data),
    .read_empty        (source_empty),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (24'd0),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (cur_write_len),
    .img_width         (bmp_orig_width),
    .img_height        (bmp_orig_height),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

wire [2:0] audio_note_snapshot;
reg [2:0] cur_img_idx_v_d;
reg note_send_pulse;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        cur_img_idx_v_d <= 3'd7;
        note_send_pulse <= 1'b1;
    end else begin
        if (cur_img_idx_v != cur_img_idx_v_d) begin
            cur_img_idx_v_d <= cur_img_idx_v;
            note_send_pulse <= 1'b1;
        end else begin
            note_send_pulse <= 1'b0;
        end
    end
end
audio_snapshot_cdc #(.WIDTH(3)) note_cdc(.src_clk(video_clk),.dst_clk(audio_mclk),.rst(rst_all),.data_in(cur_img_idx_v),.send(note_send_pulse),.data_out(audio_note_snapshot),.received());

// ===================== 音频：内�?I2S 测试音与数字音量调节 =====================
hdmi_audio_tone_i2s_64fs #(
    .PHASE_INC (32'd46819724),
    .AMP       (24'sd8200000)
) u_hdmi_audio_tone_i2s_64fs (
    .I_mclk           (audio_mclk),
    .I_rst            (rst_all),
    .I_enable         (emergency_mode_a | display_valid_a),
    .I_emergency_mode (emergency_mode_a),
    .I_note_idx       (audio_note_snapshot),
    .O_i2s_BCLK       (audio_i2s_bclk),
    .O_i2s_LRCK       (audio_i2s_lrck),
    .O_i2s_DOUT       (audio_i2s_dout)
);

wire signed [23:0] audio_left_raw, audio_right_raw;

I2S_receiver u_I2S_receiver(
    .I_clk              (video_clk),
    .I_rst              (rst_all),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (audio_raw_valid),
    .O_audio_left_data  (audio_left_raw),
    .O_audio_right_data (audio_right_raw)
);

// One registered stereo output path serves HDMI, ACR and both displays.
wire audio_output_overrun;
audio_output_stage output_stage(.clk(video_clk),.rst(rst_all),.valid_in(audio_raw_valid),
 .left_in(audio_left_raw),.right_in(audio_right_raw),.enable(display_valid_v),.emergency(emergency_mode_v),
 .note_idx(cur_img_idx_v),.volume(vol_mode_v),.valid_out(audio_valid),
 .left_out(audio_left_data),.right_out(audio_right_data),.overrun(audio_output_overrun));

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE �?AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (osd_vs),
    .I_de          (osd_de),
    .I_rgb         (osd_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一�?EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_all),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_all),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_all),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
