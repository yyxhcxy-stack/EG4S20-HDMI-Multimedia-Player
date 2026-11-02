from PIL import Image
import numpy as np

crop = np.array(Image.open('tools/crop_1x_displayed.png'))
# Gold pixels in crop_1x_displayed:
gold_mask = (crop[:, :, 0] > 140) & (crop[:, :, 1] > 70) & (crop[:, :, 2] < 70)
gold_cols = np.sum(gold_mask, axis=0)

for x in range(0, 640, 32):
    print(f"Crop X {x:3d}..{x+31:3d}: {np.sum(gold_cols[x:x+32])}")
