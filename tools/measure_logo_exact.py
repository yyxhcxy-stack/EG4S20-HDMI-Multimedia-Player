from PIL import Image
import numpy as np

img = Image.open(r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792815271765_9cee6115.jpg').convert('RGB')
arr = np.array(img)

# Logo bounding box
mask = np.min(arr, axis=2) < 220
ys, xs = np.where(mask)
ymin, ymax = ys.min(), ys.max()
xmin, xmax = xs.min(), xs.max()
cropped = arr[ymin:ymax+1, xmin:xmax+1]
H, W, _ = cropped.shape
print(f"Cropped logo size: W={W}, H={H}, Aspect Ratio={W/H:.3f}")

# Blue vs Red masks
blue_mask = (cropped[:, :, 0] < 80) & (cropped[:, :, 2] > 40)
red_mask  = (cropped[:, :, 0] > 140) & (cropped[:, :, 2] < 90)

by, bx = np.where(blue_mask)
ry, rx = np.where(red_mask)

print(f"Blue 'A' bounds: x in [{bx.min()}, {bx.max()}], y in [{by.min()}, {by.max()}] (w={bx.max()-bx.min()+1}, h={by.max()-by.min()+1})")
print(f"Red stripes bounds: x in [{rx.min()}, {rx.max()}], y in [{ry.min()}, {ry.max()}] (w={rx.max()-rx.min()+1}, h={ry.max()-ry.min()+1})")

# Relative coordinates (0.0 to 1.0)
print(f"Relative X:")
print(f"  Blue 'A': x in [{bx.min()/W:.3f}, {bx.max()/W:.3f}]")
print(f"  Red stripes: x in [{rx.min()/W:.3f}, {rx.max()/W:.3f}]")

# Let's inspect the 8 red stripes in detail
# Find contiguous y ranges in red_mask
red_y_proj = np.sum(red_mask, axis=1)
stripes = []
in_stripe = False
s_start = 0
for y in range(H):
    if red_y_proj[y] > 5:
        if not in_stripe:
            in_stripe = True
            s_start = y
    else:
        if in_stripe:
            in_stripe = False
            stripes.append((s_start, y - 1))
if in_stripe:
    stripes.append((s_start, H - 1))

print(f"\nFound {len(stripes)} red stripes:")
for i, (y1, y2) in enumerate(stripes):
    sub = red_mask[y1:y2+1, :]
    x_indices = np.where(np.sum(sub, axis=0) > 0)[0]
    mid_y = (y1 + y2) / 2
    print(f"  Stripe {i}: y=[{y1:3d}..{y2:3d}] (rel_y={mid_y/H:.3f}), x=[{x_indices.min():3d}..{x_indices.max():3d}] (rel_x=[{x_indices.min()/W:.3f}..{x_indices.max()/W:.3f}])")

# Now let's inspect the Blue 'A' at several y slices
print("\nBlue 'A' slices across height (16 uniform intervals):")
for step in range(16):
    y_target = int((step + 0.5) * H / 16)
    row = blue_mask[y_target, :]
    x_indices = np.where(row)[0]
    if len(x_indices) > 0:
        # Check gaps inside
        segs = []
        cur_s = x_indices[0]
        cur_e = x_indices[0]
        for x in x_indices[1:]:
            if x == cur_e + 1:
                cur_e = x
            else:
                segs.append((cur_s, cur_e))
                cur_s = x
                cur_e = x
        segs.append((cur_s, cur_e))
        seg_str = ", ".join([f"[{s}..{e}] (rel [{s/W:.2f}..{e/W:.2f}])" for s, e in segs])
        print(f"  Row {step:2d} (y={y_target:3d}, rel={y_target/H:.2f}): {seg_str}")
    else:
        print(f"  Row {step:2d} (y={y_target:3d}): None")
