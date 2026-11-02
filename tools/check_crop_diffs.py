from PIL import Image
import numpy as np

bmp5 = Image.open(r"C:/fpga/TF_CARD_DEPLOY/5.bmp")
w, h = bmp5.size
print("5.bmp size:", w, h)

# Save the full central crop 640x480 of 5.bmp:
crop_1x = bmp5.crop((192, 144, 832, 624))
crop_1x.save("tools/crop_1x_check.png")

# Inspect the vertical line at x=326 in crop_1x (which is x=518 in 5.bmp):
arr = np.array(crop_1x)
# Compute column difference in crop_1x across all rows:
diffs = [np.mean(np.abs(arr[:, x, :].astype(float) - arr[:, x-1, :].astype(float))) for x in range(1, 640)]
diffs = np.array(diffs)
print("Top 10 column diffs in 1.0X crop:")
top10 = np.argsort(diffs)[::-1][:10]
for idx in top10:
    print(f"Col {idx+1} (5.bmp {192+idx+1}): mean step = {diffs[idx]:.2f}")
