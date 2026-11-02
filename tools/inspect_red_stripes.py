from PIL import Image
import numpy as np

img_path = r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792815271765_9cee6115.jpg'
img = Image.open(img_path).convert('RGB')
arr = np.array(img)

mask = np.min(arr, axis=2) < 220
ys, xs = np.where(mask)
cropped = arr[ys.min():ys.max()+1, xs.min():xs.max()+1]
h, w, _ = cropped.shape

red_mask = (cropped[:, :, 0] > 130) & (cropped[:, :, 2] < 90)

# Check horizontal segments of each red stripe
# We know the stripes are at roughly y = [6, 25, 44, 64, 83, 102, 121, 140]
stripe_ys = [6, 25, 44, 64, 83, 102, 121, 140]
for idx, y in enumerate(stripe_ys):
    row = red_mask[y]
    segs = []
    in_s = False
    s_start = 0
    for x, r in enumerate(row):
        if r and not in_s: in_s = True; s_start = x
        elif not r and in_s: in_s = False; segs.append((s_start, x-1))
    if in_s: segs.append((s_start, len(row)-1))
    print(f"Stripe {idx} (y={y:3d}): {segs}")
