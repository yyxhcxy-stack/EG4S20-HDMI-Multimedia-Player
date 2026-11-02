from PIL import Image
import numpy as np

photo = Image.open(r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg')
w, h = photo.size
print("Photo size:", w, h)

# Crop around col 608 (x from 580 to 640, full height 100 to 650)
crop_608 = photo.crop((580, 100, 640, 650))
crop_608.save('tools/crop_col_608.png')

# Crop around col 696 (x from 670 to 720, full height 100 to 650)
crop_696 = photo.crop((670, 100, 720, 650))
crop_696.save('tools/crop_col_696.png')

print("Saved crop_col_608.png and crop_col_696.png!")
