module enable_equivalence(input clk,rst,valid,input signed [15:0] sample,output mismatch,output done,overrun);
wire actual_done,actual_error,gold_done,gold_error;
wire [255:0] actual_amp,gold_amp;wire [639:0] actual_re,actual_im,gold_re,gold_im;
audio_spectrum_dft actual(.clk(clk),.rst(rst),.sample_valid(valid),.sample(sample),.result_valid(actual_done),.overrun(actual_error),.amplitudes(actual_amp),.debug_re(actual_re),.debug_im(actual_im),.heights(),.ram_addr(),.ram_data(),.ram_write(),.ram_q(9'd0),.ram_grant(1'b1));
audio_spectrum_dft_reference gold(.clk(clk),.rst(rst),.sample_valid(valid),.sample(sample),.result_valid(gold_done),.overrun(gold_error),.amplitudes(gold_amp),.debug_re(gold_re),.debug_im(gold_im),.heights(),.ram_addr(),.ram_data(),.ram_write(),.ram_q(9'd0),.ram_grant(1'b1));
assign mismatch={actual_done,actual_error,actual_amp,actual_re,actual_im}!={gold_done,gold_error,gold_amp,gold_re,gold_im};assign done=actual_done;assign overrun=actual_error;
endmodule
