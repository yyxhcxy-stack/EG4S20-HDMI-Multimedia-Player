`timescale 1ns/1ps
module audio_output_stage(
    input clk, rst, valid_in,
    input signed [23:0] left_in, right_in,
    input enable, emergency,
    input [2:0] note_idx,
    input [2:0] volume,
    output reg valid_out,
    output reg signed [23:0] left_out, right_out,
    output wire overrun
);
assign overrun = 1'b0;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        valid_out <= 1'b0;
        left_out  <= 24'sd0;
        right_out <= 24'sd0;
    end else begin
        valid_out <= valid_in;
        if (valid_in) begin
            if (emergency) begin
                left_out  <= left_in;
                right_out <= right_in;
            end else if (!enable) begin
                left_out  <= 24'sd0;
                right_out <= 24'sd0;
            end else begin
                case (volume)
                    3'd0: begin // 100%
                        left_out  <= left_in;
                        right_out <= right_in;
                    end
                    3'd1: begin // 75%
                        left_out  <= (left_in >>> 1) + (left_in >>> 2);
                        right_out <= (right_in >>> 1) + (right_in >>> 2);
                    end
                    3'd2: begin // 50%
                        left_out  <= (left_in >>> 1);
                        right_out <= (right_in >>> 1);
                    end
                    3'd3: begin // 25%
                        left_out  <= (left_in >>> 2);
                        right_out <= (right_in >>> 2);
                    end
                    default: begin // 0% Mute
                        left_out  <= 24'sd0;
                        right_out <= 24'sd0;
                    end
                endcase
            end
        end
    end
end
endmodule
