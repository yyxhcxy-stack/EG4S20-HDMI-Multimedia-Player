`timescale 1ns/1ps

module tb_osd_step4_sim;
    reg [23:0] hud_target_rgb;
    reg [23:0] adj_rgb_p1;
    reg [4:0]  hud_fade_step_p1;
    reg        is_hud_box_p1;

    // Original formula
    wire [11:0] orig_blended_r = (hud_target_rgb[23:16] * hud_fade_step_p1 + adj_rgb_p1[23:16] * (5'd16 - hud_fade_step_p1));
    wire [11:0] orig_blended_g = (hud_target_rgb[15:8]  * hud_fade_step_p1 + adj_rgb_p1[15:8]  * (5'd16 - hud_fade_step_p1));
    wire [11:0] orig_blended_b = (hud_target_rgb[7:0]   * hud_fade_step_p1 + adj_rgb_p1[7:0]   * (5'd16 - hud_fade_step_p1));
    wire [23:0] orig_fade_rgb  = {orig_blended_r[11:4], orig_blended_g[11:4], orig_blended_b[11:4]};

    // Step 4 optimized: Multiplier Reduction + Operand Isolation
    wire        hud_blend_active  = is_hud_box_p1;
    wire [4:0]  eff_hud_fade_step = hud_blend_active ? hud_fade_step_p1 : 5'd0;

    wire signed [8:0]  hud_diff_r    = $signed({1'b0, hud_target_rgb[23:16]}) - $signed({1'b0, adj_rgb_p1[23:16]});
    wire signed [14:0] hud_prod_r    = hud_diff_r * $signed({1'b0, eff_hud_fade_step});
    wire signed [14:0] hud_sum_r     = $signed({1'b0, adj_rgb_p1[23:16], 4'b0}) + hud_prod_r;
    wire [11:0]        opt_blended_r = hud_sum_r[11:0];

    wire signed [8:0]  hud_diff_g    = $signed({1'b0, hud_target_rgb[15:8]})  - $signed({1'b0, adj_rgb_p1[15:8]});
    wire signed [14:0] hud_prod_g    = hud_diff_g * $signed({1'b0, eff_hud_fade_step});
    wire signed [14:0] hud_sum_g     = $signed({1'b0, adj_rgb_p1[15:8], 4'b0})  + hud_prod_g;
    wire [11:0]        opt_blended_g = hud_sum_g[11:0];

    wire signed [8:0]  hud_diff_b    = $signed({1'b0, hud_target_rgb[7:0]})   - $signed({1'b0, adj_rgb_p1[7:0]});
    wire signed [14:0] hud_prod_b    = hud_diff_b * $signed({1'b0, eff_hud_fade_step});
    wire signed [14:0] hud_sum_b     = $signed({1'b0, adj_rgb_p1[7:0], 4'b0})   + hud_prod_b;
    wire [11:0]        opt_blended_b = hud_sum_b[11:0];

    wire [23:0] opt_fade_rgb = {opt_blended_r[11:4], opt_blended_g[11:4], opt_blended_b[11:4]};

    // Waveform check
    reg        in_wave_box;
    reg [8:0]  wave_q;
    wire signed [7:0] orig_cur_wave_val = wave_q[8] ? wave_q[7:0] : 8'd0;
    wire signed [14:0] orig_wave_mult   = orig_cur_wave_val * 7'sd26;

    wire signed [7:0] opt_cur_wave_val  = (in_wave_box && wave_q[8]) ? wave_q[7:0] : 8'd0;
    wire signed [14:0] opt_wave_mult   = opt_cur_wave_val * 7'sd26;

    integer r_idx, g_idx, b_idx, step_idx, wave_idx;
    integer errors = 0;

    initial begin
        $display("[TB] Starting Step 4 Multiplier Reduction + Operand Isolation Verification...");

        is_hud_box_p1 = 1'b1;
        for (step_idx = 0; step_idx <= 16; step_idx = step_idx + 1) begin
            hud_fade_step_p1 = step_idx[4:0];
            for (r_idx = 0; r_idx < 256; r_idx = r_idx + 17) begin
                for (g_idx = 0; g_idx < 256; g_idx = g_idx + 23) begin
                    for (b_idx = 0; b_idx < 256; b_idx = b_idx + 29) begin
                        hud_target_rgb = {r_idx[7:0], g_idx[7:0], b_idx[7:0]};
                        adj_rgb_p1     = {~r_idx[7:0], ~g_idx[7:0], ~b_idx[7:0]};
                        #1;
                        if (opt_fade_rgb !== orig_fade_rgb || opt_blended_r !== orig_blended_r || opt_blended_g !== orig_blended_g || opt_blended_b !== orig_blended_b) begin
                            $display("[ERROR] HUD Mismatch at step %d: orig=%h (%d,%d,%d), opt=%h (%d,%d,%d)",
                                     step_idx, orig_fade_rgb, orig_blended_r, orig_blended_g, orig_blended_b,
                                     opt_fade_rgb, opt_blended_r, opt_blended_g, opt_blended_b);
                            errors = errors + 1;
                        end
                    end
                end
            end
        end

        // Check when is_hud_box_p1 == 0: multiplier product must be 0!
        is_hud_box_p1 = 1'b0;
        for (step_idx = 0; step_idx <= 16; step_idx = step_idx + 1) begin
            hud_fade_step_p1 = step_idx[4:0];
            for (r_idx = 0; r_idx < 256; r_idx = r_idx + 31) begin
                hud_target_rgb = {r_idx[7:0], r_idx[7:0], r_idx[7:0]};
                adj_rgb_p1     = {~r_idx[7:0], ~r_idx[7:0], ~r_idx[7:0]};
                #1;
                if (hud_prod_r !== 15'sd0 || hud_prod_g !== 15'sd0 || hud_prod_b !== 15'sd0) begin
                    $display("[ERROR] Multipliers not zeroed when inactive at step %d", step_idx);
                    errors = errors + 1;
                end
            end
        end

        // Waveform multiplier
        in_wave_box = 1'b1;
        for (wave_idx = -128; wave_idx < 128; wave_idx = wave_idx + 1) begin
            wave_q = {1'b1, wave_idx[7:0]};
            #1;
            if (opt_wave_mult !== orig_wave_mult) begin
                $display("[ERROR] Waveform in box mismatch: val=%d", wave_idx);
                errors = errors + 1;
            end
        end

        in_wave_box = 1'b0;
        for (wave_idx = -128; wave_idx < 128; wave_idx = wave_idx + 1) begin
            wave_q = {1'b1, wave_idx[7:0]};
            #1;
            if (opt_wave_mult !== 15'sd0) begin
                $display("[ERROR] Waveform outside box non-zero");
                errors = errors + 1;
            end
        end

        if (errors == 0) begin
            $display("[TB] SUCCESS: All test vectors passed with 100%% BIT-EXACT equivalence and 0 errors!");
        end else begin
            $display("[TB] FAILED with %d errors!", errors);
        end
        $finish;
    end
endmodule
