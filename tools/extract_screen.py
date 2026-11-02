import cv2
import numpy as np

img = cv2.imread(r'C:/Users/14058/.gemini/antigravity/brain/fdc36b2b-df57-4546-9df0-aa5547085c72/lcd_crop.jpg')
pts_src = np.float32([[23, 88], [180, 56], [212, 202], [54, 236]])
pts_dst = np.float32([[0, 0], [128, 0], [128, 128], [0, 128]])

M = cv2.getPerspectiveTransform(pts_src, pts_dst)
warped = cv2.warpPerspective(img, M, (128, 128))
cv2.imwrite(r'C:/Users/14058/.gemini/antigravity/brain/fdc36b2b-df57-4546-9df0-aa5547085c72/screen_128x128.png', warped)
print('Saved screen_128x128.png')
