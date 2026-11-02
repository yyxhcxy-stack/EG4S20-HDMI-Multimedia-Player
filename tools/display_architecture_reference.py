"""Apply only approved feedback/geometry/DFT label changes to historical pixel oracle.
Expected text and transaction state are supplied by the independent C++ model.
"""
import re

def adapt_architecture_reference(s):
    s=s.replace("module osd_reference (", "module osd_reference (\n    input wire reference_feedback_active,reference_feedback_value,\n    input wire [6:0] reference_feedback_char,reference_geometry_char,")
    s=s.replace("wire hud_active     = (hud_fade_step > 5'd0);", "wire hud_active     = (hud_fade_step > 5'd0)&&!active_emergency;")
    s=s.replace("    wire hud_active     =", """    wire in_feedback_box=reference_feedback_active&&de_in&&x_cnt>=432&&x_cnt<632&&y_cnt>=36&&y_cnt<92;
    wire in_feedback_border=in_feedback_box&&(x_cnt==432||x_cnt==631||y_cnt==36||y_cnt==91);
    wire in_feedback_text=in_feedback_box&&x_cnt>=444&&x_cnt<620&&((y_cnt>=40&&y_cnt<56)||(y_cnt>=66&&y_cnt<82));
    wire hud_active     =""",1)
    s=s.replace("        end else if (in_top_brand) begin", """        end else if(in_feedback_text)begin
            sel_char_code=reference_feedback_char;
            sel_font_row=reference_feedback_value?(y_cnt-66):(y_cnt-40);
            sel_font_x=(x_cnt-444)&7;
            sel_text_color=reference_feedback_value?24'hFFFFFF:24'h00FFFF;
            sel_is_text=1'b1;
        end else if (in_top_brand) begin""",1)
    s=s.replace("is_hud_box_p1          <= in_hud_box;","is_hud_box_p1          <= in_hud_box||in_feedback_box;")
    s=s.replace("is_hud_border_p1       <= in_hud_border;","is_hud_border_p1       <= in_hud_border||in_feedback_border;")
    s=s.replace("hud_fade_step_p1       <= hud_fade_step;","hud_fade_step_p1       <= reference_feedback_active?5'd16:hud_fade_step;")
    s=s.replace("border_col_p1 <= in_marq_border ?","border_col_p1 <= in_feedback_border ? 24'hFFD700 : in_marq_border ?")
    s=s.replace("4'd10: fn_top_audio_char = 7'h46; // 'F'","4'd10: fn_top_audio_char = 7'h44; // 'D'")
    for old in ("fn_hud_l8_char((x_cnt - 10'd444) >> 3)","fn_hud_l9_char(latency_mode, (x_cnt - 10'd444) >> 3)","fn_hud_l10_char(is_sdram_loading, (x_cnt - 10'd444) >> 3)"):
        assert old in s,old
        s=s.replace(old,"reference_geometry_char")
    for i in range(13,20):
        s=re.sub(rf"5'd{i}: fn_hud_l11_char = .*?;[^\n]*",f"5'd{i}: fn_hud_l11_char = 7'h20;",s)
    a=s.index("2'd2: case (idx) // 2'd2: SLID");b=s.index("endcase",a)
    section=s[a:b]
    for i,ch in enumerate("TRANS: WIPE (LASER)"):
        section=re.sub(rf"(5'd{i}: fn_hud_l6_char = ).*?;[^\n]*",lambda m:m[1]+f"7'd{ord(ch)};",section)
    return s[:a]+section+s[b:]
