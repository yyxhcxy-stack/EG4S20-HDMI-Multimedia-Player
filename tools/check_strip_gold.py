import numpy as np
from PIL import Image

for i in range(8):
    strip = np.array(Image.open(f'tools/strip_{i*128}_{(i+1)*128}.png'))
    gold_mask = (strip[:, :, 0] > 140) & (strip[:, :, 1] > 70) & (strip[:, :, 2] < 70)
    print(f"Strip {i*128}..{(i+1)*128}: gold pixel count = {np.sum(gold_mask)}")
