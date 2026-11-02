from PIL import Image

pattern_v3 = [
    # 0123456789012345
    "......RRRRRRRRRR", # 0
    "....BB..........", # 1
    "....BB.RRRRRRRR.", # 2
    "...BBB..........", # 3
    "...BBB..RRRRRRR.", # 4
    "...BBBB.........", # 5
    "...BBBB.RRRRRR..", # 6
    "..BBBBB.........", # 7
    "..BB.BB..RRRRR..", # 8
    "..BB..BB........", # 9
    ".BB...BB.RRRR...", # 10
    ".BB...BB........", # 11
    ".BB....BB.RRR...", # 12
    "BB.....BB.......", # 13
    "BBBBBB..BB.RR...", # 14
    "BBBBBB..BB......"  # 15
]

# Save standalone 16x16 and scaled 32x, 64x, 128x
img16 = Image.new('RGB', (16, 16), (255, 255, 255))
navy = (33, 43, 74) # #212B4A
red = (238, 24, 24) # #EE1818

for y in range(16):
    for x in range(16):
        ch = pattern_v3[y][x]
        if ch == 'B':
            img16.putpixel((x, y), navy)
        elif ch == 'R':
            img16.putpixel((x, y), red)

img16.resize((256, 256), Image.Resampling.NEAREST).save("tools/logo_white_256.png")

# Now dark background
img_dark = Image.new('RGB', (16, 16), (18, 28, 42))
# For dark background, let's test #2A4E88 vs #212B4A
for y in range(16):
    for x in range(16):
        ch = pattern_v3[y][x]
        if ch == 'B':
            img_dark.putpixel((x, y), (42, 78, 136)) # Slightly enhanced navy for dark background
        elif ch == 'R':
            img_dark.putpixel((x, y), red)

img_dark.resize((256, 256), Image.Resampling.NEAREST).save("tools/logo_dark_256.png")
print("Saved tools/logo_white_256.png and tools/logo_dark_256.png")
