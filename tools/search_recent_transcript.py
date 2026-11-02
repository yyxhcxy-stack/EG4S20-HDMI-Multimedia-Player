import json

with open(r'C:\Users\ly\.gemini\antigravity\brain\40b3ae6d-de44-4abb-9e2d-491feb9a7eed\.system_generated\logs\transcript.jsonl', 'r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

print(f"Total lines: {len(lines)}")
for i in range(max(0, len(lines)-150), len(lines)):
    obj = json.loads(lines[i])
    content = str(obj.get('content', ''))
    if '精进' in content or '扩展' in content or '赛题' in content or 'Logo' in content or 'logo' in content:
        print(f"--- Line {i} ({obj.get('type')}) ---")
        clean_content = content[:400].encode('ascii', errors='replace').decode('ascii')
        print(clean_content)
