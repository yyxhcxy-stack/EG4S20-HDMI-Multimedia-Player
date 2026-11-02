from PIL import Image
import numpy as np

arr = np.array(Image.open('tools/crop_1x_displayed.png'))
print("Shape:", arr.shape)

# Let's see what is around x = 400..425 in this crop (which is x=592..617 in the 1024x768 image)
# Look at the vertical line in the user photo:
# On the screen, it's a vertical seam through the relief!
# Let's inspect the columns across the image
diff_matrix = np.abs(arr[:, 1:].astype(float) - arr[:, :-1].astype(float))
print("Mean diff per col:", np.mean(diff_matrix, axis=(0, 2)).shape)
# Find highest vertical column edges
edge_cols = np.argsort(np.mean(diff_matrix, axis=(0, 2)))[::-1]
print("Top 10 edge columns:", edge_cols[:10])
for c in edge_cols[:10]:
    print(f"Col {c} (screen {c}): mean diff = {np.mean(diff_matrix[:, c, :]):.2f}")
