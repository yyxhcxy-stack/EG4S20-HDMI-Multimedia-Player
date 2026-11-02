from PIL import Image
import numpy as np

photo = np.array(Image.open(r"C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg"))
# Look at columns across the photo around x=600..750:
# Compute column-to-column diff across the entire height:
col_diff = np.mean(np.abs(photo[:, 1:, :].astype(float) - photo[:, :-1, :].astype(float)), axis=(0, 2))
# Find top 10 column diffs:
top_cols = np.argsort(col_diff)[::-1][:15]
print("Top column diffs in photo:")
for c in sorted(top_cols):
    print(f"Col {c} -> {c+1}: diff = {col_diff[c]:.2f}")
