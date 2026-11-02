`timescale 1ns / 1ps
// ============================================================================
// Module Name:  voice_emergency_rom_64kb
// Description:  On-chip 64KB ROM storing 8kHz 8-bit PCM Mandarin evacuation
//               speech broadcast ("火警警报！现场突发险情，请沿屏幕绿色指示光流有序撤离！")
//               Explicitly instantiated using Anlogic EG_LOGIC_BRAM with
//               IMPLEMENT = "32K", awakening all 16x ERAM32K blocks on EG4S20.
// ============================================================================

module voice_emergency_rom_64kb (
    input  wire        clk,
    input  wire [15:0] addr,
    output wire [7:0]  data
);

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(8),
        .ADDR_WIDTH_A(16),
        .DATA_DEPTH_A(65536),
        .DATA_WIDTH_B(8),
        .ADDR_WIDTH_B(16),
        .DATA_DEPTH_B(65536),
        .MODE("SP"),
        .REGMODE_A("NOREG"),
        .IMPLEMENT("32K"),
        .DEBUGGABLE("NO"),
        .PACKABLE("NO"),
        .INIT_FILE("voice_emergency_64kb.mif"),
        .FILL_ALL("NONE")
    ) inst (
        .dia(8'd0),
        .dib(8'd0),
        .addra(addr),
        .addrb(16'd0),
        .cea(1'b1),
        .ceb(1'b0),
        .ocea(1'b0),
        .oceb(1'b0),
        .clka(clk),
        .clkb(1'b0),
        .wea(1'b0),
        .web(1'b0),
        .bea(1'b0),
        .beb(1'b0),
        .rsta(1'b0),
        .rstb(1'b0),
        .doa(data),
        .dob()
    );

endmodule
