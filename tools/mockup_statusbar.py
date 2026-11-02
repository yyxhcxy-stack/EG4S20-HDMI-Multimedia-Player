from PIL import Image, ImageDraw, ImageFont

# Let's create a mockup of the actual HDMI top bar:
# Y = 10..26, X = 8..631
# Background is dark translucent glass over an image
# Left: Logo (16x16 at X=12..27, Y=10..25)
# Next: "ANLOGIC 2026" in Cyan at X=32..127
# Next: "[MANU]" in Cyan at X=144..207

w, h = 640, 40
mockup = Image.new('RGB', (w, h), (18, 28, 42)) # Status bar background

# Draw border
draw = ImageDraw.Draw(mockup)
draw.rectangle([8, 8, 631, 27], outline=(0, 255, 136)) # Green border

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

# Let's test two blues:
# Blue 1: 0x212B4A (exact from image)
# Blue 2: 0x2A4E88 (tuned for high visibility on dark status bar)
# Blue 3: 0x3060A8 (vivid navy)
for idx, (b_name, b_val) in enumerate([
    ("0x212B4A_exact", (33, 43, 74)),
    ("0x2A4E88_tuned", (42, 78, 136)),
    ("0x3060A8_vivid", (48, 96, 168)),
    ("0x1C3058_dark",  (28, 48, 88))
]):
    bar = mockup.copy()
    red_val = (238, 24, 24)
    for y in range(16):
        for x in range(16):
            ch = pattern[y][x]
            if ch == 'B':
                bar.putpixel((12 + x, 10 + y), b_val)
            elif ch == 'R':
                bar.putpixel((12 + x, 10 + y), red_val)
    
    # Save 4x magnified version of the logo region
    crop = bar.crop((8, 6, 160, 32))
    crop_4x = crop.resize((crop.width * 4, crop.height * 4), Image.Resampling.NEAREST)
    crop_4x.save(f"tools/mockup_bar_{b_name}.png")
    print(f"Saved tools/mockup_bar_{b_name}.png")
