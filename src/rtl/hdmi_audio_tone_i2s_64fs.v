`timescale 1ns/1ps
module hdmi_audio_tone_i2s_64fs #(parameter [31:0] PHASE_INC=32'd46819724,parameter signed [23:0] AMP=24'sd8200000,parameter integer NOTE_HOLD_FRAMES=24000)(
 input I_mclk,I_rst,I_enable,I_emergency_mode,input [2:0] I_note_idx,output O_i2s_BCLK,O_i2s_LRCK,O_i2s_DOUT);
reg [1:0] es,ms;
reg [2:0] ns0,ns1;
always @(posedge I_mclk or posedge I_rst) begin
 if(I_rst) begin es<=0;ms<=0;ns0<=0;ns1<=0;end
 else begin es<={es[0],I_enable};ms<={ms[0],I_emergency_mode};ns0<=I_note_idx;ns1<=ns0;end
end
wire signed [23:0] left,right;wire sample_tick;
audio_synth synth(.clk(I_mclk),.rst(I_rst),.sample_tick(sample_tick),.enable(es[1]),.emergency(ms[1]),.note_idx(ns1),.left(left),.right(right));
audio_i2s_tx tx(.clk(I_mclk),.rst(I_rst),.left(left),.right(right),.bclk(O_i2s_BCLK),.lrck(O_i2s_LRCK),.dout(O_i2s_DOUT),.sample_tick(sample_tick));
endmodule
