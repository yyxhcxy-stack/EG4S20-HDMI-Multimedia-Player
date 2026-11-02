"""Audit optimization scope: unchanged clocks, constraints, controls, vendor IP and ROM."""
import hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE='baseline-v2.6.1-flash'
ALLOWED={'src/rtl/'+name for name in ('uart_scada_controller.v','top_tf_hdmi_audio.v','SD/sd_card_bmp.v','video_adjust_lut.v','SD/sd_card_cmd.v','SD/frame_fifo_write.v','audio_spectrum_dft.v','audio_snapshot_cdc.v','lcd_st7735_telemetry.v','marquee_store.v','osd_display.v','scaling_core.v','scaling_pipeline.v','video_transition.v')}
def verify():
    paths=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE],cwd=ROOT).decode('utf-8').splitlines()
    protected={};changes={}
    for path in paths:
        if not(path.startswith(('src/','prj/')) or path=='voice_emergency_64kb.mif'):continue
        original=subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
        current=(ROOT/path).read_bytes()
        if path not in ALLOWED:
            assert current==original,'Protected clocks/constraints/control/IP/source changed: '+path
            protected[path]=hashlib.sha256(current).hexdigest()
        elif current!=original:changes[path]={'baseline_sha256':hashlib.sha256(original).hexdigest(),'current_sha256':hashlib.sha256(current).hexdigest()}
    for p in (ROOT/'src').rglob('*'):
        if p.is_file() and p.suffix.lower() in ('.v','.mif','.hex','.sdc','.adc'):assert p.relative_to(ROOT).as_posix() in paths,'Unreviewed new source: '+str(p)
    result={'passed':True,'baseline':subprocess.check_output(['git','rev-parse',BASE+'^{commit}'],cwd=ROOT).decode().strip(),'protected_sha256':protected,'changed_sources':changes,'frequencies_unchanged':True,'timing_exceptions_unchanged':True}
    out=ROOT/'output/verification/v262_scope.json';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(f'PASS architecture scope: {len(protected)} protected source/ROM/IP/constraints/flow files unchanged, {len(changes)} reviewed RTL changes')
if __name__=='__main__':verify()
