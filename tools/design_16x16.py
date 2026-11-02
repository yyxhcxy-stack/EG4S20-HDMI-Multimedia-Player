# Design 16x16 matrix
# Columns 0 to 15, Rows 0 to 15
# Blue 'A' on left, Red stripes on right

# Let's map coordinates:
# Apex of A: around x=4..5 at y=1
# Right edge of A slopes from x=5 (y=1) to x=10 (y=15)
# Left edge of A slopes from x=4 (y=1) to x=0 (y=15)
# Red stripes are on even rows: 0, 2, 4, 6, 8, 10, 12, 14
# Red stripes start 1 pixel to the right of A's right edge
# Red stripes end on the right, tapering leftwards

grid = []
for y in range(16):
    row = ['.'] * 16
    
    # 1. Red stripes on even rows:
    # Top stripe y=0: from x=6 to x=15
    # y=2: from x=7 to x=14
    # y=4: from x=8 to x=13
    # y=6: from x=9 to x=12
    # y=8: from x=10 to x=12
    # y=10: from x=10 to x=11
    # y=12: from x=11 to x=11
    # Let's check right edge: x_right = 15 - y//2
    # Left edge: x_left = 6 + (y+1)//2
    if y % 2 == 0:
        x_left = 6 + (y + 1) // 2
        x_right = 15 - (y // 2)
        for x in range(x_left, x_right + 1):
            if x < 16:
                row[x] = 'R'
                
    grid.append(row)

# 2. Blue 'A':
# y=0: empty or apex? Apex starts at y=1 or y=0? In logo, apex is slightly below top stripe!
# In the original logo, the top red stripe (y=0) is at the very top, and the apex of 'A' starts right below or near row 1.
# Row 1: x=4..5
# Row 2: x=4..5
# Row 3: x=3..5
# Row 4: x=3..6
# Row 5: x=3..6
# Row 6: x=2..6
# Row 7: x=2..7
# Row 8: x=2..7 (crossbar connects x=2..7)
# Row 9: x=1..7 (crossbar connects x=1..7)
# Row 10: x=1..2 and x=6..7 (hole in middle x=3..5)
# Row 11: x=1..2 and x=7..8 (hole in middle x=3..6)
# Row 12: x=1..2 and x=7..8 (hole in middle)
# Row 13: x=0..2 and x=8..9 (hole in middle)
# Row 14: x=0..4 (bottom foot/bar) and x=8..9
# Row 15: x=0..4 and x=8..9

# Let's refine based on the exact mathematical shape
def plot_grid(g):
    for y, r in enumerate(g):
        print(f"{y:2d}: " + "".join([".." if c=='.' else "BB" if c=='B' else "RR" for c in r]))

