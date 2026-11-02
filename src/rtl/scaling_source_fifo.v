// Source reader and SDRAM share the memory clock in the v2.5 path.
module scaling_source_fifo #(parameter WIDTH=32)(
 input clk,aclr,input write_valid,input [WIDTH-1:0] write_data,
 input read_enable,output reg [WIDTH-1:0] read_data,
 output empty,output [9:0] used_words,output reg overflow
);
 (* ram_style="block" *) reg [WIDTH-1:0] words[0:511];
 reg [8:0] wp,rp;reg [9:0] used;
 wire pop=read_enable&&!empty;
 wire push=write_valid&&used<512;
 assign empty=used==0;assign used_words=used;
 always @(posedge clk)begin
  if(push&&!aclr)words[wp]<=write_data;
  if(pop&&!aclr)read_data<=words[rp];
 end
 always @(posedge clk or posedge aclr)begin
  if(aclr)begin wp<=0;rp<=0;used<=0;overflow<=0;end
  else begin
   if(push)wp<=wp+1'b1;if(pop)rp<=rp+1'b1;
   if(push!=pop)used<=used+(push?10'd1:10'h3ff);
   if(write_valid&&!push)overflow<=1;
  end
 end
endmodule
