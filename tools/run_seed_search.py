import os
import subprocess
import shutil
import re
import glob

# Automatically pick the newest build_ext directory
build_dirs = sorted(glob.glob('build_ext_*'), key=os.path.getmtime, reverse=True)
if not build_dirs:
    print("No build_ext directory found!")
    exit(1)

build_dir = os.path.abspath(build_dirs[0])
source_root = os.path.abspath('.')
phy_dir = os.path.join(build_dir, 'prj', 'HX4S20_HDMI_Player_Runs', 'phy_1')
compiler = "C:/fpga/bin/td_commands_prompt.exe"
if not os.path.exists(compiler):
    compiler = "C:/Anlogic/TD6.2.1/bin/td_commands_prompt.exe"

seeds = [2, 1, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 18, 20, 25, 42, 50]

print(f"Build directory: {build_dir}")
print(f"Phy directory: {phy_dir}")
print(f"Compiler: {compiler}")

for seed in seeds:
    print(f"\n==========================================")
    print(f"Testing Place Seed: {seed}")
    print(f"==========================================")
    
    # Remove old status, markers, and intermediate placement/route DBs
    for f in ['.bitgen.end.f', '.opt_route.end.f', '.opt_place.end.f',
              '.bitgen.begin.f', '.opt_route.begin.f', '.opt_place.begin.f',
              '.bitgen.error.f', '.opt_route.error.f', '.opt_place.error.f',
              'route_flow.status', 'place_flow.status', 'HX4S20_HDMI_Player.bit',
              'HX4S20_HDMI_Player_place.db', 'HX4S20_HDMI_Player_pr.db', 'HX4S20_HDMI_Player_eco_pr.db']:
        fp = os.path.join(phy_dir, f)
        if os.path.exists(fp):
            try:
                os.remove(fp)
            except Exception:
                pass
            
    env = os.environ.copy()
    env['HX4S20_PLACE_SEED'] = str(seed)
    
    # Run compiler
    log_file = os.path.join(phy_dir, f'build_console_seed_{seed}.log')
    with open(log_file, 'w', encoding='utf-8', errors='ignore') as log_out:
        p = subprocess.run([compiler, 'HX4S20_HDMI_Player.tcl'], cwd=phy_dir, env=env, stdout=log_out, stderr=subprocess.STDOUT)
    
    status_file = os.path.join(phy_dir, 'route_flow.status')
    if os.path.exists(status_file):
        with open(status_file, 'r', encoding='utf-8', errors='ignore') as sf:
            status_text = sf.read()
            
        s_match = re.search(r"Setup\s*:\s*WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)", status_text)
        h_match = re.search(r"Hold\s*:\s*WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)", status_text)
        
        if s_match and h_match:
            s_wns = int(s_match.group(1))
            s_feps = int(s_match.group(3))
            h_wns = int(h_match.group(1))
            h_feps = int(h_match.group(3))
            
            print(f"Seed {seed} Result: Setup WNS={s_wns}ps (FEPS={s_feps}), Hold WNS={h_wns}ps (FEPS={h_feps})")
            
            if s_wns >= 0 and s_feps == 0 and h_wns >= 0 and h_feps == 0:
                print(f"\n>>> SUCCESS: TIMING CLOSED FOR SEED {seed}! <<<")
                
                # Copy bitstream to source root
                bit_src = os.path.join(phy_dir, 'HX4S20_HDMI_Player.bit')
                bit_dst = os.path.join(source_root, 'HX4S20_HDMI_Player.bit')
                if os.path.exists(bit_src):
                    shutil.copyfile(bit_src, bit_dst)
                    print(f"Copied bitstream to {bit_dst}")
                
                # Run collection script
                collect_script = os.path.join(source_root, 'tools', 'collect_extension_build.ps1')
                cmd = f'powershell -NoProfile -ExecutionPolicy Bypass -File "{collect_script}" -BuildRoot "{build_dir}" -Version "v2_6_2"'
                res = subprocess.run(cmd, shell=True)
                print(f"Collect exit code: {res.returncode}")
                exit(0)
    else:
        print(f"Seed {seed} failed (no route_flow.status). Check {log_file}")

print("No seed closed timing.")
exit(1)
