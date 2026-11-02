from PIL import Image
import numpy as np

photo = Image.open(r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg')
# Let's crop 10 vertical strips across the screen:
# From x = 400 to 750, y = 150 to 550
w, h = photo.size
for x_start in range(450, 750, 30):
    strip = photo.crop((x_start, 200, x_start + 30, 500))
    strip.save(f'tools/photo_x_{x_start}.png')
print("Saved photo strips!")
