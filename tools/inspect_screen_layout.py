from PIL import Image
import numpy as np

photo = np.array(Image.open('tools/photo_inspect.png'))
print("Photo shape:", photo.shape)

# Let's inspect rows 200..300, and columns 0..1024
# What is the layout of the monitor in the photo?
# Let's find the bezel / border of the monitor screen:
# A dark frame usually surrounds the bright LCD.
# Let's compute average brightness across Y for each X:
x_profile = np.mean(photo[100:600, :, :], axis=(0, 2))
# Print where x_profile changes from dark (bezel) to brighter (screen):
print("X profile at col 0, 10, 20, 30, 40, 50, 60:")
for x in range(0, 70, 5):
    print(f"X={x}: lum={x_profile[x]:.1f}")

print("X profile at col 850..920:")
for x in range(850, 920, 5):
    print(f"X={x}: lum={x_profile[x]:.1f}")
