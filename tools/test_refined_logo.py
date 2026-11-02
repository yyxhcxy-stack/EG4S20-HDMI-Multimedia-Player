from PIL import Image

pattern_refined = [
    # 0123456789012345
    "......RRRRRRRRRR", # 0: Red stripe 0 (x=6..15)
    "....BB..........", # 1: Apex of A (x=4..5)
    "....BB.RRRRRRRR.", # 2: A (x=4..5) + Red stripe 1 (x=7..14)
    "...BBB..........", # 3: A expanding (x=3..5)
    "...BBB.RRRRRRRR.", # 4: A (x=3..5) + Red stripe 2 (x=7..14)
    "...BBB..........", # 5: A (x=3..5)
    "...BBBB.RRRRRR..", # 6: A (x=3..6) + Red stripe 3 (x=8..13)
    "..BBBBB.........", # 7: A (x=2..6)
    "..BBBBB.RRRRRR..", # 8: A (x=2..6) + Red stripe 4 (x=8..13)
    "..BB..BB........", # 9: A (x=2..3, 6..7)
    "..BB..BB.RRRR...", # 10: A (x=2..3, 6..7) + Red stripe 5 (x=9..12)
    ".BBB..BBB.......", # 11: A (x=1..3, 6..8)
    ".BBB..BBB.RRR...", # 12: A (x=1..3, 6..8) + Red stripe 6 (x=10..12)
    ".BB....BB.......", # 13: A (x=1..2, 7..8)
    "BBBBBB.BBB.RR...", # 14: A base (x=0..5, 7..9) + Red stripe 7 (x=11..12)
    "BBBBBB.BBB......"  # 15: A base (x=0..5, 7..9)
]

for y, row in enumerate(pattern_refined):
    print(f"{y:2d}: " + "".join(["  " if c=='.' else "BB" if c=='B' else "RR" for c in row]))

img = Image.new('RGB', (16, 16), (255, 255, 255))
navy = (33, 43, 74)
red = (217, 34, 49)

for y in range(16):
    for x in range(16):
        ch = pattern_refined[y][x]
        if ch == 'B':
            img.putpixel((x, y), navy)
        elif ch == 'R':
            img.putpixel((x, y), red)

scaled = img.resize((256, 256), Image.Resampling.NEAREST)
scaled.save(r'C:/fpga/HX4S20_HDMI_Player_完整交付包_v2.8_方向4全适配/01_工程完整源码/tools/refined_logo_256.png')
print("Saved refined_logo_256.png")
