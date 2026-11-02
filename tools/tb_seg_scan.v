`timescale 1ns / 1ps

module tb_seg_scan;

    reg        clk;
    reg        rst_n;
    wire [5:0] seg_sel;
    wire [7:0] seg_data;

    reg  [7:0] seg_data_0;
    reg  [7:0] seg_data_1;
    reg  [7:0] seg_data_2;
    reg  [7:0] seg_data_3;
    reg  [7:0] seg_data_4;
    reg  [7:0] seg_data_5;

    // Instantiate UUT
    seg_scan uut (
        .clk        (clk),
        .rst_n      (rst_n),
        .seg_sel    (seg_sel),
        .seg_data   (seg_data),
        .seg_data_0 (seg_data_0),
        .seg_data_1 (seg_data_1),
        .seg_data_2 (seg_data_2),
        .seg_data_3 (seg_data_3),
        .seg_data_4 (seg_data_4),
        .seg_data_5 (seg_data_5)
    );

    // Clock generator: 50MHz -> 20ns period
    always #10 clk = ~clk;

    // Measurement variables
    integer total_cycles = 0;
    integer active_cycles = 0;
    integer blank_cycles = 0;
    integer cur_active_len = 0;
    integer cur_blank_len = 0;
    integer digit_transition_count = 0;
    integer error_count = 0;
    reg     meas_enable = 0;

    initial begin
        clk = 0;
        rst_n = 0;
        seg_data_0 = 8'h3f; // '0'
        seg_data_1 = 8'h06; // '1'
        seg_data_2 = 8'h5b; // '2'
        seg_data_3 = 8'h4f; // '3'
        seg_data_4 = 8'h66; // '4'
        seg_data_5 = 8'h6d; // '5'

        #100;
        @(negedge clk);
        rst_n = 1;

        // Wait for first clock edge where seg_sel becomes active
        @(posedge clk);
        meas_enable = 1;

        // Run for exactly 1 full 6-digit frame: 41,666 * 6 = 249,996 cycles
        repeat (249996) @(posedge clk);
        meas_enable = 0;

        $display("========================================================");
        $display("   tb_seg_scan Verification Report");
        $display("========================================================");
        $display("Total cycles observed : %0d", total_cycles);
        $display("Active cycles         : %0d (%0.4f%%)", active_cycles, (active_cycles * 100.0) / total_cycles);
        $display("Blanking cycles       : %0d (%0.4f%%)", blank_cycles, (blank_cycles * 100.0) / total_cycles);
        $display("Digit transitions     : %0d", digit_transition_count);
        $display("Error count           : %0d", error_count);

        if (error_count == 0 && active_cycles == 124998 && blank_cycles == 124998) begin
            $display(">>> TEST PASSED: Exactly 50.0000%% duty cycle chopping verified! <<<");
        end else begin
            $display(">>> TEST FAILED: Check errors above! <<<");
            $stop;
        end

        $finish;
    end

    // Monitor at every clock posedge during measurement
    always @(posedge clk) begin
        if (meas_enable) begin
            total_cycles = total_cycles + 1;

            if (seg_sel != 6'b111111) begin
                // Active phase
                active_cycles = active_cycles + 1;
                cur_active_len = cur_active_len + 1;

                if (cur_blank_len > 0) begin
                    // Finished a blanking phase
                    if (cur_blank_len != 20833) begin
                        $display("[ERROR @ cycle %0d] Blanking length expected 20833, got %0d", total_cycles, cur_blank_len);
                        error_count = error_count + 1;
                    end
                    cur_blank_len = 0;
                end
            end else begin
                // Blanking phase
                blank_cycles = blank_cycles + 1;
                cur_blank_len = cur_blank_len + 1;

                if (cur_active_len > 0) begin
                    // Finished an active phase
                    digit_transition_count = digit_transition_count + 1;
                    if (cur_active_len != 20833) begin
                        $display("[ERROR @ cycle %0d] Active length expected 20833, got %0d", total_cycles, cur_active_len);
                        error_count = error_count + 1;
                    end
                    cur_active_len = 0;
                end

                // In blanking phase, seg_data must be 8'hff (all segments off)
                if (seg_data != 8'hff) begin
                    $display("[ERROR @ cycle %0d] seg_data expected 0xFF during blanking, got 0x%02h", total_cycles, seg_data);
                    error_count = error_count + 1;
                end
            end
        end
    end

endmodule
