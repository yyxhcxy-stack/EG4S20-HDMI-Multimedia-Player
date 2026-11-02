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
red_mask  = (cropped[:, :, 0] > 130) & (cropped[:, :, 2] < 90)

# For each y in 16 normalized steps (y = 0..15):
for y_step in range(16):
    y_orig = int((y_step + 0.5) * h / 16)
    row_blue = blue_mask[y_orig]
    row_red = red_mask[y_orig]
    
    # map to 16 x positions:
    x_chars = []
    for x_step in range(16):
        x_start = int(x_step * w / 16)
        x_end = int((x_step + 1) * w / 16)
        n_blue = np.sum(row_blue[x_start:x_end])
        n_red = np.sum(row_red[x_start:x_end])
        n_total = x_end - x_start
        
        if n_blue > n_total * 0.3:
            x_chars.append('B')
        elif n_red > n_total * 0.2:
            x_chars.append('R')
        else:
            x_chars.append('.')
    print(f"{y_step:2d} (y={y_orig:3d}): " + "".join(["  " if c=='.' else "BB" if c=='B' else "RR" for c in x_chars]))
