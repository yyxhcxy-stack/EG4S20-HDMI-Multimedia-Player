// =====================================================================
// 8x16 Dot Matrix Font ROM (ASCII 64 + CJK 16 glyphs = 1280 entries)
// Hardware Native Dual-BRAM9K (1024x8 Lo + 1024x8 Hi) Implementation
// 0 LUT overhead, Native Hardware Macro Mapping on EG4S20
// =====================================================================
`timescale 1ns / 1ps

module font_rom_8x16 (
    input  wire       clk,
    input  wire [6:0] ascii_code, // Supports 0x01-0x10 (CJK) & 0x20-0x7E (ASCII)
    input  wire [3:0] row,        // 0..15 scanlines
    output wire [7:0] font_data   // 8 bits per scanline (MSB=left)
);

    wire [10:0] addr = {ascii_code, row};

    // 1-cycle pipeline delay for high-bit selection (aligned with BRAM read latency)
    reg addr10_q;
    always @(posedge clk) begin
        addr10_q <= addr[10];
    end

    wire [7:0] font_data_lo;
    wire [7:0] font_data_hi;

    // Lower 1024 bytes (ASCII 0x00..0x3F: CJK custom, symbols, numbers '0'-'9')
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(8),
        .ADDR_WIDTH_A(10),
        .DATA_DEPTH_A(1024),
        .DATA_WIDTH_B(8),
        .ADDR_WIDTH_B(10),
        .DATA_DEPTH_B(1024),
        .MODE("SP"),
        .REGMODE_A("NOREG"),
        .IMPLEMENT("9K"),
        .DEBUGGABLE("NO"),
        .PACKABLE("NO"),
        .INIT_FILE("font_rom_8x16_lo.mif"),
        .FILL_ALL("NONE")
    ) rom_lo (
        .dia(8'd0),
        .dib(8'd0),
        .addra(addr[9:0]),
        .addrb(10'd0),
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
        .doa(font_data_lo),
        .dob()
    );

    // Upper 1024 bytes (ASCII 0x40..0x7F: Letters 'A'-'Z', 'a'-'z', punctuation)
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(8),
        .ADDR_WIDTH_A(10),
        .DATA_DEPTH_A(1024),
        .DATA_WIDTH_B(8),
        .ADDR_WIDTH_B(10),
        .DATA_DEPTH_B(1024),
        .MODE("SP"),
        .REGMODE_A("NOREG"),
        .IMPLEMENT("9K"),
        .DEBUGGABLE("NO"),
        .PACKABLE("NO"),
        .INIT_FILE("font_rom_8x16_hi.mif"),
        .FILL_ALL("NONE")
    ) rom_hi (
        .dia(8'd0),
        .dib(8'd0),
        .addra(addr[9:0]),
        .addrb(10'd0),
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
        .doa(font_data_hi),
        .dob()
    );

    // Pure 8-bit 2-to-1 multiplexer (cost: 8 LUTs)
    assign font_data = addr10_q ? font_data_hi : font_data_lo;

endmodule
