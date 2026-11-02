from PIL import Image
import numpy as np

# Load original
img = Image.open(r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792815271765_9cee6115.jpg').convert('RGB')
arr = np.array(img)
mask = np.min(arr, axis=2) < 220
ys, xs = np.where(mask)
cropped = arr[ys.min():ys.max()+1, xs.min():xs.max()+1]

# Let's save a side-by-side comparison of different 16x16 rasterizations
# Option 1: Hand-crafted based on exact geometry
pattern_v1 = [
    # 0123456789012345
    "......RRRRRRRRRR", # 0: stripe 0 (x=6..15)
    "....BB..........", # 1: apex of A (x=4..5)
    "....BB.RRRRRRRR.", # 2: stripe 1 (x=7..14) + A (x=4..5)
    "...BBBB.........", # 3: A expanding (x=3..6)
    "...BBBB.RRRRRRR.", # 4: stripe 2 (x=8..14) + A (x=3..6)
    "...BBBB.........", # 5: A (x=3..6)
    "..BB..BB.RRRRRR.", # 6: stripe 3 (x=9..14) + A (x=2..3, 6..7) - or hole starts?
    "..BB..BB........", # 7: A (x=2..3, 6..7)
    "..BB..BB..RRRRR.", # 8: stripe 4 (x=10..14) + A (x=2..3, 6..7)
    ".BB....BB.......", # 9: A (x=1..2, 7..8)
    ".BB....BB..RRRR.", # 10: stripe 5 (x=11..14) + A (x=1..2, 7..8)
    ".BB....BB.......", # 11: A (x=1..2, 7..8)
    "BB......BB..RRR.", # 12: stripe 6 (x=12..14) + A (x=0..1, 8..9)
    "BB......BB......", # 13: A (x=0..1, 8..9)
    "BBBBBB...BB..RR.", # 14: stripe 7 (x=13..14) + A base (x=0..5, 9..10)
    "BBBBBB...BB....."  # 15: A base (x=0..5, 9..10)
]

# Let's also create an image scaled up 16x (256x256) to visually inspect
out_img = Image.new('RGB', (16, 16), (255, 255, 255))
navy = (28, 43, 76)     # 0x1C2B4C
red = (238, 24, 24)     # 0xEE1818

for y in range(16):
    for x in range(16):
        ch = pattern_v1[y][x]
        if ch == 'B':
            out_img.putpixel((x, y), navy)
        elif ch == 'R':
            out_img.putpixel((x, y), red)

out_scaled = out_img.resize((256, 256), Image.Resampling.NEAREST)
out_scaled.save(r'C:/fpga/HX4S20_HDMI_Player_完整交付包_v2.8_方向4全适配/01_工程完整源码/tools/preview_anlogic_16x16.png')
print("Saved preview_anlogic_16x16.png")
