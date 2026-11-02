import json

with open(r'C:\Users\ly\.gemini\antigravity\brain\40b3ae6d-de44-4abb-9e2d-491feb9a7eed\.system_generated\logs\transcript_full.jsonl', 'r', encoding='utf-8', errors='ignore') as f:
    for i, line in enumerate(f):
        if '4dcfa3f7-7195-47df-93c6-e24e3c300981' in line:
            obj = json.loads(line)
            print(f"Line {i}:")
            print(str(obj)[:1500])
