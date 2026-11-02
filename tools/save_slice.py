from PIL import Image
import numpy as np

crop = np.array(Image.open('tools/center_crop_5.png'))
# Let's save slices around x=350..450 of center_crop_5
slice_crop = Image.fromarray(crop[:, 350:470])
slice_crop.save('tools/slice_350_470.png')
print("Saved tools/slice_350_470.png")
