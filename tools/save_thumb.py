from PIL import Image

im = Image.open('tools/center_crop_5.png')
# Save at 320x240 to inspect
thumb = im.resize((320, 240))
thumb.save('tools/center_crop_thumb.png')
print("Saved tools/center_crop_thumb.png")
