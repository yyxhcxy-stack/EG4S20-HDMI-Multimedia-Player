"""TD gate synthesis of the two audio arithmetic units (not a board bitstream)."""
import argparse,hashlib,json,re,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--build-root',required=True);p.add_argument('--td',default='D:/Anlogic/TD6.2.1/bin/td_commands_prompt.exe');args=p.parse_args()
base=Path(args.build_root);base.mkdir(parents=True,exist_ok=False)
template=(ROOT/'prj/HX4S20_HDMI_Player.al').read_text(encoding='utf-8')
records=[]
for module,period in [('audio_output_stage',40),('audio_spectrum_dft',20)]:
    folder=base/module;folder.mkdir()
    source=ROOT/f'src/rtl/{module}.v';shutil.copy2(source,folder/source.name)
    top=module
    names=[source.name]
    if module=='audio_spectrum_dft':
        top='audio_dft_unit';names.append('wrapper.v')
        (folder/'wrapper.v').write_text('module audio_dft_unit(input clk,rst,valid,input [15:0] sample,output done,overrun,output [15:0] amp); wire [255:0] a; audio_spectrum_dft core(.clk(clk),.rst(rst),.sample_valid(valid),.sample(sample),.result_valid(done),.amplitudes(a),.overrun(overrun),.debug_re(),.debug_im(),.heights(),.ram_addr(),.ram_data(),.ram_write(),.ram_q(9\'d0),.ram_grant(1\'b1)); assign amp=a[15:0];endmodule')
    entries=''.join(f'<File Path="{name}">\n<FileInfo>\n<Attr Name="UsedInSyn" Val="true"/>\n<Attr Name="UsedInP&R" Val="true"/>\n<Attr Name="BelongTo" Val="design_1"/>\n<Attr Name="CompileOrder" Val="{i}"/>\n</FileInfo>\n</File>\n' for i,name in enumerate(names))
    project=re.sub(r'<Source_Files>.*?</Source_Files>',lambda m:'<Source_Files>\n<Verilog>\n'+entries+'</Verilog>\n</Source_Files>',template,flags=re.S).replace('<MODULE>top</MODULE>',f'<MODULE>{top}</MODULE>').replace('<LABEL>top</LABEL>',f'<LABEL>{top}</LABEL>')
    (folder/'HX4S20_HDMI_Player.prj').write_text(project,encoding='utf-8')
    (folder/'unit.sdc').write_text(f'create_clock -name clk -period {period} [get_ports {{clk}}]\n')
    (folder/'unit.tcl').write_text(f'import_device eagle_s20.db -package EG4S20BG256\nopen_project HX4S20_HDMI_Player.prj\nelaborate -top {top}\nread_sdc unit.sdc\noptimize_rtl\noptimize_gate -packarea\nreport_area -file unit.area\nexit\n')
    with (folder/'unit.log').open('w',encoding='utf-8') as log:
        proc=subprocess.run([args.td,'unit.tcl'],cwd=folder,input='exit\n',text=True,stdout=log,stderr=subprocess.STDOUT)
    area=folder/'unit.area';log=(folder/'unit.log').read_text(encoding='utf-8',errors='replace')
    assert proc.returncode==0 and area.exists() and 'ERROR:' not in log,folder
    data=area.read_text();assert int(re.search(r'(?m)^#dsp\s+(\d+)',data)[1])==2,data
    record={'module':module,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'dsp':2,'build_root':str(folder),'area_sha256':hashlib.sha256(area.read_bytes()).hexdigest()}
    records.append(record)
    out=ROOT/'output/verification/audio_units'/module;out.mkdir(parents=True,exist_ok=True)
    for name in ('unit.area','unit.log','unit.sdc','unit.tcl'):shutil.copy2(folder/name,out/name)
    print(f'PASS independent TD synthesis: {module}, two DSPs')
(ROOT/'output/verification/audio_units/manifest.json').write_text(json.dumps({'passed':True,'records':records},indent=2))
