module video_wave_osd (
    input             video_clk,
    input             rst,
    input             vs,
    input             de,
    input      [23:0] rgb_in,
    input             audio_valid,
	    input      [23:0] audio_left,
	    input      [2:0]  note_idx,
	    output reg [23:0] rgb_out
	);

    localparam [8:0] BOX_Y0 = 9'd420;
    localparam [8:0] BOX_H  = 9'd28;
    localparam [9:0] BOX_X0 = 10'd16;
    localparam [9:0] BOX_W  = 10'd320;
    localparam [4:0] MID_Y  = 5'd14;

    reg       de_d;
    reg       vs_d;
    reg [9:0] x_cnt;
    reg [8:0] y_cnt;
    reg [4:0] col_y [0:319];
    reg [8:0] wr_col;
    reg [5:0] decim;
    integer   i;
    reg [23:0] audio_peak_env;
    wire [23:0] audio_abs = audio_left[23] ? (-audio_left) : audio_left;

    wire signed [23:0] sample_sh = {{17{audio_left[23]}}, audio_left[23:17]};
    wire signed [5:0]  sample_mag = (sample_sh > 24'sd13) ? 6'sd13 :
                                    (sample_sh < -24'sd13) ? -6'sd13 :
                                    sample_sh[5:0];
    wire signed [6:0]  sample_y_s = 7'sd14 - sample_mag;
    wire [4:0]         sample_y = sample_y_s[4:0];

    wire        in_box = de && (y_cnt >= BOX_Y0) && (y_cnt < BOX_Y0 + BOX_H) &&
                         (x_cnt >= BOX_X0) && (x_cnt < BOX_X0 + BOX_W);
    wire [9:0]  local_x = x_cnt - BOX_X0;
    wire [4:0]  local_y = y_cnt - BOX_Y0;
    wire [4:0]  trace_y = col_y[local_x];
    wire        on_bar = (trace_y >= MID_Y) ? ((local_y >= MID_Y) && (local_y <= trace_y))
                                            : ((local_y <= MID_Y) && (local_y >= trace_y));
	    wire        on_base = (local_y == MID_Y);
	    wire in_spec = de && (x_cnt >= 10'd560) && (x_cnt < 10'd624) &&
	                   (y_cnt >= 9'd400) && (y_cnt < 9'd448);
	    wire [2:0] spec_i = (x_cnt - 10'd560) >> 3;
	    wire [3:0] spec_dist = (spec_i > note_idx) ? (spec_i - note_idx) : (note_idx - spec_i);
	    wire [5:0] spec_h = (spec_dist >= 4'd5) ? 6'd4 : (6'd40 - {spec_dist, 3'd0});
	    wire [5:0] env_factor = (audio_peak_env[23:19] != 5'd0) ? {1'b0, audio_peak_env[23:19]} + 6'd8 : 6'd8;
	    wire [11:0] spec_scaled = spec_h * env_factor;
	    wire [5:0] spec_h_dyn = spec_scaled[10:5];
	    wire spec_bar = (9'd448 - y_cnt) < {3'd0, spec_h_dyn};

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            de_d    <= 1'b0;
            vs_d    <= 1'b0;
            x_cnt   <= 10'd0;
            y_cnt   <= 9'd0;
            wr_col         <= 9'd0;
            decim          <= 6'd0;
            audio_peak_env <= 24'd0;
            rgb_out        <= 24'd0;
            for (i = 0; i < 320; i = i + 1)
                col_y[i] <= MID_Y;
        end else begin
            de_d <= de;
            vs_d <= vs;

            if (audio_valid) begin
                if (audio_abs > audio_peak_env)
                    audio_peak_env <= audio_abs;
                else if (audio_peak_env > 24'd1000)
                    audio_peak_env <= audio_peak_env - (audio_peak_env >> 11);

                if (decim == 6'd63) begin
                    decim        <= 6'd0;
                    col_y[wr_col] <= sample_y;
                    wr_col       <= (wr_col == 9'd319) ? 9'd0 : (wr_col + 9'd1);
                end else begin
                    decim <= decim + 6'd1;
                end
            end

            if (vs && !vs_d) begin
                x_cnt <= 10'd0;
                y_cnt <= 9'd0;
            end else if (de) begin
                x_cnt <= de_d ? (x_cnt + 10'd1) : 10'd0;
            end else if (de_d) begin
                x_cnt <= 10'd0;
                y_cnt <= y_cnt + 9'd1;
            end

	            if (!de)
	                rgb_out <= 24'd0;
	            else if (in_spec && spec_bar)
	                rgb_out <= 24'h40FF40;
	            else if (in_box && on_bar)
                rgb_out <= 24'h00FFFF;
            else if (in_box && on_base)
                rgb_out <= 24'h004060;
            else
                rgb_out <= rgb_in;
        end
    end

endmodule
