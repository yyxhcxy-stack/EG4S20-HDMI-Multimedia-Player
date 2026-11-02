from PIL import Image
import numpy as np

im = Image.open(r'C:\fpga\TF_CARD_DEPLOY\5.bmp')
arr = np.array(im)
print("Original 5.bmp shape:", arr.shape)

# Let's save slices of 5.bmp across X:
# X from 0..512 and X from 512..1024
left_half = Image.fromarray(arr[:, :512])
right_half = Image.fromarray(arr[:, 512:])
left_half.save('tools/5_left_half.png')
right_half.save('tools/5_right_half.png')
print("Saved left_half and right_half")
