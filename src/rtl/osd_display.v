// =====================================================================
// Module: osd_display
// Purpose: Complete On-Screen Display (OSD) Engine with:
//  1. Real-time Video Parameter Adjustment (Brightness, Contrast, Color)
//  2. Top Status Bar with Anlogic Logo, Mode, Img No, Timer, Audio, Res
//  3. Corner Real-time Parameter HUD (SW1-SW4, Brightness/Contrast/Color)
//  4. Smooth-Scrolling Commercial Marquee with Alpha Blending
//  5. 8-Band Dynamic Audio Spectrum Visualizer
//  6. Clean 2-stage Streaming Pipeline aligned to video_clk (25MHz)
//  7. Tear-free VBLANK parameter latching and robust pixel coordinates
// =====================================================================
`timescale 1ns / 1ps

`default_nettype none
module osd_display (
    input wire [6:0] marq_read_data,
    input wire marq_custom_valid,marq_hidden,marq_normal_reset,
    output wire [6:0] marq_read_addr,
    output wire marq_frame_pulse,
    input  wire        clk50,
    input  wire        video_clk,        // 25MHz pixel clock
    input  wire        rst,              // Global sync/async reset
    
    // Video stream in (from SDRAM / fade engine)
    input  wire        vs_in,
    input  wire        hs_in,
    input  wire        de_in,
    input  wire [23:0] rgb_in,
    
    // Controls & Status (all synchronized to video_clk)
    input  wire [3:0]  sw_in,            // SW1..SW4 physical DIP switches {SW4,SW3,SW2,SW1}
    input  wire [2:0]  contrast_lvl_in,  // Multi-level Contrast (0: 1.00X, 1: 1.25X, 2: 1.50X, 3: 2.00X, 4: 0.75X)
    input  wire        hud_en,           // Parameter & Telemetry HUD Enable (1: Show, 0: Hide)
    input  wire [1:0]  alpha_mode,       // 0: 25% Crystal, 1: 50% Frosted Glass, 2: 75% Dark Mask
    input  wire [1:0]  scale_mode,       // 0: 1.0X, 1: 2.0X, 2: 0.5X, 3: AUTO
    input  wire [1:0]  color_mode,       // 0: Vivid RGB, 1: Monochrome, 2: Sobel Edge
    input  wire [2:0]  trans_mode,       // 0: FADE, 1: BLND, 2: SLID, 3: MOSC, 4: AUTO
    input  wire [1:0]  trans_effect,     // Active transition effect (0: FADE, 1: BLND, 2: SLID, 3: MOSC)
    input  wire [15:0] bmp_width,        // BMP Width (640 or 320)
    input wire [9:0] scaled_width, scaled_height,
    input  wire [15:0] bmp_height,       // BMP Height (480 or 240)
    input  wire        auto_play_status, // 1: Auto, 0: Manual
    input  wire [2:0]  cur_img_idx,      // 0..4 (Image index)
    input  wire        display_valid,    // Image ready flag
    input  wire        load_fail_hold,   // Load fail flag
    input  wire        audio_valid,      // Audio active flag
    input  wire [23:0] audio_left,       // Audio PCM left sample
    input  wire        sdram_loading,    // SDRAM active write from TF ping-pong indicator
    input  wire        fade_active,      // Active transition indicator (1: switching/fading)
    input  wire [3:0]  img_total_count,  // Total images discovered on TF card
    input  wire [2:0]  vol_mode,         // 0: 100%, 1: 75%, 2: 50%, 3: 25%, 4: MUTE
    input  wire        emergency_mode,   // 1: Emergency warning & evacuation broadcast mode
    input  wire        scada_active,     // 1: SCADA bus online & telemetry active
    input  wire [3:0]  disp_state_code,  // 4-Stage State Display (1:IDLE, 2:SEEK, 3:RAM, 4:OSD)
    
    // Video stream out (fully aligned)
    output reg         vs_out,
    output reg         hs_out,
    output reg         de_out,
    output reg  [23:0] rgb_out,

    // Real-Time SDFT Multi-Screen Synergy Outputs (8 bands condensed from 16-band engine)
    output wire [39:0] sdft_spec_8b,
    output wire [39:0] sdft_peak_8b,

    // Direction 1 & 3: OSD Interactive Menu System & Color Balance
    input  wire        menu_active,      // 1: Menu mode active, 0: Normal HUD
    input  wire [2:0]  menu_cursor,      // Current menu item index (0..7)
    input  wire [1:0]  menu_bright,      // Menu controlled brightness (0..3)
    input  wire [1:0]  tone_mode         // Direction 3: Tone Mode (0: STD, 1: WARM, 2: COOL, 3: EYE)
);

    // -------------------------------------------------------------
    // 1. Switch & Key Input Synchronization (2-stage)
    // -------------------------------------------------------------
    reg [3:0] sw_s0, sw_s1;
    reg [2:0] key_c_s0, key_c_s1;
    reg       hud_s0, hud_s1;
    reg [1:0] scale_s0, scale_s1;
    reg [1:0] alpha_s0, alpha_s1;
    reg [1:0] color_mode_s0, color_mode_s1;
    reg [2:0] trans_s0, trans_s1;
    reg [1:0] trans_eff_s0, trans_eff_s1;
    reg       fade_active_s0, fade_active_s1;
    reg play_s0,play_s1;
    reg [2:0] vol_s0, vol_s1;
    reg       emerg_s0, emerg_s1;
    reg       scada_s0, scada_s1;
    wire      menu_active_s1 = menu_active;
    wire [2:0] menu_cursor_s1 = menu_cursor;
    wire [1:0] menu_bright_s1 = menu_bright;
    wire [1:0] tone_mode_s1   = tone_mode;
    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            sw_s0    <= 4'b0000;
            sw_s1    <= 4'b0000;
            key_c_s0 <= 3'd0;
            key_c_s1 <= 3'd0;
            hud_s0   <= 1'b0;
            hud_s1   <= 1'b0;
            scale_s0 <= 2'b00;
            scale_s1 <= 2'b00;
            alpha_s0 <= 2'd1;
            alpha_s1 <= 2'd1;
            color_mode_s0 <= 2'b00;
            color_mode_s1 <= 2'b00;
            play_s0<=1'b0;play_s1<=1'b0;
            trans_s0 <= 3'd4;
            trans_s1 <= 3'd4;
            trans_eff_s0 <= 2'd0;
            trans_eff_s1 <= 2'd0;
            fade_active_s0 <= 1'b0;
            fade_active_s1 <= 1'b0;
            vol_s0   <= 3'd0;
            vol_s1   <= 3'd0;
            emerg_s0 <= 1'b0;
            emerg_s1 <= 1'b0;
            scada_s0 <= 1'b0;
            scada_s1 <= 1'b0;
        end else begin
            sw_s0    <= sw_in;
            sw_s1    <= sw_s0;
            key_c_s0 <= contrast_lvl_in;
            key_c_s1 <= key_c_s0;
            hud_s0   <= hud_en;
            hud_s1   <= hud_s0;
            scale_s0 <= scale_mode;
            scale_s1 <= scale_s0;
            alpha_s0 <= alpha_mode;
            alpha_s1 <= alpha_s0;
            color_mode_s0 <= color_mode;
            color_mode_s1 <= color_mode_s0;
            play_s0<=auto_play_status;play_s1<=play_s0;
            trans_s0 <= trans_mode;
            trans_s1 <= trans_s0;
            trans_eff_s0 <= trans_effect;
            trans_eff_s1 <= trans_eff_s0;
            fade_active_s0 <= fade_active;
            fade_active_s1 <= fade_active_s0;
            vol_s0   <= vol_mode;
            vol_s1   <= vol_s0;
            emerg_s0 <= emergency_mode;
            emerg_s1 <= emerg_s0;
            scada_s0 <= scada_active;
            scada_s1 <= scada_s0;
        end
    end

    // SW & Menu Mapping:
    // sw_bright_lvl: Brightness (00: 100% normal, 01: 125% bright, 10: 75% dim, 11: 150% max)
    // key_c_s1:      Contrast Multi-Level (0: 1.00X, 1: 1.25X, 2: 1.50X, 3: 2.00X, 4: 0.75X)
    // hud_s1:        Parameter & Telemetry HUD Toggle
    // color_mode_s1: Color Mode (0: Vivid RGB, 1: Monochrome, 2: Sobel Edge, 3: 50/50 Split)
    wire [1:0] sw_bright_lvl = menu_bright_s1;
    wire [2:0] sw_contrast   = key_c_s1;
    wire       sw_hud_en     = hud_s1;

    // -------------------------------------------------------------
    // 2. Pixel Coordinate Tracking (640x480)
    //    Accurate: physical x in 0..639, physical y in 0..479
    // -------------------------------------------------------------
    reg [9:0] x_cnt;
    reg [9:0] y_cnt;
    reg       vs_in_d;
    reg       de_in_d;
    wire      frame_pulse = vs_in_d && !vs_in; // Start of vertical blanking

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            x_cnt   <= 10'd0;
            y_cnt   <= 10'd0;
            vs_in_d <= 1'b0;
            de_in_d <= 1'b0;
        end else begin
            vs_in_d <= vs_in;
            de_in_d <= de_in;
            
            if (frame_pulse) begin
                x_cnt <= 10'd0;
                y_cnt <= 10'd0;
            end else if (de_in) begin
                x_cnt <= x_cnt + 10'd1;
            end else begin
                x_cnt <= 10'd0;
                if (de_in_d) begin
                    y_cnt <= y_cnt + 10'd1;
                end
            end
        end
    end

    // -------------------------------------------------------------
    // 3. Tear-free VBLANK Parameter Latching
    //    Prevents mid-frame visual split when flipping switches
    // -------------------------------------------------------------
    reg [1:0] active_bright_lvl;
    reg [2:0] active_contrast;
    reg       active_hud_en;
    reg [1:0] active_alpha_mode;
    reg [1:0] active_color_mode;
    reg [1:0] active_scale_mode;
    reg [2:0] active_trans_mode;
    reg [2:0] active_vol_mode;
    reg       active_emergency;
    reg       active_scada;
    reg active_play,feedback_initialized;
    reg [6:0] feedback_frames;
    reg [2:0] feedback_kind;
    wire [7:0] parameter_changes={play_s1!=active_play,
        trans_s1!=active_trans_mode,alpha_s1!=active_alpha_mode,
        color_mode_s1!=active_color_mode,sw_contrast!=active_contrast,
        sw_bright_lvl!=active_bright_lvl,vol_s1!=active_vol_mode,
        scale_s1!=active_scale_mode};
    function [2:0] first_change;
        input [7:0] changes;
        begin
            if(changes[0])first_change=0;else if(changes[1])first_change=1;
            else if(changes[2])first_change=2;else if(changes[3])first_change=3;
            else if(changes[4])first_change=4;else if(changes[5])first_change=5;
            else if(changes[6])first_change=6;else first_change=7;
        end
    endfunction

    // 16-Frame Respiratory Fade Engine (0: Hidden, 16: Fully Visible, 1..15: Smooth Fade)
    reg [4:0] hud_fade_step;
    wire      target_hud_en = active_hud_en && !active_emergency;

    reg [1:0] active_tone_mode;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            active_bright_lvl <= 2'b00; // 100% normal default
            active_contrast   <= 3'd0;  // 1.0x normal
            active_tone_mode  <= 2'd0;  // 0: STANDARD (D65 6500K)
            active_hud_en     <= 1'b0;  // HUD hidden by default
            active_alpha_mode <= 2'd1;  // 50% Frosted Glass default
            active_color_mode <= 2'b00; // 0: Vivid RGB, 1: Mono, 2: Sobel
            active_scale_mode <= 2'b11; // 3: AUTO adaptive default
            active_trans_mode <= 3'd4; // 4: AUTO default
            active_vol_mode   <= 3'd0;  // 0: 100%
            active_emergency  <= 1'b0;
            active_scada      <= 1'b0;
            active_play<=0;feedback_initialized<=0;feedback_frames<=0;feedback_kind<=0;
            hud_fade_step     <= 5'd0;  // No startup HUD flash
        end else if (frame_pulse) begin
            active_bright_lvl <= sw_bright_lvl;
            active_contrast   <= sw_contrast;
            active_tone_mode  <= tone_mode_s1;
            active_hud_en     <= sw_hud_en;
            active_alpha_mode <= alpha_s1;
            active_color_mode <= color_mode_s1;
            active_scale_mode <= scale_s1;
            active_trans_mode <= trans_s1;
            active_vol_mode   <= vol_s1;
            active_emergency  <= emerg_s1;
            active_scada      <= scada_s1;
            active_play<=play_s1;feedback_initialized<=1;
            if(!feedback_initialized || sw_hud_en || emerg_s1 || active_emergency)
                feedback_frames<=0;
            else if(|parameter_changes)begin
                feedback_kind<=first_change(parameter_changes);feedback_frames<=120;
            end else if(feedback_frames!=0)feedback_frames<=feedback_frames-1'b1;

            // 16-frame respiratory stepping (267ms @ 60Hz)
            if (target_hud_en) begin
                if (hud_fade_step < 5'd16)
                    hud_fade_step <= hud_fade_step + 5'd1;
            end else begin
                if (hud_fade_step > 5'd0)
                    hud_fade_step <= hud_fade_step - 5'd1;
            end
        end
    end

    // -------------------------------------------------------------
    // 4. Video Adjustment (Handled by video_adjust_lut hardware)
    // -------------------------------------------------------------

    wire [23:0] adjusted_pixel;
    video_adjust_lut adjust_lut(video_clk,active_bright_lvl,active_contrast,active_tone_mode,rgb_in,adjusted_pixel);
    reg [23:0] passthrough_pixel;
    reg bypass_adjust;
    always @(posedge video_clk or posedge rst)begin
        if(rst)begin passthrough_pixel<=0;bypass_adjust<=1;end
        else begin passthrough_pixel<=rgb_in;bypass_adjust<=active_color_mode==2||active_color_mode==3;end
    end
    // -------------------------------------------------------------
    // 5. Real-Time Seconds Timer (MM:SS) - Video-Frame Synchronized (60Hz)
    // -------------------------------------------------------------
    reg [5:0]  frame_sec_cnt; // 0..59 (Exact 1 second @ 60Hz)
    reg [3:0]  sec_ones;
    reg [3:0]  sec_tens;
    reg [3:0]  min_ones;
    reg [3:0]  min_tens;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            frame_sec_cnt <= 6'd0;
            sec_ones      <= 4'd0;
            sec_tens      <= 4'd0;
            min_ones      <= 4'd0;
            min_tens      <= 4'd0;
        end else if (frame_pulse) begin
            if (frame_sec_cnt == 6'd59) begin
                frame_sec_cnt <= 6'd0;
                if (sec_ones == 4'd9) begin
                    sec_ones <= 4'd0;
                    if (sec_tens == 4'd5) begin
                        sec_tens <= 4'd0;
                        if (min_ones == 4'd9) begin
                            min_ones <= 4'd0;
                            if (min_tens == 4'd5)
                                min_tens <= 4'd0;
                            else
                                min_tens <= min_tens + 4'd1;
                        end else begin
                            min_ones <= min_ones + 4'd1;
                        end
                    end else begin
                        sec_tens <= sec_tens + 4'd1;
                    end
                end else begin
                    sec_ones <= sec_ones + 4'd1;
                end
            end else begin
                frame_sec_cnt <= frame_sec_cnt + 6'd1;
            end
        end
    end

    // -------------------------------------------------------------
    // 5a. Direction 3: Real-Time Single-Frame APL (Average Picture Level) Profiler
    // -------------------------------------------------------------
    // Subsamples 64 points uniformly across active display area:
    // When de_in and (x_cnt[5:0] == 6'd32) && (y_cnt[5:0] == 6'd32)
    // Fast SMPTE Luminance Y = 0.25R + 0.50G + 0.25B
    wire [7:0] pix_lum = {2'b0, rgb_in[23:18]} + {1'b0, rgb_in[15:9]} + {2'b0, rgb_in[7:2]};
    reg [5:0]  apl_sample_cnt;
    reg [13:0] apl_acc;
    reg [7:0]  frame_apl;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            apl_sample_cnt <= 6'd0;
            apl_acc        <= 14'd0;
            frame_apl      <= 8'h80; // Default 50% (0x80)
        end else if (frame_pulse) begin
            frame_apl      <= apl_acc[13:6]; // Fast divide by 64
            apl_acc        <= 14'd0;
            apl_sample_cnt <= 6'd0;
        end else if (de_in && (x_cnt[5:0] == 6'd32) && (y_cnt[5:0] == 6'd32)) begin
            if (apl_sample_cnt != 6'd63) begin
                apl_sample_cnt <= apl_sample_cnt + 6'd1;
                apl_acc        <= apl_acc + {6'd0, pix_lum};
            end
        end
    end

    // -------------------------------------------------------------
    // 5b. Smart Signage Dwell-Time Countdown & Progress Engine
    // -------------------------------------------------------------
    reg        fade_active_d;
    reg [5:0]  dwell_remain;    // 30 down to 0 (tenths of second: 3.0s down to 0.0s)
    reg [2:0]  dwell_frame_cnt; // counts 0..5 (6 frames = 0.1s at 60Hz)
    reg [9:0]  dwell_prog_x;    // 0..639 linear sweep progress across screen width
    reg [16:0] dwell_prog_cnt;  // 69,000,000 / 640 = 107,812 cycles/pixel

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            fade_active_d   <= 1'b0;
            dwell_remain    <= 6'd30; // 3.0s default
            dwell_frame_cnt <= 3'd0;
            dwell_prog_x    <= 10'd0;
            dwell_prog_cnt  <= 17'd0;
        end else begin
            fade_active_d <= fade_active;

            if (!auto_play_status || !display_valid) begin
                dwell_remain    <= 6'd30;
                dwell_frame_cnt <= 3'd0;
                dwell_prog_x    <= 10'd0;
                dwell_prog_cnt  <= 17'd0;
            end else if (fade_active) begin
                dwell_remain    <= 6'd0;
                dwell_frame_cnt <= 3'd0;
                dwell_prog_x    <= 10'd639;
                dwell_prog_cnt  <= 17'd0;
            end else if (fade_active_d && !fade_active) begin
                dwell_remain    <= 6'd30;
                dwell_frame_cnt <= 3'd0;
                dwell_prog_x    <= 10'd0;
                dwell_prog_cnt  <= 17'd0;
            end else begin
                if (frame_pulse) begin
                    if (dwell_frame_cnt >= 3'd5) begin
                        dwell_frame_cnt <= 3'd0;
                        if (dwell_remain > 6'd0)
                            dwell_remain <= dwell_remain - 6'd1;
                    end else begin
                        dwell_frame_cnt <= dwell_frame_cnt + 3'd1;
                    end
                end

                if (dwell_prog_cnt >= 17'd107_812) begin
                    dwell_prog_cnt <= 17'd0;
                    if (dwell_prog_x < 10'd639)
                        dwell_prog_x <= dwell_prog_x + 10'd1;
                end else begin
                    dwell_prog_cnt <= dwell_prog_cnt + 17'd1;
                end
            end
        end
    end

    wire [5:0] dwell_sub_20 = dwell_remain - 6'd20;
    wire [5:0] dwell_sub_10 = dwell_remain - 6'd10;
    wire [3:0] dwell_sec   = (dwell_remain >= 6'd30) ? 4'd3 : 
                             ((dwell_remain >= 6'd20) ? 4'd2 : 
                             ((dwell_remain >= 6'd10) ? 4'd1 : 4'd0));
    wire [3:0] dwell_tenth = (dwell_remain >= 6'd30) ? 4'd0 : 
                             ((dwell_remain >= 6'd20) ? dwell_sub_20[3:0] : 
                             ((dwell_remain >= 6'd10) ? dwell_sub_10[3:0] : dwell_remain[3:0]));


    // -------------------------------------------------------------
    // 5c. Emergency Mode Flashing Timers
    // -------------------------------------------------------------
    // 10Hz Red/Blue outer border flasher: 50ms toggle (3 frames @ 60Hz)
    reg [1:0]  emerg_border_fcnt;
    reg        emerg_border_phase; // 0: Red, 1: Blue
    // HUD & Top Bar emergency text / bg blinker (~3.75Hz, 8 frames @ 60Hz)
    reg [2:0]  emerg_hud_fcnt;
    reg        emerg_hud_phase;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            emerg_border_fcnt  <= 2'd0;
            emerg_border_phase <= 1'b0;
            emerg_hud_fcnt     <= 3'd0;
            emerg_hud_phase    <= 1'b0;
        end else if (frame_pulse) begin
            if (emerg_border_fcnt >= 2'd2) begin
                emerg_border_fcnt  <= 2'd0;
                emerg_border_phase <= ~emerg_border_phase;
            end else begin
                emerg_border_fcnt  <= emerg_border_fcnt + 2'd1;
            end

            if (emerg_hud_fcnt >= 3'd7) begin
                emerg_hud_fcnt  <= 3'd0;
                emerg_hud_phase <= ~emerg_hud_phase;
            end else begin
                emerg_hud_fcnt  <= emerg_hud_fcnt + 3'd1;
            end
        end
    end
    wire [23:0] emerg_border_color = emerg_border_phase ? 24'h0000FF : 24'hFF0000;

    // -------------------------------------------------------------
    // 5d. Highway Tunnel Emergency Evacuation Dynamic Optical Flow Arrow Engine
    //     (智能公路隧道应急逃生动态光流箭头诱导系统)
    // -------------------------------------------------------------
    reg [5:0] flow_phase; // 0..63 pixel wrapping phase
    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            flow_phase <= 6'd0;
        end else if (frame_pulse) begin
            // 2 pixels per frame @ 60Hz = 120 pixels/sec visual streaming velocity
            flow_phase <= flow_phase + 6'd2;
        end
    end

    // -------------------------------------------------------------
    // 6. Smooth Marquee Scrolling Engine (Continuous Loop)
    // -------------------------------------------------------------
    reg [9:0] scroll_pos; // 0..1023 (128 chars * 8 = 1024 px)
    reg       scroll_tick;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            scroll_pos  <= 10'd0;
            scroll_tick <= 1'b0;
        end else if (frame_pulse) begin
            scroll_tick <= ~scroll_tick;
            if (scroll_tick) begin
                scroll_pos <= scroll_pos + 10'd1;
            end
        end
    end

    // -------------------------------------------------------------
    reg [9:0] normal_scroll_pos;
    reg normal_scroll_tick,normal_entering;
    assign marq_frame_pulse=frame_pulse;
    always @(posedge video_clk or posedge rst) begin
        if(rst)begin normal_scroll_pos<=0;normal_scroll_tick<=0;normal_entering<=0;end
        else if(marq_normal_reset)begin
            normal_scroll_pos<=marq_custom_valid?10'd384:10'd0;
            normal_entering<=marq_custom_valid;normal_scroll_tick<=0;
        end else if(frame_pulse&&!marq_hidden&&!active_emergency)begin
            normal_scroll_tick<=!normal_scroll_tick;
            if(normal_scroll_tick)begin
                normal_scroll_pos<=normal_scroll_pos+1'b1;
                if(normal_scroll_pos==10'd1023)normal_entering<=0;
            end
        end
    end

    // 7a. Real-time Live Audio Oscilloscope Buffer (256 Samples) & Activity Detector
    // -------------------------------------------------------------
    `ifdef YOSYS
    reg [8:0] audio_history [0:255];
    `endif
    reg [7:0] wave_wr_ptr;
    reg [2:0] audio_active_frames;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            wave_wr_ptr         <= 8'd0;
            audio_active_frames <= 3'd0;
        end else begin
            if (audio_valid) begin
                wave_wr_ptr <= wave_wr_ptr + 8'd1;
                if (display_valid && (audio_left != 24'sd0)) begin
                    audio_active_frames <= 3'd6; // Hold for 6 frames (~100ms)
                end
            end
            if (frame_pulse && (audio_active_frames != 3'd0)) begin
                audio_active_frames <= audio_active_frames - 3'd1;
            end
        end
    end

    wire is_audio_playing = display_valid && (audio_active_frames != 3'd0);

    // 256-point, 16-frequency block DFT. Snapshot only complete windows.
    wire dft_valid,dft_overrun;
    wire [79:0] latest_heights;
    wire [8:0] wave_q;
    audio_spectrum_bridge #(.DISPLAY_ONLY(1)) spectrum(.video_clk(video_clk),.clk50(clk50),.rst(rst),.audio_valid(audio_valid),
      .display_valid(display_valid),.sample(audio_left[23:8]),.wave_read_address(wave_prefetch_idx),
      .wave_q(wave_q),.result_valid(dft_valid),.amplitudes(),.heights(latest_heights),.overrun(dft_overrun));

    reg [4:0] spec_bar_h[0:15],spec_bar_peak[0:15],spec_peak_hold[0:15];
    reg spec_decay_tick;
    integer bi;
    reg [4:0] target_height;
    always @(posedge video_clk or posedge rst) begin
      if(rst) begin spec_decay_tick<=0;
        for(bi=0;bi<16;bi=bi+1) begin spec_bar_h[bi]<=0;spec_bar_peak[bi]<=0;spec_peak_hold[bi]<=0;end
      end else begin

        if(frame_pulse) begin
          spec_decay_tick<=~spec_decay_tick;
          for(bi=0;bi<16;bi=bi+1) begin
            target_height=is_audio_playing ? latest_heights[bi*5+:5] : 5'd0;
            if(target_height>=spec_bar_h[bi]) spec_bar_h[bi]<=target_height;
            else spec_bar_h[bi]<=spec_bar_h[bi]-1'b1;
            if(target_height>=spec_bar_peak[bi] && target_height>0) begin spec_bar_peak[bi]<=target_height;spec_peak_hold[bi]<=14;end
            else if(spec_peak_hold[bi]!=0) spec_peak_hold[bi]<=spec_peak_hold[bi]-1'b1;
            else if(spec_decay_tick && spec_bar_peak[bi]!=0) spec_bar_peak[bi]<=spec_bar_peak[bi]-1'b1;
          end
        end
      end
    end

    // Multi-Screen Synergy: Condense 16-band SDFT spectrum to 8 frequency bands for telemetry/sub-display
    assign sdft_spec_8b[4:0]   = (spec_bar_h[0]  > spec_bar_h[1])  ? spec_bar_h[0]  : spec_bar_h[1];
    assign sdft_spec_8b[9:5]   = (spec_bar_h[2]  > spec_bar_h[3])  ? spec_bar_h[2]  : spec_bar_h[3];
    assign sdft_spec_8b[14:10] = (spec_bar_h[4]  > spec_bar_h[5])  ? spec_bar_h[4]  : spec_bar_h[5];
    assign sdft_spec_8b[19:15] = (spec_bar_h[6]  > spec_bar_h[7])  ? spec_bar_h[6]  : spec_bar_h[7];
    assign sdft_spec_8b[24:20] = (spec_bar_h[8]  > spec_bar_h[9])  ? spec_bar_h[8]  : spec_bar_h[9];
    assign sdft_spec_8b[29:25] = (spec_bar_h[10] > spec_bar_h[11]) ? spec_bar_h[10] : spec_bar_h[11];
    assign sdft_spec_8b[34:30] = (spec_bar_h[12] > spec_bar_h[13]) ? spec_bar_h[12] : spec_bar_h[13];
    assign sdft_spec_8b[39:35] = (spec_bar_h[14] > spec_bar_h[15]) ? spec_bar_h[14] : spec_bar_h[15];

    assign sdft_peak_8b[4:0]   = (spec_bar_peak[0]  > spec_bar_peak[1])  ? spec_bar_peak[0]  : spec_bar_peak[1];
    assign sdft_peak_8b[9:5]   = (spec_bar_peak[2]  > spec_bar_peak[3])  ? spec_bar_peak[2]  : spec_bar_peak[3];
    assign sdft_peak_8b[14:10] = (spec_bar_peak[4]  > spec_bar_peak[5])  ? spec_bar_peak[4]  : spec_bar_peak[5];
    assign sdft_peak_8b[19:15] = (spec_bar_peak[6]  > spec_bar_peak[7])  ? spec_bar_peak[6]  : spec_bar_peak[7];
    assign sdft_peak_8b[24:20] = (spec_bar_peak[8]  > spec_bar_peak[9])  ? spec_bar_peak[8]  : spec_bar_peak[9];
    assign sdft_peak_8b[29:25] = (spec_bar_peak[10] > spec_bar_peak[11]) ? spec_bar_peak[10] : spec_bar_peak[11];
    assign sdft_peak_8b[34:30] = (spec_bar_peak[12] > spec_bar_peak[13]) ? spec_bar_peak[12] : spec_bar_peak[13];
    assign sdft_peak_8b[39:35] = (spec_bar_peak[14] > spec_bar_peak[15]) ? spec_bar_peak[14] : spec_bar_peak[15];


    // -------------------------------------------------------------
    // 7c. Full Hardware Real-Time Telemetry Profilers
    // -------------------------------------------------------------
    // SDRAM Loading Synchronizer & Hold Stretcher (6 frames = 100ms at 60Hz)
    reg sdram_load_s0, sdram_load_s1;
    reg [2:0] load_hold_frames;
    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            sdram_load_s0    <= 1'b0;
            sdram_load_s1    <= 1'b0;
            load_hold_frames <= 3'd0;
        end else begin
            sdram_load_s0 <= sdram_loading;
            sdram_load_s1 <= sdram_load_s0;
            if (sdram_load_s1) begin
                load_hold_frames <= 3'd6; // Hold for 6 frames (100ms @ 60Hz)
            end else if (frame_pulse && (load_hold_frames > 3'd0)) begin
                load_hold_frames <= load_hold_frames - 3'd1;
            end
        end
    end
    wire is_sdram_loading = (load_hold_frames > 3'd0);

    // 6-digit Pure BCD Cumulative Frame Counter (Zero DSP, Zero Divider)
    reg [3:0] bcd_d0, bcd_d1, bcd_d2, bcd_d3, bcd_d4, bcd_d5;
    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            bcd_d0 <= 4'd0;
            bcd_d1 <= 4'd0;
            bcd_d2 <= 4'd0;
            bcd_d3 <= 4'd0;
            bcd_d4 <= 4'd0;
            bcd_d5 <= 4'd0;
        end else if (frame_pulse) begin
            if (bcd_d0 == 4'd9) begin
                bcd_d0 <= 4'd0;
                if (bcd_d1 == 4'd9) begin
                    bcd_d1 <= 4'd0;
                    if (bcd_d2 == 4'd9) begin
                        bcd_d2 <= 4'd0;
                        if (bcd_d3 == 4'd9) begin
                            bcd_d3 <= 4'd0;
                            if (bcd_d4 == 4'd9) begin
                                bcd_d4 <= 4'd0;
                                if (bcd_d5 == 4'd9)
                                    bcd_d5 <= 4'd0;
                                else
                                    bcd_d5 <= bcd_d5 + 4'd1;
                            end else begin
                                bcd_d4 <= bcd_d4 + 4'd1;
                            end
                        end else begin
                            bcd_d3 <= bcd_d3 + 4'd1;
                        end
                    end else begin
                        bcd_d2 <= bcd_d2 + 4'd1;
                    end
                end else begin
                    bcd_d1 <= bcd_d1 + 4'd1;
                end
            end else begin
                bcd_d0 <= bcd_d0 + 4'd1;
            end
        end
    end

    // Pipeline Latency Status (Dynamically calculated based on active line buffers)
    wire is_scaler_active = (active_scale_mode == 2'd1) || (active_scale_mode == 2'd2) || 
                            (active_scale_mode == 2'd3);
    wire is_sobel_active  = (active_color_mode == 2'd2);
    wire [1:0] latency_mode = {is_sobel_active, is_scaler_active};

    // -------------------------------------------------------------
    // 8. Anlogic Dual-Color Corporate Logo 16x16 ROM (Official Anlogic Identity)
    //    Split into 1-bit boolean maps to minimize LUT/MSlice logic complexity
    // -------------------------------------------------------------
    function fn_logo_is_red;
        input [3:0] y;
        input [3:0] x;
        reg [15:0] row;
        begin
            if (y[0]) begin
                fn_logo_is_red = 1'b0; // Red stripes only exist on even rows
            end else begin
                case (y[3:1])
                    3'd0: row = 16'b0000_0011_1111_1111; // Row 0
                    3'd1: row = 16'b0000_0001_1111_1110; // Row 2
                    3'd2: row = 16'b0000_0000_1111_1110; // Row 4
                    3'd3: row = 16'b0000_0000_1111_1100; // Row 6
                    3'd4: row = 16'b0000_0000_0111_1100; // Row 8
                    3'd5: row = 16'b0000_0000_0111_1000; // Row 10
                    3'd6: row = 16'b0000_0000_0011_1000; // Row 12
                    3'd7: row = 16'b0000_0000_0001_1000; // Row 14
                endcase
                fn_logo_is_red = row[4'd15 - x];
            end
        end
    endfunction

    function fn_logo_is_blue;
        input [3:0] y;
        input [3:0] x;
        reg [15:0] row;
        begin
            case (y)
                4'd0:        row = 16'b0000_0000_0000_0000;
                4'd1, 4'd2:  row = 16'b0000_1100_0000_0000;
                4'd3, 4'd4:  row = 16'b0001_1100_0000_0000;
                4'd5, 4'd6:  row = 16'b0001_1110_0000_0000;
                4'd7:        row = 16'b0011_1110_0000_0000;
                4'd8:        row = 16'b0011_0110_0000_0000;
                4'd9:        row = 16'b0011_0011_0000_0000;
                4'd10, 4'd11: row = 16'b0110_0011_0000_0000;
                4'd12:       row = 16'b0110_0001_1000_0000;
                4'd13:       row = 16'b1100_0001_1000_0000;
                4'd14, 4'd15: row = 16'b1111_1100_1100_0000;
                default:     row = 16'h0000;
            endcase
            fn_logo_is_blue = row[4'd15 - x];
        end
    endfunction

    // -------------------------------------------------------------
    // 9. Marquee Character ROM (128 Characters) - Pentatonic Audio & Cultural Heritage Edition
    // -------------------------------------------------------------
    function [6:0] fn_marquee_char;
        input [6:0] idx;
        begin
            case (idx)
                // "*** PENTATONIC AUDIO SPECTRUM: GONG-SHANG-JIAO-ZHI-YU * BRONZE CHIME PHYSICAL SYNTHESIS * DIGITAL RUBBINGS * ANLOGIC EG4S20 *** "
                7'd0: fn_marquee_char = 7'h2A; // '*'
                7'd1: fn_marquee_char = 7'h2A; // '*'
                7'd2: fn_marquee_char = 7'h2A; // '*'
                7'd3: fn_marquee_char = 7'h20; // ' '
                7'd4: fn_marquee_char = 7'h50; // 'P'
                7'd5: fn_marquee_char = 7'h45; // 'E'
                7'd6: fn_marquee_char = 7'h4E; // 'N'
                7'd7: fn_marquee_char = 7'h54; // 'T'
                7'd8: fn_marquee_char = 7'h41; // 'A'
                7'd9: fn_marquee_char = 7'h54; // 'T'
                7'd10: fn_marquee_char = 7'h4F; // 'O'
                7'd11: fn_marquee_char = 7'h4E; // 'N'
                7'd12: fn_marquee_char = 7'h49; // 'I'
                7'd13: fn_marquee_char = 7'h43; // 'C'
                7'd14: fn_marquee_char = 7'h20; // ' '
                7'd15: fn_marquee_char = 7'h41; // 'A'
                7'd16: fn_marquee_char = 7'h55; // 'U'
                7'd17: fn_marquee_char = 7'h44; // 'D'
                7'd18: fn_marquee_char = 7'h49; // 'I'
                7'd19: fn_marquee_char = 7'h4F; // 'O'
                7'd20: fn_marquee_char = 7'h20; // ' '
                7'd21: fn_marquee_char = 7'h53; // 'S'
                7'd22: fn_marquee_char = 7'h50; // 'P'
                7'd23: fn_marquee_char = 7'h45; // 'E'
                7'd24: fn_marquee_char = 7'h43; // 'C'
                7'd25: fn_marquee_char = 7'h54; // 'T'
                7'd26: fn_marquee_char = 7'h52; // 'R'
                7'd27: fn_marquee_char = 7'h55; // 'U'
                7'd28: fn_marquee_char = 7'h4D; // 'M'
                7'd29: fn_marquee_char = 7'h3A; // ':'
                7'd30: fn_marquee_char = 7'h20; // ' '
                // GONG-SHANG-JIAO-ZHI-YU (21 chars: 31..51)
                7'd31: fn_marquee_char = 7'h47; // 'G'
                7'd32: fn_marquee_char = 7'h4F; // 'O'
                7'd33: fn_marquee_char = 7'h4E; // 'N'
                7'd34: fn_marquee_char = 7'h47; // 'G'
                7'd35: fn_marquee_char = 7'h2D; // '-'
                7'd36: fn_marquee_char = 7'h53; // 'S'
                7'd37: fn_marquee_char = 7'h48; // 'H'
                7'd38: fn_marquee_char = 7'h41; // 'A'
                7'd39: fn_marquee_char = 7'h4E; // 'N'
                7'd40: fn_marquee_char = 7'h47; // 'G'
                7'd41: fn_marquee_char = 7'h2D; // '-'
                7'd42: fn_marquee_char = 7'h4A; // 'J'
                7'd43: fn_marquee_char = 7'h49; // 'I'
                7'd44: fn_marquee_char = 7'h41; // 'A'
                7'd45: fn_marquee_char = 7'h4F; // 'O'
                7'd46: fn_marquee_char = 7'h2D; // '-'
                7'd47: fn_marquee_char = 7'h5A; // 'Z'
                7'd48: fn_marquee_char = 7'h48; // 'H'
                7'd49: fn_marquee_char = 7'h49; // 'I'
                7'd50: fn_marquee_char = 7'h2D; // '-'
                7'd51: fn_marquee_char = 7'h59; // 'Y'
                7'd52: fn_marquee_char = 7'h55; // 'U'
                7'd53: fn_marquee_char = 7'h20; // ' '
                7'd54: fn_marquee_char = 7'h2A; // '*'
                7'd55: fn_marquee_char = 7'h20; // ' '
                // BRONZE CHIME PHYSICAL SYNTHESIS (31 chars: 56..86)
                7'd56: fn_marquee_char = 7'h42; // 'B'
                7'd57: fn_marquee_char = 7'h52; // 'R'
                7'd58: fn_marquee_char = 7'h4F; // 'O'
                7'd59: fn_marquee_char = 7'h4E; // 'N'
                7'd60: fn_marquee_char = 7'h5A; // 'Z'
                7'd61: fn_marquee_char = 7'h45; // 'E'
                7'd62: fn_marquee_char = 7'h20; // ' '
                7'd63: fn_marquee_char = 7'h43; // 'C'
                7'd64: fn_marquee_char = 7'h48; // 'H'
                7'd65: fn_marquee_char = 7'h49; // 'I'
                7'd66: fn_marquee_char = 7'h4D; // 'M'
                7'd67: fn_marquee_char = 7'h45; // 'E'
                7'd68: fn_marquee_char = 7'h20; // ' '
                7'd69: fn_marquee_char = 7'h50; // 'P'
                7'd70: fn_marquee_char = 7'h48; // 'H'
                7'd71: fn_marquee_char = 7'h59; // 'Y'
                7'd72: fn_marquee_char = 7'h53; // 'S'
                7'd73: fn_marquee_char = 7'h49; // 'I'
                7'd74: fn_marquee_char = 7'h43; // 'C'
                7'd75: fn_marquee_char = 7'h41; // 'A'
                7'd76: fn_marquee_char = 7'h4C; // 'L'
                7'd77: fn_marquee_char = 7'h20; // ' '
                7'd78: fn_marquee_char = 7'h53; // 'S'
                7'd79: fn_marquee_char = 7'h59; // 'Y'
                7'd80: fn_marquee_char = 7'h4E; // 'N'
                7'd81: fn_marquee_char = 7'h54; // 'T'
                7'd82: fn_marquee_char = 7'h48; // 'H'
                7'd83: fn_marquee_char = 7'h45; // 'E'
                7'd84: fn_marquee_char = 7'h53; // 'S'
                7'd85: fn_marquee_char = 7'h49; // 'I'
                7'd86: fn_marquee_char = 7'h53; // 'S'
                7'd87: fn_marquee_char = 7'h20; // ' '
                7'd88: fn_marquee_char = 7'h2A; // '*'
                7'd89: fn_marquee_char = 7'h20; // ' '
                // DIGITAL RUBBINGS (16 chars: 90..105)
                7'd90: fn_marquee_char = 7'h44; // 'D'
                7'd91: fn_marquee_char = 7'h49; // 'I'
                7'd92: fn_marquee_char = 7'h47; // 'G'
                7'd93: fn_marquee_char = 7'h49; // 'I'
                7'd94: fn_marquee_char = 7'h54; // 'T'
                7'd95: fn_marquee_char = 7'h41; // 'A'
                7'd96: fn_marquee_char = 7'h4C; // 'L'
                7'd97: fn_marquee_char = 7'h20; // ' '
                7'd98: fn_marquee_char = 7'h52; // 'R'
                7'd99: fn_marquee_char = 7'h55; // 'U'
                7'd100: fn_marquee_char = 7'h42; // 'B'
                7'd101: fn_marquee_char = 7'h42; // 'B'
                7'd102: fn_marquee_char = 7'h49; // 'I'
                7'd103: fn_marquee_char = 7'h4E; // 'N'
                7'd104: fn_marquee_char = 7'h47; // 'G'
                7'd105: fn_marquee_char = 7'h53; // 'S'
                7'd106: fn_marquee_char = 7'h20; // ' '
                7'd107: fn_marquee_char = 7'h2A; // '*'
                7'd108: fn_marquee_char = 7'h20; // ' '
                // ANLOGIC EG4S20 ***  (19 chars: 109..127)
                7'd109: fn_marquee_char = 7'h41; // 'A'
                7'd110: fn_marquee_char = 7'h4E; // 'N'
                7'd111: fn_marquee_char = 7'h4C; // 'L'
                7'd112: fn_marquee_char = 7'h4F; // 'O'
                7'd113: fn_marquee_char = 7'h47; // 'G'
                7'd114: fn_marquee_char = 7'h49; // 'I'
                7'd115: fn_marquee_char = 7'h43; // 'C'
                7'd116: fn_marquee_char = 7'h20; // ' '
                7'd117: fn_marquee_char = 7'h45; // 'E'
                7'd118: fn_marquee_char = 7'h47; // 'G'
                7'd119: fn_marquee_char = 7'h34; // '4'
                7'd120: fn_marquee_char = 7'h53; // 'S'
                7'd121: fn_marquee_char = 7'h32; // '2'
                7'd122: fn_marquee_char = 7'h30; // '0'
                7'd123: fn_marquee_char = 7'h20; // ' '
                7'd124: fn_marquee_char = 7'h2A; // '*'
                7'd125: fn_marquee_char = 7'h2A; // '*'
                7'd126: fn_marquee_char = 7'h2A; // '*'
                7'd127: fn_marquee_char = 7'h20; // ' '
                default: fn_marquee_char = 7'h20;
            endcase
        end
    endfunction

    // -------------------------------------------------------------
    // 9a. Pentatonic Scale Ribbon Character Lookup (GNG SHG JAO ZHI  YU*)
    // -------------------------------------------------------------
    function [6:0] fn_penta_scale_char;
        input [3:0] idx;
        begin
            case (idx)
                4'd0:  fn_penta_scale_char = 7'h47; // 'G'
                4'd1:  fn_penta_scale_char = 7'h4E; // 'N'
                4'd2:  fn_penta_scale_char = 7'h47; // 'G' (宫音)
                4'd3:  fn_penta_scale_char = 7'h53; // 'S'
                4'd4:  fn_penta_scale_char = 7'h48; // 'H'
                4'd5:  fn_penta_scale_char = 7'h47; // 'G' (商音)
                4'd6:  fn_penta_scale_char = 7'h4A; // 'J'
                4'd7:  fn_penta_scale_char = 7'h41; // 'A'
                4'd8:  fn_penta_scale_char = 7'h4F; // 'O' (角音)
                4'd9:  fn_penta_scale_char = 7'h5A; // 'Z'
                4'd10: fn_penta_scale_char = 7'h48; // 'H'
                4'd11: fn_penta_scale_char = 7'h49; // 'I' (徵音)
                4'd12: fn_penta_scale_char = 7'h20; // ' '
                4'd13: fn_penta_scale_char = 7'h59; // 'Y'
                4'd14: fn_penta_scale_char = 7'h55; // 'U' (羽音)
                default: fn_penta_scale_char = 7'h2A; // '*' (高阶泛音)
            endcase
        end
    endfunction

    // -------------------------------------------------------------
    // 9b. Bronze Chime Waveform Title Lookup (25 Characters)
    // -------------------------------------------------------------
    function [6:0] fn_wave_title_char;
        input [2:0] img_id;
        input [4:0] idx;
        begin
            case (img_id)
                3'd0: case (idx) // [GONG: DAKE-DING CHIME]  
                    5'd0: fn_wave_title_char = 7'h5B; // '['
                    5'd1: fn_wave_title_char = 7'h47; // 'G'
                    5'd2: fn_wave_title_char = 7'h4F; // 'O'
                    5'd3: fn_wave_title_char = 7'h4E; // 'N'
                    5'd4: fn_wave_title_char = 7'h47; // 'G'
                    5'd5: fn_wave_title_char = 7'h3A; // ':'
                    5'd6: fn_wave_title_char = 7'h20; // ' '
                    5'd7: fn_wave_title_char = 7'h44; // 'D'
                    5'd8: fn_wave_title_char = 7'h41; // 'A'
                    5'd9: fn_wave_title_char = 7'h4B; // 'K'
                    5'd10: fn_wave_title_char = 7'h45; // 'E'
                    5'd11: fn_wave_title_char = 7'h2D; // '-'
                    5'd12: fn_wave_title_char = 7'h44; // 'D'
                    5'd13: fn_wave_title_char = 7'h49; // 'I'
                    5'd14: fn_wave_title_char = 7'h4E; // 'N'
                    5'd15: fn_wave_title_char = 7'h47; // 'G'
                    5'd16: fn_wave_title_char = 7'h20; // ' '
                    5'd17: fn_wave_title_char = 7'h43; // 'C'
                    5'd18: fn_wave_title_char = 7'h48; // 'H'
                    5'd19: fn_wave_title_char = 7'h49; // 'I'
                    5'd20: fn_wave_title_char = 7'h4D; // 'M'
                    5'd21: fn_wave_title_char = 7'h45; // 'E'
                    5'd22: fn_wave_title_char = 7'h5D; // ']'
                    default: fn_wave_title_char = 7'h20;
                endcase
                3'd1: case (idx) // [SHANG: CAO-QUAN CHIME] 
                    5'd0: fn_wave_title_char = 7'h5B; // '['
                    5'd1: fn_wave_title_char = 7'h53; // 'S'
                    5'd2: fn_wave_title_char = 7'h48; // 'H'
                    5'd3: fn_wave_title_char = 7'h41; // 'A'
                    5'd4: fn_wave_title_char = 7'h4E; // 'N'
                    5'd5: fn_wave_title_char = 7'h47; // 'G'
                    5'd6: fn_wave_title_char = 7'h3A; // ':'
                    5'd7: fn_wave_title_char = 7'h20; // ' '
                    5'd8: fn_wave_title_char = 7'h43; // 'C'
                    5'd9: fn_wave_title_char = 7'h41; // 'A'
                    5'd10: fn_wave_title_char = 7'h4F; // 'O'
                    5'd11: fn_wave_title_char = 7'h2D; // '-'
                    5'd12: fn_wave_title_char = 7'h51; // 'Q'
                    5'd13: fn_wave_title_char = 7'h55; // 'U'
                    5'd14: fn_wave_title_char = 7'h41; // 'A'
                    5'd15: fn_wave_title_char = 7'h4E; // 'N'
                    5'd16: fn_wave_title_char = 7'h20; // ' '
                    5'd17: fn_wave_title_char = 7'h43; // 'C'
                    5'd18: fn_wave_title_char = 7'h48; // 'H'
                    5'd19: fn_wave_title_char = 7'h49; // 'I'
                    5'd20: fn_wave_title_char = 7'h4D; // 'M'
                    5'd21: fn_wave_title_char = 7'h45; // 'E'
                    5'd22: fn_wave_title_char = 7'h5D; // ']'
                    default: fn_wave_title_char = 7'h20;
                endcase
                3'd2: case (idx) // [JIAO: JIA-GU-WEN CHIME]
                    5'd0: fn_wave_title_char = 7'h5B; // '['
                    5'd1: fn_wave_title_char = 7'h4A; // 'J'
                    5'd2: fn_wave_title_char = 7'h49; // 'I'
                    5'd3: fn_wave_title_char = 7'h41; // 'A'
                    5'd4: fn_wave_title_char = 7'h4F; // 'O'
                    5'd5: fn_wave_title_char = 7'h3A; // ':'
                    5'd6: fn_wave_title_char = 7'h20; // ' '
                    5'd7: fn_wave_title_char = 7'h4A; // 'J'
                    5'd8: fn_wave_title_char = 7'h49; // 'I'
                    5'd9: fn_wave_title_char = 7'h41; // 'A'
                    5'd10: fn_wave_title_char = 7'h2D; // '-'
                    5'd11: fn_wave_title_char = 7'h47; // 'G'
                    5'd12: fn_wave_title_char = 7'h55; // 'U'
                    5'd13: fn_wave_title_char = 7'h2D; // '-'
                    5'd14: fn_wave_title_char = 7'h57; // 'W'
                    5'd15: fn_wave_title_char = 7'h45; // 'E'
                    5'd16: fn_wave_title_char = 7'h4E; // 'N'
                    5'd17: fn_wave_title_char = 7'h20; // ' '
                    5'd18: fn_wave_title_char = 7'h43; // 'C'
                    5'd19: fn_wave_title_char = 7'h48; // 'H'
                    5'd20: fn_wave_title_char = 7'h49; // 'I'
                    5'd21: fn_wave_title_char = 7'h4D; // 'M'
                    5'd22: fn_wave_title_char = 7'h45; // 'E'
                    5'd23: fn_wave_title_char = 7'h5D; // ']'
                    default: fn_wave_title_char = 7'h20;
                endcase
                3'd3: case (idx) // [ZHI: CHANG-LE CHIME]   
                    5'd0: fn_wave_title_char = 7'h5B; // '['
                    5'd1: fn_wave_title_char = 7'h5A; // 'Z'
                    5'd2: fn_wave_title_char = 7'h48; // 'H'
                    5'd3: fn_wave_title_char = 7'h49; // 'I'
                    5'd4: fn_wave_title_char = 7'h3A; // ':'
                    5'd5: fn_wave_title_char = 7'h20; // ' '
                    5'd6: fn_wave_title_char = 7'h43; // 'C'
                    5'd7: fn_wave_title_char = 7'h48; // 'H'
                    5'd8: fn_wave_title_char = 7'h41; // 'A'
                    5'd9: fn_wave_title_char = 7'h4E; // 'N'
                    5'd10: fn_wave_title_char = 7'h47; // 'G'
                    5'd11: fn_wave_title_char = 7'h2D; // '-'
                    5'd12: fn_wave_title_char = 7'h4C; // 'L'
                    5'd13: fn_wave_title_char = 7'h45; // 'E'
                    5'd14: fn_wave_title_char = 7'h20; // ' '
                    5'd15: fn_wave_title_char = 7'h43; // 'C'
                    5'd16: fn_wave_title_char = 7'h48; // 'H'
                    5'd17: fn_wave_title_char = 7'h49; // 'I'
                    5'd18: fn_wave_title_char = 7'h4D; // 'M'
                    5'd19: fn_wave_title_char = 7'h45; // 'E'
                    5'd20: fn_wave_title_char = 7'h5D; // ']'
                    default: fn_wave_title_char = 7'h20;
                endcase
                3'd4: case (idx) // [YU: ZENG-HOU-YI CHIME]
                    5'd0:  fn_wave_title_char = 7'h5B; // '['
                    5'd1:  fn_wave_title_char = 7'h59; // 'Y'
                    5'd2:  fn_wave_title_char = 7'h55; // 'U'
                    5'd3:  fn_wave_title_char = 7'h3A; // ':'
                    5'd4:  fn_wave_title_char = 7'h20; // ' '
                    5'd5:  fn_wave_title_char = 7'h5A; // 'Z'
                    5'd6:  fn_wave_title_char = 7'h45; // 'E'
                    5'd7:  fn_wave_title_char = 7'h4E; // 'N'
                    5'd8:  fn_wave_title_char = 7'h47; // 'G'
                    5'd9:  fn_wave_title_char = 7'h2D; // '-'
                    5'd10: fn_wave_title_char = 7'h48; // 'H'
                    5'd11: fn_wave_title_char = 7'h4F; // 'O'
                    5'd12: fn_wave_title_char = 7'h55; // 'U'
                    5'd13: fn_wave_title_char = 7'h2D; // '-'
                    5'd14: fn_wave_title_char = 7'h59; // 'Y'
                    5'd15: fn_wave_title_char = 7'h49; // 'I'
                    5'd16: fn_wave_title_char = 7'h20; // ' '
                    5'd17: fn_wave_title_char = 7'h43; // 'C'
                    5'd18: fn_wave_title_char = 7'h48; // 'H'
                    5'd19: fn_wave_title_char = 7'h49; // 'I'
                    5'd20: fn_wave_title_char = 7'h4D; // 'M'
                    5'd21: fn_wave_title_char = 7'h45; // 'E'
                    5'd22: fn_wave_title_char = 7'h5D; // ']'
                    default: fn_wave_title_char = 7'h20;
                endcase
                default: case (idx)
                    default: fn_wave_title_char = 7'h20;
                endcase
            endcase
        end
    endfunction


    // -------------------------------------------------------------
    // 9b. Emergency Mode Marquee & Pop-up Character Lookup Tables
    // -------------------------------------------------------------
    // *** EMERGENCY ALERT: FIRE DETECTED - FOLLOW EXIT SIGNS TO SAFETY - 紧急避险安全疏散 ***
    function [6:0] fn_marquee_emerg_char;
        input [6:0] idx;
        begin
            case (idx)
                7'd0: fn_marquee_emerg_char = 7'h20; // ' '
                7'd1: fn_marquee_emerg_char = 7'h2A; // '*'
                7'd2: fn_marquee_emerg_char = 7'h2A; // '*'
                7'd3: fn_marquee_emerg_char = 7'h2A; // '*'
                7'd4: fn_marquee_emerg_char = 7'h20; // ' '
                // EMERGENCY ALERT:  (17 chars: 5..21)
                7'd5: fn_marquee_emerg_char = 7'h45; // 'E'
                7'd6: fn_marquee_emerg_char = 7'h4D; // 'M'
                7'd7: fn_marquee_emerg_char = 7'h45; // 'E'
                7'd8: fn_marquee_emerg_char = 7'h52; // 'R'
                7'd9: fn_marquee_emerg_char = 7'h47; // 'G'
                7'd10: fn_marquee_emerg_char = 7'h45; // 'E'
                7'd11: fn_marquee_emerg_char = 7'h4E; // 'N'
                7'd12: fn_marquee_emerg_char = 7'h43; // 'C'
                7'd13: fn_marquee_emerg_char = 7'h59; // 'Y'
                7'd14: fn_marquee_emerg_char = 7'h20; // ' '
                7'd15: fn_marquee_emerg_char = 7'h41; // 'A'
                7'd16: fn_marquee_emerg_char = 7'h4C; // 'L'
                7'd17: fn_marquee_emerg_char = 7'h45; // 'E'
                7'd18: fn_marquee_emerg_char = 7'h52; // 'R'
                7'd19: fn_marquee_emerg_char = 7'h54; // 'T'
                7'd20: fn_marquee_emerg_char = 7'h3A; // ':'
                7'd21: fn_marquee_emerg_char = 7'h20; // ' '
                // FIRE DETECTED -  (16 chars: 22..37)
                7'd22: fn_marquee_emerg_char = 7'h46; // 'F'
                7'd23: fn_marquee_emerg_char = 7'h49; // 'I'
                7'd24: fn_marquee_emerg_char = 7'h52; // 'R'
                7'd25: fn_marquee_emerg_char = 7'h45; // 'E'
                7'd26: fn_marquee_emerg_char = 7'h20; // ' '
                7'd27: fn_marquee_emerg_char = 7'h44; // 'D'
                7'd28: fn_marquee_emerg_char = 7'h45; // 'E'
                7'd29: fn_marquee_emerg_char = 7'h54; // 'T'
                7'd30: fn_marquee_emerg_char = 7'h45; // 'E'
                7'd31: fn_marquee_emerg_char = 7'h43; // 'C'
                7'd32: fn_marquee_emerg_char = 7'h54; // 'T'
                7'd33: fn_marquee_emerg_char = 7'h45; // 'E'
                7'd34: fn_marquee_emerg_char = 7'h44; // 'D'
                7'd35: fn_marquee_emerg_char = 7'h20; // ' '
                7'd36: fn_marquee_emerg_char = 7'h2D; // '-'
                7'd37: fn_marquee_emerg_char = 7'h20; // ' '
                // FOLLOW EXIT SIGNS TO SAFETY -  (30 chars: 38..67)
                7'd38: fn_marquee_emerg_char = 7'h46; // 'F'
                7'd39: fn_marquee_emerg_char = 7'h4F; // 'O'
                7'd40: fn_marquee_emerg_char = 7'h4C; // 'L'
                7'd41: fn_marquee_emerg_char = 7'h4C; // 'L'
                7'd42: fn_marquee_emerg_char = 7'h4F; // 'O'
                7'd43: fn_marquee_emerg_char = 7'h57; // 'W'
                7'd44: fn_marquee_emerg_char = 7'h20; // ' '
                7'd45: fn_marquee_emerg_char = 7'h45; // 'E'
                7'd46: fn_marquee_emerg_char = 7'h58; // 'X'
                7'd47: fn_marquee_emerg_char = 7'h49; // 'I'
                7'd48: fn_marquee_emerg_char = 7'h54; // 'T'
                7'd49: fn_marquee_emerg_char = 7'h20; // ' '
                7'd50: fn_marquee_emerg_char = 7'h53; // 'S'
                7'd51: fn_marquee_emerg_char = 7'h49; // 'I'
                7'd52: fn_marquee_emerg_char = 7'h47; // 'G'
                7'd53: fn_marquee_emerg_char = 7'h4E; // 'N'
                7'd54: fn_marquee_emerg_char = 7'h53; // 'S'
                7'd55: fn_marquee_emerg_char = 7'h20; // ' '
                7'd56: fn_marquee_emerg_char = 7'h54; // 'T'
                7'd57: fn_marquee_emerg_char = 7'h4F; // 'O'
                7'd58: fn_marquee_emerg_char = 7'h20; // ' '
                7'd59: fn_marquee_emerg_char = 7'h53; // 'S'
                7'd60: fn_marquee_emerg_char = 7'h41; // 'A'
                7'd61: fn_marquee_emerg_char = 7'h46; // 'F'
                7'd62: fn_marquee_emerg_char = 7'h45; // 'E'
                7'd63: fn_marquee_emerg_char = 7'h54; // 'T'
                7'd64: fn_marquee_emerg_char = 7'h59; // 'Y'
                7'd65: fn_marquee_emerg_char = 7'h20; // ' '
                7'd66: fn_marquee_emerg_char = 7'h2D; // '-'
                7'd67: fn_marquee_emerg_char = 7'h20; // ' '
                // 紧急避险安全疏散 (16 half-chars: 68..83)
                7'd68: fn_marquee_emerg_char = 7'h01; // 紧_L
                7'd69: fn_marquee_emerg_char = 7'h02; // 紧_R
                7'd70: fn_marquee_emerg_char = 7'h03; // 急_L
                7'd71: fn_marquee_emerg_char = 7'h04; // 急_R
                7'd72: fn_marquee_emerg_char = 7'h05; // 避_L
                7'd73: fn_marquee_emerg_char = 7'h06; // 避_R
                7'd74: fn_marquee_emerg_char = 7'h07; // 险_L
                7'd75: fn_marquee_emerg_char = 7'h08; // 险_R
                7'd76: fn_marquee_emerg_char = 7'h09; // 安_L
                7'd77: fn_marquee_emerg_char = 7'h0A; // 安_R
                7'd78: fn_marquee_emerg_char = 7'h0B; // 全_L
                7'd79: fn_marquee_emerg_char = 7'h0C; // 全_R
                7'd80: fn_marquee_emerg_char = 7'h0D; // 疏_L
                7'd81: fn_marquee_emerg_char = 7'h0E; // 疏_R
                7'd82: fn_marquee_emerg_char = 7'h0F; // 散_L
                7'd83: fn_marquee_emerg_char = 7'h10; // 散_R
                7'd84: fn_marquee_emerg_char = 7'h20; // ' '
                7'd85: fn_marquee_emerg_char = 7'h2A; // '*'
                7'd86: fn_marquee_emerg_char = 7'h2A; // '*'
                7'd87: fn_marquee_emerg_char = 7'h2A; // '*'
                default: fn_marquee_emerg_char = 7'h20; // ' '
            endcase
        end
    endfunction

    // 屏幕中央避险公告牌 Line 0: ! EMERGENCY BROADCAST ! (23 chars)
    function [6:0] fn_popup_l0_char;
        input [4:0] col;
        begin
            case (col)
                5'd0: fn_popup_l0_char = 7'h21; // '!'
                5'd1: fn_popup_l0_char = 7'h20; // ' '
                5'd2: fn_popup_l0_char = 7'h45; // 'E'
                5'd3: fn_popup_l0_char = 7'h4D; // 'M'
                5'd4: fn_popup_l0_char = 7'h45; // 'E'
                5'd5: fn_popup_l0_char = 7'h52; // 'R'
                5'd6: fn_popup_l0_char = 7'h47; // 'G'
                5'd7: fn_popup_l0_char = 7'h45; // 'E'
                5'd8: fn_popup_l0_char = 7'h4E; // 'N'
                5'd9: fn_popup_l0_char = 7'h43; // 'C'
                5'd10: fn_popup_l0_char = 7'h59; // 'Y'
                5'd11: fn_popup_l0_char = 7'h20; // ' '
                5'd12: fn_popup_l0_char = 7'h42; // 'B'
                5'd13: fn_popup_l0_char = 7'h52; // 'R'
                5'd14: fn_popup_l0_char = 7'h4F; // 'O'
                5'd15: fn_popup_l0_char = 7'h41; // 'A'
                5'd16: fn_popup_l0_char = 7'h44; // 'D'
                5'd17: fn_popup_l0_char = 7'h43; // 'C'
                5'd18: fn_popup_l0_char = 7'h41; // 'A'
                5'd19: fn_popup_l0_char = 7'h53; // 'S'
                5'd20: fn_popup_l0_char = 7'h54; // 'T'
                5'd21: fn_popup_l0_char = 7'h20; // ' '
                5'd22: fn_popup_l0_char = 7'h21; // '!'
                default: fn_popup_l0_char = 7'h20;
            endcase
        end
    endfunction

    // 屏幕中央避险公告牌 Line 1: FIRE DETECTED - EVACUATE (24 chars)
    function [6:0] fn_popup_l1_char;
        input [4:0] col;
        begin
            case (col)
                5'd0: fn_popup_l1_char = 7'h46; // 'F'
                5'd1: fn_popup_l1_char = 7'h49; // 'I'
                5'd2: fn_popup_l1_char = 7'h52; // 'R'
                5'd3: fn_popup_l1_char = 7'h45; // 'E'
                5'd4: fn_popup_l1_char = 7'h20; // ' '
                5'd5: fn_popup_l1_char = 7'h44; // 'D'
                5'd6: fn_popup_l1_char = 7'h45; // 'E'
                5'd7: fn_popup_l1_char = 7'h54; // 'T'
                5'd8: fn_popup_l1_char = 7'h45; // 'E'
                5'd9: fn_popup_l1_char = 7'h43; // 'C'
                5'd10: fn_popup_l1_char = 7'h54; // 'T'
                5'd11: fn_popup_l1_char = 7'h45; // 'E'
                5'd12: fn_popup_l1_char = 7'h44; // 'D'
                5'd13: fn_popup_l1_char = 7'h20; // ' '
                5'd14: fn_popup_l1_char = 7'h2D; // '-'
                5'd15: fn_popup_l1_char = 7'h20; // ' '
                5'd16: fn_popup_l1_char = 7'h45; // 'E'
                5'd17: fn_popup_l1_char = 7'h56; // 'V'
                5'd18: fn_popup_l1_char = 7'h41; // 'A'
                5'd19: fn_popup_l1_char = 7'h43; // 'C'
                5'd20: fn_popup_l1_char = 7'h55; // 'U'
                5'd21: fn_popup_l1_char = 7'h41; // 'A'
                5'd22: fn_popup_l1_char = 7'h54; // 'T'
                5'd23: fn_popup_l1_char = 7'h45; // 'E'
                default: fn_popup_l1_char = 7'h20;
            endcase
        end
    endfunction

    // 屏幕中央避险公告牌 Line 2: FOLLOW EXIT SIGNS TO SAFETY (27 chars)
    function [6:0] fn_popup_l2_char;
        input [4:0] col;
        begin
            case (col)
                5'd0: fn_popup_l2_char = 7'h46; // 'F'
                5'd1: fn_popup_l2_char = 7'h4F; // 'O'
                5'd2: fn_popup_l2_char = 7'h4C; // 'L'
                5'd3: fn_popup_l2_char = 7'h4C; // 'L'
                5'd4: fn_popup_l2_char = 7'h4F; // 'O'
                5'd5: fn_popup_l2_char = 7'h57; // 'W'
                5'd6: fn_popup_l2_char = 7'h20; // ' '
                5'd7: fn_popup_l2_char = 7'h45; // 'E'
                5'd8: fn_popup_l2_char = 7'h58; // 'X'
                5'd9: fn_popup_l2_char = 7'h49; // 'I'
                5'd10: fn_popup_l2_char = 7'h54; // 'T'
                5'd11: fn_popup_l2_char = 7'h20; // ' '
                5'd12: fn_popup_l2_char = 7'h53; // 'S'
                5'd13: fn_popup_l2_char = 7'h49; // 'I'
                5'd14: fn_popup_l2_char = 7'h47; // 'G'
                5'd15: fn_popup_l2_char = 7'h4E; // 'N'
                5'd16: fn_popup_l2_char = 7'h53; // 'S'
                5'd17: fn_popup_l2_char = 7'h20; // ' '
                5'd18: fn_popup_l2_char = 7'h54; // 'T'
                5'd19: fn_popup_l2_char = 7'h4F; // 'O'
                5'd20: fn_popup_l2_char = 7'h20; // ' '
                5'd21: fn_popup_l2_char = 7'h53; // 'S'
                5'd22: fn_popup_l2_char = 7'h41; // 'A'
                5'd23: fn_popup_l2_char = 7'h46; // 'F'
                5'd24: fn_popup_l2_char = 7'h45; // 'E'
                5'd25: fn_popup_l2_char = 7'h54; // 'T'
                5'd26: fn_popup_l2_char = 7'h59; // 'Y'
                default: fn_popup_l2_char = 7'h20;
            endcase
        end
    endfunction

    // 屏幕中央避险公告牌 Line 3: *** 紧急避险 - 安全疏散 *** (27 chars)
    function [6:0] fn_popup_l3_char;
        input [4:0] col;
        begin
            case (col)
                5'd0: fn_popup_l3_char = 7'h2A; // '*'
                5'd1: fn_popup_l3_char = 7'h2A; // '*'
                5'd2: fn_popup_l3_char = 7'h2A; // '*'
                5'd3: fn_popup_l3_char = 7'h20; // ' '
                5'd4: fn_popup_l3_char = 7'h01; // 紧_L
                5'd5: fn_popup_l3_char = 7'h02; // 紧_R
                5'd6: fn_popup_l3_char = 7'h03; // 急_L
                5'd7: fn_popup_l3_char = 7'h04; // 急_R
                5'd8: fn_popup_l3_char = 7'h05; // 避_L
                5'd9: fn_popup_l3_char = 7'h06; // 避_R
                5'd10: fn_popup_l3_char = 7'h07; // 险_L
                5'd11: fn_popup_l3_char = 7'h08; // 险_R
                5'd12: fn_popup_l3_char = 7'h20; // ' '
                5'd13: fn_popup_l3_char = 7'h2D; // '-'
                5'd14: fn_popup_l3_char = 7'h20; // ' '
                5'd15: fn_popup_l3_char = 7'h09; // 安_L
                5'd16: fn_popup_l3_char = 7'h0A; // 安_R
                5'd17: fn_popup_l3_char = 7'h0B; // 全_L
                5'd18: fn_popup_l3_char = 7'h0C; // 全_R
                5'd19: fn_popup_l3_char = 7'h0D; // 疏_L
                5'd20: fn_popup_l3_char = 7'h0E; // 疏_R
                5'd21: fn_popup_l3_char = 7'h0F; // 散_L
                5'd22: fn_popup_l3_char = 7'h10; // 散_R
                5'd23: fn_popup_l3_char = 7'h20; // ' '
                5'd24: fn_popup_l3_char = 7'h2A; // '*'
                5'd25: fn_popup_l3_char = 7'h2A; // '*'
                5'd26: fn_popup_l3_char = 7'h2A; // '*'
                default: fn_popup_l3_char = 7'h20;
            endcase
        end
    endfunction

    // 顶部 HUD 状态显示:   ! EMERGENCY !    (18 chars)
    function [6:0] fn_top_emerg_char;
        input [4:0] col;
        begin
            case (col)
                5'd0: fn_top_emerg_char = 7'h20; // ' '
                5'd1: fn_top_emerg_char = 7'h20; // ' '
                5'd2: fn_top_emerg_char = 7'h21; // '!'
                5'd3: fn_top_emerg_char = 7'h20; // ' '
                5'd4: fn_top_emerg_char = 7'h45; // 'E'
                5'd5: fn_top_emerg_char = 7'h4D; // 'M'
                5'd6: fn_top_emerg_char = 7'h45; // 'E'
                5'd7: fn_top_emerg_char = 7'h52; // 'R'
                5'd8: fn_top_emerg_char = 7'h47; // 'G'
                5'd9: fn_top_emerg_char = 7'h45; // 'E'
                5'd10: fn_top_emerg_char = 7'h4E; // 'N'
                5'd11: fn_top_emerg_char = 7'h43; // 'C'
                5'd12: fn_top_emerg_char = 7'h59; // 'Y'
                5'd13: fn_top_emerg_char = 7'h20; // ' '
                5'd14: fn_top_emerg_char = 7'h21; // '!'
                5'd15: fn_top_emerg_char = 7'h20; // ' '
                5'd16: fn_top_emerg_char = 7'h20; // ' '
                default: fn_top_emerg_char = 7'h20;
            endcase
        end
    endfunction

    // -------------------------------------------------------------
    // 9c. Highway Emergency Wayfinding Sign Lookup:
    //     >>> 安全疏散  EXIT 150M > (25 chars)
    // -------------------------------------------------------------
    function [6:0] fn_flow_sign_char;
        input [4:0] col;
        begin
            case (col)
                5'd0:  fn_flow_sign_char = 7'h3E; // '>'
                5'd1:  fn_flow_sign_char = 7'h3E; // '>'
                5'd2:  fn_flow_sign_char = 7'h3E; // '>'
                5'd3:  fn_flow_sign_char = 7'h20; // ' '
                5'd4:  fn_flow_sign_char = 7'h09; // 安_L
                5'd5:  fn_flow_sign_char = 7'h0A; // 安_R
                5'd6:  fn_flow_sign_char = 7'h0B; // 全_L
                5'd7:  fn_flow_sign_char = 7'h0C; // 全_R
                5'd8:  fn_flow_sign_char = 7'h0D; // 疏_L
                5'd9:  fn_flow_sign_char = 7'h0E; // 疏_R
                5'd10: fn_flow_sign_char = 7'h0F; // 散_L
                5'd11: fn_flow_sign_char = 7'h10; // 散_R
                5'd12: fn_flow_sign_char = 7'h20; // ' '
                5'd13: fn_flow_sign_char = 7'h20; // ' '
                5'd14: fn_flow_sign_char = 7'h45; // 'E'
                5'd15: fn_flow_sign_char = 7'h58; // 'X'
                5'd16: fn_flow_sign_char = 7'h49; // 'I'
                5'd17: fn_flow_sign_char = 7'h54; // 'T'
                5'd18: fn_flow_sign_char = 7'h20; // ' '
                5'd19: fn_flow_sign_char = 7'h31; // '1'
                5'd20: fn_flow_sign_char = 7'h35; // '5'
                5'd21: fn_flow_sign_char = 7'h30; // '0'
                5'd22: fn_flow_sign_char = 7'h4D; // 'M'
                5'd23: fn_flow_sign_char = 7'h20; // ' '
                5'd24: fn_flow_sign_char = 7'h3E; // '>'
                default: fn_flow_sign_char = 7'h20;
            endcase
        end
    endfunction

    // -------------------------------------------------------------
    // 10. Zone Detection & Character Selector (Stage 1 Combinational)
    // -------------------------------------------------------------
    // 10. Zone Detection & Character Selector (Stage 1 Combinational)
    // -------------------------------------------------------------
    // Top Bar coordinates: Y = 8..27, X = 8..631 (Emergency mode: Y = 16..35, X = 16..623)
    wire in_top_box    = de_in && (active_emergency ? (y_cnt >= 10'd16 && y_cnt < 10'd36 && x_cnt >= 10'd16 && x_cnt < 10'd624)
                                                   : (y_cnt >= 10'd8  && y_cnt < 10'd28 && x_cnt >= 10'd8  && x_cnt < 10'd632));
    wire in_top_border = in_top_box && (active_emergency ? (y_cnt == 10'd16 || y_cnt == 10'd35 || x_cnt == 10'd16 || x_cnt == 10'd623)
                                                         : (y_cnt == 10'd8  || y_cnt == 10'd27 || x_cnt == 10'd8  || x_cnt == 10'd631));
    wire in_top_logo   = de_in && (active_emergency ? (y_cnt >= 10'd18 && y_cnt < 10'd34 && x_cnt >= 10'd20 && x_cnt < 10'd36)
                                                   : (y_cnt >= 10'd10 && y_cnt < 10'd26 && x_cnt >= 10'd12 && x_cnt < 10'd28));
    wire in_top_text_y = de_in && (active_emergency ? (y_cnt >= 10'd18 && y_cnt < 10'd34)
                                                   : (y_cnt >= 10'd10 && y_cnt < 10'd26));

    // Top Bar Text Zones
    wire in_top_brand = in_top_text_y && (x_cnt >= 10'd32  && x_cnt < 10'd128); // ANLOGIC 2026 (12 chars)
    wire in_top_mode  = !active_emergency && in_top_text_y && (x_cnt >= 10'd144 && x_cnt < 10'd208); // [AUTO] / [MANU] / [FAIL] (8 chars)
    wire in_top_img   = !active_emergency && in_top_text_y && (x_cnt >= 10'd224 && x_cnt < 10'd304); // IMG: 01/05 or IMG: --/05 (10 chars)
    wire in_top_time  = in_top_text_y && (x_cnt >= 10'd320 && x_cnt < 10'd424); // TIME 00:00 (13 chars)
    wire in_top_audio = in_top_text_y && (x_cnt >= 10'd440 && x_cnt < 10'd544); // AUDIO: 48KHZ (13 chars)
    wire in_top_res   = in_top_text_y && (x_cnt >= 10'd560 && x_cnt < 10'd624); // 640X480 (8 chars)

    // Parameter HUD Box coordinates: Y = 36..258 (height 223 px), X = 432..631 (width 200 px)
    // 16-Frame Smooth Respiratory Fade Engine (toggleable via KEY3 long-press)
    wire feedback_active=(feedback_frames!=0)&&!active_hud_en&&!active_emergency&&(hud_fade_step==0);
    wire in_feedback_box=feedback_active&&de_in&&x_cnt>=432&&x_cnt<632&&y_cnt>=36&&y_cnt<92;
    wire in_feedback_border=in_feedback_box&&(x_cnt==432||x_cnt==631||y_cnt==36||y_cnt==91);
    wire in_feedback_label=in_feedback_box&&x_cnt>=444&&x_cnt<620&&y_cnt>=40&&y_cnt<56;
    wire in_feedback_value=in_feedback_box&&x_cnt>=444&&x_cnt<620&&y_cnt>=66&&y_cnt<82;
    wire hud_active     = (hud_fade_step > 5'd0)&&!active_emergency;
    wire in_hud_box     = hud_active && de_in && (y_cnt >= 10'd36 && y_cnt < 10'd259 && x_cnt >= 10'd432 && x_cnt < 10'd632);
    wire in_hud_divider = hud_active && de_in && (y_cnt == 10'd166 && x_cnt >= 10'd432 && x_cnt < 10'd632);
    wire in_hud_border  = in_hud_box && (y_cnt == 10'd36 || y_cnt == 10'd258 || x_cnt == 10'd432 || x_cnt == 10'd631 || in_hud_divider);
    wire in_hud_text_x  = hud_active && (x_cnt >= 10'd444 && x_cnt < 10'd620); // 22 chars (176 px)
    wire [4:0] hud_char_pos = (x_cnt - 10'd444) >> 3;
    wire [2:0] hud_char_x   = (x_cnt - 10'd444) & 3'd7;

    wire line0_y  = (y_cnt >= 10'd40  && y_cnt < 10'd56);
    wire line1_y  = (y_cnt >= 10'd58  && y_cnt < 10'd74);
    wire line2_y  = (y_cnt >= 10'd76  && y_cnt < 10'd92);
    wire line3_y  = (y_cnt >= 10'd94  && y_cnt < 10'd110);
    wire line4_y  = (y_cnt >= 10'd112 && y_cnt < 10'd128);
    wire line5_y  = (y_cnt >= 10'd130 && y_cnt < 10'd146);
    wire line6_y  = (y_cnt >= 10'd148 && y_cnt < 10'd164);
    wire line7_y  = (y_cnt >= 10'd168 && y_cnt < 10'd184);
    wire line8_y  = (y_cnt >= 10'd186 && y_cnt < 10'd202);
    wire line9_y  = (y_cnt >= 10'd204 && y_cnt < 10'd220);
    wire line10_y = (y_cnt >= 10'd222 && y_cnt < 10'd238);
    wire line11_y = (y_cnt >= 10'd240 && y_cnt < 10'd256);

    wire in_hud_line0   = de_in && in_hud_text_x && line0_y;
    wire in_hud_line1   = de_in && in_hud_text_x && line1_y;
    wire in_hud_line2   = de_in && in_hud_text_x && line2_y;
    wire in_hud_line3   = de_in && in_hud_text_x && line3_y;
    wire in_hud_line4   = de_in && in_hud_text_x && line4_y;
    wire in_hud_line5   = de_in && in_hud_text_x && line5_y;
    wire in_hud_line6   = de_in && in_hud_text_x && line6_y;
    wire in_hud_line7   = de_in && in_hud_text_x && line7_y;
    wire in_hud_line8   = de_in && in_hud_text_x && line8_y;
    wire in_hud_line9   = de_in && in_hud_text_x && line9_y;
    wire in_hud_line10  = de_in && in_hud_text_x && line10_y;
    wire in_hud_line11  = de_in && in_hud_text_x && line11_y;

    // Direction 1 & 3: Active Menu Item Selected Row (0..7)
    wire menu_sel_line_y = (menu_cursor_s1 == 3'd0) ? line1_y :
                           (menu_cursor_s1 == 3'd1) ? line2_y :
                           (menu_cursor_s1 == 3'd2) ? line3_y :
                           (menu_cursor_s1 == 3'd3) ? line4_y :
                           (menu_cursor_s1 == 3'd4) ? line5_y :
                           (menu_cursor_s1 == 3'd5) ? line6_y :
                           (menu_cursor_s1 == 3'd6) ? line7_y : line11_y;

    wire in_hud_menu_cursor = menu_active_s1 && de_in && (x_cnt >= 10'd436 && x_cnt < 10'd444) && menu_sel_line_y;
    wire in_menu_sel_row    = menu_active_s1 && de_in && (x_cnt >= 10'd434 && x_cnt < 10'd630) && menu_sel_line_y;
    wire is_menu_sel_text   = menu_active_s1 && menu_sel_line_y && in_hud_text_x;


    // Emergency Mode Visual Zones:
    // Outer 16-pixel high-frequency red/blue flashing border
    wire in_emerg_border     = active_emergency && de_in && (x_cnt < 10'd16 || x_cnt >= 10'd624 || y_cnt < 10'd16 || y_cnt >= 10'd464);

    // Top Bar Emergency banner (overrides Mode & Img text during emergency)
    wire in_top_emerg_text   = active_emergency && in_top_text_y && (x_cnt >= 10'd144 && x_cnt < 10'd304);
    wire in_top_emerg_bg     = active_emergency && in_top_box && (x_cnt >= 10'd140 && x_cnt < 10'd308);

    // Center Pop-up Evacuation Billboard: Y = 176..303 (height 128 px), X = 128..511 (width 384 px)
    wire in_popup_box        = active_emergency && de_in && (y_cnt >= 10'd176 && y_cnt < 10'd304 && x_cnt >= 10'd128 && x_cnt < 10'd512);
    wire in_popup_border     = in_popup_box && (y_cnt < 10'd179 || y_cnt >= 10'd301 || x_cnt < 10'd131 || x_cnt >= 10'd509);
    wire in_popup_bg         = in_popup_box && !in_popup_border;
    wire [10:0] popup_diag_coord = x_cnt + y_cnt;
    wire [23:0] popup_border_col = popup_diag_coord[3] ? 24'hFFFF00 : 24'hFF0000; // Warning diagonal hazard stripes

    wire in_popup_l0         = active_emergency && de_in && (y_cnt >= 10'd188 && y_cnt < 10'd204 && x_cnt >= 10'd228 && x_cnt < 10'd412); // ! EMERGENCY BROADCAST !
    wire in_popup_l1         = active_emergency && de_in && (y_cnt >= 10'd212 && y_cnt < 10'd228 && x_cnt >= 10'd224 && x_cnt < 10'd416); // FIRE DETECTED - EVACUATE
    wire in_popup_l2         = active_emergency && de_in && (y_cnt >= 10'd236 && y_cnt < 10'd252 && x_cnt >= 10'd212 && x_cnt < 10'd428); // FOLLOW EXIT SIGNS TO SAFETY
    wire in_popup_l3         = active_emergency && de_in && (y_cnt >= 10'd260 && y_cnt < 10'd276 && x_cnt >= 10'd212 && x_cnt < 10'd428); // *** 紧急避险 - 安全疏散 ***

    // -------------------------------------------------------------
    // Cultural Heritage Evacuation Dynamic Optical Flow Guidance Corridor
    // (文博场馆突发火险应急避险动态光流导引廊道)
    // -------------------------------------------------------------
    wire flow_active      = active_emergency;
    wire in_flow_corridor = flow_active && de_in && 
                            (y_cnt >= 10'd330 && y_cnt < 10'd386 && x_cnt >= 10'd24 && x_cnt < 10'd616);

    // Hazard reflective border: 3px outer rim
    wire in_flow_border   = in_flow_corridor && 
                            (y_cnt < 10'd333 || y_cnt >= 10'd383 || x_cnt < 10'd27 || x_cnt >= 10'd613);
    wire [10:0] flow_diag_coord  = x_cnt + y_cnt;
    wire [23:0] flow_border_col  = flow_diag_coord[3] ? 24'hFFCC00 : 24'h101810;

    // Center illuminated highway evacuation wayfinding badge (X: 216..423, Y: 347..368)
    wire in_flow_sign_box = in_flow_corridor && !in_flow_border && 
                            (x_cnt >= 10'd216 && x_cnt < 10'd424 && y_cnt >= 10'd347 && y_cnt < 10'd369);
    wire in_flow_sign_border = in_flow_sign_box && 
                               (x_cnt == 10'd216 || x_cnt == 10'd423 || y_cnt == 10'd347 || y_cnt == 10'd368);
    wire in_flow_sign_bg  = in_flow_sign_box && !in_flow_sign_border;
    wire in_flow_text     = in_flow_sign_bg && 
                            (y_cnt >= 10'd350 && y_cnt < 10'd366 && x_cnt >= 10'd220 && x_cnt < 10'd420);

    // Dynamic Chevron Optical Flow Wave Engine (in trench outside center sign)
    wire in_flow_stream   = in_flow_corridor && !in_flow_border && !in_flow_sign_box;
    wire [9:0] flow_dy_10 = (y_cnt >= 10'd358) ? (y_cnt - 10'd358) : (10'd358 - y_cnt);
    wire [5:0] flow_dy    = flow_dy_10[5:0];
    wire [5:0] flow_rel_x = (x_cnt[5:0] - flow_phase + flow_dy); // 0..63 wrapping

    wire is_flow_crest = in_flow_stream && (flow_rel_x <= 6'd1);
    wire is_flow_body  = in_flow_stream && (flow_rel_x >= 6'd2 && flow_rel_x <= 6'd5);
    wire is_flow_tail1 = in_flow_stream && (flow_rel_x >= 6'd6 && flow_rel_x <= 6'd8);
    wire is_flow_tail2 = in_flow_stream && (flow_rel_x >= 6'd9 && flow_rel_x <= 6'd12);
    wire is_flow_tail3 = in_flow_stream && (flow_rel_x >= 6'd13 && flow_rel_x <= 6'd18);

    wire is_flow_arrow = is_flow_crest || is_flow_body || is_flow_tail1 || is_flow_tail2 || is_flow_tail3;

    wire [2:0] flow_arrow_col = is_flow_crest ? 3'd1 :
                                is_flow_body ? 3'd2 : is_flow_tail1 ? 3'd3 :
                                is_flow_tail2 ? 3'd4 : 3'd5;
    function [23:0] fn_flow_palette;
        input [2:0] index;
        begin case(index)
          1:fn_flow_palette=24'hE8FFE8;2:fn_flow_palette=24'h00FF66;
          3:fn_flow_palette=24'h00D048;4:fn_flow_palette=24'h008830;
          5:fn_flow_palette=24'h004418;default:fn_flow_palette=24'd0;
        endcase end
    endfunction

    wire is_flow_bg = in_flow_stream && !is_flow_arrow;

    // Marquee coordinates: Y = 448..473, X = 0..639 (Emergency: Y = 442..462, X = 16..623)
    wire in_marq_box    = (active_emergency || !marq_hidden) && de_in && (active_emergency ? (y_cnt >= 10'd442 && y_cnt < 10'd463) : (y_cnt >= 10'd448 && y_cnt < 10'd474));
    wire in_marq_border = in_marq_box && (active_emergency ? (y_cnt == 10'd442 || y_cnt == 10'd462) : (y_cnt == 10'd448 || y_cnt == 10'd473));
    wire in_marq_text   = (active_emergency || !marq_hidden) && de_in && (active_emergency ? (y_cnt >= 10'd444 && y_cnt < 10'd460 && x_cnt >= 10'd16 && x_cnt < 10'd624)
                                                     : (y_cnt >= 10'd452 && y_cnt < 10'd468));

    // Rhythm Beat Pulse Detector (Bass frequency bands 0..2)
    wire is_rhythm_beat = is_audio_playing && 
                         (spec_bar_h[0] >= 5'd16 || spec_bar_h[1] >= 5'd16 || spec_bar_h[2] >= 5'd16);

    // Box 1: 16-Band Studio Segmented LED Equalizer (X = 16..143, Y = 416..444)
    // 16 bands, each 6px wide + 2px gap = 8px per band, height 26px (9 physical LED segments)
    // Only displayed in normal playback mode to avoid collision with emergency alert banner
    wire in_audio_box    = display_valid && !active_emergency && de_in && (y_cnt >= 10'd416 && y_cnt < 10'd445 && x_cnt >= 10'd16 && x_cnt < 10'd144);
    wire in_audio_border = in_audio_box && (y_cnt == 10'd416 || y_cnt == 10'd444 || x_cnt == 10'd16 || x_cnt == 10'd143);
    wire [6:0] spec_rel_x     = x_cnt[7:0] - 8'd16; // 0..127
    wire [3:0] spec_bar_idx   = spec_rel_x[6:3];    // 0..15
    wire [2:0] spec_bar_rx    = spec_rel_x[2:0];    // 0..7
    wire       spec_bar_act   = (spec_bar_rx < 3'd6); // 6px bar, 2px gap
    wire [4:0] spec_bar_y     = 10'd443 - y_cnt;    // 0 at bottom (y=443), 26 at top (y=417)

    // Segmented LED micro-gaps (1px dark slit every 3 pixels)
    wire is_led_gap = (spec_bar_y == 5'd3  || spec_bar_y == 5'd6  || spec_bar_y == 5'd9  || 
                       spec_bar_y == 5'd12 || spec_bar_y == 5'd15 || spec_bar_y == 5'd18 || 
                       spec_bar_y == 5'd21 || spec_bar_y == 5'd24);

    // Floating Peak Cap (2 pixels thick, never cut by gap)
    wire spec_peak_on = in_audio_box && !in_audio_border && spec_bar_act && 
                        (spec_bar_y == spec_bar_peak[spec_bar_idx] || 
                         spec_bar_y == (spec_bar_peak[spec_bar_idx] - 5'd1)) && 
                        (spec_bar_peak[spec_bar_idx] > 5'd1);

    // Active lit LED segments
    wire spec_fill_on = in_audio_box && !in_audio_border && spec_bar_act && 
                        (spec_bar_y <= spec_bar_h[spec_bar_idx]) && (spec_bar_y > 5'd0);

    // Dark ghost unlit segments (authentic hardware faceplate look)
    wire spec_ghost_on = in_audio_box && !in_audio_border && spec_bar_act && 
                         (spec_bar_y > spec_bar_h[spec_bar_idx]) && (spec_bar_y <= 5'd26);

    // Grounding baseline anchor
    wire is_meter_floor = in_audio_box && !in_audio_border && (y_cnt == 10'd443);

    wire meter_bar_on = spec_fill_on || spec_peak_on || spec_ghost_on || is_meter_floor;

    // 五音声部与当前文物画音共振识别
    wire is_active_penta_band = (cur_img_idx == 3'd0 && spec_bar_idx <= 4'd2) ||
                                (cur_img_idx == 3'd1 && spec_bar_idx >= 4'd3 && spec_bar_idx <= 4'd5) ||
                                (cur_img_idx == 3'd2 && spec_bar_idx >= 4'd6 && spec_bar_idx <= 4'd8) ||
                                (cur_img_idx == 3'd3 && spec_bar_idx >= 4'd9 && spec_bar_idx <= 4'd11) ||
                                (cur_img_idx == 3'd4 && spec_bar_idx >= 4'd12 && spec_bar_idx <= 4'd15);
    wire [3:0] meter_bar_col = spec_peak_on ? (is_active_penta_band ? 4'd1 : 4'd2) :
                                (spec_fill_on ? (is_led_gap ? 4'd3 :
                                                (is_active_penta_band ?
                                                    ((spec_bar_y >= 5'd20) ? 4'd4 :
                                                    ((spec_bar_y >= 5'd10) ? 4'd5 : 4'd6)) :
                                                    ((spec_bar_y >= 5'd22) ? 4'd7 :
                                                    ((spec_bar_y >= 5'd13) ? 4'd8 : 4'd9)))) :
                                (spec_ghost_on ? (is_led_gap ? 4'd10 : 4'd11) : 4'd12));

    // Box 2: Laboratory Precision Luminous Audio Waveform Ribbon (X = 152..351, Y = 416..444)
    // Width 200px, Height 29px (Center zero reference at Y = 430)
    // Only displayed in normal playback mode to avoid collision with emergency alert banner
    wire in_wave_box    = display_valid && !active_emergency && de_in && (y_cnt >= 10'd416 && y_cnt < 10'd445 && x_cnt >= 10'd152 && x_cnt < 10'd352);
    wire in_wave_border = in_wave_box && (y_cnt == 10'd416 || y_cnt == 10'd444 || x_cnt == 10'd152 || x_cnt == 10'd351);

    // Audio Waveform Ribbon (High Dynamic Range 26x scaling with +/-12px saturation)
    wire [7:0] wave_rd_idx = wave_wr_ptr + (x_cnt[8:0] - 9'd152);
    // Prefetch the next coordinate and write pointer so a clocked BRAM
    // preserves the existing pixel latency. Read/write collisions occur
    // only at offset 255, outside the visible waveform interior (1..198).
    wire [7:0] wave_next_x=frame_pulse?8'd0:de_in?x_cnt[7:0]+8'd1:8'd0;
    wire [7:0] wave_next_ptr=wave_wr_ptr+{7'd0,audio_valid};
    wire [7:0] wave_prefetch_idx=rst?8'd104:wave_next_ptr+wave_next_x-8'd152;
    // Step 4 Low-Power Logic Optimization: Waveform Ribbon Multiplier Operand Isolation
    // The waveform ribbon height calculation (cur_wave_val * 26) is only needed inside the
    // 200x29 waveform box (<1.8% of screen area). Outside in_wave_box, cur_wave_val is clamped to 0,
    // freezing the multiplier and subsequent centering arithmetic without any extra LUT overhead.
    wire signed [7:0] cur_wave_val = (in_wave_box && wave_q[8]) ? wave_q[7:0] : 8'd0;
    wire signed [14:0] wave_mult   = cur_wave_val * 7'sd26;
    wire signed [7:0]  wave_scaled  = wave_mult[14:7];
    wire signed [5:0]  wave_clamp   = (wave_scaled > 8'sd12)  ? 6'sd12 :
                                     ((wave_scaled < -8'sd12) ? -6'sd12 : wave_scaled[5:0]);
    wire signed [9:0]  wave_target_y = 10'sd430 - wave_clamp;

    // 1. Ultra-bright pure white wave crest
    wire is_wave_crest = in_wave_box && !in_wave_border && (y_cnt == wave_target_y[9:0]);

    // 2. High-tech electric cyan outer rim glow
    wire is_wave_rim   = in_wave_box && !in_wave_border && 
                         ((wave_clamp > 6'sd0 && y_cnt == (wave_target_y[9:0] + 10'd1)) ||
                          (wave_clamp < 6'sd0 && y_cnt == (wave_target_y[9:0] - 10'd1)));

    // 3. Shaded oceanic teal translucent ribbon fill between crest and zero axis
    wire is_wave_fill  = in_wave_box && !in_wave_border && 
                         ((wave_clamp > 6'sd1 && y_cnt > (wave_target_y[9:0] + 10'd1) && y_cnt <= 10'd430) ||
                          (wave_clamp < -6'sd1 && y_cnt < (wave_target_y[9:0] - 10'd1) && y_cnt >= 10'd430));

    // 4. Subtle dotted center zero-voltage reference axis
    wire is_wave_axis  = in_wave_box && !in_wave_border && (y_cnt == 10'd430) && (x_cnt[2:0] == 3'd0);

    // 5. Laboratory reticle crosshair ticks at X = 202, 252, 302
    wire is_wave_tick  = in_wave_box && !in_wave_border && 
                         (x_cnt == 10'd202 || x_cnt == 10'd252 || x_cnt == 10'd302) && 
                         (y_cnt >= 10'd428 && y_cnt <= 10'd432);

    // Box 1 Pentatonic Tone Scale Ribbon (X = 16..143, Y = 398..413)
    wire in_penta_scale_text = display_valid && !active_emergency && de_in && (y_cnt >= 10'd398 && y_cnt < 10'd414 && x_cnt >= 10'd16 && x_cnt < 10'd144);
    // Box 2 Bronze Chime Physical Waveform Title (X = 152..351, Y = 398..413)
    wire in_wave_title_text  = display_valid && !active_emergency && de_in && (y_cnt >= 10'd398 && y_cnt < 10'd414 && x_cnt >= 10'd152 && x_cnt < 10'd352);
    // Translucent dark glass backplate behind the tone titles
    wire in_penta_title_bg   = display_valid && !active_emergency && de_in && (y_cnt >= 10'd396 && y_cnt < 10'd415 && 
                               ((x_cnt >= 10'd16 && x_cnt < 10'd144) || (x_cnt >= 10'd152 && x_cnt < 10'd352)));

    // Font Address calculation
    reg [6:0]  sel_char_code;
    reg [3:0]  sel_font_row;
    reg [2:0]  sel_font_x;
    reg [4:0] sel_text_color;
    reg        sel_is_text;

    // Top Bar character lookups
    function [6:0] fn_top_brand_char;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: fn_top_brand_char = 7'h41;
                4'd1: fn_top_brand_char = 7'h4E;
                4'd2: fn_top_brand_char = 7'h4C;
                4'd3: fn_top_brand_char = 7'h4F;
                4'd4: fn_top_brand_char = 7'h47;
                4'd5: fn_top_brand_char = 7'h49;
                4'd6: fn_top_brand_char = 7'h43;
                4'd7: fn_top_brand_char = 7'h20;
                4'd8: fn_top_brand_char = 7'h32;
                4'd9: fn_top_brand_char = 7'h30;
                4'd10: fn_top_brand_char = 7'h32;
                4'd11: fn_top_brand_char = 7'h36;
                default: fn_top_brand_char = 7'h20;
            endcase
        end
    endfunction

    function [6:0] fn_top_mode_char;
        input [3:0] st_code;
        input       fail_mode;
        input       auto_mode;
        input       is_fading;
        input [1:0] trans_eff;
        input [5:0] rem;
        input [3:0] d_sec;
        input [3:0] d_tth;
        input [2:0] idx;
        begin
            if (fail_mode || st_code == 4'd5) begin
                case (idx) // [FAIL  ]
                    3'd0: fn_top_mode_char = 7'h5B; // '['
                    3'd1: fn_top_mode_char = 7'h46; // 'F'
                    3'd2: fn_top_mode_char = 7'h41; // 'A'
                    3'd3: fn_top_mode_char = 7'h49; // 'I'
                    3'd4: fn_top_mode_char = 7'h4C; // 'L'
                    3'd5: fn_top_mode_char = 7'h5D; // ']'
                    3'd6: fn_top_mode_char = 7'h20; // ' '
                    3'd7: fn_top_mode_char = 7'h20; // ' '
                    default: fn_top_mode_char = 7'h20;
                endcase
            end else if (st_code == 4'd1) begin
                case (idx) // [1:IDLE]
                    3'd0: fn_top_mode_char = 7'h5B; // '['
                    3'd1: fn_top_mode_char = 7'h31; // '1'
                    3'd2: fn_top_mode_char = 7'h3A; // ':'
                    3'd3: fn_top_mode_char = 7'h49; // 'I'
                    3'd4: fn_top_mode_char = 7'h44; // 'D'
                    3'd5: fn_top_mode_char = 7'h4C; // 'L'
                    3'd6: fn_top_mode_char = 7'h45; // 'E'
                    3'd7: fn_top_mode_char = 7'h5D; // ']'
                    default: fn_top_mode_char = 7'h20;
                endcase
            end else if (st_code == 4'd2) begin
                case (idx) // [2:SEEK]
                    3'd0: fn_top_mode_char = 7'h5B; // '['
                    3'd1: fn_top_mode_char = 7'h32; // '2'
                    3'd2: fn_top_mode_char = 7'h3A; // ':'
                    3'd3: fn_top_mode_char = 7'h53; // 'S'
                    3'd4: fn_top_mode_char = 7'h45; // 'E'
                    3'd5: fn_top_mode_char = 7'h45; // 'E'
                    3'd6: fn_top_mode_char = 7'h4B; // 'K'
                    3'd7: fn_top_mode_char = 7'h5D; // ']'
                    default: fn_top_mode_char = 7'h20;
                endcase
            end else if (st_code == 4'd3) begin
                case (idx) // [3:RAM ]
                    3'd0: fn_top_mode_char = 7'h5B; // '['
                    3'd1: fn_top_mode_char = 7'h33; // '3'
                    3'd2: fn_top_mode_char = 7'h3A; // ':'
                    3'd3: fn_top_mode_char = 7'h52; // 'R'
                    3'd4: fn_top_mode_char = 7'h41; // 'A'
                    3'd5: fn_top_mode_char = 7'h4D; // 'M'
                    3'd6: fn_top_mode_char = 7'h20; // ' '
                    3'd7: fn_top_mode_char = 7'h5D; // ']'
                    default: fn_top_mode_char = 7'h20;
                endcase
            end else if (is_fading || (auto_mode && rem == 6'd0)) begin
                case (trans_eff)
                    2'd0: begin // [4:FADE]
                        case (idx)
                            3'd0: fn_top_mode_char = 7'h5B; // '['
                            3'd1: fn_top_mode_char = 7'h34; // '4'
                            3'd2: fn_top_mode_char = 7'h3A; // ':'
                            3'd3: fn_top_mode_char = 7'h46; // 'F'
                            3'd4: fn_top_mode_char = 7'h41; // 'A'
                            3'd5: fn_top_mode_char = 7'h44; // 'D'
                            3'd6: fn_top_mode_char = 7'h45; // 'E'
                            3'd7: fn_top_mode_char = 7'h5D; // ']'
                            default: fn_top_mode_char = 7'h20;
                        endcase
                    end
                    2'd1: begin // [4:BLND]
                        case (idx)
                            3'd0: fn_top_mode_char = 7'h5B; // '['
                            3'd1: fn_top_mode_char = 7'h34; // '4'
                            3'd2: fn_top_mode_char = 7'h3A; // ':'
                            3'd3: fn_top_mode_char = 7'h42; // 'B'
                            3'd4: fn_top_mode_char = 7'h4C; // 'L'
                            3'd5: fn_top_mode_char = 7'h4E; // 'N'
                            3'd6: fn_top_mode_char = 7'h44; // 'D'
                            3'd7: fn_top_mode_char = 7'h5D; // ']'
                            default: fn_top_mode_char = 7'h20;
                        endcase
                    end
                    2'd2: begin // [4:SLID]
                        case (idx)
                            3'd0: fn_top_mode_char = 7'h5B; // '['
                            3'd1: fn_top_mode_char = 7'h34; // '4'
                            3'd2: fn_top_mode_char = 7'h3A; // ':'
                            3'd3: fn_top_mode_char = 7'h53; // 'S'
                            3'd4: fn_top_mode_char = 7'h4C; // 'L'
                            3'd5: fn_top_mode_char = 7'h49; // 'I'
                            3'd6: fn_top_mode_char = 7'h44; // 'D'
                            3'd7: fn_top_mode_char = 7'h5D; // ']'
                            default: fn_top_mode_char = 7'h20;
                        endcase
                    end
                    default: begin // [4:MOSC]
                        case (idx)
                            3'd0: fn_top_mode_char = 7'h5B; // '['
                            3'd1: fn_top_mode_char = 7'h34; // '4'
                            3'd2: fn_top_mode_char = 7'h3A; // ':'
                            3'd3: fn_top_mode_char = 7'h4D; // 'M'
                            3'd4: fn_top_mode_char = 7'h4F; // 'O'
                            3'd5: fn_top_mode_char = 7'h53; // 'S'
                            3'd6: fn_top_mode_char = 7'h43; // 'C'
                            3'd7: fn_top_mode_char = 7'h5D; // ']'
                            default: fn_top_mode_char = 7'h20;
                        endcase
                    end
                endcase
            end else if (auto_mode) begin
                case (idx) // [4: X.YS]
                    3'd0: fn_top_mode_char = 7'h5B; // '['
                    3'd1: fn_top_mode_char = 7'h34; // '4'
                    3'd2: fn_top_mode_char = 7'h3A; // ':'
                    3'd3: fn_top_mode_char = {3'b011, d_sec};
                    3'd4: fn_top_mode_char = 7'h2E; // '.'
                    3'd5: fn_top_mode_char = {3'b011, d_tth};
                    3'd6: fn_top_mode_char = 7'h53; // 'S'
                    3'd7: fn_top_mode_char = 7'h5D; // ']'
                    default: fn_top_mode_char = 7'h20;
                endcase
            end else begin
                case (idx) // [4:MANU]
                    3'd0: fn_top_mode_char = 7'h5B; // '['
                    3'd1: fn_top_mode_char = 7'h34; // '4'
                    3'd2: fn_top_mode_char = 7'h3A; // ':'
                    3'd3: fn_top_mode_char = 7'h4D; // 'M'
                    3'd4: fn_top_mode_char = 7'h41; // 'A'
                    3'd5: fn_top_mode_char = 7'h4E; // 'N'
                    3'd6: fn_top_mode_char = 7'h55; // 'U'
                    3'd7: fn_top_mode_char = 7'h5D; // ']'
                    default: fn_top_mode_char = 7'h20;
                endcase
            end
        end
    endfunction

    function [6:0] fn_top_img_char;
        input       vld;
        input [2:0] img_id;
        input [3:0] total_imgs;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: fn_top_img_char = 7'h49; // 'I'
                4'd1: fn_top_img_char = 7'h4D; // 'M'
                4'd2: fn_top_img_char = 7'h47; // 'G'
                4'd3: fn_top_img_char = 7'h3A; // ':'
                4'd4: fn_top_img_char = 7'h20; // ' '
                4'd5: fn_top_img_char = vld ? 7'h30 : 7'h2D; // '0' or '-'
                4'd6: fn_top_img_char = vld ? (7'h31 + {4'd0, img_id}) : 7'h2D; // '1'+id or '-'
                4'd7: fn_top_img_char = 7'h2F; // '/'
                4'd8: fn_top_img_char = 7'h30; // '0'
                4'd9: fn_top_img_char = vld ? (7'h30 + {3'd0, total_imgs}) : 7'h35; // actual count or '5'
                default: fn_top_img_char = 7'h20;
            endcase
        end
    endfunction

    function [6:0] fn_top_time_char;
        input [3:0] mt, mo, st, so;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: fn_top_time_char = 7'h54; // 'T'
                4'd1: fn_top_time_char = 7'h49; // 'I'
                4'd2: fn_top_time_char = 7'h4D; // 'M'
                4'd3: fn_top_time_char = 7'h45; // 'E'
                4'd4: fn_top_time_char = 7'h20; // ' '
                4'd5: fn_top_time_char = {3'b011, mt}; // 'M'
                4'd6: fn_top_time_char = {3'b011, mo}; // 'M'
                4'd7: fn_top_time_char = 7'h3A; // ':'
                4'd8: fn_top_time_char = {3'b011, st}; // 'S'
                4'd9: fn_top_time_char = {3'b011, so}; // 'S'
                default: fn_top_time_char = 7'h20;
            endcase
        end
    endfunction

    function [6:0] fn_top_audio_char;
        input [2:0] vol;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: fn_top_audio_char = 7'h56; // 'V'
                4'd1: fn_top_audio_char = 7'h4F; // 'O'
                4'd2: fn_top_audio_char = 7'h4C; // 'L'
                4'd3: fn_top_audio_char = 7'h3A; // ':'
                4'd4: fn_top_audio_char = 7'h20; // ' '
                4'd5: case (vol)
                    3'd0: fn_top_audio_char = 7'h31; // '1'
                    3'd4: fn_top_audio_char = 7'h4D; // 'M'
                    default: fn_top_audio_char = 7'h20; // ' '
                endcase
                4'd6: case (vol)
                    3'd0: fn_top_audio_char = 7'h30; // '0'
                    3'd1: fn_top_audio_char = 7'h37; // '7'
                    3'd2: fn_top_audio_char = 7'h35; // '5'
                    3'd3: fn_top_audio_char = 7'h32; // '2'
                    default: fn_top_audio_char = 7'h55; // 'U'
                endcase
                4'd7: case (vol)
                    3'd0: fn_top_audio_char = 7'h30; // '0'
                    3'd1: fn_top_audio_char = 7'h35; // '5'
                    3'd2: fn_top_audio_char = 7'h30; // '0'
                    3'd3: fn_top_audio_char = 7'h35; // '5'
                    default: fn_top_audio_char = 7'h54; // 'T'
                endcase
                4'd8: case (vol)
                    3'd4: fn_top_audio_char = 7'h45; // 'E'
                    default: fn_top_audio_char = 7'h25; // '%'
                endcase
                4'd9:  fn_top_audio_char = 7'h20; // ' '
                4'd10: fn_top_audio_char = 7'h44; // 'D'
                4'd11: fn_top_audio_char = 7'h46; // 'F'
                4'd12: fn_top_audio_char = 7'h54; // 'T'
                default: fn_top_audio_char = 7'h20;
            endcase
        end
    endfunction


    reg [6:0] top_res_char_0, top_res_char_1, top_res_char_2, top_res_char_3;
    reg [6:0] top_res_char_4, top_res_char_5, top_res_char_6, top_res_char_7;
    reg [7:0] scada_top_toggle;
    wire      show_scada_in_top = active_scada && scada_top_toggle[7];

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            scada_top_toggle <= 8'd0;
            top_res_char_0   <= 7'h36; // '6'
            top_res_char_1   <= 7'h34; // '4'
            top_res_char_2   <= 7'h30; // '0'
            top_res_char_3   <= 7'h58; // 'X'
            top_res_char_4   <= 7'h34; // '4'
            top_res_char_5   <= 7'h38; // '8'
            top_res_char_6   <= 7'h30; // '0'
            top_res_char_7   <= 7'h20; // ' '
        end else if (frame_pulse) begin
            scada_top_toggle <= scada_top_toggle + 8'd1;
            if (active_scada && scada_top_toggle[7]) begin
                // Alternating display: "SCADA:ON"
                top_res_char_0 <= 7'h53; // 'S'
                top_res_char_1 <= 7'h43; // 'C'
                top_res_char_2 <= 7'h41; // 'A'
                top_res_char_3 <= 7'h44; // 'D'
                top_res_char_4 <= 7'h41; // 'A'
                top_res_char_5 <= 7'h3A; // ':'
                top_res_char_6 <= 7'h4F; // 'O'
                top_res_char_7 <= 7'h4E; // 'N'
            end else if (((source_w_bcd == 12'hA00 && active_scale_mode == 2'd3) || active_scale_mode == 2'd1 || active_scale_mode == 2'd2) && scada_top_toggle[6]) begin
                // Real-time Bilinear Algorithm Badge on non-native or scaled images
                top_res_char_0 <= 7'h32; // '2'
                top_res_char_1 <= 7'h44; // 'D'
                top_res_char_2 <= 7'h2D; // '-'
                top_res_char_3 <= 7'h42; // 'B'
                top_res_char_4 <= 7'h49; // 'I'
                top_res_char_5 <= 7'h4C; // 'L'
                top_res_char_6 <= 7'h49; // 'I'
                top_res_char_7 <= 7'h4E; // 'N'
            end else begin
                top_res_char_0 <= (source_w_bcd == 12'hA00) ? 7'h31 : {3'b011, source_w_bcd[11:8]};
                top_res_char_1 <= (source_w_bcd == 12'hA00) ? 7'h4B : {3'b011, source_w_bcd[7:4]};
                top_res_char_2 <= (source_w_bcd == 12'hA00) ? 7'h30 : {3'b011, source_w_bcd[3:0]};
                top_res_char_3 <= 7'h58; // 'X'
                top_res_char_4 <= {3'b011, source_h_bcd[11:8]};
                top_res_char_5 <= {3'b011, source_h_bcd[7:4]};
                top_res_char_6 <= {3'b011, source_h_bcd[3:0]};
                top_res_char_7 <= 7'h20; // ' '
            end
        end
    end

    // HUD Line Character lookups: Line 0 (Title / Alpha / Menu Title)
    function [6:0] fn_hud_menu_title_char;
        input [4:0] idx;
        begin
            case (idx)
                5'd0: fn_hud_menu_title_char = 7'h5B; // '['
                5'd1, 5'd2, 5'd18, 5'd19, 5'd20: fn_hud_menu_title_char = 7'h3D; // '='
                5'd3, 5'd7, 5'd12, 5'd17: fn_hud_menu_title_char = 7'h20; // ' '
                5'd4: fn_hud_menu_title_char = 7'h4F; // 'O'
                5'd5: fn_hud_menu_title_char = 7'h53; // 'S'
                5'd6: fn_hud_menu_title_char = 7'h44; // 'D'
                5'd8: fn_hud_menu_title_char = 7'h43; // 'C'
                5'd9: fn_hud_menu_title_char = 7'h54; // 'T'
                5'd10: fn_hud_menu_title_char = 7'h52; // 'R'
                5'd11: fn_hud_menu_title_char = 7'h4C; // 'L'
                5'd13: fn_hud_menu_title_char = 7'h4D; // 'M'
                5'd14: fn_hud_menu_title_char = 7'h45; // 'E'
                5'd15: fn_hud_menu_title_char = 7'h4E; // 'N'
                5'd16: fn_hud_menu_title_char = 7'h55; // 'U'
                5'd21: fn_hud_menu_title_char = 7'h5D; // ']'
                default: fn_hud_menu_title_char = 7'h20;
            endcase
        end
    endfunction

    function [6:0] fn_hud_l0_char;
        input [1:0] alp;
        input [4:0] idx;
        begin
            case (idx)
                5'd0:  fn_hud_l0_char = 7'h5B; // '['
                5'd1:  fn_hud_l0_char = 7'h53; // 'S'
                5'd2:  fn_hud_l0_char = 7'h45; // 'E'
                5'd3:  fn_hud_l0_char = 7'h54; // 'T'
                5'd4:  fn_hud_l0_char = 7'h54; // 'T'
                5'd5:  fn_hud_l0_char = 7'h49; // 'I'
                5'd6:  fn_hud_l0_char = 7'h4E; // 'N'
                5'd7:  fn_hud_l0_char = 7'h47; // 'G'
                5'd8:  fn_hud_l0_char = 7'h53; // 'S'
                5'd9:  fn_hud_l0_char = 7'h5D; // ']'
                5'd10: fn_hud_l0_char = 7'h20; // ' '
                5'd11: fn_hud_l0_char = 7'h20; // ' '
                5'd12: fn_hud_l0_char = 7'h20; // ' '
                5'd13: fn_hud_l0_char = 7'h5B; // '['
                5'd14: fn_hud_l0_char = 7'h41; // 'A'
                5'd15: fn_hud_l0_char = 7'h4C; // 'L'
                5'd16: fn_hud_l0_char = 7'h50; // 'P'
                5'd17: fn_hud_l0_char = 7'h3A; // ':'
                5'd18: case (alp)
                    2'd0: fn_hud_l0_char = 7'h32; // '2'
                    2'd2: fn_hud_l0_char = 7'h37; // '7'
                    default: fn_hud_l0_char = 7'h35; // '5'
                endcase
                5'd19: case (alp)
                    2'd0: fn_hud_l0_char = 7'h35; // '5'
                    2'd2: fn_hud_l0_char = 7'h35; // '5'
                    default: fn_hud_l0_char = 7'h30; // '0'
                endcase
                5'd20: fn_hud_l0_char = 7'h25; // '%'
                5'd21: fn_hud_l0_char = 7'h5D; // ']'
                default: fn_hud_l0_char = 7'h20;
            endcase
        end
    endfunction

    function [6:0] fn_hud_l1_char;
        input [1:0] lvl;
        input [4:0] idx;
        begin
            case (idx)
                5'd0: fn_hud_l1_char = 7'h42; // 'B'
                5'd1: fn_hud_l1_char = 7'h52; // 'R'
                5'd2: fn_hud_l1_char = 7'h54; // 'T'
                5'd3: fn_hud_l1_char = 7'h3A; // ':'
                5'd4: fn_hud_l1_char = 7'h20; // ' '
                5'd5: fn_hud_l1_char = (lvl == 2'b10) ? 7'h20 : 7'h31; // ' ' : '1'
                5'd6: case (lvl)
                    2'b00: fn_hud_l1_char = 7'h30; // '0'
                    2'b01: fn_hud_l1_char = 7'h32; // '2'
                    2'b10: fn_hud_l1_char = 7'h37; // '7'
                    default: fn_hud_l1_char = 7'h35; // '5'
                endcase
                5'd7: fn_hud_l1_char = (lvl == 2'b00 || lvl == 2'b11) ? 7'h30 : 7'h35; // '0' : '5'
                5'd8: fn_hud_l1_char = 7'h25; // '%'
                5'd9: fn_hud_l1_char = 7'h20; // ' '
                5'd10: fn_hud_l1_char = 7'h5B; // '['
                5'd11, 5'd12: fn_hud_l1_char = 7'h3D; // '='
                5'd13, 5'd14: fn_hud_l1_char = (lvl == 2'b10) ? 7'h20 : 7'h3D;
                5'd15, 5'd16: fn_hud_l1_char = (lvl[0]) ? 7'h3D : 7'h20;
                5'd17, 5'd18: fn_hud_l1_char = (lvl == 2'b11) ? 7'h3D : 7'h20;
                5'd19: fn_hud_l1_char = 7'h5D; // ']'
                default: fn_hud_l1_char = 7'h20;
            endcase
        end
    endfunction

    function [6:0] fn_hud_l2_char;
        input [2:0] vol;
        input [2:0] img_id;
        input [4:0] idx;
        begin
            case (idx)
                5'd0: fn_hud_l2_char = 7'h56; // 'V'
                5'd1: fn_hud_l2_char = 7'h4F; // 'O'
                5'd2: fn_hud_l2_char = 7'h4C; // 'L'
                5'd3: fn_hud_l2_char = 7'h3A; // ':'
                5'd4: fn_hud_l2_char = 7'h20; // ' '
                5'd5: case (vol)
                    3'd0: fn_hud_l2_char = 7'h31; // '1'
                    3'd4: fn_hud_l2_char = 7'h4D; // 'M'
                    default: fn_hud_l2_char = 7'h20; // ' '
                endcase
                5'd6: case (vol)
                    3'd0: fn_hud_l2_char = 7'h30; // '0'
                    3'd1: fn_hud_l2_char = 7'h37; // '7'
                    3'd2: fn_hud_l2_char = 7'h35; // '5'
                    3'd3: fn_hud_l2_char = 7'h32; // '2'
                    default: fn_hud_l2_char = 7'h55; // 'U'
                endcase
                5'd7: case (vol)
                    3'd0: fn_hud_l2_char = 7'h30; // '0'
                    3'd1: fn_hud_l2_char = 7'h35; // '5'
                    3'd2: fn_hud_l2_char = 7'h30; // '0'
                    3'd3: fn_hud_l2_char = 7'h35; // '5'
                    default: fn_hud_l2_char = 7'h54; // 'T'
                endcase
                5'd8: case (vol)
                    3'd4: fn_hud_l2_char = 7'h45; // 'E'
                    default: fn_hud_l2_char = 7'h25; // '%'
                endcase
                5'd9:  fn_hud_l2_char = 7'h20; // ' '
                5'd10: fn_hud_l2_char = 7'h5B; // '['
                // 11..18: 显示当前音名与音阶: [GONG:C5 ] / [SHANG:D5] / [JIAO:E5 ] / [ZHI:G5  ]
                5'd11: case (img_id)
                    2'd0: fn_hud_l2_char = 7'h47; // 'G'
                    2'd1: fn_hud_l2_char = 7'h53; // 'S'
                    2'd2: fn_hud_l2_char = 7'h4A; // 'J'
                    default: fn_hud_l2_char = 7'h5A; // 'Z'
                endcase
                5'd12: case (img_id)
                    2'd0: fn_hud_l2_char = 7'h4F; // 'O'
                    2'd1: fn_hud_l2_char = 7'h48; // 'H'
                    2'd2: fn_hud_l2_char = 7'h49; // 'I'
                    default: fn_hud_l2_char = 7'h48; // 'H'
                endcase
                5'd13: case (img_id)
                    2'd0: fn_hud_l2_char = 7'h4E; // 'N'
                    2'd1: fn_hud_l2_char = 7'h41; // 'A'
                    2'd2: fn_hud_l2_char = 7'h41; // 'A'
                    default: fn_hud_l2_char = 7'h49; // 'I'
                endcase
                5'd14: case (img_id)
                    2'd0: fn_hud_l2_char = 7'h47; // 'G'
                    2'd1: fn_hud_l2_char = 7'h4E; // 'N'
                    2'd2: fn_hud_l2_char = 7'h4F; // 'O'
                    default: fn_hud_l2_char = 7'h3A; // ':'
                endcase
                5'd15: case (img_id)
                    2'd0, 2'd1: fn_hud_l2_char = 7'h3A; // ':'
                    2'd2: fn_hud_l2_char = 7'h3A; // ':'
                    default: fn_hud_l2_char = 7'h47; // 'G'
                endcase
                5'd16: case (img_id)
                    2'd0: fn_hud_l2_char = 7'h43; // 'C'
                    2'd1: fn_hud_l2_char = 7'h44; // 'D'
                    2'd2: fn_hud_l2_char = 7'h45; // 'E'
                    default: fn_hud_l2_char = 7'h35; // '5'
                endcase
                5'd17: case (img_id)
                    2'd0, 2'd1, 2'd2: fn_hud_l2_char = 7'h35; // '5'
                    default: fn_hud_l2_char = 7'h20; // ' '
                endcase
                5'd18: fn_hud_l2_char = 7'h20; // ' '
                5'd19: fn_hud_l2_char = 7'h5D; // ']'
                default: fn_hud_l2_char = 7'h20;
            endcase
        end
    endfunction

    function [6:0] fn_hud_l3_char;
        input       emerg;
        input [1:0] mode;
        input [4:0] idx;
        begin
            if (emerg) case (idx)
                5'd0:  fn_hud_l3_char = 7'h46; // 'F'
                5'd1:  fn_hud_l3_char = 7'h4C; // 'L'
                5'd2:  fn_hud_l3_char = 7'h4F; // 'O'
                5'd3:  fn_hud_l3_char = 7'h57; // 'W'
                5'd4:  fn_hud_l3_char = 7'h3A; // ':'
                5'd5:  fn_hud_l3_char = 7'h20; // ' '
                5'd6:  fn_hud_l3_char = 7'h45; // 'E'
                5'd7:  fn_hud_l3_char = 7'h56; // 'V'
                5'd8:  fn_hud_l3_char = 7'h41; // 'A'
                5'd9:  fn_hud_l3_char = 7'h43; // 'C'
                5'd10: fn_hud_l3_char = 7'h20; // ' '
                5'd11: fn_hud_l3_char = 7'h5B; // '['
                5'd12: fn_hud_l3_char = 7'h41; // 'A'
                5'd13: fn_hud_l3_char = 7'h43; // 'C'
                5'd14: fn_hud_l3_char = 7'h54; // 'T'
                5'd15: fn_hud_l3_char = 7'h20; // ' '
                5'd16: fn_hud_l3_char = 7'h3E; // '>'
                5'd17: fn_hud_l3_char = 7'h3E; // '>'
                5'd18: fn_hud_l3_char = 7'h3E; // '>'
                5'd19: fn_hud_l3_char = 7'h5D; // ']'
                default: fn_hud_l3_char = 7'h20;
            endcase else case (idx)
                5'd0: case (mode)
                    2'd0, 2'd1: fn_hud_l3_char = 7'h43; // 'C'
                    2'd2:       fn_hud_l3_char = 7'h52; // 'R'
                    default:    fn_hud_l3_char = 7'h53; // 'S'
                endcase
                5'd1: case (mode)
                    2'd0, 2'd1: fn_hud_l3_char = 7'h4F; // 'O'
                    2'd2:       fn_hud_l3_char = 7'h55; // 'U'
                    default:    fn_hud_l3_char = 7'h50; // 'P'
                endcase
                5'd2: case (mode)
                    2'd0, 2'd1: fn_hud_l3_char = 7'h4C; // 'L'
                    2'd2:       fn_hud_l3_char = 7'h42; // 'B'
                    default:    fn_hud_l3_char = 7'h4C; // 'L'
                endcase
                5'd3: case (mode)
                    2'd0, 2'd1: fn_hud_l3_char = 7'h4F; // 'O'
                    2'd2:       fn_hud_l3_char = 7'h42; // 'B'
                    default:    fn_hud_l3_char = 7'h49; // 'I'
                endcase
                5'd4: case (mode)
                    2'd0, 2'd1: fn_hud_l3_char = 7'h52; // 'R'
                    2'd2:       fn_hud_l3_char = 7'h3A; // ':'
                    default:    fn_hud_l3_char = 7'h54; // 'T'
                endcase
                5'd5: fn_hud_l3_char = (mode == 2'd2) ? 7'h20 : 7'h3A; // ' ' : ':'
                5'd6: fn_hud_l3_char = (mode == 2'd2) ? 7'h49 : 7'h20; // 'I' : ' '
                5'd7: case (mode)
                    2'd0: fn_hud_l3_char = 7'h56; // 'V'
                    2'd1: fn_hud_l3_char = 7'h4D; // 'M'
                    2'd2: fn_hud_l3_char = 7'h4E; // 'N'
                    default: fn_hud_l3_char = 7'h43; // 'C'
                endcase
                5'd8: case (mode)
                    2'd0: fn_hud_l3_char = 7'h49; // 'I'
                    2'd1: fn_hud_l3_char = 7'h4F; // 'O'
                    2'd2: fn_hud_l3_char = 7'h4B; // 'K'
                    default: fn_hud_l3_char = 7'h4F; // 'O'
                endcase
                5'd9: case (mode)
                    2'd0: fn_hud_l3_char = 7'h56; // 'V'
                    2'd1: fn_hud_l3_char = 7'h4E; // 'N'
                    2'd2: fn_hud_l3_char = 7'h2D; // '-'
                    default: fn_hud_l3_char = 7'h4C; // 'L'
                endcase
                5'd10: case (mode)
                    2'd0: fn_hud_l3_char = 7'h49; // 'I'
                    2'd1: fn_hud_l3_char = 7'h4F; // 'O'
                    2'd2: fn_hud_l3_char = 7'h52; // 'R'
                    default: fn_hud_l3_char = 7'h4F; // 'O'
                endcase
                5'd11: case (mode)
                    2'd0: fn_hud_l3_char = 7'h44; // 'D'
                    2'd1: fn_hud_l3_char = 7'h20; // ' '
                    2'd2: fn_hud_l3_char = 7'h55; // 'U'
                    default: fn_hud_l3_char = 7'h52; // 'R'
                endcase
                5'd12: case (mode)
                    2'd0: fn_hud_l3_char = 7'h20; // ' '
                    2'd1: fn_hud_l3_char = 7'h28; // '('
                    2'd2: fn_hud_l3_char = 7'h42; // 'B'
                    default: fn_hud_l3_char = 7'h2F; // '/'
                endcase
                5'd13: case (mode)
                    2'd0: fn_hud_l3_char = 7'h28; // '('
                    2'd1: fn_hud_l3_char = 7'h42; // 'B'
                    2'd2: fn_hud_l3_char = 7'h42; // 'B'
                    default: fn_hud_l3_char = 7'h52; // 'R'
                endcase
                5'd14: case (mode)
                    2'd0: fn_hud_l3_char = 7'h4F; // 'O'
                    2'd1: fn_hud_l3_char = 7'h26; // '&'
                    2'd2: fn_hud_l3_char = 7'h49; // 'I'
                    default: fn_hud_l3_char = 7'h55; // 'U'
                endcase
                5'd15: case (mode)
                    2'd0: fn_hud_l3_char = 7'h52; // 'R'
                    2'd1: fn_hud_l3_char = 7'h57; // 'W'
                    2'd2: fn_hud_l3_char = 7'h4E; // 'N'
                    default: fn_hud_l3_char = 7'h42; // 'B'
                endcase
                5'd16: case (mode)
                    2'd0: fn_hud_l3_char = 7'h49; // 'I'
                    2'd1: fn_hud_l3_char = 7'h29; // ')'
                    2'd2: fn_hud_l3_char = 7'h47; // 'G'
                    default: fn_hud_l3_char = 7'h42; // 'B'
                endcase
                5'd17: fn_hud_l3_char = (mode == 2'd0) ? 7'h47 : 7'h20; // 'G' : ' '
                5'd18: fn_hud_l3_char = (mode == 2'd0) ? 7'h29 : 7'h20; // ')' : ' '
                default: fn_hud_l3_char = 7'h20;
            endcase
        end
    endfunction

    // Show both original and actual output dimensions; AUTO has no fixed ratio.
    function [6:0] fn_hud_l4_char;
        input [1:0] phase; input [1:0] mode; input [11:0] wb,hb,dwb,dhb; input [4:0] idx;
        reg [11:0] ww,hh;
        begin
            case (phase)
                2'd0: begin // Phase 0: Source Resolution
                    ww = wb; hh = hb;
                    case(idx)
                        0: fn_hud_l4_char = (mode == 3) ? "A" : (mode == 2) ? "0" : (mode == 1) ? "2" : "1";
                        1: fn_hud_l4_char = (mode == 3) ? "U" : ".";
                        2: fn_hud_l4_char = (mode == 3) ? "T" : (mode == 2) ? "5" : "0";
                        3: fn_hud_l4_char = (mode == 3) ? "O" : "X";
                        4: fn_hud_l4_char = " ";
                        5: fn_hud_l4_char = "S";
                        6: fn_hud_l4_char = "R";
                        7: fn_hud_l4_char = "C";
                        8: fn_hud_l4_char = ":";
                        9: fn_hud_l4_char = " ";
                        10: fn_hud_l4_char = (ww == 12'hA00) ? "1" : {3'b011, ww[11:8]};
                        11: fn_hud_l4_char = (ww == 12'hA00) ? "0" : {3'b011, ww[7:4]};
                        12: fn_hud_l4_char = (ww == 12'hA00) ? "2" : {3'b011, ww[3:0]};
                        13: fn_hud_l4_char = (ww == 12'hA00) ? "4" : "X";
                        14: fn_hud_l4_char = (ww == 12'hA00) ? "X" : {3'b011, hh[11:8]};
                        15: fn_hud_l4_char = (ww == 12'hA00) ? {3'b011, hh[11:8]} : {3'b011, hh[7:4]};
                        16: fn_hud_l4_char = (ww == 12'hA00) ? {3'b011, hh[7:4]}  : {3'b011, hh[3:0]};
                        17: fn_hud_l4_char = (ww == 12'hA00) ? {3'b011, hh[3:0]}  : " ";
                        default: fn_hud_l4_char = " ";
                    endcase
                end
                2'd1: begin // Phase 1: Output Resolution
                    ww = dwb; hh = dhb;
                    case(idx)
                        0: fn_hud_l4_char = (mode == 3) ? "A" : (mode == 2) ? "0" : (mode == 1) ? "2" : "1";
                        1: fn_hud_l4_char = (mode == 3) ? "U" : ".";
                        2: fn_hud_l4_char = (mode == 3) ? "T" : (mode == 2) ? "5" : "0";
                        3: fn_hud_l4_char = (mode == 3) ? "O" : "X";
                        4: fn_hud_l4_char = " ";
                        5: fn_hud_l4_char = "O";
                        6: fn_hud_l4_char = "U";
                        7: fn_hud_l4_char = "T";
                        8: fn_hud_l4_char = ":";
                        9: fn_hud_l4_char = " ";
                        10: fn_hud_l4_char = {3'b011, ww[11:8]};
                        11: fn_hud_l4_char = {3'b011, ww[7:4]};
                        12: fn_hud_l4_char = {3'b011, ww[3:0]};
                        13: fn_hud_l4_char = "X";
                        14: fn_hud_l4_char = {3'b011, hh[11:8]};
                        15: fn_hud_l4_char = {3'b011, hh[7:4]};
                        16: fn_hud_l4_char = {3'b011, hh[3:0]};
                        default: fn_hud_l4_char = " ";
                    endcase
                end
                2'd2: begin // Phase 2: Algorithm Name (2D-BILIN vs PASSTHRU)
                    case(idx)
                        0: fn_hud_l4_char = (mode == 3) ? "A" : (mode == 2) ? "0" : (mode == 1) ? "2" : "1";
                        1: fn_hud_l4_char = (mode == 3) ? "U" : ".";
                        2: fn_hud_l4_char = (mode == 3) ? "T" : (mode == 2) ? "5" : "0";
                        3: fn_hud_l4_char = (mode == 3) ? "O" : "X";
                        4: fn_hud_l4_char = " ";
                        5: fn_hud_l4_char = "A";
                        6: fn_hud_l4_char = "L";
                        7: fn_hud_l4_char = "G";
                        8: fn_hud_l4_char = ":";
                        9: fn_hud_l4_char = " ";
                        10: fn_hud_l4_char = (mode == 0 || (mode == 3 && wb == 12'h640)) ? "P" : "2";
                        11: fn_hud_l4_char = (mode == 0 || (mode == 3 && wb == 12'h640)) ? "A" : "D";
                        12: fn_hud_l4_char = (mode == 0 || (mode == 3 && wb == 12'h640)) ? "S" : "-";
                        13: fn_hud_l4_char = (mode == 0 || (mode == 3 && wb == 12'h640)) ? "S" : "B";
                        14: fn_hud_l4_char = (mode == 0 || (mode == 3 && wb == 12'h640)) ? "T" : "I";
                        15: fn_hud_l4_char = (mode == 0 || (mode == 3 && wb == 12'h640)) ? "H" : "L";
                        16: fn_hud_l4_char = (mode == 0 || (mode == 3 && wb == 12'h640)) ? "R" : "I";
                        17: fn_hud_l4_char = (mode == 0 || (mode == 3 && wb == 12'h640)) ? "U" : "N";
                        default: fn_hud_l4_char = " ";
                    endcase
                end
                2'd3: begin // Phase 3: Hardware DDA Ratio
                    case(idx)
                        0: fn_hud_l4_char = (mode == 3) ? "A" : (mode == 2) ? "0" : (mode == 1) ? "2" : "1";
                        1: fn_hud_l4_char = (mode == 3) ? "U" : ".";
                        2: fn_hud_l4_char = (mode == 3) ? "T" : (mode == 2) ? "5" : "0";
                        3: fn_hud_l4_char = (mode == 3) ? "O" : "X";
                        4: fn_hud_l4_char = " ";
                        5: fn_hud_l4_char = "R";
                        6: fn_hud_l4_char = "A";
                        7: fn_hud_l4_char = "T";
                        8: fn_hud_l4_char = ":";
                        9: fn_hud_l4_char = (mode == 1) ? "2" : ((mode == 2 || (mode == 3 && wb == 12'hA00)) ? "0" : "1");
                        10: fn_hud_l4_char = ".";
                        11: fn_hud_l4_char = (mode == 3 && wb == 12'hA00) ? "6" : ((mode == 2) ? "5" : "0");
                        12: fn_hud_l4_char = (mode == 3 && wb == 12'hA00) ? "2" : "0";
                        13: fn_hud_l4_char = (mode == 3 && wb == 12'hA00) ? "5" : "0";
                        14: fn_hud_l4_char = "X";
                        15: fn_hud_l4_char = " ";
                        16: fn_hud_l4_char = "(";
                        17: fn_hud_l4_char = (mode == 0 || (mode == 3 && wb != 12'hA00)) ? "R" : "D";
                        18: fn_hud_l4_char = (mode == 0 || (mode == 3 && wb != 12'hA00)) ? "A" : "D";
                        19: fn_hud_l4_char = (mode == 0 || (mode == 3 && wb != 12'hA00)) ? "W" : "A";
                        20: fn_hud_l4_char = ")";
                        default: fn_hud_l4_char = " ";
                    endcase
                end
            endcase
        end
    endfunction

    // Shared serial binary-to-decimal conversion, rather than pixel-path dividers.
    reg [11:0] source_w_bcd,source_h_bcd,display_w_bcd,display_h_bcd;
    reg [11:0] decimal_work;
    reg [9:0] decimal_bits;
    reg [3:0] decimal_count;
    reg [1:0] decimal_item;
    reg [11:0] decimal_adjust;
    always @(*) begin
        decimal_adjust=decimal_work;
        if(decimal_work[3:0]>=5)decimal_adjust[3:0]=decimal_work[3:0]+3;
        if(decimal_work[7:4]>=5)decimal_adjust[7:4]=decimal_work[7:4]+3;
        if(decimal_work[11:8]>=5)decimal_adjust[11:8]=decimal_work[11:8]+3;
    end
    wire [11:0] decimal_next={decimal_adjust[10:0],decimal_bits[9]};
    always @(posedge video_clk or posedge rst) begin
        if(rst) begin decimal_work<=0;decimal_bits<=0;decimal_count<=0;decimal_item<=0;
            source_w_bcd<=12'h640;source_h_bcd<=12'h480;display_w_bcd<=12'h640;display_h_bcd<=12'h480;end
        else if(decimal_count==0) begin
            decimal_work<=0;decimal_count<=10;
            case(decimal_item)
                0:decimal_bits<=(bmp_width>=16'd1000)?10'd999:bmp_width[9:0];
                1:decimal_bits<=(bmp_height>=16'd1000)?10'd999:bmp_height[9:0];
                2:decimal_bits<=scaled_width;
                3:decimal_bits<=scaled_height;
            endcase
        end else begin
            decimal_bits<={decimal_bits[8:0],1'b0};decimal_work<=decimal_next;decimal_count<=decimal_count-1'b1;
            if(decimal_count==1) begin
                case(decimal_item)
                    0:source_w_bcd<=(bmp_width>=16'd1000)?12'hA00:decimal_next;
                    1:source_h_bcd<=decimal_next;
                    2:display_w_bcd<=decimal_next;
                    3:display_h_bcd<=decimal_next;
                endcase
                decimal_item<=decimal_item+1'b1;
            end
        end
    end


    function [6:0] fn_hud_l5_char; // CONTRAST: 1.0X [STD ] / 1.2X [MED ] / 1.5X [HIGH] / 2.0X [MAX ] / 0.7X [LOW ]
        input [2:0] con;
        input [4:0] idx;
        begin
            case (idx)
                5'd0:  fn_hud_l5_char = 7'h43; // 'C'
                5'd1:  fn_hud_l5_char = 7'h4F; // 'O'
                5'd2:  fn_hud_l5_char = 7'h4E; // 'N'
                5'd3:  fn_hud_l5_char = 7'h54; // 'T'
                5'd4:  fn_hud_l5_char = 7'h52; // 'R'
                5'd5:  fn_hud_l5_char = 7'h41; // 'A'
                5'd6:  fn_hud_l5_char = 7'h53; // 'S'
                5'd7:  fn_hud_l5_char = 7'h54; // 'T'
                5'd8:  fn_hud_l5_char = 7'h3A; // ':'
                5'd9:  fn_hud_l5_char = 7'h20; // ' '
                5'd10: fn_hud_l5_char = 7'h20; // ' '
                5'd11: case (con)
                    3'd0: fn_hud_l5_char = 7'h31; // '1'
                    3'd1: fn_hud_l5_char = 7'h31; // '1'
                    3'd2: fn_hud_l5_char = 7'h31; // '1'
                    3'd3: fn_hud_l5_char = 7'h32; // '2'
                    3'd4: fn_hud_l5_char = 7'h30; // '0'
                    default: fn_hud_l5_char = 7'h31;
                endcase
                5'd12: fn_hud_l5_char = 7'h2E; // '.'
                5'd13: case (con)
                    3'd0: fn_hud_l5_char = 7'h30; // '0'
                    3'd1: fn_hud_l5_char = 7'h32; // '2'
                    3'd2: fn_hud_l5_char = 7'h35; // '5'
                    3'd3: fn_hud_l5_char = 7'h30; // '0'
                    3'd4: fn_hud_l5_char = 7'h37; // '7'
                    default: fn_hud_l5_char = 7'h30;
                endcase
                5'd14: fn_hud_l5_char = 7'h58; // 'X'
                5'd15: fn_hud_l5_char = 7'h20; // ' '
                5'd16: fn_hud_l5_char = 7'h5B; // '['
                5'd17: case (con)
                    3'd0: fn_hud_l5_char = 7'h53; // 'S'
                    3'd1: fn_hud_l5_char = 7'h4D; // 'M'
                    3'd2: fn_hud_l5_char = 7'h48; // 'H'
                    3'd3: fn_hud_l5_char = 7'h4D; // 'M'
                    3'd4: fn_hud_l5_char = 7'h4C; // 'L'
                    default: fn_hud_l5_char = 7'h53;
                endcase
                5'd18: case (con)
                    3'd0: fn_hud_l5_char = 7'h54; // 'T'
                    3'd1: fn_hud_l5_char = 7'h45; // 'E'
                    3'd2: fn_hud_l5_char = 7'h49; // 'I'
                    3'd3: fn_hud_l5_char = 7'h41; // 'A'
                    3'd4: fn_hud_l5_char = 7'h4F; // 'O'
                    default: fn_hud_l5_char = 7'h54;
                endcase
                5'd19: case (con)
                    3'd0: fn_hud_l5_char = 7'h44; // 'D'
                    3'd1: fn_hud_l5_char = 7'h44; // 'D'
                    3'd2: fn_hud_l5_char = 7'h47; // 'G'
                    3'd3: fn_hud_l5_char = 7'h58; // 'X'
                    3'd4: fn_hud_l5_char = 7'h57; // 'W'
                    default: fn_hud_l5_char = 7'h44;
                endcase
                5'd20: case (con)
                    3'd0: fn_hud_l5_char = 7'h20; // ' '
                    3'd1: fn_hud_l5_char = 7'h20; // ' '
                    3'd2: fn_hud_l5_char = 7'h48; // 'H'
                    3'd3: fn_hud_l5_char = 7'h20; // ' '
                    3'd4: fn_hud_l5_char = 7'h20; // ' '
                    default: fn_hud_l5_char = 7'h20;
                endcase
                5'd21: fn_hud_l5_char = 7'h5D; // ']'
                default: fn_hud_l5_char = 7'h20;
            endcase
        end
    endfunction

    function [6:0] fn_hud_l6_char; // TRANS: FADE (ALPHA) / TRANS: BLND (SLATS) / TRANS: SLID (LASER) / TRANS: MOSC (BLOCK) / TRANS: AUTO (CYCLE)
        input [2:0] mode;
        input [4:0] idx;
        begin
            case (idx)
                5'd0: fn_hud_l6_char = 7'h54; // 'T'
                5'd1: fn_hud_l6_char = 7'h52; // 'R'
                5'd2: fn_hud_l6_char = 7'h41; // 'A'
                5'd3: fn_hud_l6_char = 7'h4E; // 'N'
                5'd4: fn_hud_l6_char = 7'h53; // 'S'
                5'd5: fn_hud_l6_char = 7'h3A; // ':'
                5'd6: fn_hud_l6_char = 7'h20; // ' '
                5'd7: case (mode)
                    3'd0: fn_hud_l6_char = 7'h46; // 'F'
                    3'd1: fn_hud_l6_char = 7'h42; // 'B'
                    3'd2: fn_hud_l6_char = 7'h53; // 'S'
                    3'd3: fn_hud_l6_char = 7'h4D; // 'M'
                    default: fn_hud_l6_char = 7'h41; // 'A'
                endcase
                5'd8: case (mode)
                    3'd0: fn_hud_l6_char = 7'h41; // 'A'
                    3'd1: fn_hud_l6_char = 7'h4C; // 'L'
                    3'd2: fn_hud_l6_char = 7'h4C; // 'L'
                    3'd3: fn_hud_l6_char = 7'h4F; // 'O'
                    default: fn_hud_l6_char = 7'h55; // 'U'
                endcase
                5'd9: case (mode)
                    3'd0: fn_hud_l6_char = 7'h44; // 'D'
                    3'd1: fn_hud_l6_char = 7'h4E; // 'N'
                    3'd2: fn_hud_l6_char = 7'h49; // 'I'
                    3'd3: fn_hud_l6_char = 7'h53; // 'S'
                    default: fn_hud_l6_char = 7'h54; // 'T'
                endcase
                5'd10: case (mode)
                    3'd0: fn_hud_l6_char = 7'h45; // 'E'
                    3'd1: fn_hud_l6_char = 7'h44; // 'D'
                    3'd2: fn_hud_l6_char = 7'h44; // 'D'
                    3'd3: fn_hud_l6_char = 7'h43; // 'C'
                    default: fn_hud_l6_char = 7'h4F; // 'O'
                endcase
                5'd11: fn_hud_l6_char = 7'h20; // ' '
                5'd12: fn_hud_l6_char = 7'h28; // '('
                5'd13: case (mode)
                    3'd0: fn_hud_l6_char = 7'h41; // 'A' (ALPHA)
                    3'd1: fn_hud_l6_char = 7'h53; // 'S' (SLATS)
                    3'd2: fn_hud_l6_char = 7'h4C; // 'L' (LASER)
                    3'd3: fn_hud_l6_char = 7'h42; // 'B' (BLOCK)
                    default: fn_hud_l6_char = 7'h43; // 'C' (CYCLE)
                endcase
                5'd14: case (mode)
                    3'd0, 3'd1, 3'd3: fn_hud_l6_char = 7'h4C; // 'L'
                    3'd2: fn_hud_l6_char = 7'h41; // 'A'
                    default: fn_hud_l6_char = 7'h59; // 'Y'
                endcase
                5'd15: case (mode)
                    3'd0: fn_hud_l6_char = 7'h50; // 'P'
                    3'd1: fn_hud_l6_char = 7'h41; // 'A'
                    3'd2: fn_hud_l6_char = 7'h53; // 'S'
                    3'd3: fn_hud_l6_char = 7'h4F; // 'O'
                    default: fn_hud_l6_char = 7'h43; // 'C'
                endcase
                5'd16: case (mode)
                    3'd0: fn_hud_l6_char = 7'h48; // 'H'
                    3'd1: fn_hud_l6_char = 7'h54; // 'T'
                    3'd2: fn_hud_l6_char = 7'h45; // 'E'
                    3'd3: fn_hud_l6_char = 7'h43; // 'C'
                    default: fn_hud_l6_char = 7'h4C; // 'L'
                endcase
                5'd17: case (mode)
                    3'd0: fn_hud_l6_char = 7'h41; // 'A'
                    3'd1: fn_hud_l6_char = 7'h53; // 'S'
                    3'd2: fn_hud_l6_char = 7'h52; // 'R'
                    3'd3: fn_hud_l6_char = 7'h4B; // 'K'
                    default: fn_hud_l6_char = 7'h45; // 'E'
                endcase
                5'd18: fn_hud_l6_char = 7'h29; // ')'
                default: fn_hud_l6_char = 7'h20;
            endcase
        end
    endfunction

    function [6:0] fn_hud_l7_char; // MODE: AUTO (3.0S) / TONE: STD / WARM / COOL / EYE
        input       is_menu;
        input [1:0] tone;
        input       is_emerg;
        input       auto_mode;
        input [5:0] rem;
        input [3:0] d_sec;
        input [3:0] d_tth;
        input [4:0] idx;
        begin
            if (is_menu) begin
                case (idx)
                    5'd0: fn_hud_l7_char = 7'h54; // 'T'
                    5'd1: fn_hud_l7_char = 7'h4F; // 'O'
                    5'd2: fn_hud_l7_char = 7'h4E; // 'N'
                    5'd3: fn_hud_l7_char = 7'h45; // 'E'
                    5'd4: fn_hud_l7_char = 7'h3A; // ':'
                    5'd5: fn_hud_l7_char = 7'h20; // ' '
                    5'd6: case(tone) 2'd0: fn_hud_l7_char = 7'h53; 2'd1: fn_hud_l7_char = 7'h57; 2'd2: fn_hud_l7_char = 7'h43; default: fn_hud_l7_char = 7'h45; endcase
                    5'd7: case(tone) 2'd0: fn_hud_l7_char = 7'h54; 2'd1: fn_hud_l7_char = 7'h41; 2'd2: fn_hud_l7_char = 7'h4F; default: fn_hud_l7_char = 7'h59; endcase
                    5'd8: case(tone) 2'd0: fn_hud_l7_char = 7'h44; 2'd1: fn_hud_l7_char = 7'h52; 2'd2: fn_hud_l7_char = 7'h4F; default: fn_hud_l7_char = 7'h45; endcase
                    5'd9: case(tone) 2'd1: fn_hud_l7_char = 7'h4D; 2'd2: fn_hud_l7_char = 7'h4C; default: fn_hud_l7_char = 7'h20; endcase
                    default: fn_hud_l7_char = 7'h20;
                endcase
            end else if (is_emerg) begin
                case (idx)
                    5'd0:  fn_hud_l7_char = 7'h5B; // '['
                    5'd1:  fn_hud_l7_char = 7'h53; // 'S'
                    5'd2:  fn_hud_l7_char = 7'h43; // 'C'
                    5'd3:  fn_hud_l7_char = 7'h41; // 'A'
                    5'd4:  fn_hud_l7_char = 7'h44; // 'D'
                    5'd5:  fn_hud_l7_char = 7'h41; // 'A'
                    5'd6:  fn_hud_l7_char = 7'h3A; // ':'
                    5'd7:  fn_hud_l7_char = 7'h46; // 'F'
                    5'd8:  fn_hud_l7_char = 7'h49; // 'I'
                    5'd9:  fn_hud_l7_char = 7'h52; // 'R'
                    5'd10: fn_hud_l7_char = 7'h45; // 'E'
                    5'd11: fn_hud_l7_char = 7'h20; // ' '
                    5'd12: fn_hud_l7_char = 7'h41; // 'A'
                    5'd13: fn_hud_l7_char = 7'h4C; // 'L'
                    5'd14: fn_hud_l7_char = 7'h45; // 'E'
                    5'd15: fn_hud_l7_char = 7'h52; // 'R'
                    5'd16: fn_hud_l7_char = 7'h54; // 'T'
                    5'd17: fn_hud_l7_char = 7'h21; // '!'
                    5'd18: fn_hud_l7_char = 7'h5D; // ']'
                    default: fn_hud_l7_char = 7'h20;
                endcase
            end else case (idx)
                5'd0:  fn_hud_l7_char = 7'h4D; // 'M'
                5'd1:  fn_hud_l7_char = 7'h4F; // 'O'
                5'd2:  fn_hud_l7_char = 7'h44; // 'D'
                5'd3:  fn_hud_l7_char = 7'h45; // 'E'
                5'd4:  fn_hud_l7_char = 7'h3A; // ':'
                5'd5:  fn_hud_l7_char = 7'h20; // ' '
                5'd6:  fn_hud_l7_char = auto_mode ? 7'h41 : 7'h4D; // 'A' : 'M'
                5'd7:  fn_hud_l7_char = auto_mode ? 7'h55 : 7'h41; // 'U' : 'A'
                5'd8:  fn_hud_l7_char = auto_mode ? 7'h54 : 7'h4E; // 'T' : 'N'
                5'd9:  fn_hud_l7_char = auto_mode ? 7'h4F : 7'h55; // 'O' : 'U'
                5'd10: fn_hud_l7_char = auto_mode ? 7'h20 : 7'h41; // ' ' : 'A'
                5'd11: fn_hud_l7_char = auto_mode ? 7'h28 : 7'h4C; // '(' : 'L'
                5'd12: if (!auto_mode) fn_hud_l7_char = 7'h20;
                       else if (rem == 6'd0) fn_hud_l7_char = 7'h53; // 'S'
                       else fn_hud_l7_char = {3'b011, d_sec};
                5'd13: if (!auto_mode) fn_hud_l7_char = 7'h28;
                       else if (rem == 6'd0) fn_hud_l7_char = 7'h57; // 'W'
                       else fn_hud_l7_char = 7'h2E; // '.'
                5'd14: if (!auto_mode) fn_hud_l7_char = 7'h4B; // 'K'
                       else if (rem == 6'd0) fn_hud_l7_char = 7'h49; // 'I'
                       else fn_hud_l7_char = {3'b011, d_tth};
                5'd15: if (!auto_mode) fn_hud_l7_char = 7'h45; // 'E'
                       else if (rem == 6'd0) fn_hud_l7_char = 7'h54; // 'T'
                       else fn_hud_l7_char = 7'h53; // 'S'
                5'd16: if (!auto_mode) fn_hud_l7_char = 7'h59; // 'Y'
                       else if (rem == 6'd0) fn_hud_l7_char = 7'h43; // 'C'
                       else fn_hud_l7_char = 7'h29; // ')'
                5'd17: if (!auto_mode) fn_hud_l7_char = 7'h32; // '2'
                       else if (rem == 6'd0) fn_hud_l7_char = 7'h48; // 'H'
                       else fn_hud_l7_char = 7'h20;
                5'd18: fn_hud_l7_char = (auto_mode && rem != 6'd0) ? 7'h20 : 7'h29; // ')'
                default: fn_hud_l7_char = 7'h20;
            endcase
        end
    endfunction

    // Geometry is factual; no fabricated FPS, latency or bandwidth telemetry.
    function [6:0] fn_geometry_char;
        input [1:0] row;
        input [11:0] wb,hb;
        input [4:0] idx;
        begin case(idx)
            0:fn_geometry_char=row==0?"V":row==1?"I":"W";
            1:fn_geometry_char=row==0?"I":row==1?"N":"I";
            2:fn_geometry_char=row==0?"D":row==1?"P":"N";
            3:fn_geometry_char=row==0?"E":row==1?"U":"D";
            4:fn_geometry_char=row==0?"O":row==1?"T":"O";
            5:fn_geometry_char=row==2?"W":":";
            6:fn_geometry_char=row==2?":":" ";
            7:fn_geometry_char=(wb==12'hA00)?"1":{3'b011, wb[11:8]};
            8:fn_geometry_char=(wb==12'hA00)?"K":{3'b011, wb[7:4]};
            9:fn_geometry_char=(wb==12'hA00)?"0":{3'b011, wb[3:0]};
            10:fn_geometry_char="X";
            11:fn_geometry_char={3'b011, hb[11:8]};
            12:fn_geometry_char={3'b011, hb[7:4]};
            13:fn_geometry_char={3'b011, hb[3:0]};
            default:fn_geometry_char=" ";
        endcase end
    endfunction

    function [6:0] fn_hud_menu_hint_char;
        input [2:0] cur;
        input [4:0] idx;
        begin
            if (cur == 3'd7) begin
                // ">> [ PRESS TO EXIT ] <<"
                case (idx)
                    5'd0, 5'd1:   fn_hud_menu_hint_char = 7'h3E; // '>'
                    5'd2, 5'd4, 5'd10, 5'd13, 5'd18: fn_hud_menu_hint_char = 7'h20; // ' '
                    5'd3:         fn_hud_menu_hint_char = 7'h5B; // '['
                    5'd5:         fn_hud_menu_hint_char = 7'h50; // 'P'
                    5'd6:         fn_hud_menu_hint_char = 7'h52; // 'R'
                    5'd7, 5'd14:  fn_hud_menu_hint_char = 7'h45; // 'E'
                    5'd8, 5'd9:   fn_hud_menu_hint_char = 7'h53; // 'S'
                    5'd11, 5'd17: fn_hud_menu_hint_char = 7'h54; // 'T'
                    5'd12:        fn_hud_menu_hint_char = 7'h4F; // 'O'
                    5'd15:        fn_hud_menu_hint_char = 7'h58; // 'X'
                    5'd16:        fn_hud_menu_hint_char = 7'h49; // 'I'
                    5'd19:        fn_hud_menu_hint_char = 7'h5D; // ']'
                    5'd20, 5'd21: fn_hud_menu_hint_char = 7'h3C; // '<'
                    default:      fn_hud_menu_hint_char = 7'h20;
                endcase
            end else begin
                // "[K3:SEL/EXT K2:+ K4:-]"
                case (idx)
                    5'd0:  fn_hud_menu_hint_char = 7'h5B; // '['
                    5'd1, 5'd12, 5'd17: fn_hud_menu_hint_char = 7'h4B; // 'K'
                    5'd2:  fn_hud_menu_hint_char = 7'h33; // '3'
                    5'd3, 5'd14, 5'd19: fn_hud_menu_hint_char = 7'h3A; // ':'
                    5'd4:  fn_hud_menu_hint_char = 7'h53; // 'S'
                    5'd5, 5'd8:  fn_hud_menu_hint_char = 7'h45; // 'E'
                    5'd6:  fn_hud_menu_hint_char = 7'h4C; // 'L'
                    5'd7:  fn_hud_menu_hint_char = 7'h2F; // '/'
                    5'd9:  fn_hud_menu_hint_char = 7'h58; // 'X'
                    5'd10: fn_hud_menu_hint_char = 7'h54; // 'T'
                    5'd11, 5'd16: fn_hud_menu_hint_char = 7'h20; // ' '
                    5'd13: fn_hud_menu_hint_char = 7'h32; // '2'
                    5'd15: fn_hud_menu_hint_char = 7'h2B; // '+'
                    5'd18: fn_hud_menu_hint_char = 7'h34; // '4'
                    5'd20: fn_hud_menu_hint_char = 7'h2D; // '-'
                    5'd21: fn_hud_menu_hint_char = 7'h5D; // ']'
                    default: fn_hud_menu_hint_char = 7'h20;
                endcase
            end
        end
    endfunction

    function [6:0] fn_hud_l11_char; // Line 11: FRM frame counter & live APL%
        input [3:0] d5, d4, d3, d2, d1, d0;
        input [6:0] apl_hi, apl_lo;
        input [4:0] idx;
        begin
            case (idx)
                5'd0:  fn_hud_l11_char = 7'h46; // 'F'
                5'd1:  fn_hud_l11_char = 7'h52; // 'R'
                5'd2:  fn_hud_l11_char = 7'h4D; // 'M'
                5'd3:  fn_hud_l11_char = 7'h3A; // ':'
                5'd4:  fn_hud_l11_char = {3'b011, d5};
                5'd5:  fn_hud_l11_char = {3'b011, d4};
                5'd6:  fn_hud_l11_char = {3'b011, d3};
                5'd7:  fn_hud_l11_char = {3'b011, d2};
                5'd8:  fn_hud_l11_char = {3'b011, d1};
                5'd9:  fn_hud_l11_char = {3'b011, d0};
                5'd10, 5'd11, 5'd12: fn_hud_l11_char = 7'h20; // ' '
                5'd13: fn_hud_l11_char = 7'h41; // 'A'
                5'd14: fn_hud_l11_char = 7'h50; // 'P'
                5'd15: fn_hud_l11_char = 7'h4C; // 'L'
                5'd16: fn_hud_l11_char = 7'h3A; // ':'
                5'd17: fn_hud_l11_char = 7'h20; // ' '
                5'd18: fn_hud_l11_char = apl_hi;
                5'd19: fn_hud_l11_char = apl_lo;
                5'd20: fn_hud_l11_char = 7'h48; // 'H'
                5'd21: fn_hud_l11_char = 7'h20; // ' '
                default: fn_hud_l11_char = 7'h20;
            endcase
        end
    endfunction

    // Marquee char position calculation (1024-pixel wrapping)
    wire [9:0] marq_text_x = x_cnt + (active_emergency ? scroll_pos : normal_scroll_pos);
    wire [10:0] marq_entry_sum={1'b0,x_cnt}+{1'b0,normal_scroll_pos};
    wire marq_entry_blank=normal_entering&&!marq_entry_sum[10];
    function [6:0] fn_feedback_label;
        input [2:0] kind;input [4:0] idx;
        begin case(kind)
            3'd0:case(idx)
                5'd0:fn_feedback_label=7'd83;
                5'd1:fn_feedback_label=7'd67;
                5'd2:fn_feedback_label=7'd65;
                5'd3:fn_feedback_label=7'd76;
                5'd4:fn_feedback_label=7'd69;
                default:fn_feedback_label=7'h20;
            endcase
            3'd1:case(idx)
                5'd0:fn_feedback_label=7'd86;
                5'd1:fn_feedback_label=7'd79;
                5'd2:fn_feedback_label=7'd76;
                5'd3:fn_feedback_label=7'd85;
                5'd4:fn_feedback_label=7'd77;
                5'd5:fn_feedback_label=7'd69;
                default:fn_feedback_label=7'h20;
            endcase
            3'd2:case(idx)
                5'd0:fn_feedback_label=7'd66;
                5'd1:fn_feedback_label=7'd82;
                5'd2:fn_feedback_label=7'd73;
                5'd3:fn_feedback_label=7'd71;
                5'd4:fn_feedback_label=7'd72;
                5'd5:fn_feedback_label=7'd84;
                5'd6:fn_feedback_label=7'd78;
                5'd7:fn_feedback_label=7'd69;
                5'd8:fn_feedback_label=7'd83;
                5'd9:fn_feedback_label=7'd83;
                default:fn_feedback_label=7'h20;
            endcase
            3'd3:case(idx)
                5'd0:fn_feedback_label=7'd67;
                5'd1:fn_feedback_label=7'd79;
                5'd2:fn_feedback_label=7'd78;
                5'd3:fn_feedback_label=7'd84;
                5'd4:fn_feedback_label=7'd82;
                5'd5:fn_feedback_label=7'd65;
                5'd6:fn_feedback_label=7'd83;
                5'd7:fn_feedback_label=7'd84;
                default:fn_feedback_label=7'h20;
            endcase
            3'd4:case(idx)
                5'd0:fn_feedback_label=7'd73;
                5'd1:fn_feedback_label=7'd77;
                5'd2:fn_feedback_label=7'd65;
                5'd3:fn_feedback_label=7'd71;
                5'd4:fn_feedback_label=7'd69;
                5'd5:fn_feedback_label=7'd32;
                5'd6:fn_feedback_label=7'd69;
                5'd7:fn_feedback_label=7'd70;
                5'd8:fn_feedback_label=7'd70;
                5'd9:fn_feedback_label=7'd69;
                5'd10:fn_feedback_label=7'd67;
                5'd11:fn_feedback_label=7'd84;
                default:fn_feedback_label=7'h20;
            endcase
            3'd5:case(idx)
                5'd0:fn_feedback_label=7'd65;
                5'd1:fn_feedback_label=7'd76;
                5'd2:fn_feedback_label=7'd80;
                5'd3:fn_feedback_label=7'd72;
                5'd4:fn_feedback_label=7'd65;
                default:fn_feedback_label=7'h20;
            endcase
            3'd6:case(idx)
                5'd0:fn_feedback_label=7'd84;
                5'd1:fn_feedback_label=7'd82;
                5'd2:fn_feedback_label=7'd65;
                5'd3:fn_feedback_label=7'd78;
                5'd4:fn_feedback_label=7'd83;
                5'd5:fn_feedback_label=7'd73;
                5'd6:fn_feedback_label=7'd84;
                5'd7:fn_feedback_label=7'd73;
                5'd8:fn_feedback_label=7'd79;
                5'd9:fn_feedback_label=7'd78;
                default:fn_feedback_label=7'h20;
            endcase
            3'd7:case(idx)
                5'd0:fn_feedback_label=7'd80;
                5'd1:fn_feedback_label=7'd76;
                5'd2:fn_feedback_label=7'd65;
                5'd3:fn_feedback_label=7'd89;
                5'd4:fn_feedback_label=7'd32;
                5'd5:fn_feedback_label=7'd77;
                5'd6:fn_feedback_label=7'd79;
                5'd7:fn_feedback_label=7'd68;
                5'd8:fn_feedback_label=7'd69;
                default:fn_feedback_label=7'h20;
            endcase
        endcase end
    endfunction
    function [6:0] fn_feedback_value;
        input [2:0] kind; input [4:0] idx;
        begin
            case(kind)
                0: case(idx) // Scale: 1.0X / 2.0X / 0.5X / AUTO with Algorithm Details
                    0: fn_feedback_value = (active_scale_mode==3)?"A":(active_scale_mode==2)?"0":(active_scale_mode==1)?"2":"1";
                    1: fn_feedback_value = (active_scale_mode==3)?"U":".";
                    2: fn_feedback_value = (active_scale_mode==3)?"T":(active_scale_mode==2)?"5":"0";
                    3: fn_feedback_value = (active_scale_mode==3)?"O":"X";
                    4: fn_feedback_value = " ";
                    5: fn_feedback_value = "(";
                    6: fn_feedback_value = (active_scale_mode==3)?"B":(active_scale_mode==2)?"O":(active_scale_mode==1)?"I":"P";
                    7: fn_feedback_value = (active_scale_mode==3)?"I":(active_scale_mode==2)?"U":(active_scale_mode==1)?"N":"A";
                    8: fn_feedback_value = (active_scale_mode==3)?"L":(active_scale_mode==2)?"T":(active_scale_mode==1)?")":"S";
                    9: fn_feedback_value = (active_scale_mode==3)?"I":(active_scale_mode==2)?")":(active_scale_mode==1)?" ":"S";
                    10: fn_feedback_value = (active_scale_mode==3)?"N":(active_scale_mode==0)?"T":" ";
                    11: fn_feedback_value = (active_scale_mode==3)?"E":(active_scale_mode==0)?"H":" ";
                    12: fn_feedback_value = (active_scale_mode==3)?"A":(active_scale_mode==0)?"R":" ";
                    13: fn_feedback_value = (active_scale_mode==3)?"R":(active_scale_mode==0)?"U":" ";
                    14: fn_feedback_value = (active_scale_mode==3||active_scale_mode==0)?")":" ";
                    default: fn_feedback_value = " ";
                endcase
                1: fn_feedback_value = (idx < 4) ? fn_top_audio_char(active_vol_mode, idx + 5) : 7'h20;
                2: fn_feedback_value = (idx < 4) ? fn_hud_l1_char(active_bright_lvl, idx + 5) : 7'h20;
                3: case(idx) // Contrast
                    0: fn_feedback_value = (active_contrast==3)?"2":(active_contrast==4)?"0":"1";
                    1: fn_feedback_value = ".";
                    2: fn_feedback_value = (active_contrast==1)?"2":(active_contrast==2)?"5":(active_contrast==4)?"7":"0";
                    3: fn_feedback_value = (active_contrast==1||active_contrast==4)?"5":"0";
                    4: fn_feedback_value = "X";
                    default: fn_feedback_value = " ";
                endcase
                4: fn_feedback_value = fn_hud_l3_char(1'b0, active_color_mode, idx);
                5: case(idx) // Alpha: 25% / 50% / 75%
                    0: fn_feedback_value = (active_alpha_mode==0)?"2":(active_alpha_mode==2)?"7":"5";
                    1: fn_feedback_value = (active_alpha_mode==1)?"0":"5";
                    2: fn_feedback_value = "%";
                    default: fn_feedback_value = " ";
                endcase
                6: case(idx) // Trans: FADE / BLND / SLID / MOSC / AUTO
                    0: fn_feedback_value = (active_trans_mode==0)?"F":(active_trans_mode==1)?"B":(active_trans_mode==2)?"S":(active_trans_mode==3)?"M":"A";
                    1: fn_feedback_value = (active_trans_mode==0)?"A":(active_trans_mode==1)?"L":(active_trans_mode==2)?"L":(active_trans_mode==3)?"O":"U";
                    2: fn_feedback_value = (active_trans_mode==0)?"D":(active_trans_mode==1)?"N":(active_trans_mode==2)?"I":(active_trans_mode==3)?"S":"T";
                    3: fn_feedback_value = (active_trans_mode==0)?"E":(active_trans_mode==1)?"D":(active_trans_mode==2)?"D":(active_trans_mode==3)?"C":"O";
                    default: fn_feedback_value = " ";
                endcase
                7: case(idx) // Play mode: AUTO / MANUAL
                    0: fn_feedback_value = active_play ? "A" : "M";
                    1: fn_feedback_value = active_play ? "U" : "A";
                    2: fn_feedback_value = active_play ? "T" : "N";
                    3: fn_feedback_value = active_play ? "O" : "U";
                    4: fn_feedback_value = active_play ? " " : "A";
                    5: fn_feedback_value = active_play ? " " : "L";
                    default: fn_feedback_value = " ";
                endcase
            endcase
        end
    endfunction

    wire [9:0] marq_prefetch_x=frame_pulse?10'd0:de_in?x_cnt+10'd1:10'd0;
    wire [9:0] marq_prefetch_position=marq_prefetch_x+normal_scroll_pos;
    assign marq_read_addr=marq_prefetch_position[9:3];
    wire [6:0] marq_char_i = marq_text_x[9:3]; // 0..127
    wire [2:0] marq_pixel_x = marq_text_x[2:0]; // 0..7
    wire [3:0] top_font_row  = active_emergency ? (y_cnt[3:0] - 4'd2) : (y_cnt[3:0] - 4'd10);
    wire [3:0] marq_font_row = active_emergency ? (y_cnt[3:0] - 4'd12) : (y_cnt[3:0] - 4'd4);
    wire [6:0] apl_char_hi = (frame_apl[7:4] < 4'd10) ? (7'h30 + {3'b0, frame_apl[7:4]}) : (7'h37 + {3'b0, frame_apl[7:4]});
    wire [6:0] apl_char_lo = (frame_apl[3:0] < 4'd10) ? (7'h30 + {3'b0, frame_apl[3:0]}) : (7'h37 + {3'b0, frame_apl[3:0]});

    // Stage 1 Multiplexer for Font ROM
    always @(*) begin
        sel_char_code  = 7'h20;
        sel_font_row   = 4'd0;
        sel_font_x     = 3'd0;
        sel_text_color = 5'd1;
        sel_is_text    = 1'b0;
        
        if (in_top_emerg_text) begin
            sel_char_code  = fn_top_emerg_char((x_cnt - 10'd144) >> 3);
            sel_font_row   = top_font_row;
            sel_font_x     = (x_cnt - 10'd144) & 3'd7;
            sel_text_color = 5'd1; // Bright White
            sel_is_text    = 1'b1;
        end else if (in_popup_l0) begin
            sel_char_code  = fn_popup_l0_char((x_cnt - 10'd228) >> 3);
            sel_font_row   = y_cnt[3:0] - 4'd12; // 188 is 176+12
            sel_font_x     = (x_cnt - 10'd228) & 3'd7;
            sel_text_color = emerg_hud_phase ? 5'd2 : 5'd1;
            sel_is_text    = 1'b1;
        end else if (in_popup_l1) begin
            sel_char_code  = fn_popup_l1_char((x_cnt - 10'd224) >> 3);
            sel_font_row   = y_cnt[3:0] - 4'd4; // 212 is 208+4
            sel_font_x     = (x_cnt - 10'd224) & 3'd7;
            sel_text_color = 5'd3; // Alert Red-Orange
            sel_is_text    = 1'b1;
        end else if (in_popup_l2) begin
            sel_char_code  = fn_popup_l2_char((x_cnt - 10'd212) >> 3);
            sel_font_row   = y_cnt[3:0] - 4'd12; // 236 is 224+12
            sel_font_x     = (x_cnt - 10'd212) & 3'd7;
            sel_text_color = 5'd4; // Safety Green
            sel_is_text    = 1'b1;
        end else if (in_popup_l3) begin
            sel_char_code  = fn_popup_l3_char((x_cnt - 10'd212) >> 3);
            sel_font_row   = y_cnt[3:0] - 4'd4; // 260 is 256+4
            sel_font_x     = (x_cnt - 10'd212) & 3'd7;
            sel_text_color = 5'd5; // Warning Gold
            sel_is_text    = 1'b1;
        end else if (in_flow_text) begin
            sel_char_code  = fn_flow_sign_char((x_cnt - 10'd220) >> 3);
            sel_font_row   = y_cnt[3:0] - 4'd14; // Y=350 -> row 0
            sel_font_x     = (x_cnt - 10'd220) & 3'd7;
            sel_text_color = 5'd1; // Diamond Pure White
            sel_is_text    = 1'b1;
        end else if(in_feedback_label||in_feedback_value)begin
            sel_char_code=in_feedback_label?fn_feedback_label(feedback_kind,hud_char_pos):fn_feedback_value(feedback_kind,hud_char_pos);
            sel_font_row=in_feedback_label?(y_cnt-40):(y_cnt-66);
            sel_font_x=hud_char_x;
            sel_text_color=in_feedback_label?5'd6:5'd1;
            sel_is_text=1'b1;
        end else if (in_top_brand) begin
            sel_char_code  = fn_top_brand_char((x_cnt - 10'd32) >> 3);
            sel_font_row   = top_font_row;
            sel_font_x     = (x_cnt - 10'd32) & 3'd7;
            sel_text_color = 5'd6; // Neon Cyan
            sel_is_text    = 1'b1;
        end else if (in_top_mode) begin
            sel_char_code  = fn_top_mode_char(disp_state_code, load_fail_hold, auto_play_status, (fade_active || fade_active_s1), trans_eff_s1, dwell_remain, dwell_sec, dwell_tenth, (x_cnt - 10'd144) >> 3);
            sel_font_row   = top_font_row;
            sel_font_x     = (x_cnt - 10'd144) & 3'd7;
            sel_text_color = (load_fail_hold || disp_state_code == 4'd5) ? 5'd7 : // Warning Red
                             (disp_state_code == 4'd1)                  ? 5'd1 : // Diamond White
                             (disp_state_code == 4'd2)                  ? 5'd6 : // Neon Cyan
                             (disp_state_code == 4'd3)                  ? 5'd18 : // Amber Orange
                             (fade_active || fade_active_s1 || (auto_play_status && dwell_remain == 6'd0)) ? (
                                 (trans_eff_s1 == 2'd0) ? 5'd4 : // Emerald Green (FADE)
                                 (trans_eff_s1 == 2'd1) ? 5'd3 : // Solar Gold (BLND)
                                 (trans_eff_s1 == 2'd2) ? 5'd6 : // Neon Cyan (SLID)
                                                          5'd5   // Electric Purple (MOSC)
                             ) :
                             (auto_play_status ? 5'd4 : 5'd6);
            sel_is_text    = 1'b1;
        end else if (in_top_img) begin
            sel_char_code  = fn_top_img_char(display_valid, cur_img_idx, img_total_count, (x_cnt - 10'd224) >> 3);
            sel_font_row   = top_font_row;
            sel_font_x     = (x_cnt - 10'd224) & 3'd7;
            sel_text_color = display_valid ? 5'd8 : 5'd9; // Bright Gold-Yellow
            sel_is_text    = 1'b1;
        end else if (in_top_time) begin
            sel_char_code  = fn_top_time_char(min_tens, min_ones, sec_tens, sec_ones, (x_cnt - 10'd320) >> 3);
            sel_font_row   = top_font_row;
            sel_font_x     = (x_cnt - 10'd320) & 3'd7;
            sel_text_color = 5'd1; // White
            sel_is_text    = 1'b1;
        end else if (in_top_audio) begin
            sel_char_code  = fn_top_audio_char(active_vol_mode, (x_cnt - 10'd440) >> 3);
            sel_font_row   = top_font_row;
            sel_font_x     = (x_cnt - 10'd440) & 3'd7;
            sel_text_color = (active_vol_mode == 3'd4) ? 5'd10 : (is_audio_playing ? 5'd4 : 5'd11); // Solid Glowing Neon Green, Red if MUTE
            sel_is_text    = 1'b1;
        end else if (in_top_res) begin
            case ((x_cnt - 10'd560) >> 3)
                3'd0: sel_char_code = top_res_char_0;
                3'd1: sel_char_code = top_res_char_1;
                3'd2: sel_char_code = top_res_char_2;
                3'd3: sel_char_code = top_res_char_3;
                3'd4: sel_char_code = top_res_char_4;
                3'd5: sel_char_code = top_res_char_5;
                3'd6: sel_char_code = top_res_char_6;
                default: sel_char_code = top_res_char_7;
            endcase
            sel_font_row   = top_font_row;
            sel_font_x     = (x_cnt - 10'd560) & 3'd7;
            sel_text_color = show_scada_in_top ? 5'd12 : (((source_w_bcd == 12'hA00 && active_scale_mode == 2'd3) || active_scale_mode == 2'd1 || active_scale_mode == 2'd2) && scada_top_toggle[6]) ? 5'd3 : 5'd13; // Solar Gold for 2D-BILIN, Soft Cyan if RES
            sel_is_text    = 1'b1;
        end else if (in_hud_menu_cursor) begin
            sel_char_code  = 7'h3E; // '>' cursor
            sel_font_row   = (menu_cursor_s1 == 3'd6) ? (y_cnt[3:0] - 4'd8) :
                             (menu_cursor_s1 == 3'd7) ? y_cnt[3:0] :
                             (y_cnt[3:0] + 4'd6 - {menu_cursor_s1, 1'b0});
            sel_font_x     = {~x_cnt[2], x_cnt[1:0]};
            sel_text_color = 5'd6; // Electric Cyan
            sel_is_text    = 1'b1;
        end else if (in_hud_line0) begin
            sel_char_code  = active_emergency ? fn_top_emerg_char(hud_char_pos) :
                             menu_active_s1   ? fn_hud_menu_title_char(hud_char_pos) :
                             fn_hud_l0_char(active_alpha_mode, hud_char_pos);
            sel_font_row   = y_cnt[3:0] - 4'd8;
            sel_font_x     = hud_char_x;
            sel_text_color = active_emergency ? (emerg_hud_phase ? 5'd14 : 5'd8) :
                             menu_active_s1   ? 5'd6 :
                             ((hud_char_pos >= 5'd13) ? 5'd15 : 5'd5);
            sel_is_text    = 1'b1;
        end else if (in_hud_line1) begin
            sel_char_code  = fn_hud_l1_char(active_bright_lvl, hud_char_pos);
            sel_font_row   = y_cnt[3:0] - 4'd10;
            sel_font_x     = hud_char_x;
            sel_text_color = 5'd2; // Bright White if selected
            sel_is_text    = 1'b1;
        end else if (in_hud_line2) begin
            sel_char_code  = fn_hud_l2_char(active_vol_mode, cur_img_idx, hud_char_pos);
            sel_font_row   = y_cnt[3:0] - 4'd12;
            sel_font_x     = hud_char_x;
            sel_text_color = (active_vol_mode == 3'd4) ? 5'd10 : (is_rhythm_beat ? 5'd1 : 5'd5);
            sel_is_text    = 1'b1;
        end else if (in_hud_line3) begin
            sel_char_code  = fn_hud_l3_char(active_emergency, active_color_mode, hud_char_pos);
            sel_font_row   = y_cnt[3:0] - 4'd14;
            sel_font_x     = hud_char_x;
            sel_text_color = active_emergency ? (emerg_hud_phase ? 5'd6 : 5'd2) :
                             (active_color_mode == 2'd3) ? 5'd6 : // Cyan for Split-Compare
                             ((active_color_mode == 2'd2) ? 5'd5 : // Imperial Gold for Cinnabar Rubbing
                             ((active_color_mode == 2'd1) ? 5'd1 : // Pure Silver-White for Ink Rubbing
                                                            5'd16)); // Jade Green for Natural Artifact
            sel_is_text    = 1'b1;
        end else if (in_hud_line4) begin
            sel_char_code  = fn_hud_l4_char(scada_top_toggle[7:6], active_scale_mode, source_w_bcd, source_h_bcd, display_w_bcd, display_h_bcd, hud_char_pos);
            sel_font_row   = y_cnt[3:0]; // 112 is multiple of 16, row 0..15
            sel_font_x     = hud_char_x;
            sel_text_color = (scada_top_toggle[7:6] == 2'd0) ? 5'd6 :  // Neon Cyan for SRC
                             (scada_top_toggle[7:6] == 2'd1) ? 5'd19 : // Sky Blue for OUT
                             (scada_top_toggle[7:6] == 2'd2) ? 5'd3 :  // Solar Gold for 2D-BILIN
                                                               5'd4;   // Emerald Green for RATIO
            sel_is_text    = 1'b1;
        end else if (in_hud_line5) begin
            sel_char_code  = fn_hud_l5_char(active_contrast, hud_char_pos);
            sel_font_row   = y_cnt[3:0] - 4'd2; // 130 is 128+2, row 0..15
            sel_font_x     = hud_char_x;
            sel_text_color = (active_contrast == 3'd0) ? 5'd6 : // Cyan when Standard (1.00X)
                             (active_contrast == 3'd1) ? 5'd12 : // Mint Green when Medium (1.25X)
                             (active_contrast == 3'd2) ? 5'd18 : // Amber/Orange when High (1.50X)
                             (active_contrast == 3'd3) ? 5'd7 : // Crimson Red when Max (2.00X)
                                                         5'd19;  // Sky Blue when Low (0.75X)
            sel_is_text    = 1'b1;
        end else if (in_hud_line6) begin
            sel_char_code  = fn_hud_l6_char(active_trans_mode, hud_char_pos);
            sel_font_row   = y_cnt[3:0] - 4'd4; // 148 is 144+4, row 0..15
            sel_font_x     = hud_char_x;
            sel_text_color = (active_trans_mode == 3'd0) ? 5'd4 :
                             (active_trans_mode == 3'd1) ? 5'd3 :
                             (active_trans_mode == 3'd2) ? 5'd6 :
                             (active_trans_mode == 3'd3) ? 5'd5 : 5'd20;
            sel_is_text    = 1'b1;
        end else if (in_hud_line7) begin
            sel_char_code  = fn_hud_l7_char(menu_active_s1, active_tone_mode, active_emergency, auto_play_status, dwell_remain, dwell_sec, dwell_tenth, hud_char_pos);
            sel_font_row   = y_cnt[3:0] - 4'd8; // 168 is 160+8, row 0..15
            sel_font_x     = hud_char_x;
            sel_text_color = menu_active_s1 ? ((menu_cursor_s1 == 3'd6) ? 5'd2 : 5'd12) :
                             (active_emergency ? (emerg_hud_phase ? 5'd14 : 5'd8) :
                             (auto_play_status ? ((dwell_remain == 6'd0) ? 5'd2 : 5'd4) : 5'd6));
            sel_is_text    = 1'b1;
        end else if (in_hud_line8) begin
            sel_char_code  = fn_geometry_char(2'd0,12'h640,12'h480,hud_char_pos);
            sel_font_row   = y_cnt[3:0] - 4'd10; // 186 is 176+10, row 0..15
            sel_font_x     = hud_char_x;
            sel_text_color = 5'd21; // Bright Lime Green FPS
            sel_is_text    = 1'b1;
        end else if (in_hud_line9) begin
            sel_char_code  = fn_geometry_char(2'd1,source_w_bcd,source_h_bcd,hud_char_pos);
            sel_font_row   = y_cnt[3:0] - 4'd12; // 204 is 192+12, row 0..15
            sel_font_x     = hud_char_x;
            sel_text_color = 5'd6; // Neon Cyan Latency
            sel_is_text    = 1'b1;
        end else if (in_hud_line10) begin
            sel_char_code  = fn_geometry_char(2'd2,display_w_bcd,display_h_bcd,hud_char_pos);
            sel_font_row   = y_cnt[3:0] - 4'd14; // 222 is 208+14, row 0..15
            sel_font_x     = hud_char_x;
            sel_text_color = is_sdram_loading ? 5'd7 : 5'd16; // Red if Loading, Mint Green if OK
            sel_is_text    = 1'b1;
        end else if (in_hud_line11) begin
            sel_char_code  = menu_active_s1 ? fn_hud_menu_hint_char(menu_cursor_s1, hud_char_pos) :
                             fn_hud_l11_char(bcd_d5, bcd_d4, bcd_d3, bcd_d2, bcd_d1, bcd_d0, apl_char_hi, apl_char_lo, hud_char_pos);
            sel_font_row   = y_cnt[3:0]; // 240 is 240+0, row 0..15
            sel_font_x     = hud_char_x;
            sel_text_color = menu_active_s1 ? ((menu_cursor_s1 == 3'd7) ? (scada_top_toggle[5] ? 5'd1 : 5'd5) : 5'd5) : 5'd22;
            sel_is_text    = 1'b1;
        end else if (in_penta_scale_text) begin
            sel_char_code  = fn_penta_scale_char((x_cnt - 10'd16) >> 3);
            sel_font_row   = y_cnt[3:0] + 4'd2;
            sel_font_x     = (x_cnt - 10'd16) & 3'd7;
            sel_text_color = ((cur_img_idx[1:0] == 2'd0 && ((x_cnt - 10'd16) >> 3) <= 4'd2) ||
                              (cur_img_idx[1:0] == 2'd1 && ((x_cnt - 10'd16) >> 3) >= 4'd3 && ((x_cnt - 10'd16) >> 3) <= 4'd5) ||
                              (cur_img_idx[1:0] == 2'd2 && ((x_cnt - 10'd16) >> 3) >= 4'd6 && ((x_cnt - 10'd16) >> 3) <= 4'd8) ||
                              (cur_img_idx[1:0] == 2'd3 && ((x_cnt - 10'd16) >> 3) >= 4'd9 && ((x_cnt - 10'd16) >> 3) <= 4'd11)) ?
                             (is_rhythm_beat ? 5'd1 : 5'd5) :
                             (((x_cnt - 10'd16) >> 3 >= 4'd13) ? 5'd20 : 5'd23);
            sel_is_text    = 1'b1;
        end else if (in_wave_title_text) begin
            sel_char_code  = fn_wave_title_char(cur_img_idx, (x_cnt - 10'd152) >> 3);
            sel_font_row   = y_cnt[3:0] + 4'd2;
            sel_font_x     = (x_cnt - 10'd152) & 3'd7;
            sel_text_color = is_rhythm_beat ? 5'd5 : 5'd6;
            sel_is_text    = 1'b1;
        end else if (in_marq_text) begin
            sel_char_code  = active_emergency ? fn_marquee_emerg_char(marq_char_i) : (marq_custom_valid ? (marq_entry_blank ? 7'h20 : marq_read_data) : fn_marquee_char(marq_char_i));
            sel_font_row   = marq_font_row;
            sel_font_x     = marq_pixel_x;
            sel_text_color = active_emergency ? 5'd2 : 5'd5;
            sel_is_text    = 1'b1;
        end
        if (is_menu_sel_text) begin
            sel_text_color = 5'd1; // Bright White highlighted text for selected menu row
        end
    end

    // -------------------------------------------------------------
    // 11. Font ROM Instance
    // -------------------------------------------------------------
    wire [7:0] font_byte;
    font_rom_8x16 u_font_rom (
        .clk        (video_clk),
        .ascii_code (sel_char_code),
        .row        (sel_font_row),
        .font_data  (font_byte)
    );

    // -------------------------------------------------------------
    // 12. Pipeline Stage 1 -> Stage 2 Registers
    // -------------------------------------------------------------
    reg        de_p1, vs_p1, hs_p1;
    wire [23:0] adj_rgb_p1=bypass_adjust?passthrough_pixel:adjusted_pixel;
    reg [2:0]  font_x_p1;
    reg [4:0] text_color_p1;
    reg        is_text_p1;
    reg        logo_blue_p1;
    reg        logo_red_p1;
    reg        is_border_p1;
    reg [2:0] border_col_p1;
    reg        is_bg_box_p1;
    reg        is_bar_p1;
    reg [3:0] bar_col_p1;
    reg        is_wave_crest_p1;
    reg        is_wave_rim_p1;
    reg        is_wave_fill_p1;
    reg        is_wave_axis_p1;
    reg        is_wave_tick_p1;
    reg        is_emerg_border_p1;
    reg [23:0] emerg_border_col_p1;
    reg        is_popup_border_p1;
    reg [23:0] popup_border_col_p1;
    reg        is_popup_bg_p1;
    reg        is_top_emerg_bg_p1;
    reg [23:0] top_emerg_bg_col_p1;
    reg        is_flow_border_p1;
    reg [23:0] flow_border_col_p1;
    reg        is_flow_sign_border_p1;
    reg        is_flow_sign_bg_p1;
    reg        is_flow_arrow_p1;
    reg [2:0] flow_arrow_col_p1;
    reg        is_flow_bg_p1;
    reg        is_rhythm_beat_p1;
    reg        is_hud_box_p1;
    reg        is_hud_border_p1;
    reg        is_menu_sel_p1;
    reg [4:0]  hud_fade_step_p1;

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            de_p1         <= 1'b0;
            vs_p1         <= 1'b0;
            hs_p1         <= 1'b0;

            font_x_p1     <= 3'd0;
            text_color_p1 <= 5'd0;
            is_text_p1    <= 1'b0;
            logo_blue_p1  <= 1'b0;
            logo_red_p1   <= 1'b0;
            is_border_p1  <= 1'b0;
            border_col_p1 <= 3'd0;
            is_bg_box_p1  <= 1'b0;
            is_bar_p1     <= 1'b0;
            bar_col_p1    <= 24'd0;
            is_wave_crest_p1 <= 1'b0;
            is_wave_rim_p1   <= 1'b0;
            is_wave_fill_p1  <= 1'b0;
            is_wave_axis_p1  <= 1'b0;
            is_wave_tick_p1  <= 1'b0;
            is_rhythm_beat_p1   <= 1'b0;
            is_emerg_border_p1  <= 1'b0;
            emerg_border_col_p1 <= 3'd0;
            is_popup_border_p1  <= 1'b0;
            popup_border_col_p1 <= 3'd0;
            is_popup_bg_p1      <= 1'b0;
            is_top_emerg_bg_p1  <= 1'b0;
            top_emerg_bg_col_p1 <= 24'd0;
            is_flow_border_p1      <= 1'b0;
            flow_border_col_p1     <= 24'd0;
            is_flow_sign_border_p1 <= 1'b0;
            is_flow_sign_bg_p1     <= 1'b0;
            is_flow_arrow_p1       <= 1'b0;
            flow_arrow_col_p1      <= 3'd0;
            is_flow_bg_p1          <= 1'b0;
            is_hud_box_p1          <= 1'b0;
            is_hud_border_p1       <= 1'b0;
            is_menu_sel_p1         <= 1'b0;
            hud_fade_step_p1       <= 5'd0;
        end else begin
            de_p1         <= de_in;
            vs_p1         <= vs_in;
            hs_p1         <= hs_in;

            font_x_p1     <= sel_font_x;
            text_color_p1 <= sel_text_color;
            is_text_p1    <= sel_is_text;
            
            // Logo check (Dual-Color Anlogic Corporate Identity)
            logo_blue_p1  <= in_top_logo && fn_logo_is_blue(active_emergency ? (y_cnt[3:0] - 4'd2) : (y_cnt[3:0] - 4'd10),
                                                            active_emergency ? (x_cnt - 10'd20) : (x_cnt - 10'd12));
            logo_red_p1   <= in_top_logo && fn_logo_is_red(active_emergency ? (y_cnt[3:0] - 4'd2) : (y_cnt[3:0] - 4'd10),
                                                           active_emergency ? (x_cnt - 10'd20) : (x_cnt - 10'd12));
            
            // Border checks (HUD has dedicated fade blending pipeline)
            is_border_p1  <= in_top_border || in_marq_border || in_audio_border || in_wave_border;
            border_col_p1 <= in_feedback_border ? 3'd5 :
                             in_marq_border     ? 3'd1 :
                             (in_top_border && y_cnt == 10'd27 && auto_play_status) ?
                                 ((x_cnt <= dwell_prog_x) ? 3'd2 : 3'd3) :
                             (in_hud_divider && !menu_active_s1) ? 3'd4 :
                             ((in_audio_border || in_wave_border) && is_rhythm_beat) ? 3'd5 : 3'd6;
            
            // Background Alpha box checks (HUD has dedicated fade blending pipeline)
            is_bg_box_p1  <= (in_top_box && !in_top_border) || 
                             (in_marq_box && !in_marq_border) ||
                             (in_audio_box && !in_audio_border) ||
                             (in_wave_box && !in_wave_border) ||
                             in_penta_title_bg;
            
            // Audio Visualizer Bar & Precision Waveform Ribbon
            is_rhythm_beat_p1 <= is_rhythm_beat;
            is_bar_p1         <= meter_bar_on;
            bar_col_p1        <= meter_bar_col;
            is_wave_crest_p1  <= is_wave_crest;
            is_wave_rim_p1    <= is_wave_rim;
            is_wave_fill_p1   <= is_wave_fill;
            is_wave_axis_p1   <= is_wave_axis;
            is_wave_tick_p1   <= is_wave_tick;
            is_emerg_border_p1  <= in_emerg_border;
            emerg_border_col_p1 <= emerg_border_color;
            is_popup_border_p1  <= in_popup_border;
            popup_border_col_p1 <= popup_border_col;
            is_popup_bg_p1      <= in_popup_bg;
            is_top_emerg_bg_p1  <= in_top_emerg_bg;
            top_emerg_bg_col_p1 <= emerg_hud_phase ? 24'hD00000 : 24'h280000;
            is_flow_border_p1      <= in_flow_border;
            flow_border_col_p1     <= flow_border_col;
            is_flow_sign_border_p1 <= in_flow_sign_border;
            is_flow_sign_bg_p1     <= in_flow_sign_bg;
            is_flow_arrow_p1       <= is_flow_arrow;
            flow_arrow_col_p1      <= flow_arrow_col;
            is_flow_bg_p1          <= is_flow_bg;
            is_hud_box_p1          <= in_hud_box||in_feedback_box;
            is_hud_border_p1       <= in_hud_border||in_feedback_border;
            is_menu_sel_p1         <= in_menu_sel_row;
            hud_fade_step_p1       <= feedback_active?5'd16:hud_fade_step;
        end
    end

    // -------------------------------------------------------------
    // 13. Pipeline Stage 2 Output Blender & Multiplexer
    // -------------------------------------------------------------
    wire font_bit = font_byte[3'd7 - font_x_p1];

    // Multi-tier Alpha blending (25% crystal / 50% frosted glass / 75% dark contrast mask):
    wire [7:0] half_r = {1'b0, adj_rgb_p1[23:17]};
    wire [7:0] half_g = {1'b0, adj_rgb_p1[15:9]};
    wire [7:0] half_b = {1'b0, adj_rgb_p1[7:1]};
    wire [7:0] qtr_r  = {2'b00, adj_rgb_p1[23:18]};
    wire [7:0] qtr_g  = {2'b00, adj_rgb_p1[15:10]};
    wire [7:0] qtr_b  = {2'b00, adj_rgb_p1[7:2]};

    reg [7:0] bg_blend_r, bg_blend_g, bg_blend_b;
    always @(*) begin
        case (active_alpha_mode)
            2'd0: begin // 25% tint (75% video passthrough - crystal)
                bg_blend_r = half_r + qtr_r + 8'd3;
                bg_blend_g = half_g + qtr_g + 8'd5;
                bg_blend_b = half_b + qtr_b + 8'd12;
            end
            2'd2: begin // 75% tint (25% video passthrough - dark high-contrast mask)
                bg_blend_r = qtr_r + 8'd9;
                bg_blend_g = qtr_g + 8'd15;
                bg_blend_b = qtr_b + 8'd36;
            end
            default: begin // 50% tint (50% video passthrough - frosted sapphire glass default)
                bg_blend_r = half_r + 8'd6;
                bg_blend_g = half_g + 8'd10;
                bg_blend_b = half_b + 8'd24;
            end
        endcase
    end

    // Alpha blending 50% frosted dark emerald corridor trench glass:
    wire [7:0] flow_bg_r = half_r + 8'd2;
    wire [7:0] flow_bg_g = half_g + 8'd12;
    wire [7:0] flow_bg_b = half_b + 8'd6;

    // Carry palette indices across the pixel register, decode at composition.
    function [23:0] fn_text_palette;
        input [4:0] index;
        begin case(index)
            5'd0:fn_text_palette=24'h000000;
            5'd1:fn_text_palette=24'hFFFFFF;
            5'd2:fn_text_palette=24'hFFFF00;
            5'd3:fn_text_palette=24'hFF3322;
            5'd4:fn_text_palette=24'h00FF66;
            5'd5:fn_text_palette=24'hFFD700;
            5'd6:fn_text_palette=24'h00FFFF;
            5'd7:fn_text_palette=24'hFF4040;
            5'd8:fn_text_palette=24'hFFFF30;
            5'd9:fn_text_palette=24'hA0A0A0;
            5'd10:fn_text_palette=24'hFF4444;
            5'd11:fn_text_palette=24'h707070;
            5'd12:fn_text_palette=24'h00FF88;
            5'd13:fn_text_palette=24'h40FFFF;
            5'd14:fn_text_palette=24'hFF3030;
            5'd15:fn_text_palette=24'h00FFCC;
            5'd16:fn_text_palette=24'h40FF80;
            5'd17:fn_text_palette=24'hFF80FF;
            5'd18:fn_text_palette=24'hFFA500;
            5'd19:fn_text_palette=24'h80D0FF;
            5'd20:fn_text_palette=24'h00E5FF;
            5'd21:fn_text_palette=24'h00FF80;
            5'd22:fn_text_palette=24'hFFFF40;
            5'd23:fn_text_palette=24'h006688;
            default:fn_text_palette=24'd0;
        endcase end
    endfunction
    wire [23:0] text_rgb_p1=fn_text_palette(text_color_p1);
    // Carry palette indices across the pixel register, decode at composition.
    function [23:0] fn_bar_palette;
        input [3:0] index;
        begin case(index)
            4'd0:fn_bar_palette=24'h000000;
            4'd1:fn_bar_palette=24'hFFFF80;
            4'd2:fn_bar_palette=24'hE0FFFF;
            4'd3:fn_bar_palette=24'h061418;
            4'd4:fn_bar_palette=24'hFFA500;
            4'd5:fn_bar_palette=24'hFFD700;
            4'd6:fn_bar_palette=24'h00FFCC;
            4'd7:fn_bar_palette=24'hFF4500;
            4'd8:fn_bar_palette=24'h00E5FF;
            4'd9:fn_bar_palette=24'h20B2AA;
            4'd10:fn_bar_palette=24'h040C10;
            4'd11:fn_bar_palette=24'h08161A;
            4'd12:fn_bar_palette=24'h0088AA;
            default:fn_bar_palette=24'd0;
        endcase end
    endfunction
    wire [23:0] bar_rgb_p1=fn_bar_palette(bar_col_p1);
    // Carry palette indices across the pixel register, decode at composition.
    function [23:0] fn_border_palette;
        input [2:0] index;
        begin case(index)
            3'd0:fn_border_palette=24'h000000;
            3'd1:fn_border_palette=24'hD4AF37;
            3'd2:fn_border_palette=24'h00FF88;
            3'd3:fn_border_palette=24'h003344;
            3'd4:fn_border_palette=24'h0088AA;
            3'd5:fn_border_palette=24'hFFD700;
            3'd6:fn_border_palette=24'h00CCCC;
            default:fn_border_palette=24'd0;
        endcase end
    endfunction
    wire [23:0] border_rgb_p1=fn_border_palette(border_col_p1);

    // HUD Target Pixel and 16-Frame Smooth Respiratory Fade Engine (Vehicle Cockpit Tier)
    wire [23:0] hud_target_rgb = (is_text_p1 && font_bit) ? text_rgb_p1 :
                                 is_hud_border_p1          ? border_rgb_p1 :
                                 is_menu_sel_p1            ? 24'h0B2F52 : // Illuminated Sapphire highlight bar for selected menu item
                                 {bg_blend_r, bg_blend_g, bg_blend_b};
    wire [11:0] hud_blended_r  = (hud_target_rgb[23:16] * hud_fade_step_p1 + adj_rgb_p1[23:16] * (5'd16 - hud_fade_step_p1));
    wire [11:0] hud_blended_g  = (hud_target_rgb[15:8]  * hud_fade_step_p1 + adj_rgb_p1[15:8]  * (5'd16 - hud_fade_step_p1));
    wire [11:0] hud_blended_b  = (hud_target_rgb[7:0]   * hud_fade_step_p1 + adj_rgb_p1[7:0]   * (5'd16 - hud_fade_step_p1));
    wire [23:0] hud_fade_rgb   = {hud_blended_r[11:4], hud_blended_g[11:4], hud_blended_b[11:4]};

    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            de_out  <= 1'b0;
            vs_out  <= 1'b0;
            hs_out  <= 1'b0;
            rgb_out <= 24'd0;
        end else begin
            de_out <= de_p1;
            vs_out <= vs_p1;
            hs_out <= hs_p1;
            
            if (!de_p1) begin
                rgb_out <= 24'd0;
            end else if (is_emerg_border_p1) begin
                rgb_out <= emerg_border_col_p1; // 10Hz Red/Blue outer margin strobe
            end else if (is_hud_box_p1) begin
                rgb_out <= hud_fade_rgb; // 16-frame respiratory fade-in/fade-out & multi-level alpha glass HUD
            end else if (is_text_p1 && font_bit) begin
                rgb_out <= text_rgb_p1; // High-contrast OSD & emergency text ALWAYS visible
            end else if (logo_blue_p1) begin
                rgb_out <= 24'h204888; // Anlogic Tech Navy Blue Logo ('A')
            end else if (logo_red_p1) begin
                rgb_out <= 24'hEE1818; // Anlogic Crimson Red Logo (8 Stripes)
            end else if (is_popup_border_p1) begin
                rgb_out <= popup_border_col_p1; // Hazard diagonal warning border
            end else if (is_flow_sign_border_p1) begin
                rgb_out <= 24'h00FF66; // High-visibility glowing green sign border
            end else if (is_flow_border_p1) begin
                rgb_out <= flow_border_col_p1; // Highway reflective hazard border
            end else if (is_flow_arrow_p1) begin
                rgb_out <= fn_flow_palette(flow_arrow_col_p1); // Dynamic optical flow chevron arrow!
            end else if (is_popup_bg_p1) begin
                rgb_out <= 24'h100202; // Solid high-contrast dark emergency billboard background
            end else if (is_top_emerg_bg_p1) begin
                rgb_out <= top_emerg_bg_col_p1; // Blinking red background for ! EMERGENCY !
            end else if (is_flow_sign_bg_p1) begin
                rgb_out <= 24'h022410; // Dark forest green sign background
            end else if (is_flow_bg_p1) begin
                rgb_out <= {flow_bg_r, flow_bg_g, flow_bg_b}; // Alpha translucent corridor glass
            end else if (is_border_p1) begin
                rgb_out <= border_rgb_p1; // Neon Cyan / Gold / Beat pulse border
            end else if (is_wave_crest_p1) begin
                rgb_out <= 24'hFFFFFF; // Ultra-bright pure white wave crest
            end else if (is_wave_rim_p1) begin
                rgb_out <= is_rhythm_beat_p1 ? 24'hFFD700 : 24'h00E5FF; // Bronze chime gold flash / Cyan glow rim
            end else if (is_wave_fill_p1) begin
                rgb_out <= is_rhythm_beat_p1 ? 24'h0F2420 : 24'h004870; // Bronze resonance deep jade / oceanic teal fill
            end else if (is_bar_p1) begin
                rgb_out <= bar_rgb_p1; // Studio Segmented LED Equalizer + Diamond Ice Peak Cap + Ghost segments
            end else if (is_wave_tick_p1) begin
                rgb_out <= 24'h00B0D0; // Laboratory reticle crosshair ticks
            end else if (is_wave_axis_p1) begin
                rgb_out <= 24'h007090; // Subtle dotted zero axis reference
            end else if (is_bg_box_p1) begin
                rgb_out <= {bg_blend_r, bg_blend_g, bg_blend_b}; // Alpha translucent glass
            end else begin
                rgb_out <= adj_rgb_p1; // Passthrough adjusted video
            end
        end
    end

endmodule
`default_nettype wire
