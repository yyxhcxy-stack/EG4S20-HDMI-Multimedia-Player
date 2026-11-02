from PIL import Image

im = Image.open(r'C:\fpga\TF_CARD_DEPLOY\5.bmp')
print("5.bmp size:", im.size)

# Save 8 vertical strips of 128 pixels each:
# 0..128, 128..256, 256..384, 384..512, 512..640, 640..768, 768..896, 896..1024
for i in range(8):
    strip = im.crop((i*128, 0, (i+1)*128, 768))
    strip.save(f'tools/strip_{i*128}_{(i+1)*128}.png')
print("Saved 8 strips!")
