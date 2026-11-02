from PIL import Image
import numpy as np

img_path = r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792815271765_9cee6115.jpg'
img = Image.open(img_path).convert('RGB')
arr = np.array(img)

mask = np.min(arr, axis=2) < 220
ys, xs = np.where(mask)
cropped = arr[ys.min():ys.max()+1, xs.min():xs.max()+1]

blue_mask = (cropped[:, :, 0] < 80) & (cropped[:, :, 2] > 50)

# Check middle of "A" in original coordinates
# Let's sample a few horizontal slices of blue_mask
print(f"H={cropped.shape[0]}, W={cropped.shape[1]}")
for y_pct in [0.2, 0.4, 0.6, 0.75, 0.85, 0.95]:
    y = int(y_pct * cropped.shape[0])
    row = blue_mask[y]
    # find continuous blue segments
    segs = []
    in_s = False
    s_start = 0
    for x, b in enumerate(row):
        if b and not in_s:
            in_s = True
            s_start = x
        elif not b and in_s:
            in_s = False
            segs.append((s_start, x-1))
    if in_s: segs.append((s_start, len(row)-1))
    print(f"y={y:3d} ({y_pct*100:4.1f}%): segments={segs}")
