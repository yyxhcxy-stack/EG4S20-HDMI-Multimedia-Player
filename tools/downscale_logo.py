from PIL import Image
import numpy as np

img_path = r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792815271765_9cee6115.jpg'
img = Image.open(img_path).convert('RGB')
arr = np.array(img)

# Crop exactly to the logo
mask = np.min(arr, axis=2) < 220
ys, xs = np.where(mask)
min_y, max_y = ys.min(), ys.max()
min_x, max_x = xs.min(), xs.max()

cropped = img.crop((min_x, min_y, max_x + 1, max_y + 1))
print(f"Original cropped: {cropped.size}")

# Resize to 16x16 using LANCZOS or BOX
resized = cropped.resize((16, 16), Image.Resampling.LANCZOS)
arr16 = np.array(resized)

grid = []
for y in range(16):
    row = []
    for x in range(16):
        r, g, b = arr16[y, x]
        # Classify pixel: background (white), blue, or red
        if r > 200 and g > 200 and b > 200:
            row.append('.')
        elif b > r and b > 50:
            row.append('B')
        elif r > 120 and r > b * 1.5:
            row.append('R')
        else:
            # Thresholding
            if b > 70 and r < 80:
                row.append('B')
            elif r > 100 and b < 80:
                row.append('R')
            else:
                row.append('.')
    grid.append("".join(row))

for y, row in enumerate(grid):
    print(f"{y:2d}: " + "".join(["  " if c=='.' else "BB" if c=='B' else "RR" for c in row]))
