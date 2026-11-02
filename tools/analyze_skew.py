import cv2
import numpy as np

img = cv2.imread(r'C:/Users/14058/.gemini/antigravity/brain/fdc36b2b-df57-4546-9df0-aa5547085c72/lcd_crop.jpg')
h, w, _ = img.shape
print(f'Cropped image size: {w}x{h}')

debug = img.copy()
for x in range(0, w, 20):
    cv2.line(debug, (x, 0), (x, h), (100, 100, 100), 1)
    cv2.putText(debug, str(x), (x, 15), cv2.FONT_HERSHEY_SIMPLEX, 0.3, (0, 255, 255), 1)
for y in range(0, h, 20):
    cv2.line(debug, (0, y), (w, y), (100, 100, 100), 1)
    cv2.putText(debug, str(y), (5, y), cv2.FONT_HERSHEY_SIMPLEX, 0.3, (0, 255, 255), 1)
cv2.imwrite(r'C:/Users/14058/.gemini/antigravity/brain/fdc36b2b-df57-4546-9df0-aa5547085c72/debug_grid.png', debug)
print('Saved debug_grid.png')
