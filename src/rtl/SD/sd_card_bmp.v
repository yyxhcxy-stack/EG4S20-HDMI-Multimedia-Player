
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter integer AUTO_PLAY_SEC     = 1,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd1048576,
    parameter [3:0]   SCAN_TARGET_COUNT = 4'd4
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    output [2:0]                cur_img_idx,
    output                      auto_play_status,
    output [3:0]                state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output [15:0]               bmp_orig_width,
    output [15:0]               bmp_orig_height,
    output [15:0]               disp_bmp_width,
    output [15:0]               disp_bmp_height,
    output [15:0]               buf0_w_out,
    output [15:0]               buf0_h_out,
    output [15:0]               buf1_w_out,
    output [15:0]               buf1_h_out,
    output [2:0]                buf0_idx_out,
    output [2:0]                buf1_idx_out,
    output reg                  display_valid,
    output                      load_fail_hold,
    output [7:0]                play_pos,
    output [3:0]                img_count_out,

    // Actual SDRAM reader ownership; release old bank only after new read ACK.
    input [1:0]                 reader_bank,
    input                       reader_valid,
    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

wire key_next_press;
wire key_auto_press;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire             load_done;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [3:0]       scan_found_total;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [3:0]        img_found_count;
reg [2:0]        img_idx;              // 当前真正显示中的图片编号
reg [2:0]        load_idx;             // 当前正在写入的图片编�?
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg [31:0]       img_sector4;
reg [31:0]       img_sector5;
reg [31:0]       img_sector6;
reg [31:0]       img_sector7;
localparam [31:0] DEFAULT_SECTOR_0 = 32'd17024;
localparam [31:0] DEFAULT_SECTOR_1 = 32'd18880;
localparam [31:0] DEFAULT_SECTOR_2 = 32'd20736;
localparam [31:0] DEFAULT_SECTOR_3 = 32'd22592;
localparam [31:0] DEFAULT_SECTOR_4 = 32'd24448;

reg [3:0]        scan_found_cnt;
reg              next_req_pending;
reg              load_busy;
reg              load_abort;
	reg [31:0]       load_timeout_cnt;
	reg [31:0]       fail_hold_cnt;
	reg              load_fail_latch;

// bmp_ready 先表示“源文件读取/�?FIFO 完成”；真正切显示要�?write_finish_toggle 同步�?
reg              source_done_seen;
reg              write_done_seen;

// 同步 mem_clk 域的 write_finish_toggle
	reg [2:0]        wrfin_tgl_sync;
	wire             write_finish_pulse;
	reg              scan_done_d;
	wire             scan_done_rise;
	reg              card_missing;

