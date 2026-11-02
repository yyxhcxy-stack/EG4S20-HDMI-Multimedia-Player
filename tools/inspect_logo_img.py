from PIL import Image
import numpy as np

img_path = r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792815271765_9cee6115.jpg'
img = Image.open(img_path).convert('RGB')
print('Image size:', img.size)

# Sample colors
arr = np.array(img)
# Let's find dark blue pixels (high B, low R) and red pixels (high R, low G, low B)
# Dark blue in this logo: R < 60, G < 60, B between 40 and 100
# Red in this logo: R > 150, G < 60, B < 60

blues = []
reds = []
for y in range(arr.shape[0]):
    for x in range(arr.shape[1]):
        r, g, b = arr[y, x]
        if r < 60 and g < 60 and b > 40:
            blues.append((r, g, b))
        elif r > 160 and g < 60 and b < 80:
            reds.append((r, g, b))

if blues:
    avg_blue = np.mean(blues, axis=0).astype(int)
    print('Average blue:', avg_blue, hex(avg_blue[0]), hex(avg_blue[1]), hex(avg_blue[2]))
if reds:
    avg_red = np.mean(reds, axis=0).astype(int)
    print('Average red:', avg_red, hex(avg_red[0]), hex(avg_red[1]), hex(avg_red[2]))
