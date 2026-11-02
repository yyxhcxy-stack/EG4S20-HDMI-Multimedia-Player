from PIL import Image
import numpy as np

photo = np.array(Image.open(r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg'))

# The top status bar has bright text (ANLOGIC 2026, [MANUAL], etc.)
# Let's find where the monitor screen bounds are:
# Screen has bright pixels, black bezel around it.
# Look at row 150 across columns:
r150 = photo[150, :, :]
print("Row 150 brightness:")
# Screen appears between roughly x=50 and x=900, y=100 and y=650
# Let's save a crop of the entire screen area from the photo
screen_crop = Image.fromarray(photo[100:660, 30:900])
screen_crop.save('tools/photo_screen.png')
print("Saved photo_screen.png")
