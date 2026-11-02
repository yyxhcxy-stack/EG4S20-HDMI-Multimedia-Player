`timescale 1ns / 1ps
// ============================================================================
// Module Name:  uart_scada_controller
// Project:      HX4S20_HDMI_Player (Tunnel SCADA Bus & 1Hz Telemetry)
// Description:  Hardware UART transceiver and ASCII industrial command parser
//               for Railway & Long Tunnel Smart Emergency Broadcast & Multimedia Display.
//
// Technical Specs:
//   - Clock Domain: 50MHz clk (Zero additional PLLs, strictly 50MHz domain)
//   - Baud Rate:    115200 bps, 8N1 (50,000,000 / 115200 = 434 clock cycles/bit)
//   - Pin Binding:  RXD -> F12, TXD -> D12 (CH340 USB-UART bridge)
//   - Telemetry:    Periodic status push disabled; UART sends command ACKs only
//   - Command Set:  CMD:EMERG=1, CMD:EMERG=0, CMD:NEXT, CMD:AUTO=1, CMD:AUTO=0,
//                   CMD:SCALE=0..3, CMD:VOL=0..4
//   - Response:     [ACK] OK: <command>\r\n or [ACK] ERR: <command>\r\n
// ============================================================================

module uart_scada_controller (
    input  wire        clk,             // 50MHz system clock
    input  wire        rst,             // Active high reset (rst_all)
    
    // Physical UART pins
    input  wire        uart_rx,         // FPGA RX (Pin F12, CH340 USB)
    output reg         uart_tx,         // FPGA TX (Pin D12, CH340 USB)
    input  wire        ble_rx,          // FPGA BLE RX (Pin F13, HC-08D Bluetooth)
    output reg         ble_tx,          // FPGA BLE TX (Pin J13, HC-08D Bluetooth)
    
    // Status inputs for telemetry report
    input  wire        emergency_mode,  // 0: NORMAL, 1: EMERGENCY
    input  wire        auto_play_status,// Current auto carousel status
    input  wire [1:0]  scale_mode_in,   // 0: 1.0X, 1: 2.0X, 2: 0.5X, 3: AUTO
    input  wire [2:0]  vol_mode_in,     // 0: 100%, 1: 75%, 2: 50%, 3: 25%, 4: MUTE
    
    // Control outputs to system
    output reg         cmd_emerg_set,   // Pulse: force emergency mode
    output reg         cmd_emerg_clr,   // Pulse: clear emergency mode
    output reg         cmd_next_pulse,  // Pulse: manual switch next BMP
    output reg         cmd_auto_set,    // Pulse: start auto carousel
    output reg         cmd_auto_clr,    // Pulse: pause auto carousel
    output reg         cmd_scale_vld,   // Pulse: valid scale mode set
    output reg  [1:0]  cmd_scale_val,   // Target scale mode (0..3)
    output reg         cmd_vol_vld,     // Pulse: valid volume set
    output reg  [2:0]  cmd_vol_val,     // Target volume mode (0..4)
    output reg         cmd_trans_vld,   // Pulse: valid transition mode set
    output reg  [2:0]  cmd_trans_val,   // Target transition mode (0: FADE, 1: BLND, 2: SLID, 3: MOSC, 4: AUTO)
    output reg         cmd_alpha_vld,   // Pulse: valid alpha mode set
    output reg  [1:0]  cmd_alpha_val,   // Target alpha mode (0: 25%, 1: 50%, 2: 75%)
    
    input wire video_clk,marq_frame_pulse,
    input wire [6:0] marq_read_addr,
    output wire [6:0] marq_read_data,
    output wire marq_custom_valid,marq_hidden,marq_normal_reset,

    // Activity indicator for OSD & diagnostics
    output wire        scada_active,    // Constant 1'b1 indicating SCADA telemetry active
    output reg         scada_rx_pulse   // High on valid command received
);

    // ========================================================================
    // 1. Parameters & Timing Constants
    // ========================================================================
    localparam CLK_FREQ_HZ     = 50_000_000;
    localparam BAUD_RATE       = 115_200;
    localparam BIT_CYCLES      = 9'd434;        // 50,000,000 / 115,200 = 434
    localparam HALF_BIT_CYCLES = 9'd217;        // Center sampling point
    localparam ONE_SEC_CYCLES  = 26'd50_000_000; // 1.0 second 1Hz telemetry

    assign scada_active = 1'b1;

    // ========================================================================
    // 2. Dual-Channel UART Receiver (PC USB @ 115200 + BLE @ 9600/115200)
    // ========================================================================
    localparam RX_IDLE  = 2'd0;
    localparam RX_START = 2'd1;
    localparam RX_DATA  = 2'd2;
    localparam RX_STOP  = 2'd3;

    // ------------------------------------------------------------------------
    // 2. Dual Baud Rate Prescaler (115200 for PC, 16x Oversampled 9600 for BLE)
    // ------------------------------------------------------------------------
    reg [8:0]  ble_div_cnt;
    wire       ble_sample_tick = (ble_div_cnt == 9'd325); // 50MHz / (9600 * 16) = 325.52

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ble_div_cnt <= 9'd0;
        end else begin
            if (ble_div_cnt >= 9'd325)
                ble_div_cnt <= 9'd0;
            else
                ble_div_cnt <= ble_div_cnt + 9'd1;
        end
    end

    // ------------------------------------------------------------------------
    // 2.1 PC UART Receiver (Fixed 115200 Baud, 8N1)
    // ------------------------------------------------------------------------
    reg [1:0]  pc_rx_sync;
    reg [1:0]  pc_rx_state;
    reg [8:0]  pc_rx_clk_cnt;
    reg [2:0]  pc_rx_bit_idx;
    reg [7:0]  pc_rx_byte;
    reg        pc_rx_byte_vld;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc_rx_sync     <= 2'b11;
            pc_rx_state    <= RX_IDLE;
            pc_rx_clk_cnt  <= 9'd0;
            pc_rx_bit_idx  <= 3'd0;
            pc_rx_byte     <= 8'd0;
            pc_rx_byte_vld <= 1'b0;
        end else begin
            pc_rx_sync     <= {pc_rx_sync[0], uart_rx};
            pc_rx_byte_vld <= 1'b0;

            case (pc_rx_state)
                RX_IDLE: begin
                    pc_rx_clk_cnt <= 9'd0;
                    pc_rx_bit_idx <= 3'd0;
                    if (!pc_rx_sync[1]) begin
                        pc_rx_state <= RX_START;
                    end
                end

                RX_START: begin
                    if (pc_rx_clk_cnt == HALF_BIT_CYCLES - 9'd1) begin
                        if (!pc_rx_sync[1]) begin
                            pc_rx_clk_cnt <= 9'd0;
                            pc_rx_state   <= RX_DATA;
                        end else begin
                            pc_rx_state   <= RX_IDLE;
                        end
                    end else begin
                        pc_rx_clk_cnt <= pc_rx_clk_cnt + 9'd1;
                    end
                end

                RX_DATA: begin
                    if (pc_rx_clk_cnt == BIT_CYCLES - 9'd1) begin
                        pc_rx_clk_cnt <= 9'd0;
                        if (pc_rx_bit_idx == 3'd7) begin
                            pc_rx_state <= RX_STOP;
                        end else begin
                            pc_rx_bit_idx <= pc_rx_bit_idx + 3'd1;
                        end
                    end else begin
                        if (pc_rx_clk_cnt == HALF_BIT_CYCLES - 9'd1) begin
                            pc_rx_byte[pc_rx_bit_idx] <= pc_rx_sync[1];
                        end
                        pc_rx_clk_cnt <= pc_rx_clk_cnt + 9'd1;
                    end
                end

                RX_STOP: begin
                    if (pc_rx_clk_cnt == HALF_BIT_CYCLES - 9'd1) begin
                        if (pc_rx_sync[1]) begin
                            pc_rx_byte_vld <= 1'b1;
                        end
                        pc_rx_state   <= RX_IDLE;
                        pc_rx_clk_cnt <= 9'd0;
                    end else begin
                        pc_rx_clk_cnt <= pc_rx_clk_cnt + 9'd1;
                    end
                end

                default: pc_rx_state <= RX_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // 2.2 BLE Receiver (HC-08D Factory Default 9600 Baud, 16x Oversampled)
    // ------------------------------------------------------------------------
    localparam BLE_RX_IDLE  = 2'd0;
    localparam BLE_RX_START = 2'd1;
    localparam BLE_RX_DATA  = 2'd2;
    localparam BLE_RX_STOP  = 2'd3;

    reg [1:0]  ble_rx_sync;
    reg [1:0]  ble_rx_state;
    reg [3:0]  ble_rx_sample_cnt;
    reg [2:0]  ble_rx_bit_idx;
    reg [7:0]  ble_rx_byte;
    reg        ble_rx_byte_vld;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ble_rx_sync       <= 2'b11;
            ble_rx_state      <= BLE_RX_IDLE;
            ble_rx_sample_cnt <= 4'd0;
            ble_rx_bit_idx    <= 3'd0;
            ble_rx_byte       <= 8'd0;
            ble_rx_byte_vld   <= 1'b0;
        end else begin
            ble_rx_sync       <= {ble_rx_sync[0], ble_rx};
            ble_rx_byte_vld   <= 1'b0;

            case (ble_rx_state)
                BLE_RX_IDLE: begin
                    ble_rx_sample_cnt <= 4'd0;
                    ble_rx_bit_idx    <= 3'd0;
                    if (!ble_rx_sync[1]) begin
                        ble_rx_state <= BLE_RX_START;
                    end
                end

                BLE_RX_START: begin
                    if (ble_sample_tick) begin
                        if (ble_rx_sample_cnt == 4'd7) begin
                            if (!ble_rx_sync[1]) begin
                                ble_rx_sample_cnt <= ble_rx_sample_cnt + 4'd1;
                            end else begin
                                ble_rx_state <= BLE_RX_IDLE;
                            end
                        end else if (ble_rx_sample_cnt == 4'd15) begin
                            ble_rx_sample_cnt <= 4'd0;
                            ble_rx_state      <= BLE_RX_DATA;
                            ble_rx_bit_idx    <= 3'd0;
                        end else begin
                            ble_rx_sample_cnt <= ble_rx_sample_cnt + 4'd1;
                        end
                    end
                end

                BLE_RX_DATA: begin
                    if (ble_sample_tick) begin
                        if (ble_rx_sample_cnt == 4'd7) begin
                            ble_rx_byte[ble_rx_bit_idx] <= ble_rx_sync[1];
                            ble_rx_sample_cnt <= ble_rx_sample_cnt + 4'd1;
                        end else if (ble_rx_sample_cnt == 4'd15) begin
                            ble_rx_sample_cnt <= 4'd0;
                            if (ble_rx_bit_idx == 3'd7) begin
                                ble_rx_state <= BLE_RX_STOP;
                            end else begin
                                ble_rx_bit_idx <= ble_rx_bit_idx + 3'd1;
                            end
                        end else begin
                            ble_rx_sample_cnt <= ble_rx_sample_cnt + 4'd1;
                        end
                    end
                end

                BLE_RX_STOP: begin
                    if (ble_sample_tick) begin
                        if (ble_rx_sample_cnt == 4'd7) begin
                            if (ble_rx_sync[1]) begin
                                ble_rx_byte_vld <= 1'b1;
                            end
                            ble_rx_state <= BLE_RX_IDLE;
                        end else begin
                            ble_rx_sample_cnt <= ble_rx_sample_cnt + 4'd1;
                        end
                    end
                end

                default: ble_rx_state <= BLE_RX_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // 2.3 Zero-Cost Channel Multiplexer (Pure Combinational)
    // ------------------------------------------------------------------------
    wire       rx_byte_vld = pc_rx_byte_vld | ble_rx_byte_vld;
    wire [7:0] rx_byte     = ble_rx_byte_vld ? ble_rx_byte : pc_rx_byte;

    // ========================================================================
    // 3. ASCII Command Line Buffering & Protocol Parser
    // ========================================================================
    wire [7:0] rx_char  = rx_byte;
    // Case-insensitive uppercase converter
    wire [7:0] rx_upper = (rx_char >= 8'h61 && rx_char <= 8'h7A) ? (rx_char - 8'h20) : rx_char;

    reg [7:0] cmd_buf [0:10];
    integer command_shift_index;
    reg [4:0] cmd_len;
    reg       parse_trigger;
    reg text_mode,text_invalid,cmd_overflow,parsed_text;
    reg [7:0] text_count;
    reg marq_write_valid;reg [9:0] marq_write_addr;reg [6:0] marq_write_data;
    reg marq_submit,marq_is_text,marq_enable_value;reg [7:0] marq_length;
    wire marq_busy,marq_done,marq_write_bank,marq_read_bank;
    wire [7:0] marq_ram_read_data;
    reg marq_ack_wait,marq_reply_pending,pending_text,pending_enable;
    wire marq_unavailable=marq_busy||marq_ack_wait;
    marquee_store subtitle_store(.clk(clk),.video_clk(video_clk),.rst(rst),.frame_pulse(marq_frame_pulse),
     .submit(marq_submit),.is_text(marq_is_text),.enable_value(marq_enable_value),.text_length(marq_length),
     .busy(marq_busy),.done(marq_done),.write_bank(marq_write_bank),.read_bank(marq_read_bank),
     .read_addr(marq_read_addr),.ram_read_data(marq_ram_read_data),.read_data(marq_read_data),
     .custom_valid(marq_custom_valid),.hidden(marq_hidden),.normal_reset(marq_normal_reset));

    // ACK metadata selects a held command echo RAM bank or a compact constant reply.
    reg ack_echo_bank,rx_echo_bank;
    reg [1:0] ack_body_kind; // 0: legacy echo, 1: TEXT, 2/3: MARQ=0/1
    reg [4:0]   ack_len;
    reg         ack_is_ok;
    reg         ack_req_pulse; // Single-cycle strobe into Sequencer block

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cmd_len<=0;parse_trigger<=0;text_mode<=0;text_invalid<=0;cmd_overflow<=0;parsed_text<=0;text_count<=0;
            marq_write_valid<=0;marq_write_addr<=0;marq_write_data<=0;
        end else begin
            parse_trigger<=0;marq_write_valid<=0;
            if (rx_byte_vld) begin
                if (rx_char==8'h0D || rx_char==8'h0A) begin
                    if(cmd_len!=0)begin parse_trigger<=1;parsed_text<=text_mode;end
                end else if(text_mode)begin
                    if(((rx_char>=8'h20&&rx_char<=8'h5F)||(rx_char>=8'h61&&rx_char<=8'h7A))&&text_count<128)begin
                        if(!text_invalid&&!marq_unavailable)begin
                            marq_write_valid<=1;marq_write_addr<={2'b01,marq_write_bank,text_count[6:0]};marq_write_data<=rx_upper[6:0];
                        end
                        text_count<=text_count+1'b1;
                    end else text_invalid<=1;
                end else if(rx_char>=8'h20&&rx_char<=8'h7E)begin
                    if(cmd_len<31)begin
                        for(command_shift_index=10;command_shift_index>0;command_shift_index=command_shift_index-1)cmd_buf[command_shift_index]<=cmd_buf[command_shift_index-1];
                        cmd_buf[0]<=rx_upper;cmd_len<=cmd_len+1'b1;
                        marq_write_valid<=1;marq_write_addr<={1'b1,3'd0,rx_echo_bank,cmd_len};marq_write_data<=rx_upper[6:0];end
                    else cmd_overflow<=1;
                    if(cmd_len==8 && rx_upper=="=" && cmd_buf[7]=="C"&&cmd_buf[6]=="M"&&cmd_buf[5]=="D"&&cmd_buf[4]==":"&&
                       cmd_buf[3]=="T"&&cmd_buf[2]=="E"&&cmd_buf[1]=="X"&&cmd_buf[0]=="T")begin
                        text_mode<=1;text_count<=0;text_invalid<=marq_unavailable;
                    end
                end
            end else if(parse_trigger)begin
                cmd_len<=0;text_mode<=0;text_count<=0;text_invalid<=0;cmd_overflow<=0;
            end
        end
    end

    // Command interpreter owns ACK metadata and the two legacy echo bank indices.

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cmd_emerg_set  <= 1'b0;
            cmd_emerg_clr  <= 1'b0;
            cmd_next_pulse <= 1'b0;
            cmd_auto_set   <= 1'b0;
            cmd_auto_clr   <= 1'b0;
            cmd_scale_vld  <= 1'b0;
            cmd_scale_val  <= 2'd0;
            cmd_vol_vld    <= 1'b0;
            cmd_vol_val    <= 3'd0;
            cmd_trans_vld  <= 1'b0;
            cmd_trans_val  <= 3'd4;
            cmd_alpha_vld  <= 1'b0;
            cmd_alpha_val  <= 2'd1;
            scada_rx_pulse <= 1'b0;
            ack_req_pulse  <= 1'b0;
            ack_is_ok      <= 1'b0;
            ack_len        <= 5'd0;
            ack_body_kind  <= 2'd0;ack_echo_bank<=0;rx_echo_bank<=0;
            marq_submit<=0;marq_is_text<=0;marq_enable_value<=1;marq_length<=0;
            marq_ack_wait<=0;marq_reply_pending<=0;pending_text<=0;pending_enable<=1;
        end else begin
            // Default 1-cycle pulses
            cmd_emerg_set  <= 1'b0;
            cmd_emerg_clr  <= 1'b0;
            cmd_next_pulse <= 1'b0;
            cmd_auto_set   <= 1'b0;
            cmd_auto_clr   <= 1'b0;
            cmd_scale_vld  <= 1'b0;
            cmd_vol_vld    <= 1'b0;
            cmd_trans_vld  <= 1'b0;
            cmd_alpha_vld  <= 1'b0;
            scada_rx_pulse <= 1'b0;
            ack_req_pulse  <= 1'b0;
            marq_submit<=0;
            if(marq_done)marq_reply_pending<=1;

            if (parse_trigger) begin
                // Publish the received legacy command bank; continue into the other bank.
                if(!parsed_text)begin ack_echo_bank<=rx_echo_bank;rx_echo_bank<=!rx_echo_bank;end
                ack_body_kind<=0;
                ack_len       <= cmd_len;
                ack_req_pulse <= 1'b1;

                if(parsed_text)begin
                    ack_body_kind<=1;ack_len<=8;ack_is_ok<=0;
                    if(!text_invalid && text_count!=0 && !marq_unavailable)begin
                        marq_submit<=1;marq_is_text<=1;marq_length<=text_count;
                        pending_text<=1;marq_ack_wait<=1;ack_req_pulse<=0;scada_rx_pulse<=1;
                    end
                end else if(cmd_overflow)begin ack_is_ok<=0;end
                else if(cmd_len==10 && cmd_buf[9]=="C"&&cmd_buf[8]=="M"&&cmd_buf[7]=="D"&&cmd_buf[6]==":"&&
                        cmd_buf[5]=="M"&&cmd_buf[4]=="A"&&cmd_buf[3]=="R"&&cmd_buf[2]=="Q"&&cmd_buf[1]=="="&&
                        (cmd_buf[0]=="0"||cmd_buf[0]=="1"))begin
                    ack_is_ok<=0;
                    if(!marq_unavailable)begin
                        marq_submit<=1;marq_is_text<=0;marq_enable_value<=cmd_buf[0]=="1";
                        pending_text<=0;pending_enable<=cmd_buf[0]=="1";marq_ack_wait<=1;
                        ack_req_pulse<=0;scada_rx_pulse<=1;
                    end
                end
                // Match 1: CMD:EMERG=0/1 (11 chars)
                else if (cmd_len == 5'd11 &&
                    cmd_buf[10]  == "C" && cmd_buf[9]  == "M" && cmd_buf[8]  == "D" && cmd_buf[7]  == ":" &&
                    cmd_buf[6]  == "E" && cmd_buf[5]  == "M" && cmd_buf[4]  == "E" && cmd_buf[3]  == "R" &&
                    cmd_buf[2]  == "G" && cmd_buf[1]  == "=" && (cmd_buf[0] == "0" || cmd_buf[0] == "1")) begin
                    if (cmd_buf[0] == "1") cmd_emerg_set <= 1'b1;
                    else                   cmd_emerg_clr <= 1'b1;
                    scada_rx_pulse <= 1'b1;
                    ack_is_ok      <= 1'b1;
                end
                // Match 2: CMD:NEXT (8 chars)
                else if (cmd_len == 5'd8 &&
                    cmd_buf[7]  == "C" && cmd_buf[6]  == "M" && cmd_buf[5]  == "D" && cmd_buf[4]  == ":" &&
                    cmd_buf[3]  == "N" && cmd_buf[2]  == "E" && cmd_buf[1]  == "X" && cmd_buf[0]  == "T") begin
                    cmd_next_pulse <= 1'b1;
                    scada_rx_pulse <= 1'b1;
                    ack_is_ok      <= 1'b1;
                end
                // Match 3: CMD:AUTO=0/1 (10 chars)
                else if (cmd_len == 5'd10 &&
                    cmd_buf[9]  == "C" && cmd_buf[8]  == "M" && cmd_buf[7]  == "D" && cmd_buf[6]  == ":" &&
                    cmd_buf[5]  == "A" && cmd_buf[4]  == "U" && cmd_buf[3]  == "T" && cmd_buf[2]  == "O" &&
                    cmd_buf[1]  == "=" && (cmd_buf[0] == "0" || cmd_buf[0] == "1")) begin
                    if (cmd_buf[0] == "1") cmd_auto_set <= 1'b1;
                    else                   cmd_auto_clr <= 1'b1;
                    scada_rx_pulse <= 1'b1;
                    ack_is_ok      <= 1'b1;
                end
                // Match 6: CMD:SCALE=0..3 (11 chars)
                else if (cmd_len == 5'd11 &&
                    cmd_buf[10]  == "C" && cmd_buf[9]  == "M" && cmd_buf[8]  == "D" && cmd_buf[7]  == ":" &&
                    cmd_buf[6]  == "S" && cmd_buf[5]  == "C" && cmd_buf[4]  == "A" && cmd_buf[3]  == "L" &&
                    cmd_buf[2]  == "E" && cmd_buf[1]  == "=" && (cmd_buf[0] >= "0" && cmd_buf[0] <= "3")) begin
                    cmd_scale_vld  <= 1'b1;
                    cmd_scale_val  <= cmd_buf[0][1:0];
                    scada_rx_pulse <= 1'b1;
                    ack_is_ok      <= 1'b1;
                end
                // Match 7: CMD:VOL=0..4 (9 chars)
                else if (cmd_len == 5'd9 &&
                    cmd_buf[8]  == "C" && cmd_buf[7]  == "M" && cmd_buf[6]  == "D" && cmd_buf[5]  == ":" &&
                    cmd_buf[4]  == "V" && cmd_buf[3]  == "O" && cmd_buf[2]  == "L" &&
                    cmd_buf[1]  == "=" && (cmd_buf[0] >= "0" && cmd_buf[0] <= "4")) begin
                    cmd_vol_vld    <= 1'b1;
                    cmd_vol_val    <= cmd_buf[0][2:0] - 3'd0;
                    scada_rx_pulse <= 1'b1;
                    ack_is_ok      <= 1'b1;
                end
                // Match 8: CMD:TRANS=0..4 (11 chars)
                else if (cmd_len == 5'd11 &&
                    cmd_buf[10]  == "C" && cmd_buf[9]  == "M" && cmd_buf[8]  == "D" && cmd_buf[7]  == ":" &&
                    cmd_buf[6]  == "T" && cmd_buf[5]  == "R" && cmd_buf[4]  == "A" && cmd_buf[3]  == "N" &&
                    cmd_buf[2]  == "S" && cmd_buf[1]  == "=" && (cmd_buf[0] >= "0" && cmd_buf[0] <= "4")) begin
                    cmd_trans_vld  <= 1'b1;
                    cmd_trans_val  <= cmd_buf[0][2:0] - 3'd0;
                    scada_rx_pulse <= 1'b1;
                    ack_is_ok      <= 1'b1;
                end
                // Match 9: CMD:ALPHA=0..2 (11 chars)
                else if (cmd_len == 5'd11 &&
                    cmd_buf[10]  == "C" && cmd_buf[9]  == "M" && cmd_buf[8]  == "D" && cmd_buf[7]  == ":" &&
                    cmd_buf[6]  == "A" && cmd_buf[5]  == "L" && cmd_buf[4]  == "P" && cmd_buf[3]  == "H" &&
                    cmd_buf[2]  == "A" && cmd_buf[1]  == "=" && (cmd_buf[0] >= "0" && cmd_buf[0] <= "2")) begin
                    cmd_alpha_vld  <= 1'b1;
                    cmd_alpha_val  <= cmd_buf[0][1:0];
                    scada_rx_pulse <= 1'b1;
                    ack_is_ok      <= 1'b1;
                end
                // Match 10: CMD:STATUS (10 chars)
                else if (cmd_len == 5'd10 &&
                    cmd_buf[9]  == "C" && cmd_buf[8]  == "M" && cmd_buf[7]  == "D" && cmd_buf[6]  == ":" &&
                    cmd_buf[5]  == "S" && cmd_buf[4]  == "T" && cmd_buf[3]  == "A" && cmd_buf[2]  == "T" &&
                    cmd_buf[1]  == "U" && cmd_buf[0]  == "S") begin
                    scada_rx_pulse <= 1'b1;
                    ack_is_ok      <= 1'b1;
                end
                // Unknown command error
                else begin
                    ack_is_ok <= 1'b0;
                end
            end else if(marq_reply_pending && seq_state==SEQ_IDLE && !ack_pending && !ack_req_pulse)begin
                ack_body_kind<=pending_text ? 2'd1 : (pending_enable ? 2'd3 : 2'd2);
                ack_len<=pending_text ? 5'd8 : 5'd10;ack_is_ok<=1;ack_req_pulse<=1;
                marq_reply_pending<=0;marq_ack_wait<=0;
            end
        end
    end

    // ========================================================================
    // 4. On-Demand Tunnel SCADA Query-Response Architecture (Low-Power)
    // ========================================================================
    // Low-Power Architecture Upgrade (Phase 3):
    // 1. Eliminated 50MHz 26-bit telem_timer counter (saves 26 DFFs, eliminates 50M toggles/s).
    // 2. Telemetry is 100% on-demand event-driven: UART TX stays in static sleep (0 switching power).
    // 3. Responds immediately to CMD:STATUS and CMD:STATUS? via zero-overhead BRAM echo pipeline.

    // ACK Prefix ROM: "[ACK] OK: " (10 chars) or "[ACK] ERR: " (11 chars)
    function [7:0] fn_ack_prefix;
        input is_ok;
        input [3:0] idx;
        begin
            if (is_ok) begin
                case (idx)
                    4'd0: fn_ack_prefix = 8'h5B; // '['
                    4'd1: fn_ack_prefix = 8'h41; // 'A'
                    4'd2: fn_ack_prefix = 8'h43; // 'C'
                    4'd3: fn_ack_prefix = 8'h4B; // 'K'
                    4'd4: fn_ack_prefix = 8'h5D; // ']'
                    4'd5: fn_ack_prefix = 8'h20; // ' '
                    4'd6: fn_ack_prefix = 8'h4F; // 'O'
                    4'd7: fn_ack_prefix = 8'h4B; // 'K'
                    4'd8: fn_ack_prefix = 8'h3A; // ':'
                    4'd9: fn_ack_prefix = 8'h20; // ' '
                    default: fn_ack_prefix = 8'h20;
                endcase
            end else begin
                case (idx)
                    4'd0:  fn_ack_prefix = 8'h5B; // '['
                    4'd1:  fn_ack_prefix = 8'h41; // 'A'
                    4'd2:  fn_ack_prefix = 8'h43; // 'C'
                    4'd3:  fn_ack_prefix = 8'h4B; // 'K'
                    4'd4:  fn_ack_prefix = 8'h5D; // ']'
                    4'd5:  fn_ack_prefix = 8'h20; // ' '
                    4'd6:  fn_ack_prefix = 8'h45; // 'E'
                    4'd7:  fn_ack_prefix = 8'h52; // 'R'
                    4'd8:  fn_ack_prefix = 8'h52; // 'R'
                    4'd9:  fn_ack_prefix = 8'h3A; // ':'
                    4'd10: fn_ack_prefix = 8'h20; // ' '
                    default: fn_ack_prefix = 8'h20;
                endcase
            end
        end
    endfunction

    // ========================================================================
    // 5. FIFO Storage & Message Serialization Engine
    // ========================================================================
    reg [7:0] fifo_wr_ptr,fifo_rd_ptr;
    wire [7:0] fifo_head;
    reg fifo_head_valid;
    wire fifo_not_empty=(fifo_rd_ptr!=fifo_wr_ptr);
    // One existing 9K RAM: FIFO 0..255, text banks 256..511, command echo banks 512..575.
    // Port A writes one FIFO byte or staged text byte, otherwise prefetches
    // the FIFO head. Video port B reads only the held active text bank.
    reg cache_write_pending;reg ack_byte_ready;
    reg [9:0] cache_address;reg [6:0] cache_data;
    wire ram_write=fifo_wr_en||cache_write_pending;
    wire echo_read_request=(seq_state==SEQ_ACK_BODY)&&ack_body_kind==0&&!ack_byte_ready;
    wire echo_read=echo_read_request&&!ram_write;
    wire [9:0] ram_address=fifo_wr_en?{2'b00,fifo_wr_ptr}:
       cache_write_pending?cache_address:echo_read_request?{1'b1,3'd0,ack_echo_bank,ack_idx}:{2'b00,fifo_rd_ptr};
    wire [7:0] ram_data=fifo_wr_en?fifo_din_comb:{1'b0,cache_data};
    always @(posedge clk or posedge rst)begin
      if(rst)begin cache_write_pending<=0;ack_byte_ready<=0;cache_address<=0;cache_data<=0;fifo_head_valid<=0;end
      else begin
        fifo_head_valid<=!ram_write&&!echo_read_request&&fifo_not_empty;
        if(echo_read)ack_byte_ready<=1;
        else if(seq_state!=SEQ_ACK_BODY||fifo_wr_en)ack_byte_ready<=0;
        if(marq_write_valid)begin cache_write_pending<=1;cache_address<=marq_write_addr;cache_data<=marq_write_data;end
        else if(cache_write_pending&&!fifo_wr_en)cache_write_pending<=0;
      end
    end
`ifdef YOSYS
    reg [7:0] shared_ram[0:1023];reg [7:0] ram_q_a,ram_q_b;
    always @(posedge clk)begin ram_q_a<=shared_ram[ram_address];if(ram_write&&!rst)shared_ram[ram_address]<=ram_data;end
    always @(posedge video_clk)ram_q_b<=shared_ram[{2'b01,marq_read_bank,marq_read_addr}];
    assign fifo_head=ram_q_a;assign marq_ram_read_data=ram_q_b;
`else
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
      .DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
      .WRITEMODE_A("READBEFOREWRITE"),.WRITEMODE_B("NORMAL"),.IMPLEMENT("9K"),.PACKABLE("NO"),.INIT_FILE("NONE"),.FILL_ALL("NONE"))
    shared_uart_bram(.clka(clk),.clkb(video_clk),.addra(ram_address),.addrb({2'b01,marq_read_bank,marq_read_addr}),
      .dia(ram_data),.dib(8'd0),.cea(1'b1),.ceb(1'b1),.ocea(1'b1),.oceb(1'b1),.wea(ram_write&&!rst),.web(1'b0),
      .rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.doa(fifo_head),.dob(marq_ram_read_data));
`endif

    // Remaining free bytes in FIFO ring buffer
    wire [7:0] fifo_room = 8'd255 - (fifo_wr_ptr - fifo_rd_ptr);

    localparam SEQ_IDLE     = 3'd0;
    localparam SEQ_ACK_PRE  = 3'd1;
    localparam SEQ_ACK_BODY = 3'd2;
    localparam SEQ_ACK_CR   = 3'd3;
    localparam SEQ_ACK_LF   = 3'd4;

    reg [2:0] seq_state;
    reg       ack_pending;
    reg [4:0] ack_idx;

    // Write enable and data mux into FIFO
    wire fifo_wr_en = (seq_state != SEQ_IDLE) && ((seq_state!=SEQ_ACK_BODY)||ack_body_kind!=0||ack_byte_ready);

    function [7:0] fn_marq_ack;
        input [1:0] kind;input [4:0] idx;
        begin
            case(idx)
                0:fn_marq_ack="C";1:fn_marq_ack="M";2:fn_marq_ack="D";3:fn_marq_ack=":";
                4:fn_marq_ack=kind==1?"T":"M";5:fn_marq_ack=kind==1?"E":"A";
                6:fn_marq_ack=kind==1?"X":"R";7:fn_marq_ack=kind==1?"T":"Q";
                8:fn_marq_ack="=";9:fn_marq_ack=kind==3?"1":"0";
                default:fn_marq_ack=0;
            endcase
        end
    endfunction
    reg [7:0] fifo_din_comb;
    always @(*) begin
        case (seq_state)
            SEQ_ACK_PRE:  fifo_din_comb = fn_ack_prefix(ack_is_ok, ack_idx[3:0]);
            SEQ_ACK_BODY: fifo_din_comb = ack_body_kind==0 ? fifo_head : fn_marq_ack(ack_body_kind,ack_idx);
            SEQ_ACK_CR:   fifo_din_comb = 8'h0D; // '\r'
            SEQ_ACK_LF:   fifo_din_comb = 8'h0A; // '\n'
            default:      fifo_din_comb = 8'h00;
        endcase
    end

    // Serialization FSM & Pointer Control (Single driver for ack_pending, telem_pending, seq_state)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fifo_wr_ptr         <= 8'd0;
            seq_state           <= SEQ_IDLE;
            ack_pending         <= 1'b0;
            ack_idx             <= 5'd0;
        end else begin
            // Increment write pointer on actual FIFO write
            if (fifo_wr_en) begin
                fifo_wr_ptr <= fifo_wr_ptr + 8'd1;
            end

            // Capture new command ACK request strobe from Command Interpreter
            if (ack_req_pulse) begin
                ack_pending <= 1'b1;
            end

            case (seq_state)
                SEQ_IDLE: begin
                    ack_idx   <= 5'd0;
                    // Command ACK has high priority and requires ~45 bytes free in FIFO
                    if ((ack_pending || ack_req_pulse) && (fifo_room >= 8'd45)) begin
                        ack_pending <= 1'b0; // Immediately cleared, eliminating infinite loop
                        seq_state   <= SEQ_ACK_PRE;
                    end
                end

                SEQ_ACK_PRE: begin
                    if (ack_is_ok) begin
                        if (ack_idx >= 5'd9) begin
                            ack_idx   <= 5'd0;
                            seq_state <= SEQ_ACK_BODY;
                        end else begin
                            ack_idx <= ack_idx + 5'd1;
                        end
                    end else begin
                        if (ack_idx >= 5'd10) begin
                            ack_idx   <= 5'd0;
                            seq_state <= SEQ_ACK_BODY;
                        end else begin
                            ack_idx <= ack_idx + 5'd1;
                        end
                    end
                end

                SEQ_ACK_BODY: if(fifo_wr_en)begin
                    if (ack_idx >= ack_len - 5'd1) begin
                        seq_state <= SEQ_ACK_CR;
                    end else begin
                        ack_idx <= ack_idx + 5'd1;
                    end
                end

                SEQ_ACK_CR: begin
                    seq_state <= SEQ_ACK_LF;
                end

                SEQ_ACK_LF: begin
                    seq_state <= SEQ_IDLE;
                end

                default: seq_state <= SEQ_IDLE;
            endcase
        end
    end

    // ========================================================================
    // 6. Dual UART Transmitters (PC USB 115200 + HC-08D BLE 9600)
    // ========================================================================
    localparam TX_IDLE  = 2'd0;
    localparam TX_START = 2'd1;
    localparam TX_DATA  = 2'd2;
    localparam TX_STOP  = 2'd3;

    // 6.1 PC USB Transmitter (Fixed 115200 Baud)
    reg [1:0]  tx_state;
    reg [8:0]  tx_clk_cnt;
    reg [2:0]  tx_bit_idx;
    reg [7:0]  tx_shift;

    // 6.2 BLE Transmitter (Fixed 9600 Baud via 16x oversampler)
    reg [3:0]  ble_tx_sample_cnt;
    reg [3:0]  ble_tx_bit_idx;
    reg [7:0]  ble_tx_shift;
    reg        ble_tx_active;

    wire tx_both_idle = (tx_state == TX_IDLE) && (!ble_tx_active);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            uart_tx           <= 1'b1;
            tx_state          <= TX_IDLE;
            tx_clk_cnt        <= 9'd0;
            tx_bit_idx        <= 3'd0;
            tx_shift          <= 8'd0;

            ble_tx            <= 1'b1;
            ble_tx_active     <= 1'b0;
            ble_tx_sample_cnt <= 4'd0;
            ble_tx_bit_idx    <= 4'd0;
            ble_tx_shift      <= 8'd0;

            fifo_rd_ptr       <= 8'd0;
        end else begin
            // Pop FIFO only when BOTH transmitters are IDLE and FIFO has valid data
            if (tx_both_idle && fifo_not_empty && fifo_head_valid) begin
                tx_shift          <= fifo_head;
                tx_state          <= TX_START;
                uart_tx           <= 1'b0; // Start bit
                tx_clk_cnt        <= 9'd0;
                tx_bit_idx        <= 3'd0;

                ble_tx_shift      <= fifo_head;
                ble_tx_active     <= 1'b1;
                ble_tx            <= 1'b0; // Start bit
                ble_tx_sample_cnt <= 4'd0;
                ble_tx_bit_idx    <= 4'd0;

                fifo_rd_ptr       <= fifo_rd_ptr + 8'd1;
            end else begin
                // PC Transmitter Engine (115200 Baud)
                case (tx_state)
                    TX_IDLE: begin
                        uart_tx    <= 1'b1;
                        tx_clk_cnt <= 9'd0;
                        tx_bit_idx <= 3'd0;
                    end

                    TX_START: begin
                        uart_tx <= 1'b0;
                        if (tx_clk_cnt >= BIT_CYCLES - 9'd1) begin
                            tx_clk_cnt <= 9'd0;
                            tx_state   <= TX_DATA;
                            tx_bit_idx <= 3'd0;
                        end else begin
                            tx_clk_cnt <= tx_clk_cnt + 9'd1;
                        end
                    end

                    TX_DATA: begin
                        uart_tx <= tx_shift[tx_bit_idx];
                        if (tx_clk_cnt >= BIT_CYCLES - 9'd1) begin
                            tx_clk_cnt <= 9'd0;
                            if (tx_bit_idx == 3'd7) begin
                                tx_state <= TX_STOP;
                            end else begin
                                tx_bit_idx <= tx_bit_idx + 3'd1;
                            end
                        end else begin
                            tx_clk_cnt <= tx_clk_cnt + 9'd1;
                        end
                    end

                    TX_STOP: begin
                        uart_tx <= 1'b1;
                        if (tx_clk_cnt >= BIT_CYCLES - 9'd1) begin
                            tx_clk_cnt <= 9'd0;
                            tx_state   <= TX_IDLE;
                        end else begin
                            tx_clk_cnt <= tx_clk_cnt + 9'd1;
                        end
                    end

                    default: tx_state <= TX_IDLE;
                endcase

                // BLE Transmitter Engine (9600 Baud)
                if (ble_tx_active) begin
                    if (ble_sample_tick) begin
                        if (ble_tx_sample_cnt == 4'd15) begin
                            ble_tx_sample_cnt <= 4'd0;
                            if (ble_tx_bit_idx == 4'd8) begin
                                // Send stop bit
                                ble_tx         <= 1'b1;
                                ble_tx_bit_idx <= 4'd9;
                            end else if (ble_tx_bit_idx == 4'd9) begin
                                // Finished stop bit
                                ble_tx         <= 1'b1;
                                ble_tx_active  <= 1'b0;
                            end else begin
                                // Send next data bit
                                ble_tx         <= ble_tx_shift[ble_tx_bit_idx];
                                ble_tx_bit_idx <= ble_tx_bit_idx + 4'd1;
                            end
                        end else begin
                            ble_tx_sample_cnt <= ble_tx_sample_cnt + 4'd1;
                        end
                    end
                end else begin
                    ble_tx            <= 1'b1;
                    ble_tx_sample_cnt <= 4'd0;
                    ble_tx_bit_idx    <= 4'd0;
                end
            end
        end
    end

endmodule
