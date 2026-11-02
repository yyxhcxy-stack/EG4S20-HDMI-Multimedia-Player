from PIL import Image
import numpy as np

im = Image.open(r'C:\fpga\TF_CARD_DEPLOY\5.bmp')
print("Image size:", im.size)
arr = np.array(im)
print("Array shape:", arr.shape)

# Let's crop the center 640x480 (from x=192..832, y=144..624) which is 1.0X scale
center_crop = arr[144:624, 192:832]
crop_im = Image.fromarray(center_crop)
crop_im.save(r'tools/center_crop_5.png')
print("Saved tools/center_crop_5.png")
