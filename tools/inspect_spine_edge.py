from PIL import Image
import numpy as np

spine = np.array(Image.open('tools/spine_crop_512.png'))
print("Spine crop shape:", spine.shape) # 600x64x3 (cols 480..544 of 5.bmp)
# Col 38 in spine corresponds to 480 + 38 = 518 in 5.bmp (screen X = 326).
# Let's inspect rows 100..200 at col 36, 37, 38, 39:
for r in range(100, 115):
    print(f"Row {r}: col 36 (x=516):{spine[r, 36]}, col 37 (x=517):{spine[r, 37]}, col 38 (x=518):{spine[r, 38]}, col 39 (x=519):{spine[r, 39]}")
