module audio_baseline(input clk,rst,output bclk,lrck,dout);
hdmi_audio_tone_i2s_64fs tx(.I_mclk(clk),.I_rst(rst),.I_enable(1'b1),.I_emergency_mode(1'b0),.I_note_idx(3'd0),.O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
endmodule
