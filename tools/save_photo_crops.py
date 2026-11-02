from PIL import Image
import numpy as np

photo = Image.open(r"C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg")
# Let's save crops of the top, bottom, left, right, center
w, h = photo.size
photo.crop((0, 0, w, 60)).save("tools/photo_top.png")
photo.crop((0, h-60, w, h)).save("tools/photo_bottom.png")
photo.crop((int(w*0.3), int(h*0.2), int(w*0.7), int(h*0.8))).save("tools/photo_center.png")
print("Saved top, bottom, center crops")
