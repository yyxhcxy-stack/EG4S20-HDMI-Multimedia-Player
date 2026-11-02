import pypdf
reader = pypdf.PdfReader(r'C:\fpga\saitijiexi.pdf')
print("Total pages:", len(reader.pages))
for i, page in enumerate(reader.pages):
    txt = page.extract_text()
    if '扩展' in txt or '状态' in txt or '图层' in txt or '1.' in txt:
        print(f"=== Page {i+1} ===")
        for line in txt.split('\n'):
            if any(k in line for k in ['扩展', '状态', '图层', '空闲', '搜索', 'SDRAM', 'OSD', 'Logo', 'logo']):
                print("  ", line.strip())
