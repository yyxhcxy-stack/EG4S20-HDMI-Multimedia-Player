`timescale 1ns/1ps

module tb_scaling_core;
    reg clk, rst, start;
    reg [1:0] mode;
    reg [10:0] width;
    reg [9:0] height;
    reg src_empty;
    reg [23:0] src_data;
    wire src_read;
    reg out_full;
    wire out_write;
    wire [23:0] out_data;
    wire [9:0] out_w;
    wire [8:0] out_h;
    wire config_ready;
    wire done;

    scaling_core uut (
        .clk(clk), .rst(rst), .start(start),
        .mode(mode), .width(width), .height(height),
        .src_empty(src_empty), .src_data(src_data), .src_read(src_read),
        .out_full(out_full), .out_write(out_write), .out_data(out_data),
        .out_w(out_w), .out_h(out_h),
        .config_ready(config_ready), .done(done)
    );

    always #4 clk = ~clk; // 125MHz (8ns period)

    reg [23:0] fake_mem [0:1024*768-1];
    integer read_idx;
    integer out_pixel_cnt;
    integer cur_ox, cur_oy;

    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        mode = 2'd0; // 1.0X scale
        width = 11'd1024;
        height = 10'd768;
        src_empty = 0;
        src_data = 24'd0;
        out_full = 0;
        read_idx = 0;
        out_pixel_cnt = 0;
        cur_ox = 0;
        cur_oy = 0;

        // Initialize fake_mem with distinct pattern:
        // pixel value = {y[7:0], x[10:3], x[2:0], 5'b0}
        // so we can uniquely identify which source (X, Y) each output pixel came from!
        for (integer y = 0; y < 768; y = y + 1) begin
            for (integer x = 0; x < 1024; x = x + 1) begin
                fake_mem[y*1024 + x] = {y[7:0], x[10:3], x[2:0], 5'd0};
            end
        end

        #40 rst = 0;
        #16 start = 1;
        #8  start = 0;

        // Wait until done
        wait(done);
        $display("Frame finished! Total output pixels: %d", out_pixel_cnt);
        $finish;
    end

    // Feeder: on src_read, provide next pixel
    always @(posedge clk) begin
        if (src_read) begin
            src_data <= fake_mem[read_idx];
            read_idx <= read_idx + 1;
        end
    end

    // Monitor output
    always @(posedge clk) begin
        if (out_write) begin
            out_pixel_cnt <= out_pixel_cnt + 1;
            // Check if cur_ox is around 446..450
            if (cur_oy == 200 && cur_ox >= 445 && cur_ox <= 450) begin
                $display("OY=%d, OX=%d: out_data=0x%06x (expected SX=%d, SY=%d)", 
                    cur_oy, cur_ox, out_data, 192 + cur_ox, 144 + cur_oy);
            end
            if (cur_ox == out_w - 1) begin
                cur_ox <= 0;
                cur_oy <= cur_oy + 1;
            end else begin
                cur_ox <= cur_ox + 1;
            end
        end
    end

endmodule
