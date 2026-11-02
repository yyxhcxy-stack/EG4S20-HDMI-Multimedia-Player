"""Adapt only the intended HUD default and normal marquee of the historical oracle."""


def adapt_hud_reference(s):
    for name in ('hud_s0', 'hud_s1', 'active_hud_en'):
        import re
        s, count = re.subn(rf"({name}\s*<=\s*)1'b1;", rf"\g<1>1'b0;", s)
        assert count == 1, name
    s, count = re.subn(r"(hud_fade_step\s*<=\s*)5'd16;", r"\g<1>5'd0;", s)
    assert count == 1
    return s


def adapt_marquee_reference(s):
    s = s.replace('module osd_reference (', 'module osd_reference (\n    input wire reference_marq_hidden,reference_marq_custom,\n    input wire [6:0] reference_marq_char,\n    input wire [9:0] reference_marq_position,')
    s = s.replace('wire in_marq_box    = de_in &&', 'wire in_marq_box    = (active_emergency || !reference_marq_hidden) && de_in &&')
    s = s.replace('wire in_marq_text   = de_in &&', 'wire in_marq_text   = (active_emergency || !reference_marq_hidden) && de_in &&')
    s = s.replace('wire [9:0] marq_text_x = x_cnt + scroll_pos;', 'wire [9:0] marq_text_x = x_cnt + (active_emergency ? scroll_pos : reference_marq_position);')
    s = s.replace('fn_marquee_emerg_char(marq_char_i) : fn_marquee_char(marq_char_i);', 'fn_marquee_emerg_char(marq_char_i) : (reference_marq_custom ? reference_marq_char : fn_marquee_char(marq_char_i));')
    assert 'input wire reference_marq_hidden' in s
    return s
