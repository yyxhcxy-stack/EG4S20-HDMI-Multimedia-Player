from PIL import Image
import numpy as np

photo = np.array(Image.open(r"C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg"))
bmp5 = np.array(Image.open(r"C:/fpga/TF_CARD_DEPLOY/5.bmp"))

print("Photo shape:", photo.shape)
print("5.bmp shape:", bmp5.shape)

diff = np.abs(photo.astype(float) - bmp5.astype(float))
print("Max diff:", np.max(diff), "Mean diff:", np.mean(diff))

# Let's inspect differences:
if np.mean(diff) < 5.0:
    print("They are the same image (with JPEG compression differences)!")
else:
    print("They are different!")
