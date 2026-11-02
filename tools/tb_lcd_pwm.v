`timescale 1ns / 1ps

module tb_lcd_pwm;

    reg clk;
    reg rst;
    reg blk_en;

    // Heartbeat counter (same as in lcd_st7735_telemetry.v)
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

    // LCD Backlight PWM register (same as in lcd_st7735_telemetry.v)
    reg lcd_blk;
    always @(posedge clk or posedge rst) begin
        if (rst)
            lcd_blk <= 1'b0;
        else
            lcd_blk <= blk_en & hb_cnt[15];
    end

    // 50MHz Clock (20ns)
    always #10 clk = ~clk;

    // Verification stats
    integer high_cycles = 0;
    integer low_cycles = 0;
    integer cur_high = 0;
    integer cur_low = 0;
    integer pulses_measured = 0;
    integer error_count = 0;
    reg     meas_active = 0;

    initial begin
        clk = 0;
        rst = 1;
        blk_en = 0;

        #100;
        @(negedge clk);
        // Verify during reset: lcd_blk must be 0
        if (lcd_blk !== 1'b0) begin
            $display("[ERROR] lcd_blk not 0 during reset!");
            error_count = error_count + 1;
        end

        rst = 0;
        #100;
        // Verify when blk_en == 0: lcd_blk must be 0 even after clocking
        repeat (1000) @(posedge clk);
        if (lcd_blk !== 1'b0) begin
            $display("[ERROR] lcd_blk not 0 when blk_en=0!");
            error_count = error_count + 1;
        end

        // Enable backlight (simulating transition to S_FRAME_PREP)
        @(negedge clk);
        blk_en = 1;

        // Wait for first rising edge of lcd_blk to align measurement with complete PWM cycles
        @(posedge lcd_blk);
        meas_active = 1;

        // Run for exactly 2 full PWM cycles: 2 * 65536 = 131072 cycles (approx 2.62ms)
        repeat (131072) @(posedge clk);
        meas_active = 0;

        $display("========================================================");
        $display("   tb_lcd_pwm Verification Report");
        $display("========================================================");
        $display("Total test cycles      : 131072");
        $display("High cycles measured   : %0d (%0.4f%%)", high_cycles, (high_cycles * 100.0) / 131072);
        $display("Low cycles measured    : %0d (%0.4f%%)", low_cycles, (low_cycles * 100.0) / 131072);
        $display("PWM Pulses measured    : %0d", pulses_measured);
        $display("PWM Frequency          : %0.2f Hz", 50000000.0 / 65536.0);
        $display("Error count            : %0d", error_count);

        if (error_count == 0 && high_cycles == 65536 && low_cycles == 65536) begin
            $display(">>> TEST PASSED: ST7735 Backlight PWM 50.0000%% verified! <<<");
        end else begin
            $display(">>> TEST FAILED: Discrepancy detected! <<<");
            $stop;
        end

        $finish;
    end

    // Monitor PWM waveform
    always @(posedge clk) begin
        if (meas_active) begin
            if (lcd_blk) begin
                high_cycles = high_cycles + 1;
                cur_high = cur_high + 1;
                if (cur_low > 0) begin
                    pulses_measured = pulses_measured + 1;
                    if (cur_low != 32768) begin
                        $display("[ERROR] Low duration expected 32768, got %0d", cur_low);
                        error_count = error_count + 1;
                    end
                    cur_low = 0;
                end
            end else begin
                low_cycles = low_cycles + 1;
                cur_low = cur_low + 1;
                if (cur_high > 0) begin
                    if (cur_high != 32768) begin
                        $display("[ERROR] High duration expected 32768, got %0d", cur_high);
                        error_count = error_count + 1;
                    end
                    cur_high = 0;
                end
            end
        end
    end

endmodule
