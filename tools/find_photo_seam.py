from PIL import Image
import numpy as np

photo = np.array(Image.open("tools/photo_inspect.png"))
# Let's inspect the vertical line in the image!
# Where is the vertical line located?
# Let's compute vertical gradient and horizontal gradient
# If there is a vertical crease/seam, the gradient along X (diff between col x and col x-1)
# will have a strong peak or discontinuity along that entire column!
col_diff = np.mean(np.abs(photo[100:600, 1:, :] - photo[100:600, :-1, :]), axis=(0, 2))
# Print top 20 columns with highest diff in range 300..800:
candidates = []
for c in range(300, 800):
    candidates.append((col_diff[c], c))
candidates.sort(reverse=True)
print("Top 15 column discontinuities between 300 and 800:")
for diff, c in candidates[:15]:
    print(f"Col {c} -> {c+1}: diff = {diff:.2f}")
