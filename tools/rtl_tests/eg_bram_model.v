// Behavioral model of the used EG4 DP/READBEFOREWRITE configuration.
// Source: official TN308, plus TD6.2 EG4 primitive template. Not an encrypted vendor model.
module EG_LOGIC_BRAM #(
 parameter DATA_WIDTH_A=9,DATA_WIDTH_B=9,ADDR_WIDTH_A=8,ADDR_WIDTH_B=8,
 DATA_DEPTH_A=256,DATA_DEPTH_B=256,MODE="DP",REGMODE_A="NOREG",REGMODE_B="NOREG",
 WRITEMODE_A="READBEFOREWRITE",WRITEMODE_B="NORMAL",IMPLEMENT="9K",PACKABLE="NO",
 INIT_FILE="NONE",FILL_ALL="NONE"
)(input clka,clkb,input [ADDR_WIDTH_A-1:0] addra,input [ADDR_WIDTH_B-1:0] addrb,
input [DATA_WIDTH_A-1:0] dia,input [DATA_WIDTH_B-1:0] dib,
input cea,ceb,ocea,oceb,wea,web,rsta,rstb,bea,beb,
output reg [DATA_WIDTH_A-1:0] doa,output reg [DATA_WIDTH_B-1:0] dob);
// Native 9-bit true dual-port ERAM9K, as documented in TN308 table 7.
reg [8:0] memory[0:(DATA_DEPTH_A>1024?DATA_DEPTH_A:1024)-1];
initial if(INIT_FILE=="font_rom_8x16.mif")$readmemh("src/rtl/font_rom_8x16.hex",memory);
always @(posedge clka) if(cea)begin doa<=memory[addra];if(wea)memory[addra]<=dia;end
always @(posedge clkb) if(ceb)begin dob<=memory[addrb];if(web)memory[addrb]<=dib;end
endmodule
