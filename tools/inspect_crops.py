from PIL import Image
import numpy as np

top = np.array(Image.open("tools/photo_top.png"))
print("Top crop shape:", top.shape)
# Find white or bright pixels in top crop:
bright = (top[:, :, 0] > 180) & (top[:, :, 1] > 180) & (top[:, :, 2] > 180)
print("Number of bright pixels:", np.sum(bright))

# Let's inspect center crop:
center = np.array(Image.open("tools/photo_center.png"))
print("Center crop shape:", center.shape)

# Let's check if there is a vertical line in center crop:
# In center crop, width is w*0.4 = 410 pixels (from 307 to 716 in photo)
center_diff = np.mean(np.abs(center[:, 1:, :] - center[:, :-1, :]), axis=(0, 2))
top_diff_indices = np.argsort(center_diff)[::-1][:10]
print("Top diffs in center crop (relative to center x=0):")
for idx in top_diff_indices:
    print(f"Rel x {idx} (Photo x {307+idx}): diff={center_diff[idx]:.2f}")
