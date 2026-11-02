import cv2
import numpy as np

# Load the reference ideal rendering
ref = cv2.imread('tools/sim_lcd_preview.png')
# ref is 128x128

# Load the warped captured image
cap = cv2.imread(r'C:/Users/14058/.gemini/antigravity/brain/fdc36b2b-df57-4546-9df0-aa5547085c72/screen_128x128.png')

print('ref shape:', ref.shape)
print('cap shape:', cap.shape)

# Let's test different stride shifts:
# What if the screen hardware width W_hw is not 128?
# If pixels are sent at 128 pixels per row, but display wraps at W_hw:
# row y in display will receive pixels from stream index [y * W_hw : (y+1) * W_hw]
# Let's simulate for W_hw in [128, 129, 130, 131, 132, 160]:
stream = ref.reshape(-1, 3) # 128 * 128 = 16384 pixels

for W_hw in [128, 129, 130, 131, 132, 133, 140, 160]:
    sim = np.zeros((128, W_hw, 3), dtype=np.uint8)
    total_pix = min(len(stream), 128 * W_hw)
    sim.flat[:total_pix*3] = stream[:total_pix].flat
    # crop or resize sim to 128x128
    sim_crop = sim[:, :128]
    cv2.imwrite(f'tools/sim_stride_{W_hw}.png', sim_crop)
    print(f'Wrote tools/sim_stride_{W_hw}.png')
