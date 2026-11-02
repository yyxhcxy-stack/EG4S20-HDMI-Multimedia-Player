from PIL import Image
import numpy as np

# Load photo and crop_1x_displayed
photo = np.array(Image.open(r"C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg"))
crop_1x = np.array(Image.open("tools/crop_1x_displayed.png"))

print("crop_1x shape:", crop_1x.shape) # (480, 640, 3)

# In crop_1x, what is at screen X = 445..452?
# Let's inspect rows 150..350:
print("Theoretical crop_1x at rows 200..205 around X=448:")
for y in range(200, 206):
    print(f"Y={y}: X=446:{crop_1x[y, 446]}, X=447:{crop_1x[y, 447]}, X=448:{crop_1x[y, 448]}, X=449:{crop_1x[y, 449]}")

# Now let's see what is in photo around photo X=605..615:
# Let's find corresponding Y in photo.
# If photo height is 768, top bar is around Y=35..65.
# Active video is roughly Y in [50, 715] (height ~ 665).
# So Y_screen = (Y_photo - 50) / 665 * 480.
# For Y_screen = 200: Y_photo ~ 50 + 200/480*665 = 327.
print("Photo around Y=325..330 around col 608..613:")
for y in range(325, 331):
    print(f"Y={y}: col 608:{photo[y, 608]}, col 609:{photo[y, 609]}, col 610:{photo[y, 610]}, col 611:{photo[y, 611]}, col 612:{photo[y, 612]}")
