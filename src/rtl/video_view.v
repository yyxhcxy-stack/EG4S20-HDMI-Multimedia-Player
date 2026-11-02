module video_view (
    input             video_clk,
    input             rst,
    input             de,
    input      [23:0] rgb_in,
    input             contrast_on,
    output     [23:0] rgb_out
);

    wire [7:0] con_r = contrast(rgb_in[23:16]);
    wire [7:0] con_g = contrast(rgb_in[15:8]);
    wire [7:0] con_b = contrast(rgb_in[7:0]);

    assign rgb_out = (!de) ? 24'd0 :
                     contrast_on ? {con_r, con_g, con_b} : rgb_in;

    function [7:0] contrast;
        input [7:0] ch;
        reg [9:0] scaled;
        begin
            scaled = {1'b0, ch, 1'b0};
            if (scaled < 10'd128)
                contrast = 8'd0;
            else if (scaled > 10'd383)
                contrast = 8'hff;
            else
                contrast = scaled[7:0] - 8'd128;
        end
    endfunction

endmodule
