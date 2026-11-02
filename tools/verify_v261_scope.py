"""Reject importing unrelated v2.7/v2.8 video changes into the v2.6 minimal build."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = '3f33674fdc745da6b67bb4786a1e246fdf7fe639'
ALLOWED = {'src/rtl/osd_display.v', 'src/rtl/top_tf_hdmi_audio.v',
           'src/rtl/uart_scada_controller.v', 'src/rtl/marquee_store.v',
           'prj/HX4S20_HDMI_Player.al'}


def verify():
    paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASE], cwd=ROOT).decode('utf-8').splitlines()
    protected = {}
    for path in paths:
        if not (path.startswith(('src/', 'prj/')) or path == 'voice_emergency_64kb.mif') or path in ALLOWED:
            continue
        original = subprocess.check_output(['git', 'show', BASE + ':' + path], cwd=ROOT)
        assert (ROOT / path).read_bytes() == original, 'Unrelated baseline file changed: ' + path
        protected[path] = hashlib.sha256(original).hexdigest()
    assert len(protected) > 40
    for p in (ROOT / 'src').rglob('*'):
        if p.is_file() and p.suffix.lower() in ('.v', '.mif', '.hex', '.sdc', '.adc'):
            path = p.relative_to(ROOT).as_posix()
            assert path in paths or path in ALLOWED, 'Unexpected new source: ' + path
    result = {'passed': True, 'baseline': BASE, 'protected_sha256': protected,
              'changed_source_sha256': {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in ALLOWED}}
    out = ROOT / 'output/verification/v261_scope.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(f'PASS minimal scope: {len(protected)} baseline source/IP/constraint/flow files byte-identical')


if __name__ == '__main__':
    verify()
