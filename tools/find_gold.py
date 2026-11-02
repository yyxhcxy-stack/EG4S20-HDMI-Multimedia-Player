from PIL import Image
import numpy as np

arr = np.array(Image.open(r'C:\fpga\TF_CARD_DEPLOY\5.bmp'))
# Golden text has high red, medium-high green, lower blue: e.g. R > 150, G > 80, B < 80
gold_mask = (arr[:, :, 0] > 140) & (arr[:, :, 1] > 70) & (arr[:, :, 2] < 70)
# Column projection of gold text:
col_gold = np.sum(gold_mask, axis=0)

print("Gold text distribution across X (0..1023):")
for x in range(0, 1024, 64):
    print(f"X {x:4d}..{x+63:4d}: {np.sum(col_gold[x:x+64])}")
