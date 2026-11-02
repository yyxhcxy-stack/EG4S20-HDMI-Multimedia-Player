module bmp_read(
    input                       clk,
    input                       rst,
    output                      ready,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [3:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [3:0]            scan_found_total,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input  [31:0]               load_sector,
    input                       load_abort,
    output reg                  load_done,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg [15:0]           bmp_orig_width,
    output reg [15:0]           bmp_orig_height,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data
);

localparam ST_IDLE      = 3'd0;
localparam ST_SCAN      = 3'd1;
localparam ST_LOAD_HDR  = 3'd2;
localparam ST_LOAD_WAIT = 3'd3;
localparam ST_LOAD_DATA   = 3'd4;
localparam ST_LOAD_SETTLE = 3'd5;

reg [2:0]  state;
reg [9:0]  rd_cnt;
reg [3:0]  settle_cnt;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [15:0] width;
reg [1:0] width_upper_nonzero;
reg [15:0] height;
reg [1:0] height_upper_nonzero;
reg [31:0] dib_size;
reg [1:0] planes_match;
reg [1:0] bit_count_match;
reg [3:0] compression_nonzero;

reg [31:0] scan_sector;
reg [31:0] load_sector_latched;
reg [31:0] bmp_len_cnt;
reg [1:0]  bmp_byte_idx;
reg        write_req_ack_d0;
reg        write_req_ack_d1;

// Accepted images are at most 640 pixels wide. Register header-derived
// geometry before it reaches the 100 MHz pixel-byte counter.
reg [11:0] row_pixel_bytes;
reg [11:0] row_total_bytes;
reg [11:0] row_last_byte;
reg [21:0] pixel_array_bytes;
wire [1:0] pad_len = (2'd0 - row_pixel_bytes[1:0]);
reg  [31:0] calc_file_len;
reg  [31:0] effective_file_len;
reg  [31:0] file_sector_count;
reg declared_length_nonzero;
reg [22:0] scan_sector_upper;
reg scan_sector_round;
reg  [31:0] effective_last_byte;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        row_pixel_bytes    <= 12'd0;
        row_total_bytes    <= 12'd0;
        row_last_byte      <= 12'd0;
        pixel_array_bytes  <= 22'd0;
        calc_file_len      <= 32'd0;
        effective_file_len <= 32'd0;
        file_sector_count  <= 32'd1;
        declared_length_nonzero<=0;scan_sector_upper<=0;scan_sector_round<=0;
        effective_last_byte <= 32'd0;
    end else begin
        row_pixel_bytes    <= {1'd0, width[10:0]} + {width[10:0], 1'b0};
        row_total_bytes    <= row_pixel_bytes + {10'd0, pad_len};
        row_last_byte      <= row_total_bytes - 12'd1;
        pixel_array_bytes  <= row_total_bytes * height[9:0];
        calc_file_len      <= pixel_offset + {10'd0, pixel_array_bytes};
        effective_file_len <= calc_file_len;
        // Valid headers always have a nonzero calculated length. Invalid
        // headers use the one-sector miss path, never this skip count.
        declared_length_nonzero<=file_len!=0;
        scan_sector_upper<=declared_length_nonzero?file_len[31:9]:effective_file_len[31:9];
        scan_sector_round<=declared_length_nonzero?(|file_len[8:0]):(|effective_file_len[8:0]);
        file_sector_count<={9'd0,scan_sector_upper}+{31'd0,scan_sector_round};
        effective_last_byte <= effective_file_len - 32'd1;
    end
end

reg header_match;
reg header_signature_ok, header_dimensions_ok, header_encoding_ok;
reg load_complete;
wire bmp_data_valid;
wire [31:0] next_scan_sector_if_match = scan_sector + file_sector_count;
wire [31:0] next_scan_sector_if_miss = scan_sector + 32'd1;
reg scan_match_out_of_range, scan_at_limit;

assign ready = (state == ST_IDLE);
always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_match <= 1'b0;
        header_signature_ok <= 1'b0;
        header_dimensions_ok <= 1'b0;
        header_encoding_ok <= 1'b0;
    end else begin
        // Header fields finish by byte 33; these two stages settle long
        // before the sector-end decision at byte 512.
        header_signature_ok <= (header_0 == "B") && (header_1 == "M");
        header_dimensions_ok <= (width_upper_nonzero == 0) && (width > 16'd0) && (width <= 16'd1024) &&
                                (height_upper_nonzero == 0) && (height > 16'd0) && (height <= 16'd768);
        header_encoding_ok <= (&bit_count_match) && (compression_nonzero == 0) &&
                              (&planes_match) && (dib_size >= 32'd40) &&
                              (pixel_offset >= 32'd54) && (dib_size <= pixel_offset - 32'd14) &&
                              (calc_file_len >= pixel_offset) &&
                              ((file_len == 0) || (file_len >= calc_file_len));
        header_match <= header_signature_ok && header_dimensions_ok && header_encoding_ok;
    end
end
assign bmp_data_valid = (sd_sec_read_data_valid == 1'b1) &&
                        (bmp_len_cnt >= pixel_offset) &&
                        (bmp_len_cnt <  effective_file_len);
always @(posedge clk or posedge rst) begin
    if (rst) begin
        scan_match_out_of_range <= 1'b0;
        scan_at_limit <= 1'b0;
        load_complete <= 1'b0;
    end else begin
        // Current sector and decoded length settle long before sector end.
        // Register the decision, sharing the two existing address sums.
        scan_match_out_of_range <= (next_scan_sector_if_match > scan_max_sector);
        scan_at_limit <= (scan_sector >= scan_max_sector);
        // Detect the last byte on its accepting edge, including an exact
        // 512-byte file where sector_end follows immediately afterwards.
        if (state != ST_LOAD_DATA) load_complete <= 1'b0;
        else if ((bmp_len_cnt >= effective_file_len) ||
                 (sd_sec_read_data_valid && bmp_len_cnt == effective_last_byte))
            load_complete <= 1'b1;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else begin
        rd_cnt <= 10'd0;
    end
end

// Register the byte selector once, keeping SD-valid/state decode out of every
// header field's clock enable. Header parsing still finishes well before byte 512.
reg header_byte_valid;reg [5:0] header_byte_index;reg [7:0] header_byte_data;
always @(posedge clk or posedge rst) begin
    if(rst)begin header_byte_valid<=0;header_byte_index<=0;header_byte_data<=0;end
    else begin
        header_byte_valid<=((state==ST_SCAN)||(state==ST_LOAD_HDR)) && sd_sec_read_data_valid && rd_cnt<34;
        header_byte_index<=rd_cnt[5:0];header_byte_data<=sd_sec_read_data;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        dib_size <= 0; planes_match <= 0;
        width_upper_nonzero <= 0; height_upper_nonzero <= 0;
        bit_count_match <= 0;
        compression_nonzero <= 0;
    end else if (header_byte_valid) begin
        case (header_byte_index)
            6'd0 : header_0 <= header_byte_data;
            6'd1 : header_1 <= header_byte_data;

            6'd2 : file_len[7:0] <= header_byte_data;
            6'd3 : file_len[15:8] <= header_byte_data;
            6'd4 : file_len[23:16] <= header_byte_data;
            6'd5 : file_len[31:24] <= header_byte_data;

            6'd10: pixel_offset[7:0] <= header_byte_data;
            6'd11: pixel_offset[15:8] <= header_byte_data;
            6'd12: pixel_offset[23:16] <= header_byte_data;
            6'd13: pixel_offset[31:24] <= header_byte_data;

            6'd14: dib_size[7:0] <= header_byte_data;
            6'd15: dib_size[15:8] <= header_byte_data;
            6'd16: dib_size[23:16] <= header_byte_data;
            6'd17: dib_size[31:24] <= header_byte_data;
            6'd26: planes_match[0] <= header_byte_data == 8'd1;
            6'd27: planes_match[1] <= header_byte_data == 8'd0;
            6'd18: width[7:0] <= header_byte_data;
            6'd19: width[15:8] <= header_byte_data;
            6'd20: width_upper_nonzero[0] <= header_byte_data != 0;
            6'd21: width_upper_nonzero[1] <= header_byte_data != 0;

            6'd22: height[7:0] <= header_byte_data;
            6'd23: height[15:8] <= header_byte_data;
            6'd24: height_upper_nonzero[0] <= header_byte_data != 0;
            6'd25: height_upper_nonzero[1] <= header_byte_data != 0;

            6'd28: bit_count_match[0] <= header_byte_data == 8'd24;
            6'd29: bit_count_match[1] <= header_byte_data == 8'd0;

            6'd30: compression_nonzero[0] <= header_byte_data != 0;
            6'd31: compression_nonzero[1] <= header_byte_data != 0;
            6'd32: compression_nonzero[2] <= header_byte_data != 0;
            6'd33: compression_nonzero[3] <= header_byte_data != 0;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid)
            bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end else begin
        bmp_len_cnt <= 32'd0;
    end
end

reg [11:0] row_byte_cnt;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        row_byte_cnt <= 12'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid) begin
            if (row_byte_cnt == row_last_byte)
                row_byte_cnt <= 12'd0;
            else
                row_byte_cnt <= row_byte_cnt + 12'd1;
        end
    end else begin
        row_byte_cnt <= 12'd0;
    end
end

wire is_pixel_byte = (row_byte_cnt < row_pixel_bytes);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_byte_idx   <= 2'd0;
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid && is_pixel_byte) begin
            case (bmp_byte_idx)
                2'd0: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[7:0]  <= sd_sec_read_data;
                    bmp_byte_idx   <= 2'd1;
                end
                2'd1: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[15:8] <= sd_sec_read_data;
                    bmp_byte_idx   <= 2'd2;
                end
                2'd2: begin
                    bmp_data_wr_en  <= 1'b1;
                    bmp_data[23:16] <= sd_sec_read_data;
                    bmp_byte_idx    <= 2'd0;
                end
                default: bmp_byte_idx <= 2'd0;
            endcase
        end else begin
            bmp_data_wr_en <= 1'b0;
            if (bmp_data_valid && !is_pixel_byte) begin
                bmp_byte_idx <= 2'd0;
            end
        end
    end else begin
        bmp_byte_idx   <= 2'd0;
        bmp_data_wr_en <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        write_req_ack_d0 <= 1'b0;
        write_req_ack_d1 <= 1'b0;
    end else begin
        write_req_ack_d0 <= write_req_ack;
        write_req_ack_d1 <= write_req_ack_d0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state               <= ST_IDLE;
        state_code          <= 4'd0;
        sd_sec_read         <= 1'b0;
        sd_sec_read_addr    <= 32'd0;
        write_req           <= 1'b0;
        scan_done           <= 1'b0;
        scan_found_valid    <= 1'b0;
        scan_found_sector   <= 32'd0;
        scan_found_total    <= 4'd0;
        scan_sector         <= 32'd0;
        load_sector_latched <= 32'd0;
        load_done           <= 1'b0;
        bmp_orig_width      <= 16'd640;
        bmp_orig_height     <= 16'd480;
        settle_cnt          <= 4'd0;
    end else if (!sd_init_done) begin
        state               <= ST_IDLE;
        state_code          <= 4'd0;
        sd_sec_read         <= 1'b0;
        sd_sec_read_addr    <= 32'd0;
        write_req           <= 1'b0;
        scan_done           <= 1'b0;
        scan_found_valid    <= 1'b0;
        scan_found_sector   <= 32'd0;
        scan_found_total    <= 4'd0;
        scan_sector         <= 32'd0;
        load_sector_latched <= 32'd0;
        load_done           <= 1'b0;
        bmp_orig_width      <= 16'd640;
        bmp_orig_height     <= 16'd480;
        settle_cnt          <= 4'd0;
    end else if (load_abort) begin
        settle_cnt          <= 4'd0;
        state               <= ST_IDLE;
        state_code          <= 4'd1;
        sd_sec_read         <= 1'b0;
        sd_sec_read_addr    <= 32'd0;
        write_req           <= 1'b0;
        load_sector_latched <= 32'd0;
        load_done           <= 1'b0;
    end else begin
        scan_found_valid <= 1'b0;
        load_done        <= 1'b0;

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    scan_done        <= 1'b0;
                    scan_found_total <= 4'd0;
                    scan_sector      <= scan_start_sector;
                    sd_sec_read_addr <= scan_start_sector;
                    state            <= ST_SCAN;
                end else if (load_start) begin
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr    <= load_sector;
                    state               <= ST_LOAD_HDR;
                end
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;

                    if (header_match) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 4'd1;

                        if ((scan_found_total + 4'd1 >= scan_target_count) || scan_match_out_of_range) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end
                    end else begin
                        if (scan_at_limit) begin
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_miss;
                            scan_sector      <= next_scan_sector_if_miss;
                        end
                    end
                end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (header_match) begin
                        // header_match has already bounded these dimensions.
                        // Explicitly zero unused bits so downstream geometry
                        // does not synthesize arithmetic for impossible sizes.
                        bmp_orig_width   <= {5'd0, width[10:0]};
                        bmp_orig_height  <= {6'd0, height[9:0]};
                        write_req        <= 1'b0;
                        settle_cnt       <= 4'd0;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_SETTLE;
                    end else begin
                        state <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_SETTLE: begin
                state_code <= 4'd2;
                if (settle_cnt == 4'd15) begin
                    write_req <= 1'b1;
                    state     <= ST_LOAD_WAIT;
                end else begin
                    settle_cnt <= settle_cnt + 4'd1;
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (write_req_ack_d1) begin
                    write_req <= 1'b0;
                    state     <= ST_LOAD_DATA;
                end
            end

            ST_LOAD_DATA: begin
                state_code  <= 4'd4;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (load_complete) begin
                        state     <= ST_IDLE;
                        load_done <= 1'b1;
                    end else begin
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    end
                end
            end

            default: begin
                settle_cnt  <= 4'd0;
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
    end
end

endmodule
