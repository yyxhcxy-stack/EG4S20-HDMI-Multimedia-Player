from PIL import Image
import numpy as np

img = Image.open('tools/slice_350_470.png')
arr = np.array(img)
# Compute column difference in this slice:
diffs = np.mean(np.abs(arr[:, 1:].astype(float) - arr[:, :-1].astype(float)), axis=(0, 2))
for i, d in enumerate(diffs):
    print(f"Slice col {i} (global crop {350+i}): diff = {d:.2f}")
