// Exact original brightness/contrast transfer curves, synchronous lookup.
module video_adjust_lut(input clk,input [1:0] brightness,input [2:0] contrast,input [1:0] tone_mode,input [23:0] rgb_in,output wire [23:0] rgb_out);
    // Exact floor(channel * gain / 256), using constant shifts only.
    function [7:0] fn_bright;
        input [7:0] ch;
        input [1:0] lvl;
        reg [10:0] scaled;
        begin
            case(lvl)
                2'd0: scaled = {1'b0,ch,2'b0};
                2'd1: scaled = ({3'b0,ch} << 2) + {3'b0,ch};
                2'd2: scaled = ({3'b0,ch} << 1) + {3'b0,ch};
                2'd3: scaled = ({3'b0,ch} << 2) + ({3'b0,ch} << 1);
            endcase
            fn_bright = scaled[10] ? 8'hff : scaled[9:2];
        end
    endfunction

    function [7:0] fn_contrast;

        input [7:0] ch;

        input [2:0] lvl;

        reg [9:0]   val;

        begin

            case (lvl)

                3'd0: begin // 1.00X Standard Baseline (100%): No Change

                    fn_contrast = ch;

                end

                3'd1: begin // 1.25X Medium Dynamic (+25%): 1.25*(ch-128)+128 = ch + (ch>>2) - 32

                    val = {2'b00, ch} + {4'b0000, ch[7:2]};

                    if (val < 10'd32)

                        fn_contrast = 8'd0;

                    else if (val > 10'd287)

                        fn_contrast = 8'd255;

                    else

                        fn_contrast = val[7:0] - 8'd32;

                end

                3'd2: begin // 1.50X High Dynamic (+50%): 1.5*(ch-128)+128 = ch + (ch>>1) - 64

                    val = {2'b00, ch} + {3'b000, ch[7:1]};

                    if (val < 10'd64)

                        fn_contrast = 8'd0;

                    else if (val > 10'd319)

                        fn_contrast = 8'd255;

                    else

                        fn_contrast = val[7:0] - 8'd64;

                end

                3'd3: begin // 2.00X Maximum Contrast (+100%): 2.0*(ch-128)+128 = 2*ch - 128

                    val = {1'b0, ch, 1'b0};

                    if (val < 10'd128)

                        fn_contrast = 8'd0;

                    else if (val > 10'd383)

                        fn_contrast = 8'd255;

                    else

                        fn_contrast = val[7:0] - 8'd128;

                end

                3'd4: begin // 0.75X Soft Low Dynamic (-25%): 0.75*(ch-128)+128 = (ch>>1) + (ch>>2) + 32

                    val = {3'b000, ch[7:1]} + {4'b0000, ch[7:2]} + 10'd32;

                    if (val > 10'd255)

                        fn_contrast = 8'd255;

                    else

                        fn_contrast = val[7:0];

                end

                default: begin

                    fn_contrast = ch;

                end

            endcase

        end

    endfunction




    // Factor brightness out of the ROM: four contrast curves x 256 bytes.
    // Three read ports require three 1024x8 copies, rather than 3x5120.
    (* ram_style = "block" *) reg [7:0] curve_r[0:1023],curve_g[0:1023],curve_b[0:1023];
    integer curve_index;
    initial begin
        for(curve_index=0;curve_index<1024;curve_index=curve_index+1)begin
            curve_r[curve_index]=fn_contrast(curve_index%256,1+curve_index/256);
            curve_g[curve_index]=fn_contrast(curve_index%256,1+curve_index/256);
            curve_b[curve_index]=fn_contrast(curve_index%256,1+curve_index/256);
        end
    end
    wire [7:0] red=fn_bright(rgb_in[23:16],brightness);
    wire [7:0] green=fn_bright(rgb_in[15:8],brightness);
    wire [7:0] blue=fn_bright(rgb_in[7:0],brightness);
    wire [1:0] curve=contrast[1:0]-2'd1;
    wire contrast_enabled=contrast>=1&&contrast<=4;
    reg [7:0] qr,qg,qb;
    reg [23:0] bright_q;
    reg contrast_q;
    // Keep the ROM read registers direct so TD maps true synchronous BRAM.
    always @(posedge clk)begin
        qr<=curve_r[{curve,red}];qg<=curve_g[{curve,green}];qb<=curve_b[{curve,blue}];
        bright_q<={red,green,blue};contrast_q<=contrast_enabled;
    end

    wire [7:0] cur_r = contrast_q ? qr : bright_q[23:16];
    wire [7:0] cur_g = contrast_q ? qg : bright_q[15:8];
    wire [7:0] cur_b = contrast_q ? qb : bright_q[7:0];

    // Direction 3: Color Balance & Channel Tone Gain Adjustment
    // 0: STANDARD (D65 6500K baseline: 100% natural unaltered color)
    // 1: WARM (5000K cinema: +12.5% R clamped to 255, -12.5% B)
    // 2: COOL (8500K tech: -12.5% R, +12.5% B clamped to 255)
    // 3: EYE-CARE (anti-blue: -25% B, +6.25% G clamped to 255)
    wire [8:0] r_warm_sum = {1'b0, cur_r} + {4'b0, cur_r[7:3]};
    wire [7:0] r_warm     = r_warm_sum[8] ? 8'hff : r_warm_sum[7:0];
    wire [7:0] r_cool     = cur_r - {3'b0, cur_r[7:3]};
    wire [7:0] tone_r     = (tone_mode == 2'd1) ? r_warm :
                            (tone_mode == 2'd2) ? r_cool : cur_r;

    wire [8:0] g_eye_sum  = {1'b0, cur_g} + {5'b0, cur_g[7:4]};
    wire [7:0] g_eye      = g_eye_sum[8] ? 8'hff : g_eye_sum[7:0];
    wire [7:0] tone_g     = (tone_mode == 2'd3) ? g_eye  : cur_g;

    wire [7:0] b_warm     = cur_b - {3'b0, cur_b[7:3]};
    wire [8:0] b_cool_sum = {1'b0, cur_b} + {4'b0, cur_b[7:3]};
    wire [7:0] b_cool     = b_cool_sum[8] ? 8'hff : b_cool_sum[7:0];
    wire [7:0] b_eye      = cur_b - {2'b0, cur_b[7:2]};
    wire [7:0] tone_b     = (tone_mode == 2'd1) ? b_warm :
                            (tone_mode == 2'd2) ? b_cool :
                            (tone_mode == 2'd3) ? b_eye  : cur_b;

    assign rgb_out = {tone_r, tone_g, tone_b};
endmodule
