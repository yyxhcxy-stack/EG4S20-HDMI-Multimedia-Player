import json

with open(r'C:\Users\ly\.gemini\antigravity\brain\40b3ae6d-de44-4abb-9e2d-491feb9a7eed\.system_generated\logs\transcript.jsonl', 'r', encoding='utf-8', errors='ignore') as f:
    for i, line in enumerate(f):
        obj = json.loads(line)
        content = str(obj.get('content', ''))
        thinking = str(obj.get('thinking', ''))
        if '精进' in content or '精进' in thinking or '拓展' in content or '扩展1' in content:
            print(f"Line {i} content: {content[:300]}")
            if '精进' in thinking:
                print(f"Line {i} thinking: {thinking[:300]}")
