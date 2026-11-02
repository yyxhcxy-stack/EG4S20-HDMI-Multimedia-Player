import numpy as np
from PIL import Image

arr = np.array(Image.open('tools/spine_orig_source.png'))
print("Shape:", arr.shape)
# Compute column difference:
diffs = np.mean(np.abs(arr[:, 1:].astype(float) - arr[:, :-1].astype(float)), axis=(0, 2))
print("Max diff in spine_orig_source:", np.argmax(diffs), "val:", np.max(diffs))
for i, d in enumerate(diffs):
    if d > 12:
        print(f"Col {650+i}: diff = {d:.2f}")
