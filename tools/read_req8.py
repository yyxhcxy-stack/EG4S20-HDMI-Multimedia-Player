import json

with open(r'C:\Users\ly\.gemini\antigravity\brain\40b3ae6d-de44-4abb-9e2d-491feb9a7eed\.system_generated\logs\transcript.jsonl', 'r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

for i in range(21350, min(21450, len(lines))):
    obj = json.loads(lines[i])
    t = obj.get('type')
    content = str(obj.get('content', ''))
    if t in ('USER_INPUT', 'PLANNER_RESPONSE'):
        print(f"=== Line {i}: {t} ===")
        # decode safely
        print(content[:1500])
