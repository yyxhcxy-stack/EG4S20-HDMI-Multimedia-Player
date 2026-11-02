// Held frame descriptor for two text banks in the EXISTING UART FIFO RAM.
// UART owns inactive bank; the video frame commit acknowledges its release.
module marquee_store(
 input clk,video_clk,rst,frame_pulse,
 input submit,is_text,enable_value,input [7:0] text_length,
 output busy,output reg done,
 output write_bank,output reg read_bank,
 input [6:0] read_addr,input [7:0] ram_read_data,output [6:0] read_data,
 output reg custom_valid,hidden,normal_reset
);
 reg [2:0] producer_release,video_release;
 always @(posedge clk or posedge rst)
  if(rst)producer_release<=3'b111;else producer_release<={producer_release[1:0],1'b0};
 always @(posedge video_clk or posedge rst)
  if(rst)video_release<=3'b111;else video_release<={video_release[1:0],1'b0};
 wire producer_rst=producer_release[2],video_rst=video_release[2];
 reg producer_bank,request_toggle,held_bank,held_is_text,held_enable;
 reg [7:0] held_length,active_length;
 reg [1:0] request_sync,ack_sync;
 reg acknowledge_toggle,ack_seen,read_in_range;
 assign busy=request_toggle!=ack_sync[1];
 assign write_bank=!producer_bank;
 always @(posedge clk or posedge producer_rst)begin
  if(producer_rst)begin producer_bank<=0;request_toggle<=0;held_bank<=0;held_is_text<=0;held_enable<=1;held_length<=0;ack_sync<=0;ack_seen<=0;done<=0;end
  else begin
   ack_sync<={ack_sync[0],acknowledge_toggle};ack_seen<=ack_sync[1];done<=ack_sync[1]!=ack_seen;
   if(submit&&!busy)begin
    held_bank<=!producer_bank;held_is_text<=is_text;held_enable<=enable_value;held_length<=text_length;request_toggle<=!request_toggle;
    if(is_text)producer_bank<=!producer_bank;
   end
  end
 end
 always @(posedge video_clk or posedge video_rst)begin
  if(video_rst)begin request_sync<=0;acknowledge_toggle<=0;read_bank<=0;active_length<=0;custom_valid<=0;hidden<=0;normal_reset<=0;read_in_range<=0;end
  else begin
   request_sync<={request_sync[0],request_toggle};normal_reset<=0;
   read_in_range<=read_addr<active_length;
   if(frame_pulse&&request_sync[1]!=acknowledge_toggle)begin
    if(held_is_text)begin read_bank<=held_bank;active_length<=held_length;custom_valid<=1;normal_reset<=1;end
    else begin hidden<=!held_enable;normal_reset<=held_enable;end
    acknowledge_toggle<=request_sync[1];
   end
  end
 end
 assign read_data=read_in_range?ram_read_data[6:0]:7'h20;
endmodule
