`timescale 1ns/1ps
// Bundled data is held until acknowledgement returns; no per-bit resampling.
module audio_snapshot_cdc #(parameter WIDTH=80, HOLD_INPUT=1)(input src_clk,dst_clk,rst,
 input [WIDTH-1:0] data_in,input send,output reg [WIDTH-1:0] data_out,output reg received);
// Asynchronously assert, release only after three edges in each domain.
// A stopped clock keeps its local logic reset. Bundled payload remains held
// through the independently released request/ack synchronizers.
reg [2:0] src_release,dst_release;
always @(posedge src_clk or posedge rst)
 if(rst) src_release<=3'b111; else src_release<={src_release[1:0],1'b0};
always @(posedge dst_clk or posedge rst)
 if(rst) dst_release<=3'b111; else dst_release<={dst_release[1:0],1'b0};
wire src_rst=src_release[2],dst_rst=dst_release[2];
wire [WIDTH-1:0] held;
reg [WIDTH-1:0] payload;
assign held=HOLD_INPUT ? payload : data_in;
reg request,ack;
reg [1:0] req_sync,ack_sync;
always @(posedge src_clk or posedge src_rst) begin
 if(src_rst) begin payload<=0;request<=0;ack_sync<=0;end
 else begin ack_sync<={ack_sync[0],ack};if(send && ack_sync[1]==request) begin if(HOLD_INPUT)payload<=data_in;request<=~request;end end
end
always @(posedge dst_clk or posedge dst_rst) begin
 if(dst_rst) begin req_sync<=0;ack<=0;data_out<=0;received<=0;end
 else begin req_sync<={req_sync[0],request};received<=0;
  if(req_sync[1]!=ack) begin data_out<=held;ack<=req_sync[1];received<=1;end
 end
end
endmodule
