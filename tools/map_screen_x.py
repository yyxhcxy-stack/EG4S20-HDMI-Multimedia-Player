import numpy as np
from PIL import Image

photo_screen = np.array(Image.open('tools/photo_screen.png'))
# Find top status bar in photo_screen (it has distinct bright border at y around 30..50):
# Let's find left edge and right edge of top bar:
top_bar = photo_screen[30:50, :, :]
lum = np.mean(top_bar, axis=(0, 2))
# Find where lum > 50:
bright_x = np.where(lum > 30)[0]
print("Top bar X bounds in photo_screen:", bright_x[0], bright_x[-1], "width:", bright_x[-1] - bright_x[0])

# So screen_x in photo_screen:
left = bright_x[0]
width = bright_x[-1] - bright_x[0]
# Columns 595..614 in photo_screen corresponds to:
for col in [595, 608, 612]:
    norm_x = (col - left) / width * 640
    print(f"Photo col {col} -> Screen X = {norm_x:.1f}")
