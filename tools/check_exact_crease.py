import numpy as np
from PIL import Image

arr = np.array(Image.open('tools/crop_1x_displayed.png'))
# Let's inspect column averages around x=410..425
for x in range(405, 425):
    col = arr[:, x, :]
    col_prev = arr[:, x-1, :]
    step = np.mean(np.abs(col.astype(float) - col_prev.astype(float)))
    print(f"Crop col {x}: mean pixel value = {np.mean(col):.1f}, step from prev = {step:.2f}")
