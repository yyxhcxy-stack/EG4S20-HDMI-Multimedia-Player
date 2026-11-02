// Stable frame descriptor handshake, memory-clock renderer, pixel-clock output.
module scaling_pipeline(
 input mem_clk,video_clk,rst, input frame_req,output frame_ack,
 input [20:0] frame_base,input [15:0] width,height,input [1:0] mode,
 output reg read_req,input read_ack,output reg [20:0] read_base,read_len,
 input src_empty,input [23:0] src_data,output src_read,
 input hs,vs,de,input display_valid,
 output reg hs_out,vs_out,de_out,output reg [23:0] rgb_out,
 output [9:0] display_w,display_h,output reg underflow
);
 reg req_d;reg [20:0] base_v;reg [10:0] w_v;reg [9:0] h_v;reg [1:0] m_v;
 always @(posedge video_clk or posedge rst) begin
  if(rst) begin req_d<=0;base_v<=0;w_v<=640;h_v<=480;m_v<=0;end
  else begin req_d<=frame_req;if(frame_req&&!req_d) begin base_v<=frame_base;w_v<=width[10:0];h_v<=height[9:0];m_v<=mode;end end
 end
 reg [2:0] req_m;reg ack_m;reg [1:0] ack_v;reg [2:0] request_state;reg [9:0] read_rows;
 reg core_start;reg [10:0] w_m;reg [9:0] h_m;reg [1:0] m_m;reg [20:0] base_m;
 reg [9:0] crop_y_m;reg [20:0] crop_offset;
 assign frame_ack=ack_v[1];
 always @(posedge video_clk or posedge rst) if(rst)ack_v<=0;else ack_v<={ack_v[0],ack_m};
 always @(posedge mem_clk or posedge rst) begin
  if(rst) begin req_m<=0;ack_m<=0;read_req<=0;read_base<=0;read_len<=307200;request_state<=0;core_start<=0;w_m<=640;h_m<=480;m_m<=0;base_m<=0;read_rows<=480;end
  else begin
   req_m<={req_m[1:0],req_d};core_start<=0;
   case(request_state)
    0:if(req_m[2])begin
       w_m<=w_v;h_m<=h_v;m_m<=m_v;base_m<=base_v;
       request_state<=1;
      end
    1:begin
       if(m_m==2'd0 && h_m>10'd480) begin
           crop_y_m <= (h_m - 10'd480) >> 1;
           read_rows <= 10'd481;
       end else if(m_m==2'd1 && h_m>10'd240) begin
           crop_y_m <= (h_m - 10'd240) >> 1;
           read_rows <= 10'd241;
       end else begin
           crop_y_m <= 10'd0;
           read_rows <= h_m;
       end
       request_state<=6;
      end
    6:begin
       crop_offset<=w_m*crop_y_m;
       read_len<=w_m*read_rows;
       request_state<=5;
      end
    5:begin
       if((m_m==2'd0 && h_m>10'd480) || (m_m==2'd1 && h_m>10'd240))
           read_base<=base_m+crop_offset;
       else
           read_base<=base_m;
       request_state<=4;
      end
    4:begin read_req<=1;request_state<=2;end
    2:if(read_ack)begin read_req<=0;ack_m<=1;request_state<=3;end
    3:if(!req_m[2])begin ack_m<=0;core_start<=1;request_state<=0;end
    default:request_state<=0;
   endcase
  end
 end
 wire fifo_full,fifo_empty,write_pixel;wire [23:0] scaled_pixel,fifo_pixel;
 wire [9:0] ow;wire [8:0] oh;wire configured,done;
 scaling_core core(mem_clk,rst,core_start,m_m,w_m,h_m,(src_empty || request_state!=0 || core_start),src_data,src_read,fifo_full,write_pixel,scaled_pixel,ow,oh,configured,done);
 wire pop;
 // Held request clears both domains before the new source request is released.
 scaling_async_fifo output_fifo(mem_clk,video_clk,rst|frame_req,write_pixel,scaled_pixel,fifo_full,pop,fifo_pixel,fifo_empty);
 reg [9:0] ow0,ow1;reg [8:0] oh0,oh1;
 always @(posedge video_clk or posedge rst) begin
  if(rst)begin ow0<=640;ow1<=640;oh0<=480;oh1<=480;end
  else begin ow0<=ow;ow1<=ow0;oh0<=oh;oh1<=oh0;end
 end
 assign display_w=ow1;assign display_h=oh1;
 reg [9:0] x,y;reg de_prev,vs_prev;
 wire [9:0] left=(10'd640-ow1)>>1,top=(10'd480-oh1)>>1;
 wire inside=de&&x>=left&&x<left+ow1&&y>=top&&y<top+oh1;
 assign pop=inside&&display_valid&&!fifo_empty&&!frame_req;
 reg [1:0] hs_pipe,vs_pipe,de_pipe;
 reg pop_d,inside_d,valid_d;reg [23:0] rgb_d;
 always @(posedge video_clk or posedge rst) begin
  if(rst) begin x<=0;y<=0;de_prev<=0;vs_prev<=0;underflow<=0;hs_pipe<=0;vs_pipe<=0;de_pipe<=0;pop_d<=0;inside_d<=0;valid_d<=0;rgb_d<=0;hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;end
  else begin
   vs_prev<=vs;de_prev<=de;
   if(vs_prev&&!vs)begin x<=0;y<=0;underflow<=0;end
   else if(de)x<=x+1'b1;
   else begin x<=0;if(de_prev)y<=y+1'b1;end
   if(inside&&display_valid&&fifo_empty&&!frame_req)underflow<=1;
   hs_pipe<={hs_pipe[0],hs};vs_pipe<={vs_pipe[0],vs};de_pipe<={de_pipe[0],de};
   pop_d<=pop;inside_d<=inside;valid_d<=display_valid;
   rgb_d<=!valid_d?24'd0:pop_d?fifo_pixel:inside_d?24'd0:24'h141c28;
   hs_out<=hs_pipe[1];vs_out<=vs_pipe[1];de_out<=de_pipe[1];rgb_out<=rgb_d;
  end
 end
endmodule

// Registered read, Gray pointers with two-stage synchronizers. Memory is never reset.
module scaling_async_fifo(
 input wrclk,rdclk,rst,input we,input [23:0] di,output full,
 input re,output reg [23:0] dout,output empty
);
 reg [2:0] wr_release,rd_release;
 always @(posedge wrclk or posedge rst)
  if(rst)wr_release<=3'b111;else wr_release<={wr_release[1:0],1'b0};
 always @(posedge rdclk or posedge rst)
  if(rst)rd_release<=3'b111;else rd_release<={rd_release[1:0],1'b0};
 wire wr_rst=wr_release[2],rd_rst=rd_release[2];
 reg [23:0] mem[0:1023];
 reg [10:0] wp,rp,wg,rg;reg [10:0] rg0,rg1,wg0,wg1;
 wire [10:0] wn=wp+(we&&!full),rn=rp+(re&&!empty);
 wire [10:0] wgn=(wn>>1)^wn,rgn=(rn>>1)^rn;
 reg full_flag,empty_flag;
 // Registered look-ahead flags remove a Gray comparison from the pointer
 // increment path. Releasing a full/empty flag is conservatively delayed.
 assign full=full_flag;assign empty=empty_flag;
 always @(posedge wrclk)if(!wr_rst&&we&&!full)mem[wp[9:0]]<=di;
 always @(posedge rdclk)if(!rd_rst&&re&&!empty)dout<=mem[rp[9:0]];
 always @(posedge wrclk or posedge wr_rst)begin
  if(wr_rst)begin wp<=0;wg<=0;rg0<=0;rg1<=0;full_flag<=1;end
  else begin rg0<=rg;rg1<=rg0;wp<=wn;wg<=wgn;full_flag<=wgn=={~rg1[10:9],rg1[8:0]};end
 end
 always @(posedge rdclk or posedge rd_rst)begin
  if(rd_rst)begin rp<=0;rg<=0;wg0<=0;wg1<=0;empty_flag<=1;end
  else begin wg0<=wg;wg1<=wg0;rp<=rn;rg<=rgn;empty_flag<=rgn==wg1;end
 end
endmodule
