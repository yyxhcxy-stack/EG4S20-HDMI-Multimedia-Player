from PIL import Image
import numpy as np

img_path = r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792815271765_9cee6115.jpg'
img = Image.open(img_path).convert('RGB')
arr = np.array(img)

mask = np.min(arr, axis=2) < 220
ys, xs = np.where(mask)
cropped = Image.fromarray(arr[ys.min():ys.max()+1, xs.min():xs.max()+1])

# Try 16x16 resize
res16 = cropped.resize((16, 16), Image.Resampling.LANCZOS)
arr16 = np.array(res16)

# Let's inspect pixel values
for y in range(16):
    line = []
    for x in range(16):
        r, g, b = arr16[y, x]
        # Decide if blue, red, or empty
        # Blue: b > 60 and r < 100
        # Red: r > 120 and b < 100
        if r < 100 and b > 55:
            line.append('B')
        elif r > 130 and b < 90:
            line.append('R')
        else:
            line.append('.')
    print(f"{y:2d}: " + "".join(["  " if c=='.' else "BB" if c=='B' else "RR" for c in line]))
