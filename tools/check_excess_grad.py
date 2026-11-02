from PIL import Image
import numpy as np

actual = np.array(Image.open('tools/screen_actual_displayed.png'))
expected = np.array(Image.open('tools/crop_1x_displayed.png'))

# Compute column-to-column horizontal gradient in actual screen:
grad_actual = np.mean(np.abs(actual[50:430, 1:, :] - actual[50:430, :-1, :]), axis=(0, 2))
grad_expected = np.mean(np.abs(expected[50:430, 1:, :] - expected[50:430, :-1, :]), axis=(0, 2))

# Find columns where actual gradient is much higher than expected gradient:
excess_grad = grad_actual - grad_expected
top_excess = np.argsort(excess_grad)[::-1][:15]
print("Top excess gradient columns in actual screen vs expected:")
for c in sorted(top_excess):
    print(f"Col {c} -> {c+1}: actual={grad_actual[c]:.2f}, expected={grad_expected[c]:.2f}, excess={excess_grad[c]:.2f}")
