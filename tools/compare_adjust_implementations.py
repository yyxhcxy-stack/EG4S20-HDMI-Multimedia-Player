"""Compare baseline ROM and exact arithmetic with actual TD synthesis."""
import argparse,hashlib,json,re,subprocess,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--build-root',required=True);a=p.parse_args()
base=Path(a.build_root);base.mkdir(parents=True,exist_ok=False)
template=(ROOT/'prj/HX4S20_HDMI_Player.al').read_text(encoding='utf-8')
records=[]
for name in ('baseline_rom','arithmetic','compact_rom'):
 folder=base/name;folder.mkdir()
 data=subprocess.check_output(['git','show','baseline-v2.6.1-flash:src/rtl/video_adjust_lut.v'],cwd=ROOT) if name=='baseline_rom' else subprocess.check_output(['git','show','310f3a4:src/rtl/video_adjust_lut.v'],cwd=ROOT) if name=='arithmetic' else (ROOT/'src/rtl/video_adjust_lut.v').read_bytes()
 (folder/'video_adjust_lut.v').write_bytes(data)
 entries='<File Path="video_adjust_lut.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="0"/></FileInfo></File>'
 project=re.sub(r'<Source_Files>.*?</Source_Files>',lambda m:'<Source_Files><Verilog>'+entries+'</Verilog></Source_Files>',template,flags=re.S).replace('<MODULE>top</MODULE>','<MODULE>video_adjust_lut</MODULE>').replace('<LABEL>top</LABEL>','<LABEL>video_adjust_lut</LABEL>')
 (folder/'HX4S20_HDMI_Player.prj').write_text(project,encoding='utf-8')
 (folder/'unit.sdc').write_text('create_clock -name clk -period 40 [get_ports {clk}]\n')
 (folder/'unit.tcl').write_text('import_device eagle_s20.db -package EG4S20BG256\nopen_project HX4S20_HDMI_Player.prj\nelaborate -top video_adjust_lut\nread_sdc unit.sdc\noptimize_rtl\noptimize_gate -packarea\nreport_area -file unit.area\nexit\n')
 with (folder/'unit.log').open('w',encoding='utf-8') as log:
  proc=subprocess.run(['D:/Anlogic/TD6.2.1/bin/td_commands_prompt.exe','unit.tcl'],cwd=folder,input='exit\n',text=True,stdout=log,stderr=subprocess.STDOUT)
 log=(folder/'unit.log').read_text(errors='replace');area=folder/'unit.area'
 assert proc.returncode==0 and area.exists() and 'ERROR:' not in log,folder
 text=area.read_text();counts={k:int(re.search(r'(?m)^#'+k+r'\s+(\d+)',text)[1]) for k in ('lut','reg','dsp','bram','bram32k')}
 records.append({'variant':name,'source_sha256':hashlib.sha256(data).hexdigest(),'resources':counts,'area_sha256':hashlib.sha256(area.read_bytes()).hexdigest(),'build_root':str(folder)})
 out=ROOT/'output/verification/v262_adjust_compare'/name;out.mkdir(parents=True,exist_ok=True)
 for file in ('unit.area','unit.log','unit.sdc','unit.tcl'):shutil.copy2(folder/file,out/file)
 print(name,counts,flush=True)
(ROOT/'output/verification/v262_adjust_compare/manifest.json').write_text(json.dumps({'passed':True,'records':records},indent=2))
