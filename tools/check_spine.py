from PIL import Image

im = Image.open('tools/crop_1x_displayed.png')
# Crop x = 380 to 460, y = 100 to 450
sub = im.crop((380, 100, 460, 450))
sub.save('tools/crop_sub_spine.png')
print("Saved tools/crop_sub_spine.png")
