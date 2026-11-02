`timescale 1ns/1ps
module audio_synth(input clk,rst,sample_tick,enable,emergency,input [2:0] note_idx,
 output reg signed [23:0] left,right);
    function [31:0] inc0_lut;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: inc0_lut = 32'd46819724;  // π¨“Ù (ª∆÷” C5 523.25Hz - …Ã÷‹¥ÛøÀ∂¶)
                3'd1: inc0_lut = 32'd52553362;  // …Ã“Ù (Ã´¥ÿ D5 587.33Hz - ∫∫Œ∫≤‹»´±Æ)
                3'd2: inc0_lut = 32'd58989156;  // Ω«“Ù (π√œ¥ E5 659.25Hz - “Û–Êº◊π«Œƒ)
                3'd3: inc0_lut = 32'd70150310;  // ·Á“Ù (¡÷÷” G5 783.99Hz - ≥§¿÷Œ¥—ÎÕﬂµ±)
                default: inc0_lut = 32'd78741068; // ”“Ù (ƒœ¬¿ A5 880.00Hz)
            endcase
        end
    endfunction
    function [31:0] inc1_lut;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: inc1_lut = 32'd129222438; // 2.76 * 523.25 = 1444.17Hz
                3'd1: inc1_lut = 32'd145047279; // 2.76 * 587.33 = 1621.03Hz
                3'd2: inc1_lut = 32'd162810070; // 2.76 * 659.25 = 1819.54Hz
                3'd3: inc1_lut = 32'd193614856; // 2.76 * 783.99 = 2163.81Hz
                default: inc1_lut = 32'd217325348; // 2.76 * 880.00 = 2428.80Hz
            endcase
        end
    endfunction
    function [31:0] inc2_lut;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: inc2_lut = 32'd252826510; // 5.40 * 523.25 = 2825.55Hz
                3'd1: inc2_lut = 32'd283788155; // 5.40 * 587.33 = 3171.58Hz
                3'd2: inc2_lut = 32'd318541442; // 5.40 * 659.25 = 3559.98Hz
                3'd3: inc2_lut = 32'd378811674; // 5.40 * 783.99 = 4233.55Hz
                default: inc2_lut = 32'd425201767; // 5.40 * 880.00 = 4752.00Hz
            endcase
        end
    endfunction
reg [31:0] phase0,phase1,phase2,alarm_phase;
reg [23:0] env0,env1,env2;
// reg [17:0] chime_count;
reg [18:0] emerg_count;
reg [14:0] alarm_count;
reg alarm_select,enabled_last,emergency_last;
reg [2:0] note_last;
reg signed [23:0] previous_bell;
wire [15:0] fold0=phase0[31] ? ~phase0[30:15]:phase0[30:15];
wire [15:0] fold1=phase1[31] ? ~phase1[30:15]:phase1[30:15];
wire [15:0] fold2=phase2[31] ? ~phase2[30:15]:phase2[30:15];
wire signed [16:0] triangle0=$signed({1'b0,fold0})-17'sd32768;
wire signed [16:0] triangle1=$signed({1'b0,fold1})-17'sd32768;
wire signed [16:0] triangle2=$signed({1'b0,fold2})-17'sd32768;
reg signed [31:0] prod0,prod1,prod2;
wire bell_active = enable && !emergency && (|{env0[23:9], env1[23:9], env2[23:9]});
always @(posedge clk) begin if (bell_active) begin prod0<=triangle0*$signed({1'b0,env0[23:9]});prod1<=triangle1*$signed({1'b0,env1[23:9]});prod2<=triangle2*$signed({1'b0,env2[23:9]});end end
wire signed [25:0] bell_sum=(prod0>>>7)+(prod1>>>7)+(prod2>>>7);
wire signed [23:0] bell=bell_sum>26'sd8000000 ? 24'sd8000000:bell_sum< -26'sd8000000 ? -24'sd8000000:bell_sum[23:0];
wire signed [23:0] alarm=alarm_phase[31] ? -24'sd8200000:24'sd8200000;
reg [15:0] rom_addr,voice_index;
wire [7:0] rom_data;
voice_emergency_rom_64kb rom(.clk(clk),.addr(rom_addr),.data(rom_data));
wire signed [23:0] converted={~rom_data[7],rom_data[6:0],16'd0};
reg signed [23:0] voice_a,voice_b;
reg [2:0] preload,voice_step;
reg interp_kick;
wire interp_ready;
wire signed [24:0] interpolated;
audio_voice_interp interp(.clk(clk),.rst(rst),.kick(interp_kick),.a(voice_a),.b(voice_b),.phase(voice_step),.value(interpolated),.ready(interp_ready));
wire signed [26:0] voice_boost=$signed(interpolated)+(interpolated>>>1)+(interpolated>>>2);
wire signed [23:0] voice=voice_boost>27'sd8200000 ? 24'sd8200000:voice_boost< -27'sd8200000 ? -24'sd8200000:voice_boost[23:0];
always @(posedge clk or posedge rst) begin
 if(rst) begin
  left<=0;right<=0;phase0<=0;phase1<=0;phase2<=0;env0<=0;env1<=0;env2<=0;enabled_last<=0;note_last<=0;previous_bell<=0;
  emerg_count<=0;alarm_count<=0;alarm_select<=0;alarm_phase<=0;emergency_last<=0;rom_addr<=0;voice_index<=0;voice_a<=0;voice_b<=0;preload<=0;voice_step<=0;interp_kick<=0;
 end else begin
  interp_kick<=0;
  if(!emergency) begin preload<=0;rom_addr<=0;end
  else if(preload<5) case(preload)
   0:begin rom_addr<=0;preload<=1;end
   1:preload<=2;
   2:begin voice_a<=converted;rom_addr<=1;preload<=3;end
   3:preload<=4;
   4:begin voice_b<=converted;rom_addr<=2;preload<=5;interp_kick<=1;end
  endcase
  if(sample_tick) begin
   emergency_last<=emergency;
   if(emergency) begin
    enabled_last<=0;
    if(!emergency_last) begin emerg_count<=0;alarm_count<=0;alarm_select<=0;voice_index<=0;voice_step<=0;end
    else if(emerg_count==498815) begin emerg_count<=0;alarm_count<=0;alarm_select<=0;alarm_phase<=0;voice_index<=0;voice_step<=0;preload<=0;end
    else begin
     emerg_count<=emerg_count+1'b1;
     if(emerg_count<96000) begin
      if(alarm_count==23999) begin alarm_count<=0;alarm_select<=~alarm_select;end else alarm_count<=alarm_count+1'b1;
      alarm_phase<=alarm_phase+(alarm_select ? 32'd78741068:32'd39370534);
     end else if(emerg_count>=105600) begin
      if(voice_step==5) begin
       voice_step<=0;voice_a<=voice_b;voice_b<=voice_index>=65534 ? voice_b:converted;
       if(voice_index!=65535) voice_index<=voice_index+1'b1;
       rom_addr<=rom_addr==65535 ? 16'd65535:rom_addr+1'b1;interp_kick<=1;
      end else voice_step<=voice_step+1'b1;
     end
    end
    left<=emerg_count<96000 ? alarm:emerg_count<105600 ? 24'sd0:voice;
    right<=emerg_count<96000 ? alarm:emerg_count<105600 ? 24'sd0:voice;
   end else if(!enable) begin
    left<=0;right<=0;env0<=0;env1<=0;env2<=0;enabled_last<=0;previous_bell<=0;note_last<=note_idx;emerg_count<=0;
   end else begin
    emerg_count<=0;
    if(!enabled_last || note_idx!=note_last) begin enabled_last<=1;note_last<=note_idx;env0<=8000000;env1<=4200000;env2<=2600000;end
    else begin
     if(env0!=0) env0<=env0-((env0>>15)==0 ? 24'd1:(env0>>15));
     if(env1!=0) env1<=env1-((env1>>14)==0 ? 24'd1:(env1>>14));
     if(env2!=0) env2<=env2-((env2>>13)==0 ? 24'd1:(env2>>13));
    end
    phase0<=phase0+inc0_lut(note_idx);phase1<=phase1+inc1_lut(note_idx);phase2<=phase2+inc2_lut(note_idx);
    left<=bell;right<=(bell>>>1)+(previous_bell>>>1);previous_bell<=bell;
   end
  end
 end
end
endmodule
