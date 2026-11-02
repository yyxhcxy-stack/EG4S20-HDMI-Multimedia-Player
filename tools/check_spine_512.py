from PIL import Image
import numpy as np

bmp5 = np.array(Image.open(r"C:/fpga/TF_CARD_DEPLOY/5.bmp"))
print("bmp5 shape:", bmp5.shape)

# Let's save a crop of columns 480..544 (around 512) across rows 100..700:
spine_crop = bmp5[100:700, 480:544, :]
Image.fromarray(spine_crop).save("tools/spine_crop_512.png")
print("Saved tools/spine_crop_512.png")

# Let's check the column differences inside spine_crop:
for x in range(505, 520):
    col = bmp5[200:500, x, :]
    col_prev = bmp5[200:500, x-1, :]
    diff = np.mean(np.abs(col.astype(float) - col_prev.astype(float)))
    print(f"5.bmp X={x} (screen {x-192}): mean RGB={np.mean(col, axis=0).astype(int)}, step from prev={diff:.2f}")
