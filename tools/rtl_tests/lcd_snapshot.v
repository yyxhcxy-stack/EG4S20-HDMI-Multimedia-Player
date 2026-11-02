module lcd_snapshot(input srcclk,dstclk,rst,send,input [79:0] data,
input [4:0] map_height,output [4:0] mapped_height,
output [79:0] received_data,output received,output scl,mosi,cs,dc,lrst,blk);
lcd_height_map mapping(.height(map_height),.mapped(mapped_height));
audio_snapshot_cdc c(.src_clk(srcclk),.dst_clk(dstclk),.rst(rst),.send(send),.data_in(data),.data_out(received_data),.received(received));
lcd_st7735_telemetry lcd(.clk(dstclk),.rst(rst),.cur_img_idx(3'd0),.scale_mode(2'd3),.vol_mode(3'd0),.audio_pcm(24'd0),.audio_valid(1'b0),.emergency_mode(1'b0),.sdft_spec_8b(received_data[39:0]),.sdft_peak_8b(received_data[79:40]),.lcd_scl(scl),.lcd_mosi(mosi),.lcd_cs(cs),.lcd_dc(dc),.lcd_rst(lrst),.lcd_blk(blk));
endmodule
