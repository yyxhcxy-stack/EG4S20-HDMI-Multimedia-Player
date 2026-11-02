from PIL import Image, ImageDraw

photo = Image.open(r'C:/Users/ly/.gemini/antigravity/brain/40b3ae6d-de44-4abb-9e2d-491feb9a7eed/.user_uploaded/media_1792821319064_dca271f9.jpg')
draw = ImageDraw.Draw(photo)

# Draw vertical lines at several X coordinates so we can pinpoint exactly what is where:
for x in [550, 600, 650, 700]:
    draw.line([(x, 0), (x, 768)], fill=(255, 0, 0), width=2)
photo.save('tools/annotated_photo.png')
print("Saved annotated photo!")
