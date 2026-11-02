import json

with open(r'C:\Users\ly\.gemini\antigravity\brain\40b3ae6d-de44-4abb-9e2d-491feb9a7eed\.system_generated\logs\transcript_full.jsonl', 'r', encoding='utf-8', errors='ignore') as f:
    for i, line in enumerate(f):
        if i == 21882:
            obj = json.loads(line)
            content = obj.get('content', '')
            with open('tools/audit_findings.md', 'w', encoding='utf-8') as out:
                out.write(content)
            print("Wrote audit_findings.md successfully!")
            break
