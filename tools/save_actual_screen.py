from PIL import Image
import numpy as np

photo = Image.open('tools/photo_inspect.png')
screen = photo.crop((25, 20, 888, 680)).resize((640, 480), Image.Resampling.BICUBIC)
screen.save('tools/screen_actual_displayed.png')
print("Saved tools/screen_actual_displayed.png (640x480)!")

# Now compare screen_actual_displayed with crop_1x_displayed!
actual = np.array(screen)
expected = np.array(Image.open('tools/crop_1x_displayed.png'))

print("Actual shape:", actual.shape, "Expected shape:", expected.shape)

# Let's save a side-by-side or difference image:
diff = np.abs(actual.astype(float) - expected.astype(float))
Image.fromarray(np.clip(diff * 2, 0, 255).astype(np.uint8)).save('tools/diff_actual_vs_expected.png')
print("Saved tools/diff_actual_vs_expected.png!")
