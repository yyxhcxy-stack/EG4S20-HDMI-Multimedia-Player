`timescale 1ns / 1ps
module tb_lcd_sim;
    reg clk;
    reg rst;
    wire lcd_scl, lcd_mosi, lcd_cs, lcd_dc, lcd_rst, lcd_blk;

    lcd_st7735_telemetry #(
        .COL_OFFSET(8'd0),
        .ROW_OFFSET(8'd0)
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
        .trans_mode(2'd3),
        .active_trans(2'd3),
        .color_mode(2'd2),
        .sdft_spec_8b(40'd0),
        .sdft_peak_8b(40'd0)
    );

    always #10 clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;
        #100;
        rst = 0;
        $display("TB initialized successfully!");
        #500;
        $finish;
    end
endmodule
