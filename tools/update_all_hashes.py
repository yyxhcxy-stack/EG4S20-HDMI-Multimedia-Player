import os
import hashlib
import json

manifest_path = 'output/verification/all_suites_manifest.json'
with open(manifest_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

for root, _, files in os.walk('src'):
    for f in files:
        full_path = os.path.join(root, f)
        rel_path = os.path.normpath(full_path)
        with open(full_path, 'rb') as fp:
            h = hashlib.sha256(fp.read()).hexdigest().lower()
        data['rtl_sha256'][rel_path] = h

with open(manifest_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)

print('All source hashes updated successfully in all_suites_manifest.json')
