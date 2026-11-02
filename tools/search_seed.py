import os
import sys
import shutil
import subprocess
import re

TD_COMPILER = r"D:/TD/bin/td_commands_prompt.exe"
BASE_DIR = r"D:/FPGA/HX4S20_v2.6.2_d5faf4c_handoff/project"
BUILD_ROOT = r"D:/FPGA/HX4S20_v2.6.2_d5faf4c_handoff/project/build_ext_20261012_192821"
RUNS_DIR = os.path.join(BUILD_ROOT, "prj", "HX4S20_HDMI_Player_Runs")
SYN_DIR = os.path.join(RUNS_DIR, "syn_1")
PHY_TEMPLATE = os.path.join(RUNS_DIR, "phy_1")

def parse_timing(status_file):
    if not os.path.isfile(status_file):
        return None
    with open(status_file, "r", encoding="utf-8", errors="ignore") as f:
        text = f.read()
    
    setup_m = re.search(r"Setup\s*:\s*WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)", text)
    hold_m  = re.search(r"Hold\s*:\s*WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)", text)
    if setup_m and hold_m:
        setup_wns = int(setup_m.group(1))
        setup_feps = int(setup_m.group(3))
        hold_wns = int(hold_m.group(1))
        hold_feps = int(hold_m.group(3))
        return setup_wns, setup_feps, hold_wns, hold_feps
    return None

def test_seed(seed):
    phy_dir = os.path.join(RUNS_DIR, f"phy_seed_{seed}")
    os.makedirs(phy_dir, exist_ok=True)
    
    # Copy essential files
    for fname in ["settings.cfg", "HX4S20_HDMI_Player.tcl", "HX4S20_HDMI_Player.prj", "voice_emergency_64kb.mif", "font_rom_8x16.mif"]:
        src = os.path.join(PHY_TEMPLATE, fname)
        dst = os.path.join(phy_dir, fname)
        if os.path.isfile(src):
            shutil.copyfile(src, dst)
            
    print(f"\n==========================================")
    print(f"Testing Place Seed: {seed} in {phy_dir}")
    print(f"==========================================")
    
    env = os.environ.copy()
    env["HX4S20_PLACE_SEED"] = str(seed)
    
    log_file = os.path.join(phy_dir, "build_console.log")
    with open(log_file, "w", encoding="utf-8") as out_f:
        p = subprocess.Popen(
            [TD_COMPILER, "HX4S20_HDMI_Player.tcl"],
            cwd=phy_dir,
            env=env,
            stdin=subprocess.PIPE,
            stdout=out_f,
            stderr=subprocess.STDOUT,
            text=True
        )
        p.communicate(input="exit\n")
        
    status_file = os.path.join(phy_dir, "route_flow.status")
    timing = parse_timing(status_file)
    if timing:
        s_wns, s_feps, h_wns, h_feps = timing
        print(f"Seed {seed} Result: Setup WNS={s_wns}ps (FEPS={s_feps}), Hold WNS={h_wns}ps (FEPS={h_feps})")
        if s_wns >= 0 and s_feps == 0 and h_wns >= 0 and h_feps == 0:
            print(f">>> TIMING CLOSED FOR SEED {seed}! <<<")
            return True, phy_dir
    else:
        print(f"Seed {seed} failed to generate timing status.")
    return False, phy_dir

if __name__ == "__main__":
    seeds_to_test = [1, 2, 3, 5, 7, 11, 13, 20, 42]
    found = False
    for s in seeds_to_test:
        closed, pdir = test_seed(s)
        if closed:
            found = True
            print(f"Golden seed found: {s}")
            # Overwrite phy_1 with the golden seed directory files
            for item in os.listdir(pdir):
                sitem = os.path.join(pdir, item)
                ditem = os.path.join(PHY_TEMPLATE, item)
                if os.path.isfile(sitem):
                    shutil.copyfile(sitem, ditem)
            print(f"Copied golden results to {PHY_TEMPLATE}")
            break
            
    if not found:
        print("No seed closed timing among tested seeds.")
        sys.exit(1)
    else:
        print("Success!")
        sys.exit(0)
