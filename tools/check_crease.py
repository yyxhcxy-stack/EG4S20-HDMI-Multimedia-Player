from PIL import Image
import numpy as np

im = Image.open('tools/center_crop_5.png')
w, h = im.size
print(f"Crop size: {w}x{h}")

# Check columns around x = 400..450 in the crop (which corresponds to x = 592..642 in original 1024x768)
arr = np.array(im)
# Compute column-to-column difference:
diffs = np.mean(np.abs(arr[:, 1:].astype(float) - arr[:, :-1].astype(float)), axis=(0, 2))
print("Max diff at column:", np.argmax(diffs), "value:", np.max(diffs))
for x in range(380, 460):
    if diffs[x] > 20:
        print(f"Column {x} has large diff: {diffs[x]:.2f}")
