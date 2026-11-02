import struct
import os

folder = r"C:\fpga\TF_CARD_DEPLOY"
for name in ['1.bmp', '2.bmp', '3.bmp', '4.bmp', '5.bmp']:
    p = os.path.join(folder, name)
    if os.path.exists(p):
        with open(p, 'rb') as f:
            data = f.read(54)
            magic, size, res1, res2, offset = struct.unpack('<2sIHHI', data[:14])
            hdr_size, w, h, planes, bpp, comp = struct.unpack('<IiiHHI', data[14:34])
            print(f"{name:<10}: {w}x{h}, bpp={bpp}, offset={offset}, filesize={size}, calc_bytes={w*h*(bpp//8)}")
