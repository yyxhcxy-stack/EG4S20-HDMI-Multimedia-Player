"""Prove the lifecycle regression fails on the original full controller."""
from pathlib import Path
import subprocess,shutil,importlib.util,hashlib,json
root=Path(__file__).resolve().parents[1]
out=root/'output/verification/bank_baseline_failure';out.mkdir(parents=True,exist_ok=True)
base=subprocess.check_output(['git','show','baseline-v2.6.1-flash:src/rtl/SD/sd_card_bmp.v'],cwd=root).decode('utf-8')
# Inputs are ignored on purpose: original design has no reader handoff.
base=base.replace('    input                       write_finish_toggle,','    input [1:0] reader_bank, input reader_valid,\n    input                       write_finish_toggle,')
(out/'sd_card_bmp.v').write_text(base,encoding='utf-8')
yosys=shutil.which('yowasp-yosys');cpp=shutil.which('g++')
inc=Path(importlib.util.find_spec('yowasp_yosys').origin).parent/'share/include/backends/cxxrtl/runtime'
with (out/'elaborate.log').open('w',encoding='utf-8') as log:
 subprocess.run([yosys,'-Q','-T','-p',f'read_verilog tools/rtl_tests/bank_transport_mock.v "{(out/"sd_card_bmp.v").as_posix()}"; chparam -set CLK_FREQ_HZ 1000 -set AUTO_PLAY_SEC 20 sd_card_bmp; hierarchy -check -top sd_card_bmp; proc; check -assert; write_cxxrtl -g0 "{(out/"bank_lifecycle.cc").as_posix()}"'],cwd=root,stdout=log,stderr=subprocess.STDOUT,check=True)
subprocess.run([cpp,'-O2','-std=c++17','-I'+str(out),'-I'+str(inc),str(root/'tools/rtl_tests/bank_lifecycle_test.cpp'),'-o',str(out/'test.exe')],cwd=root,check=True)
r=subprocess.run([str(out/'test.exe')],capture_output=True,text=True)
(out/'expected_failure.txt').write_text(r.stdout+r.stderr,encoding='utf-8')
assert r.returncode!=0 and 'Writer overwrote reader-owned bank before handoff' in r.stderr,(r.returncode,r.stdout,r.stderr)
proof={'passed':True,'baseline_expected_failure':True,'baseline':'baseline-v2.6.1-flash','result':r.stderr.strip(),'test_sha256':hashlib.sha256((root/'tools/rtl_tests/bank_lifecycle_test.cpp').read_bytes()).hexdigest(),'mock_sha256':hashlib.sha256((root/'tools/rtl_tests/bank_transport_mock.v').read_bytes()).hexdigest()}
(out/'manifest.json').write_text(json.dumps(proof,indent=2),encoding='utf-8')
print('PASS bank baseline failure reproduced: '+r.stderr.strip())
