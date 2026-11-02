from PIL import Image
import numpy as np

arr = np.array(Image.open(r'C:\fpga\TF_CARD_DEPLOY\5.bmp'))
print("5.bmp shape:", arr.shape)

# Let's inspect rows 200..400 across columns 630..650:
sub = arr[200:400, 630:650, :]
# Mean color of col 638, 639, 640, 641, 642:
for x in range(635, 645):
    col = arr[200:400, x, :]
    print(f"5.bmp col {x} (screen {x-192}): mean RGB = {np.mean(col, axis=0).astype(int)}")
