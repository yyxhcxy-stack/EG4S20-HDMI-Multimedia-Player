"""Run the actual Verilog through Yosys CXXRTL, then compare output pixels.

Requires yowasp-yosys and g++ (no vendor IP models needed). The old mathematical
scripts are supplemental checks; this runner elaborates the changed RTL itself.
"""
from pathlib import Path
import argparse
import hashlib
import json
from datetime import datetime, timezone
import importlib.util
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output" / "verification"


def run(args, *, stdout=None):
    subprocess.run(args, cwd=ROOT, check=True, stdout=stdout, stderr=subprocess.STDOUT)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (ROOT / "output/scaling_preview").mkdir(parents=True, exist_ok=True)
    yosys = shutil.which("yowasp-yosys")
    compiler = shutil.which("g++")
    if not yosys or not compiler:
        sys.exit("Install yowasp-yosys and provide g++ on PATH before running RTL tests.")
    package = Path(importlib.util.find_spec("yowasp_yosys").origin).parent
    include = package / "share/include/backends/cxxrtl/runtime"
    suites = [
        ("bank_lifecycle", "sd_card_bmp", "tools/rtl_tests/bank_transport_mock.v src/rtl/SD/sd_card_bmp.v"),
        ("cdc_reset", "cdc_reset", "src/rtl/audio_snapshot_cdc.v tools/rtl_tests/cdc_reset.v"),
        ("audio_system", "audio_system", "tools/rtl_tests/voice_rom_model.v src/rtl/audio_voice_interp.v src/rtl/audio_synth.v src/rtl/audio_i2s_tx.v src/rtl/I2S_receiver.v src/rtl/audio_output_stage.v src/rtl/audio_snapshot_cdc.v src/rtl/audio_spectrum_dft.v src/rtl/audio_spectrum_bridge.v src/rtl/audio_arc_calculate.v tools/rtl_tests/audio_system.v"),
        ("audio_synth", "audio_synth", "tools/rtl_tests/voice_rom_model.v src/rtl/audio_voice_interp.v src/rtl/audio_synth.v"),
        ("audio_output", "audio_output_stage", "src/rtl/audio_output_stage.v"),
        ("lcd_snapshot", "lcd_snapshot", "src/rtl/audio_snapshot_cdc.v src/rtl/font_rom_8x8.v src/rtl/lcd_st7735_telemetry.v output/verification/lcd_height_map.v tools/rtl_tests/lcd_snapshot.v"),
        ("audio_i2s", "audio_i2s", "src/rtl/audio_i2s_tx.v src/rtl/I2S_receiver.v tools/rtl_tests/audio_i2s.v"),
        ("spectrum_dft", "audio_spectrum_dft", "src/rtl/audio_spectrum_dft.v"),
        ("enable_equivalence", "enable_equivalence", "src/rtl/audio_spectrum_dft.v output/verification/audio_spectrum_dft_reference.v tools/rtl_tests/enable_equivalence.v"),
        ("sd_command_equivalence", "sd_command_equivalence", "src/rtl/SD/sd_card_cmd.v output/verification/sd_card_cmd_reference.v tools/rtl_tests/sd_command_equivalence.v"),
        ("storage_pressure", "scaling_pipeline", "src/rtl/scaling_geometry.v src/rtl/scaling_core.v src/rtl/scaling_pipeline.v"),
        ("scaling_geometry", "scaling_geometry", "src/rtl/scaling_geometry.v"),
        ("frame_boundary", "frame_boundary", "src/rtl/SD/color_bar.v src/rtl/SD/video_timing_data.v src/rtl/scaling_geometry.v src/rtl/scaling_core.v src/rtl/scaling_pipeline.v tools/rtl_tests/frame_boundary.v"),
        ("seg_digits", "seg_digits", "output/verification/seg_digits.v"),
        ("keys", "key3_current", "output/verification/key3_current.v"),
        ("source_fifo", "scaling_source_fifo", "src/rtl/scaling_source_fifo.v"),
        ("adjust", "video_adjust_lut", "src/rtl/video_adjust_lut.v"),        ("osd", "osd_display", "src/rtl/video_adjust_lut.v src/rtl/font_rom_8x16.v src/rtl/audio_snapshot_cdc.v src/rtl/audio_spectrum_dft.v src/rtl/audio_spectrum_bridge.v src/rtl/osd_display.v"),
        ("parameter_feedback", "osd_display", "src/rtl/video_adjust_lut.v src/rtl/font_rom_8x16.v src/rtl/audio_snapshot_cdc.v src/rtl/audio_spectrum_dft.v src/rtl/audio_spectrum_bridge.v src/rtl/osd_display.v"),
        ("osd_bram", "osd_display", "tools/rtl_tests/eg_bram_model.v src/rtl/video_adjust_lut.v output/verification/font_vendor.v src/rtl/audio_snapshot_cdc.v src/rtl/audio_spectrum_dft.v output/verification/spectrum_vendor.v output/verification/osd_vendor.v"),
        ("scaling_system", "scaling_system", "src/rtl/scaling_geometry.v src/rtl/scaling_core.v src/rtl/scaling_pipeline.v src/rtl/scaling_source_fifo.v src/rtl/SD/frame_fifo_read.v tools/rtl_tests/scaling_system.v"),
        ("scaling_core", "scaling_core", "src/rtl/scaling_geometry.v src/rtl/scaling_core.v"),
        ("scaling_pipeline", "scaling_pipeline", "src/rtl/scaling_geometry.v src/rtl/scaling_core.v src/rtl/scaling_pipeline.v"),
        ("transition", "video_transition", "src/rtl/video_transition.v"),
        ("bmp", "bmp_read", "src/rtl/SD/bmp_read.v"),
        ("frame_reader", "frame_fifo_read", "src/rtl/SD/frame_fifo_read.v"),
        ("frame_writer", "frame_fifo_write", "src/rtl/SD/frame_fifo_write.v"),
        ("frame_writer256", "frame_fifo_write", "src/rtl/SD/frame_fifo_write.v"),
        ("fonts", "font_test", "tools/rtl_tests/eg_bram_model.v output/verification/font_vendor.v src/rtl/font_rom_8x8.v tools/rtl_tests/font_test.v"),
        ("uart", "uart_scada_controller", "src/rtl/marquee_store.v src/rtl/uart_scada_controller.v"),
        ("marquee_control", "uart_scada_controller", "src/rtl/marquee_store.v src/rtl/uart_scada_controller.v"),
        ("marquee_osd", "osd_display", "src/rtl/video_adjust_lut.v src/rtl/font_rom_8x16.v src/rtl/audio_snapshot_cdc.v src/rtl/audio_spectrum_dft.v src/rtl/audio_spectrum_bridge.v src/rtl/osd_display.v"),
    ]
    available_suites = [item[0] for item in suites]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', nargs='+', choices=[item[0] for item in suites],
                        help='Run only selected suites; omitted means all suites.')
    selected = parser.parse_args().suite
    if selected:
        suites = [item for item in suites if item[0] in selected]
    source_hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in sorted((ROOT / "src/rtl").rglob("*.v"))}
    test_inputs=list((ROOT/"tools/rtl_tests").rglob("*"))
    test_inputs += [ROOT/"tools"/name for name in ("verify_extension_rtl.py","audio_reference.py","verify_audio_reference.py","marquee_minimal_reference.py","display_architecture_reference.py")]
    test_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(test_inputs) if p.is_file()}
    reference_revisions={rev:subprocess.check_output(["git","rev-parse",rev+"^{commit}"],cwd=ROOT).decode().strip() for rev in ("baseline-v2.6.1-flash","8f152c1")}
    memory_hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in sorted((ROOT / "src/rtl").rglob("*")) if p.is_file() and p.suffix.lower() in (".hex", ".mif")}
    import re
    glyphs = {int(i): int(v,16) for i,v in re.findall(r"glyph_rom\[(\d+)\]\s*=\s*8'h([0-9A-Fa-f]+)", (ROOT/"src/rtl/font_rom_8x16.v").read_text(encoding="utf-8"))}
    glyph_hex = [int(v,16) for v in (ROOT/"src/rtl/font_rom_8x16.hex").read_text().split()]
    glyph_mif = {int(i,16):int(v,16) for i,v in re.findall(r"([0-9A-Fa-f]{4})\s*:\s*([0-9A-Fa-f]{2})\s*;", (ROOT/"src/rtl/font_rom_8x16.mif").read_text())}
    assert len(glyphs)==len(glyph_hex)==len(glyph_mif)==2048
    assert all(glyphs[i]==glyph_hex[i]==glyph_mif[i] for i in range(2048)), "Font initialization assets diverged"
    started = datetime.now(timezone.utc).isoformat()
    (OUT / "font_vendor.v").write_bytes((ROOT / "src/rtl/font_rom_8x16.v").read_bytes().replace(b"`ifdef YOSYS", b"`ifdef FORCE_BEHAVIORAL_RAM"))
    for name, top, source in suites:
        if name == "lcd_snapshot":
            lcd_text=(ROOT/"src/rtl/lcd_st7735_telemetry.v").read_text(encoding="utf-8")
            begin=lcd_text.index("    function [4:0] spectrum_height;")
            end=lcd_text.index("    endfunction",begin)+len("    endfunction")
            (OUT/"lcd_height_map.v").write_text("module lcd_height_map(input [4:0] height,output [4:0] mapped);\n"+lcd_text[begin:end]+"\nassign mapped=spectrum_height(height);endmodule\n")
        if name == "enable_equivalence":
            reference = subprocess.check_output(["git","show","baseline-v2.6.1-flash:src/rtl/audio_spectrum_dft.v"],cwd=ROOT)
            reference = reference.replace(b"module audio_spectrum_dft",b"module audio_spectrum_dft_reference",1)
            (OUT / "audio_spectrum_dft_reference.v").write_bytes(reference)
        if name == "sd_command_equivalence":
            reference = subprocess.check_output(["git","show","baseline-v2.6.1-flash:src/rtl/SD/sd_card_cmd.v"],cwd=ROOT)
            reference = reference.replace(b"module sd_card_cmd(",b"module sd_card_cmd_reference(",1)
            (OUT / "sd_card_cmd_reference.v").write_bytes(reference)
        if name == "seg_digits":
            text = (ROOT / "src/rtl/top_tf_hdmi_audio.v").read_text(encoding="utf-8")
            begin=text.index("function [7:0] fn_vu_bcd;")
            end=text.index("function [7:0] fn_seg_code;",begin)
            (OUT / "seg_digits.v").write_text("module seg_digits(input [6:0] vu_amp,output [3:0] vu_tens,vu_ones);\n"+text[begin:end]+"endmodule\n",encoding="utf-8")
        if name == "keys":
            original = subprocess.check_output(["git", "show", "c1d62bb:src/rtl/top_tf_hdmi_audio.v"], cwd=ROOT).decode("utf-8")
            current = (ROOT / "src/rtl/top_tf_hdmi_audio.v").read_text(encoding="utf-8")
            original = original.replace("hud_en      <= 1'b1;", "hud_en      <= 1'b0;")
            for module, text in [("key3_current", current),("key3_reference", original)]:
                begin = text.index("localparam K3_IDLE")
                end = text.index("// KEY4", begin)
                declarations = "reg [1:0] key3_sync; reg [3:0] key3_state; reg [26:0] key3_timer;\n"
                if module == "key3_current":
                    declarations += "reg k3_debounce_early,k3_long_early,k3_click_early,k3_cool_early; wire k3_timer_running=|key3_timer;\n"
                header = f"module {module}(input clk,rst_all,key3_gated,cmd_scale_vld,cmd_vol_vld,cmd_alpha_vld,input [1:0] cmd_scale_val,cmd_alpha_val,input [2:0] cmd_vol_val,output reg [1:0] scale_mode,alpha_mode,output reg [2:0] vol_mode,output reg hud_en);\n"
                (OUT / f"{module}.v").write_text(header + declarations + text[begin:end] + "endmodule\n", encoding="utf-8")
            with (OUT / "key3_reference_elaborate.log").open("w",encoding="utf-8") as log:
                run([yosys,"-Q","-T","-p","read_verilog output/verification/key3_reference.v; hierarchy -top key3_reference; write_cxxrtl -g0 output/verification/key3_reference.cc"],stdout=log)
        if name in ("osd", "osd_bram", "marquee_osd", "parameter_feedback"):
            if name == "osd_bram":
                vendor_text = (ROOT / "src/rtl/osd_display.v").read_bytes().replace(b"`ifdef YOSYS", b"`ifdef FORCE_BEHAVIORAL_RAM")
                (OUT / "osd_vendor.v").write_bytes(vendor_text)
                (OUT / "spectrum_vendor.v").write_bytes((ROOT / "src/rtl/audio_spectrum_bridge.v").read_bytes().replace(b"`ifdef YOSYS", b"`ifdef FORCE_BEHAVIORAL_RAM"))
            original = subprocess.check_output(["git", "show", "8f152c1:src/rtl/osd_display.v"], cwd=ROOT)
            reference_text = original.decode("utf-8").replace("module osd_display", "module osd_reference", 1)
            reference_text = reference_text.replace("input  wire        video_clk", "input wire [79:0] reference_bars, reference_peaks,\n    input  wire        video_clk", 1)
            start = reference_text.index("            // 60Hz Studio Ballistics")
            end = reference_text.index("    // Multi-Screen Synergy:", start)
            reference_text = reference_text[:start] + "        end\n    end\n    always @* begin\n" + "".join(f"      spec_bar_h[{i}]=reference_bars[{i*5}+:5]; spec_bar_peak[{i}]=reference_peaks[{i*5}+:5];\n" for i in range(16)) + "    end\n\n" + reference_text[end:]
            from marquee_minimal_reference import adapt_hud_reference,adapt_marquee_reference
            reference_text = adapt_marquee_reference(adapt_hud_reference(reference_text))
            from display_architecture_reference import adapt_architecture_reference
            reference_text = adapt_architecture_reference(reference_text)
            (OUT / "osd_reference.v").write_text(reference_text, encoding="utf-8")
            reference_digest = hashlib.sha256(reference_text.encode("utf-8") + (ROOT / "src/rtl/video_adjust_lut.v").read_bytes()
                                              + (ROOT / "src/rtl/font_rom_8x16.v").read_bytes()).hexdigest()
            reference_stamp = OUT / "osd_reference_inputs.sha256"
            if not ((OUT / "osd_reference.cc").exists() and reference_stamp.exists()
                    and reference_stamp.read_text() == reference_digest):
                with (OUT / "osd_reference_elaborate.log").open("w", encoding="utf-8") as log:
                    run([yosys, "-Q", "-T", "-p", "read_verilog src/rtl/video_adjust_lut.v src/rtl/font_rom_8x16.v output/verification/osd_reference.v; hierarchy -top osd_reference; write_cxxrtl -g0 output/verification/osd_reference.cc"], stdout=log)
                reference_stamp.write_text(reference_digest)
        with (OUT / f"{name}_elaborate.log").open("w", encoding="utf-8") as log:
            run([yosys, "-Q", "-T", "-p",
                 f"read_verilog {source}; {'chparam -set CLK_FREQ_HZ 1000 -set AUTO_PLAY_SEC 20 sd_card_bmp; ' if name == 'bank_lifecycle' else 'chparam -set BURST_SIZE 256 frame_fifo_write; ' if name == 'frame_writer256' else ''}hierarchy -check -top {top}; proc; check -assert; write_cxxrtl -g0 output/verification/{name}.cc"], stdout=log)
        exe = OUT / f"{name}_test.exe"
        compiler_flags = ["-DPARAMETER_TEST"] if name == "parameter_feedback" else ["-DMARQUEE_TEST"] if name == "marquee_osd" else ["-DANLOGIC_RAM_MODEL"] if name == "osd_bram" else ["-DWRITER256"] if name == "frame_writer256" else []
        bench_name = "osd" if name in ("osd_bram","marquee_osd","parameter_feedback") else "frame_writer" if name == "frame_writer256" else name
        run([compiler, "-std=c++17", "-O2", *compiler_flags, "-I", str(include), "-I", str(OUT),
             str(ROOT / f"tools/rtl_tests/{bench_name}_test.cpp"), "-o", str(exe)])
        result = subprocess.run([str(exe)], cwd=ROOT, capture_output=True, text=True)
        if name == "marquee_control" and result.returncode == 0:
            (OUT / "uart_vendor.v").write_bytes((ROOT / "src/rtl/uart_scada_controller.v").read_bytes().replace(b"`ifdef YOSYS", b"`ifdef FORCE_BEHAVIORAL_RAM"))
            with (OUT / "marquee_control_vendor_elaborate.log").open("w",encoding="utf-8") as log:
                run([yosys,"-Q","-T","-p","read_verilog tools/rtl_tests/eg_bram_model.v src/rtl/marquee_store.v output/verification/uart_vendor.v; hierarchy -check -top uart_scada_controller; proc; check -assert; write_cxxrtl -g0 output/verification/marquee_control_vendor.cc"],stdout=log)
            vendor_exe=OUT / "marquee_control_vendor_test.exe"
            run([compiler,"-std=c++17","-O2","-DUART_BRAM_MODEL","-I",str(include),"-I",str(OUT),str(ROOT/"tools/rtl_tests/marquee_control_test.cpp"),"-o",str(vendor_exe)])
            vendor=subprocess.run([str(vendor_exe)],cwd=ROOT,capture_output=True,text=True)
            result.stdout += "Vendor DP RAM model: " + vendor.stdout + vendor.stderr
            result.returncode=vendor.returncode
        if name == "audio_system" and result.returncode == 0:
            actual = subprocess.run([str(exe), "actual_pll"], cwd=ROOT, capture_output=True, text=True)
            result.stdout += actual.stdout + actual.stderr
            result.returncode = actual.returncode
        if name == "spectrum_dft" and result.returncode == 0:
            from verify_audio_reference import verify
            result.stdout += verify() + "\n"
        (OUT / f"{name}_result.txt").write_text(result.stdout + result.stderr, encoding="utf-8")
        print(result.stdout, end="")
        if result.returncode:
            sys.exit(result.stderr or f"{name} RTL regression failed")
    changed = [name for name, digest in source_hashes.items()
               if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest]
    changed += [name for name,digest in memory_hashes.items() if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest]
    changed += [name for name,digest in test_hashes.items() if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest]
    if changed:
        sys.exit("RTL changed during regression; rerun on stable sources: " + ", ".join(changed))
    metadata = {"started_utc": started, "finished_utc": datetime.now(timezone.utc).isoformat(),
                "git_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip(),
                "test_sha256":test_hashes,"reference_revisions":reference_revisions, "suites": [item[0] for item in suites], "rtl_sha256": source_hashes, "memory_sha256": memory_hashes, "passed": True}
    (OUT / "rtl_regression_manifest.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    for name, _, _ in suites:
        (OUT / f"{name}_manifest.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    records = []
    for name in available_suites:
        evidence = OUT / f"{name}_manifest.json"
        if not evidence.exists(): break
        item = json.loads(evidence.read_text(encoding="utf-8"))
        if not item["passed"] or name not in item["suites"] or item["rtl_sha256"] != source_hashes or item.get("memory_sha256") != memory_hashes or item.get("test_sha256") != test_hashes or item.get("reference_revisions") != reference_revisions: break
        result = OUT / f"{name}_result.txt"
        if not result.exists() or not result.read_text(encoding="utf-8").startswith("PASS"): break
        records.append({"suite": name, "manifest": item,
                        "result_sha256": hashlib.sha256(result.read_bytes()).hexdigest()})
    if len(records) == len(available_suites):
        merged = {"passed": True, "suites": available_suites, "rtl_sha256": source_hashes,
                  "memory_sha256":memory_hashes,"test_sha256":test_hashes,"reference_revisions":reference_revisions,"verified_git_commit": metadata["git_commit"], "records": records}
        (OUT / "all_suites_manifest.json").write_text(json.dumps(merged, indent=2), encoding="utf-8")
    print("Selected extension RTL suites passed." if selected else "All extension RTL suites passed.")


if __name__ == "__main__":
    main()
