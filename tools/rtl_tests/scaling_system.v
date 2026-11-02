// Unencrypted synchronous FIFO/SDRAM boundary model; production controller/renderer.
module scaling_system(
 input mem_clk,video_clk,rst,frame_req,input [20:0] frame_base,input [15:0] width,height,input [1:0] mode,
 input hs,vs,de,display_valid,output hs_out,vs_out,de_out,output [23:0] rgb_out,
 output frame_ack,underflow,output [9:0] display_w,display_h,
 input wr_busy,input data_valid,input [23:0] memory_data,
 output app_read,output [20:0] app_address,output [20:0] read_base,read_len,
 output fifo_clear,output reg source_underflow
);
 wire request,ack,pop,empty;wire [23:0] pixel;
 wire [9:0] used;wire source_overflow;
 scaling_source_fifo #(.WIDTH(24)) source_fifo(
  .clk(mem_clk),.aclr(rst|fifo_clear),.write_valid(data_valid),.write_data(memory_data),
  .read_enable(pop),.read_data(pixel),.empty(empty),.used_words(used),.overflow(source_overflow)
 );
 always @(posedge mem_clk or posedge rst)if(rst)source_underflow<=0;else if(fifo_clear)source_underflow<=0;else if((pop&&empty)||source_overflow)source_underflow<=1;
 frame_fifo_read #(.BURST_SIZE(256),.SAME_CLOCK_REQUEST(1)) reader(
  .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.Sdr_rd_en(data_valid),.App_wr_busy(wr_busy),.O_rd_busy(),
  .App_rd_en(app_read),.App_rd_addr(app_address),.read_req(request),.read_req_ack(ack),.read_finish(),
  .read_addr_0(read_base),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),
  .read_len(read_len),.read_stride_2x(1'b0),.read_line_width(width),.fifo_aclr(fifo_clear),.wrusedw(used)
 );
 scaling_pipeline pipeline(
  .mem_clk(mem_clk),.video_clk(video_clk),.rst(rst),.frame_req(frame_req),.frame_ack(frame_ack),
  .frame_base(frame_base),.width(width),.height(height),.mode(mode),.read_req(request),.read_ack(ack),.read_base(read_base),.read_len(read_len),
  .src_empty(empty),.src_data(pixel),.src_read(pop),.hs(hs),.vs(vs),.de(de),.display_valid(display_valid),
  .hs_out(hs_out),.vs_out(vs_out),.de_out(de_out),.rgb_out(rgb_out),.display_w(display_w),.display_h(display_h),.underflow(underflow)
 );
endmodule
