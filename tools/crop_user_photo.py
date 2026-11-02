from PIL import Image
import numpy as np

photo_path = r"C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg"
im = Image.open(photo_path)
print("Photo size:", im.size)

# The monitor screen in the photo:
# Let's inspect different vertical slices across the screen
arr = np.array(im)
H, W, _ = arr.shape

# Let's save a crop around the center of the screen
# The screen is roughly X in [W*0.2, W*0.8], Y in [H*0.15, H*0.85]
screen_crop = im.crop((int(W*0.15), int(H*0.15), int(W*0.85), int(H*0.85)))
screen_crop.save("tools/user_photo_screen.png")
print("Saved tools/user_photo_screen.png")
