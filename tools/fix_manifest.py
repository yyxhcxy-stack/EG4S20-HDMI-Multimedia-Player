import os
import hashlib
import json

BASE = r"D:\FPGA\HX4S20_v2.6.2_d5faf4c_handoff\project"
RTL_DIR = os.path.join(BASE, "src", "rtl")
MANIFEST = os.path.join(BASE, "output", "verification", "all_suites_manifest.json")

with open(MANIFEST, "r", encoding="utf-8") as f:
    data = json.load(f)

new_rtl_sha = {}
for root, _, files in os.walk(RTL_DIR):
    for f in files:
        if f.endswith(".v"):
            full = os.path.join(root, f)
            rel = os.path.relpath(full, BASE)
            with open(full, "rb") as fp:
                h = hashlib.sha256(fp.read()).hexdigest().lower()
            new_rtl_sha[rel] = h

print(f"Total .v files found in src/rtl: {len(new_rtl_sha)}")
data["rtl_sha256"] = new_rtl_sha

with open(MANIFEST, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)

print("Manifest successfully updated with exact RTL inventory.")