wire auto_tick;
wire [2:0] next_from_current;
wire reader_handoff_done = reader_valid && reader_bank == disp_buf_idx;
reg [2:0] next_idx_stage, next_idx_ready;
reg [31:0] next_sector_ready;
reg [1:0] next_cache_warm;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        next_idx_stage <= 0; next_idx_ready <= 0; next_sector_ready <= 0; next_cache_warm <= 0;
    end else begin
        next_idx_stage <= next_from_current;
        next_idx_ready <= next_idx_stage;
        next_sector_ready <= sector_lut(next_idx_stage);
        if (scan_found_valid || (load_busy && source_done_seen && write_done_seen))
            next_cache_warm <= 0;
        else next_cache_warm <= {next_cache_warm[0], 1'b1};
    end
end

reg [15:0] buf0_w, buf0_h;
reg [15:0] buf1_w, buf1_h;
reg [2:0]  buf0_idx, buf1_idx;
assign disp_bmp_width  = (disp_buf_idx == 2'd0) ? buf0_w : buf1_w;
assign disp_bmp_height = (disp_buf_idx == 2'd0) ? buf0_h : buf1_h;
assign buf0_w_out      = buf0_w;
assign buf0_h_out      = buf0_h;
assign buf1_w_out      = buf1_w;
assign buf1_h_out      = buf1_h;
assign buf0_idx_out    = buf0_idx;
assign buf1_idx_out    = buf1_idx;

assign cur_img_idx     = img_idx;
assign img_count_out   = (img_found_count != 4'd0) ? img_found_count : SCAN_TARGET_COUNT;
assign auto_play_status = auto_play_en;
assign write_en         = bmp_data_wr_en;
assign write_data       = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
assign auto_tick        = (auto_cnt >= ((CLK_FREQ_HZ * AUTO_PLAY_SEC) - 1));
assign next_from_current = next_index_limited(img_idx, img_found_count);
	assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
	assign scan_done_rise = scan_done & ~scan_done_d;
		assign load_fail_hold = load_fail_latch | card_missing;
	assign play_pos = (!auto_play_en || !display_valid || (auto_cnt[27:20] > 8'd255))
	                ? ((auto_play_en && display_valid) ? 8'd255 : 8'd0)
	                : auto_cnt[27:20];

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (2)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press)
);

function [2:0] next_index_limited;
    input [2:0] cur;
    input [3:0] count;
    reg [3:0] candidate;
    begin
        candidate = {1'b0,cur} + 4'd1;
        if (count <= 4'd1 || candidate >= count)
            next_index_limited = 3'd0;
        else
            next_index_limited = candidate[2:0];
    end
endfunction

function [31:0] sector_lut;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: sector_lut = img_sector0;
            3'd1: sector_lut = img_sector1;
            3'd2: sector_lut = img_sector2;
            3'd3: sector_lut = img_sector3;
            3'd4: sector_lut = img_sector4;
            3'd5: sector_lut = img_sector5;
            3'd6: sector_lut = img_sector6;
            3'd7: sector_lut = img_sector7;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定�?buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
	        wrfin_tgl_sync        <= 3'b000;
	        scan_done_d           <= 1'b0;
	        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b1;
        auto_cnt              <= 32'd0;
        img_found_count       <= SCAN_TARGET_COUNT;
        scan_found_cnt        <= 4'd0;
        img_idx               <= 3'd0;
        load_idx              <= 3'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        buf0_w                <= 16'd640;
        buf0_h                <= 16'd480;
        buf1_w                <= 16'd640;
        buf1_h                <= 16'd480;
        buf0_idx              <= 3'd0;
        buf1_idx              <= 3'd0;
        img_sector0           <= DEFAULT_SECTOR_0;
        img_sector1           <= DEFAULT_SECTOR_1;
        img_sector2           <= DEFAULT_SECTOR_2;
        img_sector3           <= DEFAULT_SECTOR_3;
        img_sector4           <= DEFAULT_SECTOR_4;
        img_sector5           <= 32'd0;
        img_sector6           <= 32'd0;
        img_sector7           <= 32'd0;
        next_req_pending      <= 1'b0;
        load_busy             <= 1'b0;
        load_abort            <= 1'b0;
	        load_timeout_cnt      <= 32'd0;
	        fail_hold_cnt         <= 32'd0;
	        load_fail_latch       <= 1'b0;
	        card_missing          <= 1'b0;
	        source_done_seen      <= 1'b0;
	        write_done_seen       <= 1'b0;
	        display_valid         <= 1'b0;
	    end else begin
	        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
	        scan_done_d      <= scan_done;
	        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;

	        if (!sd_init_done) begin
	            scan_kicked           <= 1'b0;
	            scan_found_cnt        <= 4'd0;
	            next_req_pending      <= 1'b0;
	            load_busy             <= 1'b0;
	            load_abort            <= 1'b0;
	            load_timeout_cnt      <= 32'd0;
	            source_done_seen      <= 1'b0;
	            write_done_seen       <= 1'b0;
	            if (display_valid)
	                card_missing      <= 1'b1;
	            if (!display_valid) begin
	                first_image_committed <= 1'b0;
	                img_found_count       <= SCAN_TARGET_COUNT;
	                img_idx               <= 3'd0;
	                load_idx              <= 3'd0;
	                pending_buf_idx       <= 2'd0;
	                write_buf_idx         <= 2'd0;
	                disp_buf_idx          <= 2'd0;
	            end
	        end else begin
	            // 扫描阶段缓存�?8 张图的起�?sector
            if (scan_found_valid) begin
                case (scan_found_cnt)
                    4'd0: img_sector0 <= scan_found_sector;
                    4'd1: img_sector1 <= scan_found_sector;
                    4'd2: img_sector2 <= scan_found_sector;
                    4'd3: img_sector3 <= scan_found_sector;
                    4'd4: img_sector4 <= scan_found_sector;
                    4'd5: img_sector5 <= scan_found_sector;
                    4'd6: img_sector6 <= scan_found_sector;
                    4'd7: img_sector7 <= scan_found_sector;
                    default: ;
                endcase

                img_found_count <= scan_found_cnt + 4'd1;

                if (scan_found_cnt < SCAN_TARGET_COUNT)
                    scan_found_cnt <= scan_found_cnt + 4'd1;
            end

	            if (scan_done_rise) begin
	                if (card_missing)
	                    next_req_pending <= 1'b1;
	                card_missing <= 1'b0;
	                if (scan_found_valid)
	                    img_found_count <= scan_found_cnt + 4'd1;
	                else if (scan_found_cnt > 4'd0)
	                    img_found_count <= scan_found_cnt;
	            end

            // 记住 bmp_read 已经把源图送完 FIFO，但还不能切显示，得等整帧写�?
            if (load_busy && load_done)
                source_done_seen <= 1'b1;

            // 写完成可能早于源结束，电平锁存，避免单拍脉冲丢失后一直等
            if (load_busy && write_finish_pulse)
                write_done_seen <= 1'b1;

            // 源图送完且整帧写完才提交。超时则放弃本次，不改当前显示缓�?
            if (load_busy && source_done_seen && write_done_seen) begin
                load_busy             <= 1'b0;
                load_abort            <= 1'b0;
                load_timeout_cnt      <= 32'd0;
	                source_done_seen      <= 1'b0;
	                write_done_seen       <= 1'b0;
	                fail_hold_cnt         <= 32'd0;
	                load_fail_latch       <= 1'b0;
	                card_missing          <= 1'b0;
	                disp_buf_idx          <= pending_buf_idx;
                if (pending_buf_idx == 2'd0) begin
                    buf0_w   <= bmp_orig_width;
                    buf0_h   <= bmp_orig_height;
                    buf0_idx <= load_idx;
                end else begin
                    buf1_w   <= bmp_orig_width;
                    buf1_h   <= bmp_orig_height;
                    buf1_idx <= load_idx;
                end
                img_idx               <= load_idx;
                display_valid         <= 1'b1;
                first_image_committed <= 1'b1;
            end else if (load_busy) begin
	                if (load_timeout_cnt >= (CLK_FREQ_HZ * 4)) begin
	                    load_busy        <= 1'b0;
	                    load_abort       <= 1'b1;
	                    load_timeout_cnt <= 32'd0;
	                    source_done_seen <= 1'b0;
	                    write_done_seen  <= 1'b0;
	                    fail_hold_cnt    <= 32'd0;
	                    load_fail_latch  <= 1'b1;
	                    card_missing     <= 1'b1;
	                end else begin
                    load_abort       <= 1'b0;
                    load_timeout_cnt <= load_timeout_cnt + 32'd1;
                end
	            end else begin
	                load_abort       <= 1'b0;
	                load_timeout_cnt <= 32'd0;
	                if (load_fail_latch) begin
	                    if (fail_hold_cnt >= (CLK_FREQ_HZ * 2)) begin
	                        fail_hold_cnt   <= 32'd0;
	                        load_fail_latch <= 1'b0;
	                    end else begin
	                        fail_hold_cnt <= fail_hold_cnt + 32'd1;
	                    end
	                end
	            end

            // 上电后自动发起一次“扫描前 5 �?BMP�?
	            if (!scan_kicked && bmp_ready) begin
	                scan_start_pulse      <= 1'b1;
	                scan_kicked           <= 1'b1;
	                scan_found_cnt        <= 4'd0;
	                if (!display_valid)
	                    first_image_committed <= 1'b0;
	                auto_cnt              <= 32'd0;
	                next_req_pending      <= 1'b0;
	                load_busy             <= 1'b0;
	                load_abort            <= 1'b0;
	                load_timeout_cnt      <= 32'd0;
	                source_done_seen      <= 1'b0;
	                write_done_seen       <= 1'b0;
	            end else begin
                // 忙的时候也只记 1 次“下一张”请求，不会累积成连跳两�?
                if (key_next_press && (img_found_count > 4'd0)) begin
                    next_req_pending <= 1'b1;
                    auto_cnt         <= 32'd0;
                end

                // 自动播放开/�?
                if (key_auto_press && (img_found_count > 4'd1)) begin
                    auto_play_en <= ~auto_play_en;
                    auto_cnt     <= 32'd0;
                end

                // 自动播放 1s 计数：只有当前没有写图任务时才计�?
                if (auto_play_en && display_valid && !load_busy && first_image_committed && (img_found_count > 4'd1)) begin
                    if (auto_tick)
                        auto_cnt <= 32'd0;
                    else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 首图自动加载�?buffer0
                if (!first_image_committed && bmp_ready && !load_busy && (img_found_count != 4'd0)) begin
                    load_idx         <= 3'd0;
                    load_sector      <= img_sector0;
                    pending_buf_idx  <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    load_abort       <= 1'b0;
                    load_timeout_cnt <= 32'd0;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 手动下一张优先：写到“非当前显示”的另一�?buffer
                else if (reader_handoff_done && next_cache_warm[1] && bmp_ready && display_valid && !load_busy && next_req_pending && (img_found_count != 4'd0)) begin
                    load_idx         <= next_idx_ready;
                    load_sector      <= next_sector_ready;
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    load_abort       <= 1'b0;
                    load_timeout_cnt <= 32'd0;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 自动播放下一张：同样写到“非当前显示”的另一�?buffer
                else if (reader_handoff_done && next_cache_warm[1] && bmp_ready && display_valid && !load_busy && auto_play_en && auto_tick && (img_found_count > 4'd1)) begin
                    load_idx         <= next_idx_ready;
                    load_sector      <= next_sector_ready;
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    load_abort       <= 1'b0;
                    load_timeout_cnt <= 32'd0;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
            end
        end
    end
end

bmp_read bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),

    .load_start             (load_start_pulse),
    .load_sector            (load_sector),
    .load_abort             (load_abort),
    .load_done              (load_done),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .bmp_orig_width         (bmp_orig_width),
    .bmp_orig_height        (bmp_orig_height),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按�?0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
