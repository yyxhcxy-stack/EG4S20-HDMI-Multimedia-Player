import numpy as np
from PIL import Image

photo = np.array(Image.open(r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg'))
# Search x between 500 and 700:
# For each column x, compute the vertical consistency of the gradient (dx):
sub = photo[250:500, 500:700, :].astype(float)
dx = np.abs(sub[:, 1:, :] - sub[:, :-1, :])
mean_dx_across_y = np.mean(dx, axis=(0, 2))
print("Max vertical gradient in x=500..700:")
best_x = 500 + np.argmax(mean_dx_across_y)
print(f"Peak at photo x = {best_x}, gradient = {np.max(mean_dx_across_y):.2f}")
for offset in range(-5, 6):
    x = best_x + offset
    print(f"Photo X {x}: grad = {mean_dx_across_y[x - 500]:.2f}")
