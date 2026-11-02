module audio_i2s(input txclk,rxclk,rst,manual,rxreset,mb,mw,md,input [23:0] left,right,
 output bclk,lrck,dout,tick,valid,output [23:0] rxleft,rxright);
audio_i2s_tx tx(.clk(txclk),.rst(rst),.left(left),.right(right),.bclk(bclk),.lrck(lrck),.dout(dout),.sample_tick(tick));
I2S_receiver rx(.I_clk(rxclk),.I_rst(rst|rxreset),.I_i2s_BCLK(manual?mb:bclk),.I_i2s_LRCK(manual?mw:lrck),.I_i2s_DOUT(manual?md:dout),.O_audio_valid(valid),.O_audio_left_data(rxleft),.O_audio_right_data(rxright));
endmodule
