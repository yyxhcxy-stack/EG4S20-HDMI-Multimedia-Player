`timescale 1ns / 1ps

module tb_lcd_trace;
    reg clk;
    reg rst;

    wire lcd_scl;
    wire lcd_mosi;
    wire lcd_cs;
    wire lcd_dc;
    wire lcd_rst;
    wire lcd_blk;

    lcd_st7735_telemetry #(
        .COL_OFFSET(8'd2),
        .ROW_OFFSET(8'd3)
    ) dut (
        .clk(clk),
        .rst(rst),
        .lcd_scl(lcd_scl),
        .lcd_mosi(lcd_mosi),
        .lcd_cs(lcd_cs),
        .lcd_dc(lcd_dc),
        .lcd_rst(lcd_rst),
        .lcd_blk(lcd_blk),
        .cur_img_idx(3'd0),
        .scale_mode(2'd0),
        .vol_mode(3'd0),
        .audio_pcm(24'd0),
        .audio_valid(1'b0),
        .emergency_mode(1'b0),
        .sdft_spec_8b(40'd0),
        .sdft_peak_8b(40'd0)
    );

    always #10 clk = ~clk;

    // Monitor SPI bytes
    reg [7:0] rx_byte;
    integer bit_idx = 0;
    integer byte_count = 0;
    reg last_scl = 0;
    reg last_cs = 1;

    always @(posedge clk) begin
        if (!lcd_cs) begin
            if (last_scl == 0 && lcd_scl == 1) begin
                rx_byte = {rx_byte[6:0], lcd_mosi};
                bit_idx = bit_idx + 1;
                if (bit_idx == 8) begin
                    byte_count = byte_count + 1;
                    if (byte_count <= 80) begin
                        $display("[%0t ns] Byte %0d: 0x%02h (DC=%b, state=%0d, prep_step=%0d)", 
                            $time, byte_count, rx_byte, lcd_dc, dut.state, dut.prep_step);
                    end
                    bit_idx = 0;
                end
            end
        end else begin
            bit_idx = 0;
        end
        last_scl <= lcd_scl;
        last_cs <= lcd_cs;
    end

    initial begin
        clk = 0;
        rst = 1;
        #100;
        rst = 0;
        // In simulation, accelerate delay counters if needed
        // Let's run for some time
    end
endmodule
