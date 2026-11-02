`timescale 1ns/1ps
module audio_i2s_tx(input clk,rst,input signed [23:0] left,right,
 output reg bclk,lrck,dout,output wire sample_tick);
reg [1:0] div;
reg [5:0] bit_index;
reg [23:0] held_left,held_right;
wire falling=(div==2'd3);
assign sample_tick=falling && bit_index==6'd63;
always @(posedge clk or posedge rst) begin
 if(rst) begin div<=0;bit_index<=63;bclk<=0;lrck<=1;dout<=0;held_left<=0;held_right<=0;end
 else begin
  div<=div+1'b1;
  if(div==1) bclk<=1;
  if(falling) begin
   bclk<=0;bit_index<=bit_index+1'b1;
   if(bit_index==63) begin lrck<=0;dout<=0;held_left<=left;held_right<=right;end
   else if(bit_index==31) begin lrck<=1;dout<=0;end
   else if(bit_index<24) dout<=held_left[23-bit_index];
   else if(bit_index>=32 && bit_index<56) dout<=held_right[55-bit_index];
   else dout<=0;
  end
 end
end
endmodule
