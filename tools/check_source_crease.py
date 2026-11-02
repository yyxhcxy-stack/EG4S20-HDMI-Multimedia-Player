from PIL import Image
import numpy as np

src = Image.open(r'C:\Users\ly\.gemini\antigravity\brain\40b3ae6d-de44-4abb-9e2d-491feb9a7eed\zenghouyi_bronze_chime_bell_inscription_1792556884917.jpg')
w, h = src.size
print("Source image size:", w, h)

# Let's crop the same region from the original source jpg:
# In process_5_bmp.ps1:
# targetRatio = 1024 / 768 = 1.3333
# srcRatio = 1200 / 896 = 1.3392
# srcCropW = int(896 * 1.3333) = 1194
# srcCropX = (1200 - 1194) / 2 = 3
# In 1024x768, crop_x was 192 (0.1875 of 1024) to 832 (0.8125 of 1024)
# In the original 1200x896, the spine is at x = 3 + 1194 * (512+90)/1024 = 3 + 1194 * 0.588 = 705
# Let's crop around x = 650..750, y = 150..600 from the source jpg:
spine_orig = src.crop((650, 150, 750, 600))
spine_orig.save('tools/spine_orig_source.png')
print("Saved spine_orig_source.png")
