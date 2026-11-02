pattern_v3 = [
    # 0123456789012345
    "......RRRRRRRRRR", # 0: Stripe 0: x=6..15
    "....BB..........", # 1: Apex of A: x=4..5
    "....BB.RRRRRRRR.", # 2: A: x=4..5, gap: 6, Stripe 1: x=7..14
    "...BBB..........", # 3: A: x=3..5
    "...BBB..RRRRRRR.", # 4: A: x=3..5, gap: 6..7, Stripe 2: x=8..14
    "...BBBB.........", # 5: A: x=3..6
    "...BBBB.RRRRRR..", # 6: A: x=3..6, gap: 7, Stripe 3: x=8..13
    "..BBBBB.........", # 7: A: x=2..6
    "..BB.BB..RRRRR..", # 8: A: x=2..3, 5..6 (hole x=4), gap: 7..8, Stripe 4: x=9..13
    "..BB..BB........", # 9: A: x=2..3, 6..7 (hole x=4..5)
    ".BB...BB.RRRR...", # 10: A: x=1..2, 6..7 (hole x=3..5), gap: 8, Stripe 5: x=9..12
    ".BB...BB........", # 11: A: x=1..2, 6..7 (hole x=3..5)
    ".BB....BB.RRR...", # 12: A: x=1..2, 7..8 (hole x=3..6), gap: 9, Stripe 6: x=10..12
    "BB.....BB.......", # 13: A: x=0..1, 7..8 (hole x=2..6)
    "BBBBBB..BB.RR...", # 14: A base: x=0..5, 8..9 (gap x=6..7), gap: 10, Stripe 7: x=11..12
    "BBBBBB..BB......"  # 15: A base: x=0..5, 8..9 (gap x=6..7)
]

for y, row in enumerate(pattern_v3):
    print(f"{y:2d}: " + "".join(["  " if c=='.' else "BB" if c=='B' else "RR" for c in row]))
