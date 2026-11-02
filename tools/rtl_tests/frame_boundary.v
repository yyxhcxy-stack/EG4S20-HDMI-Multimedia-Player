// Actual timing generator plus the top-level descriptor latching order.
module frame_boundary(
 input mem_clk,video_clk,rst,input [1:0] requested_mode,input [15:0] requested_width,requested_height,input [20:0] requested_base,
 output read_req,output [20:0] read_base,read_len,output [9:0] display_w,display_h,
 output frame_pulse
);
 wire hs,vs,de,frame_req,frame_ack;reg vs_prev;
 reg [1:0] active_mode;reg [15:0] active_width,active_height;reg [20:0] active_base;
 assign frame_pulse=vs_prev&&!vs;
 always @(posedge video_clk or posedge rst)begin
  if(rst)begin vs_prev<=0;active_mode<=3;active_width<=640;active_height<=480;active_base<=0;end
  else begin vs_prev<=vs;if(frame_pulse)begin active_mode<=requested_mode;active_width<=requested_width;active_height<=requested_height;active_base<=requested_base;end end
 end
 video_timing_data timing(.video_clk(video_clk),.rst(rst),.read_req(frame_req),.read_req_ack(frame_ack),.hs(hs),.vs(vs),.de(de));
 scaling_pipeline pipeline(
  .mem_clk(mem_clk),.video_clk(video_clk),.rst(rst),.frame_req(frame_req),.frame_ack(frame_ack),
  .frame_base(active_base),.width(active_width),.height(active_height),.mode(active_mode),
  .read_req(read_req),.read_ack(read_req),.read_base(read_base),.read_len(read_len),
  .src_empty(1'b1),.src_data(24'd0),.src_read(),.hs(hs),.vs(vs),.de(de),.display_valid(1'b1),
  .hs_out(),.vs_out(),.de_out(),.rgb_out(),.display_w(display_w),.display_h(display_h),.underflow()
 );
endmodule
