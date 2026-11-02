from PIL import Image
import numpy as np

arr = np.array(Image.open('tools/crop_512_640.png'))
print("crop_512_640 shape:", arr.shape)

# Let's check vertical edges inside crop_512_640:
# For each column x from 0 to 127 (which corresponds to 512+x in 5.bmp, and 320+x on screen):
col_diffs = np.mean(np.abs(arr[:, 1:].astype(float) - arr[:, :-1].astype(float)), axis=(0, 2))
for i in range(len(col_diffs)):
    # 512 + i in 5.bmp, 320 + i on screen
    screen_x = 320 + i
    if col_diffs[i] > 15:
        print(f"Screen X {screen_x} (5.bmp X {512+i}): diff = {col_diffs[i]:.2f}")
