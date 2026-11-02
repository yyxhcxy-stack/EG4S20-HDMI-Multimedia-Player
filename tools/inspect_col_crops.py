from PIL import Image
import numpy as np

c608 = np.array(Image.open('tools/crop_col_608.png'))
c696 = np.array(Image.open('tools/crop_col_696.png'))

print("c608 shape:", c608.shape)
print("c696 shape:", c696.shape)

# Let's check the column differences inside c608 (columns 0..60 correspond to photo x 580..640):
diff608 = np.mean(np.abs(c608[:, 1:, :] - c608[:, :-1, :]), axis=(0, 2))
print("Max diff in c608 at rel col:", np.argmax(diff608), "photo x:", 580 + np.argmax(diff608), "val:", np.max(diff608))

# Let's check the column differences inside c696 (columns 0..50 correspond to photo x 670..720):
diff696 = np.mean(np.abs(c696[:, 1:, :] - c696[:, :-1, :]), axis=(0, 2))
print("Max diff in c696 at rel col:", np.argmax(diff696), "photo x:", 670 + np.argmax(diff696), "val:", np.max(diff696))
