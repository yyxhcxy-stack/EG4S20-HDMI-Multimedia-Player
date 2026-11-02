from PIL import Image

# Strip 640..768 is where "曾侯" is:
im = Image.open(r'C:\fpga\TF_CARD_DEPLOY\5.bmp')
crop_640_768 = im.crop((640, 100, 768, 500))
crop_640_768.save('tools/crop_640_768.png')

# Strip 384..512 is where "乙乍持用終" is:
crop_384_512 = im.crop((384, 100, 512, 500))
crop_384_512.save('tools/crop_384_512.png')

# Strip 512..640 is between them:
crop_512_640 = im.crop((512, 100, 640, 500))
crop_512_640.save('tools/crop_512_640.png')
print("Crops saved!")
