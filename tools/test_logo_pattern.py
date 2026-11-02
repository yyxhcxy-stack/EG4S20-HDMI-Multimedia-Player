# Test refined 16x16 matrix

logo_16x16 = [
    # 0123456789012345
    "......RRRRRRRRRR", # 0: Top red stripe (x=6..15)
    "....BB..........", # 1: Apex of A (x=4..5)
    "....B..RRRRRRRR.", # 2: A (x=4) + red stripe (x=7..14)
    "...BBB..........", # 3: A expanding (x=3..5)
    "...BB...RRRRRRR.", # 4: A (x=3..4) + red stripe (x=8..14)
    "...BB...........", # 5: A (x=3..4)
    "..BBBB...RRRRRR.", # 6: A (x=2..5) + red stripe (x=9..14)
    "..BBBB..........", # 7: A (x=2..5)
    "..BB.BB...RRRRR.", # 8: A crossbar / hole + red stripe (x=10..14)
    ".BB..BB.........", # 9: A with hole (x=1..2, 5..6)
    ".BB...BB...RRRR.", # 10: A with hole (x=1..2, 6..7) + red stripe (x=11..14)
    ".BB...BB........", # 11: A with hole
    "BB.....BB...RRR.", # 12: A (x=0..1, 7..8) + red stripe (x=12..14)
    "BB.....BB.......", # 13: A (x=0..1, 7..8)
    "BBBBBB..BB...RR.", # 14: A bottom bar (x=0..5, 8..9) + red stripe (x=13..14)
    "BBBBBB..BB......"  # 15: A base foot (x=0..5, 8..9)
]

for y, row in enumerate(logo_16x16):
    print(f"{y:2d}: " + "".join([".." if c=='.' else "BB" if c=='B' else "RR" for c in row]))
