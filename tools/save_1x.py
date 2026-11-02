from PIL import Image
import numpy as np

# In 1.0X scale, the center 640x480 of 1024x768 is cropped:
# X from 192 to 832, Y from 144 to 624.
im = Image.open(r'C:\Users\ly\.gemini\antigravity\brain\40b3ae6d-de44-4abb-9e2d-491feb9a7eed\preview_5_bmp_final.png')
print("Image size:", im.size)
crop_1x = im.crop((192, 144, 832, 624))
crop_1x.save('tools/crop_1x_displayed.png')
print("Saved tools/crop_1x_displayed.png!")
