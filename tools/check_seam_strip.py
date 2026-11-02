from PIL import Image
import numpy as np

crop = np.array(Image.open("tools/crop_1x_displayed.png")) # 480x640x3
print("crop_1x shape:", crop.shape)

# Let's save a crop of columns 430..470 across all rows 0..480:
seam_strip = crop[:, 430:470, :]
Image.fromarray(seam_strip).save("tools/seam_strip_crop1x.png")
print("Saved tools/seam_strip_crop1x.png")

# Let's check mean color along columns in crop_1x:
for x in range(435, 455):
    col = crop[:, x, :]
    col_prev = crop[:, x-1, :]
    diff = np.mean(np.abs(col.astype(float) - col_prev.astype(float)))
    print(f"Col {x}: mean RGB = {np.mean(col, axis=0).astype(int)}, step from prev = {diff:.2f}")
