module cdc_reset(input srcclk,dstclk,rst,send,input [79:0] data,output [79:0] result,output valid);
audio_snapshot_cdc c(.src_clk(srcclk),.dst_clk(dstclk),.rst(rst),.send(send),.data_in(data),.data_out(result),.received(valid));
endmodule
