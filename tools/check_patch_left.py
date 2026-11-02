from PIL import Image
import numpy as np

photo = np.array(Image.open(r"C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg"))
crop_1x = np.array(Image.open("tools/crop_1x_displayed.png"))

# Check left patch: col 555..605, row 300..350:
patch_left = photo[300:350, 555:605, :]
min_ssd = 1e12
best_match = (0, 0)
p_sub = patch_left.astype(float) - np.mean(patch_left)
for dy in range(150, 220):
    for dx in range(350, 450):
        ref = crop_1x[dy:dy+50, dx:dx+50, :].astype(float)
        if ref.shape == patch_left.shape:
            r_sub = ref - np.mean(ref)
            ssd = np.mean((p_sub - r_sub)**2)
            if ssd < min_ssd:
                min_ssd = ssd
                best_match = (dx, dy)

print(f"Best match for LEFT patch (col 555..605) in crop_1x is at X={best_match[0]}, Y={best_match[1]}, SSD={min_ssd:.1f}")
