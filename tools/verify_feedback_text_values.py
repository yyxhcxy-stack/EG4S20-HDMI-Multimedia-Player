"""Supplemental exhaustive actual-RTL text lookup check; independent expected strings."""
import hashlib,importlib.util,json,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/verification/feedback_text_values';OUT.mkdir(parents=True,exist_ok=True)
src=(ROOT/'src/rtl/osd_display.v').read_text(encoding='utf-8')
functions=[]
for name in ('fn_top_audio_char','fn_hud_l0_char','fn_hud_l1_char','fn_hud_l3_char','fn_hud_l4_char','fn_hud_l5_char','fn_hud_l6_char','fn_hud_l7_char','fn_feedback_label','fn_feedback_value'):
    begin=src.index('    function [6:0] '+name+';');end=src.index('    endfunction',begin)+len('    endfunction');functions.append(src[begin:end])
header='module feedback_text_values(input [2:0] kind,param,input [4:0] idx,output [6:0] label,value);\n'
header+='wire [1:0] active_scale_mode=param[1:0],active_bright_lvl=param[1:0],active_color_mode=param[1:0],active_alpha_mode=param[1:0],active_trans_mode=param[1:0];wire [2:0] active_vol_mode=param,active_contrast=param;wire active_play=param[0];\n'
(OUT/'lookup.v').write_text(header+'\n'.join(functions)+'\nassign label=fn_feedback_label(kind,idx);assign value=fn_feedback_value(kind,idx);endmodule\n')
yosys=shutil.which('yowasp-yosys');compiler=shutil.which('g++');assert yosys and compiler
with (OUT/'elaborate.log').open('w') as log:subprocess.run([yosys,'-Q','-T','-p','read_verilog output/verification/feedback_text_values/lookup.v; hierarchy -check -top feedback_text_values; proc; check -assert; write_cxxrtl -g0 output/verification/feedback_text_values/lookup.cc'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
bench=r'''#include "lookup.cc"
#include <string>
#include <vector>
#include <iostream>
int main(){cxxrtl_design::p_feedback__text__values d;
std::string labels[]={"SCALE","VOLUME","BRIGHTNESS","CONTRAST","IMAGE EFFECT","ALPHA","TRANSITION","PLAY MODE"};
std::vector<std::vector<std::string>> values={{"1.0X","2.0X","0.5X","AUTO"},{"100%"," 75%"," 50%"," 25%","MUTE"},{"100%","125%"," 75%","150%"},{"1.00X","1.25X","1.50X","2.00X","0.75X"},{"COLOR: VIVID (ORIG)","COLOR: MONO (B&W)","RUBB: INK-RUBBING","SPLIT: COLOR/RUBB"},{"25%","50%","75%"},{"FADE","BLND","WIPE","AUTO"},{"MANUAL","AUTO"}};
unsigned checks=0;for(unsigned k=0;k<8;k++)for(unsigned p=0;p<values[k].size();p++)for(unsigned i=0;i<32;i++){d.p_kind.set(k);d.p_param.set(p);d.p_idx.set(i);d.step();d.step();unsigned label=i<labels[k].size()?unsigned(labels[k][i]):32,value=i<values[k][p].size()?unsigned(values[k][p][i]):32;if(d.p_label.get<unsigned>()!=label||d.p_value.get<unsigned>()!=value){std::cerr<<"Text mismatch kind="<<k<<" parameter="<<p<<" index="<<i<<" expected="<<value<<" got="<<d.p_value.get<unsigned>()<<"\n";return 1;}checks++;}
std::cout<<"PASS feedback text: "<<checks<<" actual RTL label/value characters, all valid levels of eight parameters and trailing blanks\n";}
'''
(OUT/'test.cpp').write_text(bench)
include=Path(importlib.util.find_spec('yowasp_yosys').origin).parent/'share/include/backends/cxxrtl/runtime'
subprocess.run([compiler,'-std=c++17','-O2','-I',str(include),'-I',str(OUT),str(OUT/'test.cpp'),'-o',str(OUT/'test.exe')],cwd=ROOT,check=True)
r=subprocess.run([str(OUT/'test.exe')],cwd=ROOT,capture_output=True,text=True);print(r.stdout,r.stderr,end='');assert r.returncode==0
(OUT/'result.txt').write_text(r.stdout)
(OUT/'manifest.json').write_text(json.dumps({'passed':True,'source_sha256':hashlib.sha256((ROOT/'src/rtl/osd_display.v').read_bytes()).hexdigest(),'checker_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'result_sha256':hashlib.sha256((OUT/'result.txt').read_bytes()).hexdigest()},indent=2))
