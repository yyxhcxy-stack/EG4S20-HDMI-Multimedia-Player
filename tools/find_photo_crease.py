import numpy as np
from PIL import Image

photo_screen = np.array(Image.open('tools/photo_screen.png'))
print("photo_screen shape:", photo_screen.shape)

# Let's compute column diffs in photo_screen:
# Crop Y to just the bell image area (avoid top and bottom OSD text):
bell_area = photo_screen[100:400, :, :]
col_diffs = np.mean(np.abs(bell_area[:, 1:].astype(float) - bell_area[:, :-1].astype(float)), axis=(0, 2))

# Find the peak diff around the middle
top_cols = np.argsort(col_diffs)[::-1][:15]
print("Top diff columns in photo_screen:")
for c in sorted(top_cols):
    print(f"Col {c}: diff = {col_diffs[c]:.2f}")
