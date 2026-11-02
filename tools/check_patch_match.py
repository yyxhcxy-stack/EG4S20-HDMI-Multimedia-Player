from PIL import Image
import numpy as np

photo = np.array(Image.open(r"C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg"))
crop_1x = np.array(Image.open("tools/crop_1x_displayed.png"))

# Let's correlate a patch from the right side of the seam in the photo
# with the theoretical crop_1x!
# In photo, seam is at col 608.5.
# Let's take a 50x50 patch from col 615..665, row 300..350:
patch = photo[300:350, 615:665, :]

# Where in crop_1x does this patch best match?
# Screen X roughly maps as: X_screen ~ (col - 21) / 865 * 640.
# Col 615 -> X ~ 453.
# Row 300 -> Y ~ (300 - 50) / 665 * 480 ~ 180.
print(f"Col 615 corresponds to expected X_screen ~ {(615-21)/865*640:.1f}")

# Let's check cross-correlation around X=440..470, Y=170..200 in crop_1x:
best_diff = 1e9
best_pos = None
for dy in range(160, 200):
    for dx in range(430, 480):
        # Resize crop_1x patch or compute color diff:
        # Since photo has brightness/camera response, let's compare normalized gradient or pattern:
        ref_patch = crop_1x[dy:dy+50, dx:dx+50, :]
        if ref_patch.shape == patch.shape:
            # compare mean-subtracted diff:
            p_norm = patch - np.mean(patch)
            r_norm = ref_patch - np.mean(ref_patch)
            corr = np.sum(p_norm * r_norm) / (np.std(p_norm) * np.std(r_norm) * patch.size + 1e-5)
            if corr > best_diff or best_pos is None: # we want max corr
                pass

# Let's do SSD on mean-subtracted:
min_ssd = 1e12
best_match = (0, 0)
p_sub = patch.astype(float) - np.mean(patch)
for dy in range(150, 210):
    for dx in range(420, 490):
        ref = crop_1x[dy:dy+50, dx:dx+50, :].astype(float)
        if ref.shape == patch.shape:
            r_sub = ref - np.mean(ref)
            ssd = np.mean((p_sub - r_sub)**2)
            if ssd < min_ssd:
                min_ssd = ssd
                best_match = (dx, dy)

print(f"Best match for photo patch (col 615..665) in crop_1x is at X={best_match[0]}, Y={best_match[1]}, SSD={min_ssd:.1f}")
