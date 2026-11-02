"""TD gate synthesis of marquee metadata and the shared UART RAM owner."""
import argparse,hashlib,json,re,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--build-root',required=True);p.add_argument('--td',default='D:/Anlogic/TD6.2.1/bin/td_commands_prompt.exe');args=p.parse_args()
base=Path(args.build_root);base.mkdir(parents=True,exist_ok=False)
template=(ROOT/'prj/HX4S20_HDMI_Player.al').read_text(encoding='utf-8')
records=[]
for module,period in [('marquee_store',20),('uart_scada_controller',20)]:
    folder=base/module;folder.mkdir()
    source=ROOT/f'src/rtl/{module}.v';shutil.copy2(source,folder/source.name)
    top=module
    names=[source.name]
    if module=='uart_scada_controller':
        names.append('marquee_store.v');shutil.copy2(ROOT/'src/rtl/marquee_store.v',folder/'marquee_store.v')
    if module=='audio_spectrum_dft':
        top='audio_dft_unit';names.append('wrapper.v')
        (folder/'wrapper.v').write_text('module audio_dft_unit(input clk,rst,valid,input [15:0] sample,output done,overrun,output [15:0] amp); wire [255:0] a; audio_spectrum_dft core(.clk(clk),.rst(rst),.sample_valid(valid),.sample(sample),.result_valid(done),.amplitudes(a),.overrun(overrun),.debug_re(),.debug_im(),.heights(),.ram_addr(),.ram_data(),.ram_write(),.ram_q(9\'d0),.ram_grant(1\'b1)); assign amp=a[15:0];endmodule')
    entries=''.join(f'<File Path="{name}">\n<FileInfo>\n<Attr Name="UsedInSyn" Val="true"/>\n<Attr Name="UsedInP&R" Val="true"/>\n<Attr Name="BelongTo" Val="design_1"/>\n<Attr Name="CompileOrder" Val="{i}"/>\n</FileInfo>\n</File>\n' for i,name in enumerate(names))
    project=re.sub(r'<Source_Files>.*?</Source_Files>',lambda m:'<Source_Files>\n<Verilog>\n'+entries+'</Verilog>\n</Source_Files>',template,flags=re.S).replace('<MODULE>top</MODULE>',f'<MODULE>{top}</MODULE>').replace('<LABEL>top</LABEL>',f'<LABEL>{top}</LABEL>')
    (folder/'HX4S20_HDMI_Player.prj').write_text(project,encoding='utf-8')
    (folder/'unit.sdc').write_text('create_clock -name clk -period 20 [get_ports {clk}]\ncreate_clock -name video_clk -period 40 [get_ports {video_clk}]\nset_clock_groups -asynchronous -group [get_clocks clk] -group [get_clocks video_clk]\n')
    (folder/'unit.tcl').write_text(f'import_device eagle_s20.db -package EG4S20BG256\nopen_project HX4S20_HDMI_Player.prj\nelaborate -top {top}\nread_sdc unit.sdc\noptimize_rtl\noptimize_gate -packarea\nreport_area -file unit.area\nexit\n')
    with (folder/'unit.log').open('w',encoding='utf-8') as log:
        proc=subprocess.run([args.td,'unit.tcl'],cwd=folder,input='exit\n',text=True,stdout=log,stderr=subprocess.STDOUT)
    area=folder/'unit.area';log=(folder/'unit.log').read_text(encoding='utf-8',errors='replace')
    assert proc.returncode==0 and area.exists() and 'ERROR:' not in log,folder
    data=area.read_text();counts={k:int(re.search(r'(?m)^#'+k+r'\s+(\d+)',data)[1]) for k in ('dsp','bram','bram32k')};assert counts=={'dsp':0,'bram':int(module=='uart_scada_controller'),'bram32k':0},data
    record={'module':module,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),**counts,'dependencies':{name:hashlib.sha256((folder/name).read_bytes()).hexdigest() for name in names},'build_root':str(folder),'area_sha256':hashlib.sha256(area.read_bytes()).hexdigest()}
    records.append(record)
    out=ROOT/'output/verification/marquee_unit'/module;out.mkdir(parents=True,exist_ok=True)
    for name in ('unit.area','unit.log','unit.sdc','unit.tcl'):shutil.copy2(folder/name,out/name)
    print(f'PASS independent TD synthesis: {module}, {counts["dsp"]} DSP, {counts["bram"]} 9K RAM')
(ROOT/'output/verification/marquee_unit/manifest.json').write_text(json.dumps({'passed':True,'records':records},indent=2))
