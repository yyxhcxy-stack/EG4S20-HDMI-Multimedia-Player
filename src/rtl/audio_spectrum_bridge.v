`timescale 1ns/1ps
// Native 9-bit true-dual-port ERAM: waveform 0..255, DFT scratch 256..399.
// DFT runs on the existing 50 MHz board clock, not a new clock/exception.
module audio_spectrum_bridge #(parameter DISPLAY_ONLY=0)(input video_clk,clk50,rst,audio_valid,display_valid,
 input [15:0] sample,input [7:0] wave_read_address,
 output [8:0] wave_q,output [79:0] heights,output result_valid,output [255:0] amplitudes,output overrun);
wire [16:0] sample50;wire valid50;
audio_snapshot_cdc #(.WIDTH(17)) input_cdc(.src_clk(video_clk),.dst_clk(clk50),.rst(rst),
 .data_in({display_valid,sample}),.send(audio_valid),.data_out(sample50),.received(valid50));
wire [9:0] dft_address;wire [8:0] dft_data,ram_q;wire dft_write,dft_valid;wire [255:0] dft_amplitudes;wire [79:0] dft_heights;
reg [7:0] wave_pointer;
always @(posedge clk50 or posedge rst)if(rst)wave_pointer<=0;else if(valid50)wave_pointer<=wave_pointer+1'b1;
wire [9:0] address=valid50 ? {2'd0,wave_pointer} : dft_address;
wire [8:0] data=valid50 ? {sample50[16],sample50[15:8]} : dft_data;
wire write=valid50||dft_write;
audio_spectrum_dft #(.EXTERNAL_RAM(1),.DISPLAY_ONLY(DISPLAY_ONLY)) dft(.clk(clk50),.rst(rst),.sample_valid(valid50),.sample(sample50[15:0]),
 .result_valid(dft_valid),.amplitudes(dft_amplitudes),.overrun(overrun),.debug_re(),.debug_im(),.heights(dft_heights),
 .ram_addr(dft_address),.ram_data(dft_data),.ram_write(dft_write),.ram_q(ram_q),.ram_grant(!valid50));
// DFT pending amplitudes remain unchanged until the final sample of the NEXT window.
// The receiver acknowledges within ~10 clocks; this hold contract saves 256 redundant FFs.
generate if(DISPLAY_ONLY)begin
 audio_snapshot_cdc #(.WIDTH(80),.HOLD_INPUT(0)) result_cdc(.src_clk(clk50),.dst_clk(video_clk),.rst(rst),
 .data_in(dft_heights),.send(dft_valid),.data_out(heights),.received(result_valid));
 assign amplitudes=0;
end else begin
 audio_snapshot_cdc #(.WIDTH(256),.HOLD_INPUT(0)) result_cdc(.src_clk(clk50),.dst_clk(video_clk),.rst(rst),
 .data_in(dft_amplitudes),.send(dft_valid),.data_out(amplitudes),.received(result_valid));
 assign heights=0;
end endgenerate
`ifdef YOSYS
reg [8:0] memory[0:1023];reg [8:0] aq,bq;
always @(posedge clk50)begin aq<=memory[address];if(write&&!rst)memory[address]<=data;end
always @(posedge video_clk)bq<=memory[{2'd0,wave_read_address}];
assign ram_q=aq;assign wave_q=bq;
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(9),.DATA_WIDTH_B(9),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
 .DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("READBEFOREWRITE"),.WRITEMODE_B("NORMAL"),.IMPLEMENT("9K"),.PACKABLE("NO"),.INIT_FILE("NONE"),.FILL_ALL("NONE"))
 audio_history_bram(.clka(clk50),.clkb(video_clk),.addra(address),.addrb({2'd0,wave_read_address}),
 .dia(data),.dib(9'd0),.cea(1'b1),.ceb(1'b1),.ocea(1'b1),.oceb(1'b1),.wea(write&&!rst),.web(1'b0),
 .rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.doa(ram_q),.dob(wave_q));
`endif
endmodule
