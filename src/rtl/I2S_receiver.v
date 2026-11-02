`timescale 1ns/1ps
module I2S_receiver(input I_clk,I_rst,I_i2s_BCLK,I_i2s_LRCK,I_i2s_DOUT,
 output reg O_audio_valid,output reg [23:0] O_audio_left_data,O_audio_right_data);
reg [2:0] bs,ws,ds;
reg old_ws,locked,left_good;
reg [5:0] count;
reg [23:0] shift,left_hold;
wire edge_b=bs[1]&&!bs[2];
always @(posedge I_clk or posedge I_rst) begin
 if(I_rst) begin bs<=0;ws<=0;ds<=0;old_ws<=0;locked<=0;left_good<=0;count<=0;shift<=0;left_hold<=0;O_audio_valid<=0;O_audio_left_data<=0;O_audio_right_data<=0;end
 else begin
  bs<={bs[1:0],I_i2s_BCLK};ws<={ws[1:0],I_i2s_LRCK};ds<={ds[1:0],I_i2s_DOUT};O_audio_valid<=0;
  if(edge_b) begin
   if(ws[1]!=old_ws) begin
    old_ws<=ws[1];count<=0;shift<=0;locked<=1;
    if(locked && count==31) begin
     if(ws[1]) begin left_hold<=shift;left_good<=1;end
     else begin
      if(left_good) begin O_audio_left_data<=left_hold;O_audio_right_data<=shift;O_audio_valid<=1;end
      left_good<=0;
     end
    end else left_good<=0;
   end else if(locked) begin
    if(count<24) shift<={shift[22:0],ds[1]};
    if(count<63) count<=count+1'b1;
    else begin locked<=0;left_good<=0;end
   end
  end
 end
end
endmodule
