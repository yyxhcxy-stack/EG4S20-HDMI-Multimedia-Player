from PIL import Image
import numpy as np

img_path = r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792815271765_9cee6115.jpg'
img = Image.open(img_path).convert('RGB')
arr = np.array(img)

mask = np.min(arr, axis=2) < 220
ys, xs = np.where(mask)
cropped = arr[ys.min():ys.max()+1, xs.min():xs.max()+1]
h, w, _ = cropped.shape
print(f"Cropped dimensions: {w} x {h}")

# How many red stripes are in the image?
# Let's sample a vertical column through the middle of the red stripes (e.g. x = w * 0.7)
col = cropped[:, int(w * 0.7)]
is_red = (col[:, 0] > 140) & (col[:, 1] < 80) & (col[:, 2] < 80)

# Count continuous segments of red
stripes = []
in_stripe = False
start = 0
for i, r in enumerate(is_red):
    if r and not in_stripe:
        in_stripe = True
        start = i
    elif not r and in_stripe:
        in_stripe = False
        stripes.append((start, i - 1))
if in_stripe:
    stripes.append((start, len(is_red) - 1))

print(f"Number of red stripes: {len(stripes)}")
for idx, (s, e) in enumerate(stripes):
    print(f"Stripe {idx}: y=[{s}, {e}], height={e - s + 1}")
