module audio_system(input mclk,vclk,clk50,rst,enable,emergency,input [2:0] note,vol,
 output tx_tick,output [23:0] synth_l,synth_r,raw_l,raw_r,out_l,out_r,
 output raw_valid,out_valid,dft_valid,display_dft_valid,output [79:0] display_heights,output [255:0] amplitudes,
 output acr_valid,output [19:0] cts,n,output output_overrun,dft_overrun);
wire bclk,lrck,dout;
audio_synth synth(.clk(mclk),.rst(rst),.sample_tick(tx_tick),.enable(enable),.emergency(emergency),.note_idx(note),.left(synth_l),.right(synth_r));
audio_i2s_tx tx(.clk(mclk),.rst(rst),.left(synth_l),.right(synth_r),.bclk(bclk),.lrck(lrck),.dout(dout),.sample_tick(tx_tick));
I2S_receiver rx(.I_clk(vclk),.I_rst(rst),.I_i2s_BCLK(bclk),.I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),.O_audio_valid(raw_valid),.O_audio_left_data(raw_l),.O_audio_right_data(raw_r));
audio_output_stage stage(.clk(vclk),.rst(rst),.valid_in(raw_valid),.left_in(raw_l),.right_in(raw_r),.enable(enable),.emergency(emergency),.note_idx(note),.volume(vol),.valid_out(out_valid),.left_out(out_l),.right_out(out_r),.overrun(output_overrun));
audio_spectrum_bridge spectrum(.video_clk(vclk),.clk50(clk50),.rst(rst),.audio_valid(out_valid),.display_valid(enable),.sample(out_l[23:8]),.wave_read_address(8'd0),.wave_q(),.amplitudes(amplitudes),.result_valid(dft_valid),.overrun(dft_overrun));
audio_spectrum_bridge #(.DISPLAY_ONLY(1)) display_spectrum(.video_clk(vclk),.clk50(clk50),.rst(rst),.audio_valid(out_valid),.display_valid(enable),.sample(out_l[23:8]),.wave_read_address(8'd0),.wave_q(),.amplitudes(),.heights(display_heights),.result_valid(display_dft_valid),.overrun());
audio_arc_calculate acr(.I_clk(vclk),.I_rst(rst),.I_audio_valid(out_valid),.O_acr_valid(acr_valid),.O_acr_cts(cts),.O_acr_n(n));
endmodule
