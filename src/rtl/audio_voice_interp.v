`timescale 1ns/1ps
module audio_voice_interp(input clk,rst,kick,input signed [23:0] a,b,input [2:0] phase,
 output wire signed [24:0] value,output wire ready);
reg [25:0] dividend,quotient;
reg [2:0] remainder,r;
reg [4:0] count;
reg negative,valid;
reg signed [25:0] q;
wire signed [24:0] diff=$signed({b[23],b})-$signed({a[23],a});
wire [3:0] rem_next={remainder,dividend[25]};
wire ge6=rem_next>=6;
wire [25:0] quot_next={quotient[24:0],ge6};
wire [3:0] reduced=ge6 ? rem_next-4'd6:rem_next;
reg signed [27:0] delta;
reg [5:0] rr;
reg [2:0] correction;
always @* begin
 case(phase)
 0:begin delta=0;rr=3;end
 1:begin delta=q;rr={3'd0,r}+6'd3;end
 2:begin delta=q<<<1;rr=({3'd0,r}<<1)+6'd3;end
 3:begin delta=(q<<<1)+q;rr=({3'd0,r}<<1)+{3'd0,r}+6'd3;end
 4:begin delta=q<<<2;rr=({3'd0,r}<<2)+6'd3;end
 default:begin delta=(q<<<2)+q;rr=({3'd0,r}<<2)+{3'd0,r}+6'd3;end
 endcase
 correction=rr>=30 ? 5:rr>=24 ? 4:rr>=18 ? 3:rr>=12 ? 2:rr>=6 ? 1:0;
end
assign value=$signed({a[23],a})+delta+$signed({1'b0,correction});
assign ready=valid && count==0;
always @(posedge clk or posedge rst) begin
 if(rst) begin dividend<=0;quotient<=0;remainder<=0;count<=0;negative<=0;valid<=0;q<=0;r<=0;end
 else if(kick) begin dividend<=diff[24] ? -diff:diff;quotient<=0;remainder<=0;count<=26;negative<=diff[24];valid<=0;end
 else if(count!=0) begin
  dividend<=dividend<<1;quotient<=quot_next;remainder<=reduced[2:0];count<=count-1'b1;
  if(count==1) begin
   q<=negative ? -$signed(quot_next)-(reduced!=0):$signed(quot_next);
   r<=negative&&reduced!=0 ? 6-reduced:reduced;valid<=1;
  end
 end
end
endmodule
