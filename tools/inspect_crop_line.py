from PIL import Image
import numpy as np

crop = Image.open('tools/crop_1x_check.png')
# Save an enlarged image of the center 100 columns:
sub = crop.crop((270, 0, 370, 480))
sub.save('tools/center_100_cols.png')
print("Saved tools/center_100_cols.png")

# Let's inspect rows 150..250, cols 320..335 in crop:
arr = np.array(crop)
# Look at the vertical line along col 326:
# Is there a noticeable vertical line running through all rows?
v_steps = []
for y in range(480):
    step = np.abs(arr[y, 326, :].astype(float) - arr[y, 325, :].astype(float))
    v_steps.append(np.mean(step))
print("Mean step across all 480 rows at col 326:", np.mean(v_steps))
print("Max step at col 326:", np.max(v_steps), "Min step:", np.min(v_steps))

# Compare with average column step across the image:
all_steps = [np.mean(np.abs(arr[:, x, :].astype(float) - arr[:, x-1, :].astype(float))) for x in range(1, 640)]
print("Average column step across entire image:", np.mean(all_steps))
print("Col 326 step:", all_steps[325], "Col 327 step:", all_steps[326])
