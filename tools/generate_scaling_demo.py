"""Create 24-bit BMP fixtures and HDMI previews from actual CXXRTL pixel dumps."""
from pathlib import Path
from PIL import Image, ImageDraw
import struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/scaling_preview"
SIZES = [(640,480),(320,240),(333,221),(160,120),(640,360),(240,320),
         (1,1),(1,479),(639,1),(2,3),(3,2),(639,479),(127,129)]


def pixels(w, h, pattern):
    for y in range(h):
        for x in range(w):
            if pattern == "checker":
                yield (255,255,255) if (x ^ y) & 1 else (0,0,0)
            elif pattern == "corners":
                if x == 0 and y == 0: yield (255,0,0)
                elif x == w-1 and y == 0: yield (0,255,0)
                elif x == 0 and y == h-1: yield (0,0,255)
                elif x == w-1 and y == h-1: yield (255,255,0)
                elif x == 0 or y == 0 or x == w-1 or y == h-1: yield (255,255,255)
                else: yield (18,52,86)
            else:
                yield ((x*17+y*3)&255, (x*5+y*31)&255, (x*13+y*11)&255)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    fixtures = OUT / "bmp_inputs"
    fixtures.mkdir(exist_ok=True)
    for w,h in SIZES:
        for pattern in ("gradient", "checker", "corners"):
            im = Image.new("RGB", (w,h))
            im.putdata(list(pixels(w,h,pattern)))
            path = fixtures / f"{w}x{h}_{pattern}.bmp"
            im.save(path)
            header = path.read_bytes()[:54]
            assert struct.unpack_from("<ii",header,18) == (w,h)
            assert struct.unpack_from("<H",header,28)[0] == 24
    sheet = Image.new("RGB",(1280,1020),(20,28,40))
    labels = ["1x: original centered", "2x: center crop + bilinear",
              "0.5x: rounded 2x2 average", "AUTO: aspect fit + bilinear"]
    for mode,label in enumerate(labels):
        source = OUT / f"mode{mode}.ppm"
        if not source.exists():
            raise SystemExit("Run the scaling_core RTL suite first to generate pixel dumps.")
        with Image.open(source) as im:
            frame = Image.new("RGB",(640,480),(0,0,0))
            frame.paste(im,((640-im.width)//2,(480-im.height)//2))
            frame.save(OUT / f"mode{mode}_hdmi.png")
            tile = Image.new("RGB",(640,510),(20,28,40))
            ImageDraw.Draw(tile).text((12,8),f"333x221 BMP | {label}",fill="white")
            tile.paste(frame,(0,30))
            sheet.paste(tile,((mode%2)*640,(mode//2)*510))
    sheet.save(OUT / "scaling_modes.png")
    print(f"Created {len(SIZES)*3} valid BMP fixtures and four actual RTL previews in {OUT}")


if __name__ == "__main__":
    main()
