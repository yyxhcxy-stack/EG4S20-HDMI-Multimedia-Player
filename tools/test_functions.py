pattern_v3 = [
    # 0123456789012345
    "......RRRRRRRRRR", # 0
    "....BB..........", # 1
    "....BB.RRRRRRRR.", # 2
    "...BBB..........", # 3
    "...BBB..RRRRRRR.", # 4
    "...BBBB.........", # 5
    "...BBBB.RRRRRR..", # 6
    "..BBBBB.........", # 7
    "..BB.BB..RRRRR..", # 8
    "..BB..BB........", # 9
    ".BB...BB.RRRR...", # 10
    ".BB...BB........", # 11
    ".BB....BB.RRR...", # 12
    "BB.....BB.......", # 13
    "BBBBBB..BB.RR...", # 14
    "BBBBBB..BB......"  # 15
]

# Simulate fn_logo_is_red and fn_logo_is_blue
def fn_logo_is_red(y, x):
    if y % 2 == 1:
        return False
    rows = {
        0: 0b0000_0011_1111_1111,
        1: 0b0000_0001_1111_1110,
        2: 0b0000_0000_1111_1110,
        3: 0b0000_0000_1111_1100,
        4: 0b0000_0000_0111_1100,
        5: 0b0000_0000_0111_1000,
        6: 0b0000_0000_0011_1000,
        7: 0b0000_0000_0001_1000,
    }
    row = rows[y // 2]
    return bool((row >> (15 - x)) & 1)

def fn_logo_is_blue(y, x):
    rows = {
        0: 0,
        1: 0b0000_1100_0000_0000,
        2: 0b0000_1100_0000_0000,
        3: 0b0001_1100_0000_0000,
        4: 0b0001_1100_0000_0000,
        5: 0b0001_1110_0000_0000,
        6: 0b0001_1110_0000_0000,
        7: 0b0011_1110_0000_0000,
        8: 0b0011_0110_0000_0000,
        9: 0b0011_0011_0000_0000,
        10: 0b0110_0011_0000_0000,
        11: 0b0110_0011_0000_0000,
        12: 0b0110_0001_1000_0000,
        13: 0b1100_0001_1000_0000,
        14: 0b1111_1100_1100_0000,
        15: 0b1111_1100_1100_0000,
    }
    row = rows[y]
    return bool((row >> (15 - x)) & 1)

# Verify against pattern
all_match = True
for y in range(16):
    for x in range(16):
        b = fn_logo_is_blue(y, x)
        r = fn_logo_is_red(y, x)
        assert not (b and r), f"Overlap at ({x},{y})"
        expected = pattern_v3[y][x]
        actual = 'B' if b else 'R' if r else '.'
        if actual != expected:
            print(f"Mismatch at ({x},{y}): expected {expected}, got {actual}")
            all_match = False

if all_match:
    print("ALL 256 PIXELS MATCH EXACTLY!")
