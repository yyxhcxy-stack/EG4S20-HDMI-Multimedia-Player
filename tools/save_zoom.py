from PIL import Image

im = Image.open('tools/crop_1x_displayed.png')
# Crop around x=380..440, y=100..400
zoom = im.crop((380, 80, 450, 400))
# Scale up 2x so we can see every pixel clearly
zoom2x = zoom.resize((140, 640), Image.NEAREST)
zoom2x.save('tools/zoom_crease.png')
print("Saved tools/zoom_crease.png!")
