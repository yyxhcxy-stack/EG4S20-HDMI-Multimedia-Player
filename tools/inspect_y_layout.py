from PIL import Image
import numpy as np

photo = np.array(Image.open('tools/photo_inspect.png'))
# Active screen X is [25, 888].
# Let's inspect Y profile in the center of active screen (col 300..600):
y_profile = np.mean(photo[:, 300:600, :], axis=(1, 2))
print("Y profile at top (0..80):")
for y in range(0, 80, 5):
    print(f"Y={y}: lum={y_profile[y]:.1f}")
print("Y profile at bottom (680..768):")
for y in range(680, 768, 5):
    print(f"Y={y}: lum={y_profile[y]:.1f}")
