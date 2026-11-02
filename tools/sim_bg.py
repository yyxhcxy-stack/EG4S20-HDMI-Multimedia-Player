from PIL import Image
import numpy as np

# Let's test the logo against a typical dark glass background: (20, 30, 45)
bg_color = (20, 30, 45)

colors_to_test = [
    ("Original image blue", (33, 43, 74), (217, 34, 49)),
    ("Tech Navy Blue 1", (28, 43, 76), (238, 24, 24)),
    ("Tech Navy Blue 2 (slightly brighter)", (40, 75, 140), (238, 24, 24)),
    ("Vivid Tech Blue", (48, 90, 168), (238, 24, 24)),
]

pattern = [
    # 0123456789012345
    "......RRRRRRRRRR", # 0: stripe 0 (x=6..15)
    "....BB..........", # 1: apex of A (x=4..5)
    "....BB.RRRRRRRR.", # 2: stripe 1 (x=7..14) + A (x=4..5)
    "...BBBB.........", # 3: A expanding (x=3..6)
    "...BBBB.RRRRRRR.", # 4: stripe 2 (x=8..14) + A (x=3..6)
    "...BBBB.........", # 5: A (x=3..6)
    "..BB..BB.RRRRRR.", # 6: stripe 3 (x=9..14) + A (x=2..3, 6..7)
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

for label, b_col, r_col in colors_to_test:
    img = Image.new('RGB', (16, 16), bg_color)
    for y in range(16):
        for x in range(16):
            if pattern[y][x] == 'B':
                img.putpixel((x, y), b_col)
            elif pattern[y][x] == 'R':
                img.putpixel((x, y), r_col)
    scaled = img.resize((128, 128), Image.Resampling.NEAREST)
    fname = f"tools/sim_{label.replace(' ', '_').replace('(', '').replace(')', '')}.png"
    scaled.save(fname)
    print(f"Saved {fname}")
