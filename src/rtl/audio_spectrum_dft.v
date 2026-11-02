`timescale 1ns/1ps
// Scratch accumulators share unused addresses of the existing waveform BRAM.
module audio_spectrum_dft #(parameter EXTERNAL_RAM=0, DISPLAY_ONLY=0)(input clk,rst,sample_valid,input signed [15:0] sample,
 output reg result_valid,output wire [255:0] amplitudes,output reg overrun,
 output wire [639:0] debug_re,debug_im, output wire [79:0] heights,
 output wire [9:0] ram_addr,output wire [8:0] ram_data,output wire ram_write,
 input [8:0] ram_q,input ram_grant);
assign debug_re = 640'd0;
assign debug_im = 640'd0;
reg [1:0] state;
reg [3:0] bin;
reg [3:0] segment;
reg [7:0] n,phase;
reg [11:0] sample_gap;
reg signed [15:0] held_sample,cr,ci;
reg signed [31:0] pr,pi;
reg [80:0] read_word;
reg [255:0] pending;
assign amplitudes=DISPLAY_ONLY ? 256'd0 : pending;
reg [79:0] pending_heights;reg [15:0] normalized;
assign heights=pending_heights;
function [4:0] height;input [15:0] amp;reg [21:0] scaled;begin
 scaled=({6'd0,amp}<<4)+({6'd0,amp}<<3)+({6'd0,amp}<<1)+22'd4096;
 height=(scaled>>13)>26 ? 5'd26 : (scaled>>13);end endfunction
reg [39:0] abs_r,abs_i;
reg [40:0] magnitude;
wire signed [39:0] sum_r=$signed(read_word[39:0]);
wire signed [39:0] sum_i=$signed(read_word[79:40]);
wire signed [39:0] old_r=n==0 ? 40'sd0 : $signed(read_word[39:0]);
wire signed [39:0] old_i=n==0 ? 40'sd0 : $signed(read_word[79:40]);
wire [9:0] base=10'd256+{3'd0,bin,3'd0}+{6'd0,bin};
assign ram_addr=base+(segment>8 ? 4'd8 : segment);
assign ram_data=read_word[8:0];
assign ram_write=state==3;
wire [8:0] memory_q;
wire grant;
generate if(EXTERNAL_RAM) begin assign memory_q=ram_q;assign grant=ram_grant;end
else begin
 (* ram_style="block" *) reg [8:0] scratch[0:1023];
 reg [8:0] q;
 always @(posedge clk) begin q<=scratch[ram_addr];if(ram_write)scratch[ram_addr]<=ram_data;end
 assign memory_q=q;assign grant=1'b1;
end endgenerate
integer j;
// k increments are 1,2,4,8,13; walk n*k exactly modulo 256.
// One phase register replaces sixteen banks of phase state and their mux.
wire [7:0] thirteen_n=(n<<3)+(n<<2)+n;
wire [7:0] phase_delta=bin<7 ? n : bin<9 ? (n<<1) : bin<12 ? (n<<2) : bin<14 ? (n<<3) : thirteen_n;
function signed [15:0] quarter;input [6:0] a;begin
 case(a)
 7'd0:quarter=16'sd32767;
 7'd1:quarter=16'sd32757;
 7'd2:quarter=16'sd32728;
 7'd3:quarter=16'sd32678;
 7'd4:quarter=16'sd32609;
 7'd5:quarter=16'sd32521;
 7'd6:quarter=16'sd32412;
 7'd7:quarter=16'sd32285;
 7'd8:quarter=16'sd32137;
 7'd9:quarter=16'sd31971;
 7'd10:quarter=16'sd31785;
 7'd11:quarter=16'sd31580;
 7'd12:quarter=16'sd31356;
 7'd13:quarter=16'sd31113;
 7'd14:quarter=16'sd30852;
 7'd15:quarter=16'sd30571;
 7'd16:quarter=16'sd30273;
 7'd17:quarter=16'sd29956;
 7'd18:quarter=16'sd29621;
 7'd19:quarter=16'sd29268;
 7'd20:quarter=16'sd28898;
 7'd21:quarter=16'sd28510;
 7'd22:quarter=16'sd28105;
 7'd23:quarter=16'sd27683;
 7'd24:quarter=16'sd27245;
 7'd25:quarter=16'sd26790;
 7'd26:quarter=16'sd26319;
 7'd27:quarter=16'sd25832;
 7'd28:quarter=16'sd25329;
 7'd29:quarter=16'sd24811;
 7'd30:quarter=16'sd24279;
 7'd31:quarter=16'sd23731;
 7'd32:quarter=16'sd23170;
 7'd33:quarter=16'sd22594;
 7'd34:quarter=16'sd22005;
 7'd35:quarter=16'sd21403;
 7'd36:quarter=16'sd20787;
 7'd37:quarter=16'sd20159;
 7'd38:quarter=16'sd19519;
 7'd39:quarter=16'sd18868;
 7'd40:quarter=16'sd18204;
 7'd41:quarter=16'sd17530;
 7'd42:quarter=16'sd16846;
 7'd43:quarter=16'sd16151;
 7'd44:quarter=16'sd15446;
 7'd45:quarter=16'sd14732;
 7'd46:quarter=16'sd14010;
 7'd47:quarter=16'sd13279;
 7'd48:quarter=16'sd12539;
 7'd49:quarter=16'sd11793;
 7'd50:quarter=16'sd11039;
 7'd51:quarter=16'sd10278;
 7'd52:quarter=16'sd9512;
 7'd53:quarter=16'sd8739;
 7'd54:quarter=16'sd7962;
 7'd55:quarter=16'sd7179;
 7'd56:quarter=16'sd6393;
 7'd57:quarter=16'sd5602;
 7'd58:quarter=16'sd4808;
 7'd59:quarter=16'sd4011;
 7'd60:quarter=16'sd3212;
 7'd61:quarter=16'sd2410;
 7'd62:quarter=16'sd1608;
 7'd63:quarter=16'sd804;
 7'd64:quarter=16'sd0;
 default:quarter=0;
 endcase
end endfunction
function signed [15:0] cosine;input [7:0] p;reg [6:0] a;reg neg;begin
 case(p[7:6])
 0:begin a={1'b0,p[5:0]};neg=0;end
 1:begin a=7'd64-{1'b0,p[5:0]};neg=1;end
 2:begin a={1'b0,p[5:0]};neg=1;end
 default:begin a=7'd64-{1'b0,p[5:0]};neg=0;end
 endcase
 cosine=neg?-quarter(a):quarter(a);
end endfunction

reg signed [15:0] coefficient_q;
wire signed [15:0] coefficient=cosine(phase-(segment==0 ? 8'd0 : 8'd64));
always @(posedge clk)coefficient_q<=segment==0 ? coefficient : -coefficient;
// cr/ci are committed in segments 1/2; segment 3 captures both products.
// Products remain stable until the accumulator consumes them in state 2.
// Repeated capture while RAM arbitration stalls is harmless.
always @(posedge clk) if(state==1 && segment==3) begin
 pr<=held_sample*cr;pi<=held_sample*ci;
end
always @(posedge clk or posedge rst) begin
 if(rst) begin sample_gap<=0;state<=0;bin<=0;segment<=0;n<=0;held_sample<=0;cr<=0;ci<=0;read_word<=0;pending<=0;pending_heights<=0;normalized<=0;result_valid<=0;overrun<=0;abs_r<=0;abs_i<=0;magnitude<=0;
  phase<=0;
 end else begin
  result_valid<=0;
  if(sample_valid)sample_gap<=0;else if(sample_gap!=4095)sample_gap<=sample_gap+1'b1;
  if(sample_gap==4094 && !sample_valid)begin state<=0;n<=0;phase<=0;end
  else if(sample_valid && state!=0) begin overrun<=1;state<=0;n<=0;phase<=0;end
  else case(state)
 0:if(sample_valid) begin held_sample<=sample;phase<=n;bin<=0;segment<=0;state<=1;end
 1:if(grant) begin
  if(segment==1) cr<=coefficient_q;
  if(segment==2) ci<=coefficient_q;
  if(segment!=0) read_word<={memory_q,read_word[80:9]};
  if(segment==9)begin segment<=0;state<=2;end else segment<=segment+1'b1;
 end
 2:begin
  read_word<={1'd0,(old_i+{{8{pi[31]}},pi}),(old_r+{{8{pr[31]}},pr})};
  state<=3;segment<=0;
 end
 3:if(grant) begin
  read_word<=read_word>>9;
  if(n==255)case(segment)
   0:begin abs_r<=sum_r[39] ? -sum_r : sum_r;abs_i<=sum_i[39] ? -sum_i : sum_i;end
   1:magnitude<=abs_r>abs_i ? {1'b0,abs_r}+({1'b0,abs_i}>>1) : {1'b0,abs_i}+({1'b0,abs_r}>>1);
   2:begin normalized<=((magnitude+41'd2097152)>>22)>65535 ? 16'hffff : ((magnitude+41'd2097152)>>22);
     if(!DISPLAY_ONLY)pending[bin*16+:16]<=((magnitude+41'd2097152)>>22)>65535 ? 16'hffff : ((magnitude+41'd2097152)>>22);end
   3:if(DISPLAY_ONLY)pending_heights[bin*5+:5]<=height(normalized);
  endcase
  if(segment==8) begin
   phase<=phase+phase_delta;segment<=0;
   if(bin==15) begin
    n<=n+1'b1;state<=0;
    if(n==255) begin result_valid<=1;end
   end else begin bin<=bin+1'b1;state<=1;end
  end else segment<=segment+1'b1;
 end
 endcase
 end
end
endmodule
