// Frame configuration only: one restoring divider shared by aspect and DDA setup.
module scaling_geometry(
    input clk, rst, start, input [1:0] mode,
    input [10:0] width, input [9:0] height,
    output reg ready, output reg [9:0] out_w, output reg [8:0] out_h, output reg [10:0] crop_x, output reg [9:0] crop_y,
    output reg [13:0] step_x, step_y,
    output reg [10:0] rem_x, output reg [9:0] rem_y, output reg [10:0] den_x, output reg [9:0] den_y
);
    reg [3:0] state;
    reg [21:0] dividend;
    reg [10:0] remainder;
    reg [10:0] divisor;
    reg [4:0] count;
    reg wide;
    reg [19:0] aspect_w, aspect_h;
    wire [14:0] width_times_15 = {width, 4'b0} - {4'b0, width};
    wire [12:0] height_times_5 = {1'b0, height, 2'b0} + {3'b0, height};
    always @(posedge clk) begin
        aspect_w <= {1'b0, width_times_15, 5'b0};
        aspect_h <= {height_times_5, 7'b0};
    end
    wire [11:0] trial = {remainder, dividend[21]};
    wire [11:0] reduced = trial - {1'b0, divisor};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= 0; ready <= 0; out_w <= 640; out_h <= 480; crop_x <= 0; crop_y <= 0;
            step_x <= 0; step_y <= 0; rem_x <= 0; rem_y <= 0; den_x <= 1; den_y <= 1;
            dividend <= 0; remainder <= 0; divisor <= 1; count <= 0; wide <= 0;
        end else if (start) begin
            ready <= 0; crop_x <= 0; crop_y <= 0; rem_x <= 0; rem_y <= 0; den_x <= 1; den_y <= 1;
            if (mode == 2'd0) begin
                out_w  <= (width > 640) ? 10'd640 : width[9:0];
                out_h  <= (height > 480) ? 9'd480 : height[8:0];
                crop_x <= (width > 640) ? ((width - 11'd640) >> 1) : 11'd0;
                crop_y <= 10'd0;
                step_x <= 14'd4096; step_y <= 14'd4096; state <= 4'd9;
            end else if (mode == 2'd1) begin
                out_w  <= (width > 320) ? 10'd640 : {width[8:0], 1'b0};
                out_h  <= (height > 240) ? 9'd480 : {height[7:0], 1'b0};
                crop_x <= (width > 320) ? ((width - 11'd320) >> 1) : 11'd0;
                crop_y <= 10'd0;
                step_x <= 14'd2048; step_y <= 14'd2048; state <= 4'd9;
            end else if (mode == 2'd2) begin
                out_w  <= (width + 11'd1) >> 1;
                out_h  <= (height + 10'd1) >> 1;
                step_x <= 14'd8192; step_y <= 14'd8192; state <= 4'd9;
            end else begin
                // Products settle in parallel; compare on the following setup clock.
                state <= 4'd8;
            end
        end else case (state)
            4'd8: begin
                wide  <= (aspect_w >= aspect_h);
                state <= 4'd10;
            end
            4'd10: begin
                if (wide) begin
                    out_w    <= 10'd640;
                    dividend <= {2'b0, aspect_h};
                    divisor  <= width;
                end else begin
                    out_h    <= 9'd480;
                    dividend <= {2'b0, aspect_w};
                    divisor  <= {1'b0, height};
                end
                remainder <= 11'd0;
                count     <= 5'd22;
                state     <= 4'd1;
            end
            4'd1, 4'd3, 4'd5: begin
                dividend  <= {dividend[20:0], !reduced[11]};
                remainder <= reduced[11] ? trial[10:0] : reduced[10:0];
                count     <= count - 1'b1;
                if (count == 5'd1) state <= state + 1'b1;
            end
            4'd2: begin
                if (wide)
                    out_h <= (dividend == 0) ? 9'd1 : dividend[8:0];
                else
                    out_w <= (dividend == 0) ? 10'd1 : dividend[9:0];
                state <= 4'd7;
            end
            4'd7: begin
                dividend  <= {(width - 11'd1), 12'b0};
                divisor   <= (out_w > 1) ? {1'b0, (out_w - 1'b1)} : 11'd1;
                den_x     <= (out_w > 1) ? {1'b0, (out_w - 1'b1)} : 11'd1;
                remainder <= 11'd0;
                count     <= 5'd22;
                state     <= 4'd3;
            end
            4'd4: begin
                step_x    <= (out_w > 1) ? dividend[13:0] : 14'd0;
                rem_x     <= (out_w > 1) ? remainder : 11'd0;
                dividend  <= {(height - 10'd1), 12'b0};
                divisor   <= (out_h > 1) ? {2'b0, (out_h - 1'b1)} : 11'd1;
                den_y     <= (out_h > 1) ? (out_h - 1'b1) : 10'd1;
                remainder <= 11'd0;
                count     <= 5'd22;
                state     <= 4'd5;
            end
            4'd6: begin
                step_y <= (out_h > 1) ? dividend[13:0] : 14'd0;
                rem_y  <= (out_h > 1) ? remainder[9:0] : 10'd0;
                state  <= 4'd9;
            end
            4'd9: begin
                ready <= 1'b1;
                state <= 4'd0;
            end
            default: ;
        endcase
    end
endmodule
