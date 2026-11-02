from PIL import Image
import numpy as np

photo = np.array(Image.open(r"C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg"))
print("Dimensions:", photo.shape)
# Look at top area:
print("Row 0 mean RGB:", np.mean(photo[0, :, :], axis=0))
print("Row 20 mean RGB:", np.mean(photo[20, :, :], axis=0))
# Let's see if there is an OSD or status bar:
# Look for text or bar in row 0..40:
for r in range(0, 50, 5):
    print(f"Row {r}: min={np.min(photo[r, :, :], axis=0)}, max={np.max(photo[r, :, :], axis=0)}, mean={np.mean(photo[r, :, :], axis=0).astype(int)}")

# Let's save a thumbnail of photo to inspect:
im = Image.fromarray(photo)
im.save("tools/photo_inspect.png")
print("Saved tools/photo_inspect.png")
