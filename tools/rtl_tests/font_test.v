module font_test(input clk, input [6:0] ascii_code, input [3:0] row,
                 input [5:0] char_idx, input [2:0] row8,
                 output [7:0] data16, data8);
    font_rom_8x16 a (.clk(clk), .ascii_code(ascii_code), .row(row), .font_data(data16));
    font_rom_8x8 b (.clk(clk), .char_idx(char_idx), .row(row8), .font_data(data8));
endmodule
