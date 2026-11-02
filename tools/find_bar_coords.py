import numpy as np
from PIL import Image

photo = np.array(Image.open(r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg'))

# The top bar of the monitor has a cyan/blue line at y around 130..160
# Let's inspect rows around 130..170:
for y in range(130, 160, 5):
    row = photo[y, :, :]
    # Blue/cyan top bar: high G and B, lower R
    is_bar = (row[:, 1] > 60) & (row[:, 2] > 60)
    indices = np.where(is_bar)[0]
    if len(indices) > 100:
        print(f"Y={y}: bar left = {indices[0]}, bar right = {indices[-1]}, width = {indices[-1] - indices[0]}")
