// One clock ROM latency, using the identical source asset; not a vendor model.
module voice_emergency_rom_64kb(input clk,input [15:0] addr,output reg [7:0] data);
reg [7:0] memory[0:65535];
initial $readmemh("src/rtl/voice_emergency_64kb.hex",memory);
always @(posedge clk) data<=memory[addr];
endmodule
