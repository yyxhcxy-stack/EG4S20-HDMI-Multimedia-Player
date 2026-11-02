from PIL import Image

photo = Image.open(r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg')
w, h = photo.size
print("Photo size:", w, h)

# The monitor screen is roughly in the center:
# Let's save a crop of the seam region from the photo:
# X from roughly 0.55*w to 0.70*w, Y from 0.15*h to 0.85*h
seam_crop = photo.crop((int(0.55*w), int(0.15*h), int(0.72*w), int(0.85*h)))
seam_crop.save('tools/photo_seam_crop.png')
print("Saved tools/photo_seam_crop.png!")
