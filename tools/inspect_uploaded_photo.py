from PIL import Image
import numpy as np

photo_path = r"C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg"
im = Image.open(photo_path)
print("Format:", im.format, "Size:", im.size, "Mode:", im.mode)
# Let's inspect what is inside this image!
arr = np.array(im)
print("Top-left pixel:", arr[0, 0])
print("Center pixel:", arr[384, 512])

# Is it a photo of a monitor? Or a screenshot?
# Let's check the corners:
print("Corners:", arr[0, 0], arr[0, -1], arr[-1, 0], arr[-1, -1])
