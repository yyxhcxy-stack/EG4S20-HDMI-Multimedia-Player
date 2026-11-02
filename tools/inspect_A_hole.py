from PIL import Image
import numpy as np

img_path = r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792815271765_9cee6115.jpg'
img = Image.open(img_path).convert('RGB')
arr = np.array(img)

mask = np.min(arr, axis=2) < 220
ys, xs = np.where(mask)
cropped = arr[ys.min():ys.max()+1, xs.min():xs.max()+1]
h, w, _ = cropped.shape

blue_mask = (cropped[:, :, 0] < 80) & (cropped[:, :, 2] > 50)

# Print 30x30 ascii art of just the blue mask
res = Image.fromarray(blue_mask.astype(np.uint8)*255).resize((30, 24), Image.Resampling.NEAREST)
arr_b = np.array(res) > 128
for row in arr_b:
    print("".join(["██" if p else "  " for p in row]))
