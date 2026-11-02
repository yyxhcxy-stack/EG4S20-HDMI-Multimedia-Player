from PIL import Image
import numpy as np

img_path = r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792815271765_9cee6115.jpg'
img = Image.open(img_path).convert('RGB')
arr = np.array(img)

# Non-white pixels: where min(r, g, b) < 220
mask = np.min(arr, axis=2) < 220
ys, xs = np.where(mask)
min_y, max_y = ys.min(), ys.max()
min_x, max_x = xs.min(), xs.max()

print(f"Bounding box: x=[{min_x}, {max_x}], y=[{min_y}, {max_y}], width={max_x - min_x + 1}, height={max_y - min_y + 1}")
cropped = img.crop((min_x, min_y, max_x + 1, max_y + 1))
print("Cropped size:", cropped.size)
