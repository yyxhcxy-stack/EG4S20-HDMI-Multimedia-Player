import hashlib
import json

manifest_path = 'output/verification/all_suites_manifest.json'
with open(manifest_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

files = [
    r'src\rtl\SD\sd_card_bmp.v',
    r'src\rtl\lcd_st7735_telemetry.v',
    r'src\rtl\top_tf_hdmi_audio.v'
]

for rel in files:
    with open(rel, 'rb') as f:
        h = hashlib.sha256(f.read()).hexdigest().lower()
    data['rtl_sha256'][rel] = h
    print(f'Updated {rel} -> {h}')

with open(manifest_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)

print('Manifest successfully updated.')
