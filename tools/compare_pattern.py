from PIL import Image
import numpy as np

# Load cropped original
img = Image.open(r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792815271765_9cee6115.jpg').convert('RGB')
arr = np.array(img)
mask = np.min(arr, axis=2) < 220
ys, xs = np.where(mask)
cropped = arr[ys.min():ys.max()+1, xs.min():xs.max()+1]
H, W, _ = cropped.shape

blue_mask = (cropped[:, :, 0] < 80) & (cropped[:, :, 2] > 40)
red_mask  = (cropped[:, :, 0] > 140) & (cropped[:, :, 2] < 90)

# Current pattern in test
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

# Let's inspect row by row:
# For each row y in 0..15, what are the exact x spans of Blue and Red in the original image?
print(f"Row comparison (Target 16x16 vs Original scaled to 16):")
for y in range(16):
    y_start = int(y * H / 16)
    y_end = int((y + 1) * H / 16)
    
    b_slice = blue_mask[y_start:y_end, :]
    r_slice = red_mask[y_start:y_end, :]
    
    # Check each column x in 0..15
    orig_chars = []
    for x in range(16):
        x_start = int(x * W / 16)
        x_end = int((x + 1) * W / 16)
        
        b_count = np.sum(b_slice[:, x_start:x_end])
        r_count = np.sum(r_slice[:, x_start:x_end])
        tot = (y_end - y_start) * (x_end - x_start)
        
        if b_count > tot * 0.35:
            orig_chars.append('B')
        elif r_count > tot * 0.2:
            orig_chars.append('R')
        else:
            orig_chars.append('.')
    
    orig_str = "".join(orig_chars)
    patt_str = pattern[y]
    print(f"y={y:2d}:  Pattern: {patt_str}   |   Orig: {orig_str}")
