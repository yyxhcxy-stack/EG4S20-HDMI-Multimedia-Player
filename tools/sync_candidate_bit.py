import shutil
import hashlib
import json

src_bit = "build_ext_20261012_192821/prj/HX4S20_HDMI_Player_Runs/phy_1/HX4S20_HDMI_Player.bit"
dst_bit1 = "output/extension_v2_6_2/HX4S20_HDMI_Player_v2_6_2_candidate.bit"
dst_bit2 = "output/extension_v2_6_2/board_candidate.bit"
dst_bit3 = "image.bit"

shutil.copyfile(src_bit, dst_bit1)
shutil.copyfile(src_bit, dst_bit2)
shutil.copyfile(src_bit, dst_bit3)

with open(src_bit, "rb") as f:
    sha = hashlib.sha256(f.read()).hexdigest().lower()

with open("output/extension_v2_6_2/build_result.json", "r", encoding="utf-8") as f:
    data = json.load(f)

data["artifact_sha256"]["bit"] = sha

with open("output/extension_v2_6_2/build_result.json", "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)

print(f"Successfully synchronized new bitstream with SHA256: {sha}")
