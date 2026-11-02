"""Render actual OSD RTL previews; no board capture or manufactured measurements."""
import hashlib,importlib.util,json,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/v262_preview';OUT.mkdir(parents=True,exist_ok=True)
yosys=shutil.which('yowasp-yosys');compiler=shutil.which('g++')
assert yosys and compiler,'Provide yowasp-yosys and g++'
include=Path(importlib.util.find_spec('yowasp_yosys').origin).parent/'share/include/backends/cxxrtl/runtime'
sources='src/rtl/video_adjust_lut.v src/rtl/font_rom_8x16.v src/rtl/audio_snapshot_cdc.v src/rtl/audio_spectrum_dft.v src/rtl/audio_spectrum_bridge.v src/rtl/osd_display.v'
with (OUT/'elaborate.log').open('w') as log:subprocess.run([yosys,'-Q','-T','-p',f'read_verilog {sources}; hierarchy -check -top osd_display; proc; check -assert; write_cxxrtl -g0 output/v262_preview/osd_preview.cc'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
subprocess.run([compiler,'-std=c++17','-O2','-I',str(include),'-I',str(OUT),str(ROOT/'tools/render_v262_preview.cpp'),'-o',str(OUT/'preview.exe')],cwd=ROOT,check=True)
subprocess.run([str(OUT/'preview.exe')],cwd=ROOT,check=True)
from PIL import Image,ImageDraw,ImageFont
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
canvas=Image.new('RGB',(1280,1016),'#111827');draw=ImageDraw.Draw(canvas)
labels=['默认简洁界面','调参短提示（对比度1.25×）','手动打开完整面板','应急显示（面板立即隐藏）']
for i,name in enumerate(('default','feedback','hud','emergency')):
    im=Image.open(OUT/(name+'.ppm'));assert im.size==(640,480)
    im.save(OUT/(name+'.png'));x=(i%2)*640;y=(i//2)*508
    draw.text((x+12,y+4),'RTL仿真：'+labels[i],font=font,fill='white');canvas.paste(im,(x,y+28))
canvas.save(OUT/'display_comparison.png')
(OUT/'manifest.json').write_text(json.dumps({'kind':'actual RTL simulation, not board photographs','rtl_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'src/rtl').rglob('*.v'))},'images':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.glob('*.png')}},indent=2),encoding='utf-8')
print('PASS actual RTL preview:',OUT/'display_comparison.png')
