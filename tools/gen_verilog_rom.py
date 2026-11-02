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

print("Verilog bit vectors:")
for y, row in enumerate(pattern_v3):
    b_bits = "".join(['1' if c=='B' else '0' for c in row])
    r_bits = "".join(['1' if c=='R' else '0' for c in row])
    
    b_hex = f"{int(b_bits, 2):04X}"
    r_hex = f"{int(r_bits, 2):04X}"
    
    b_bin = f"16'b{b_bits[:4]}_{b_bits[4:8]}_{b_bits[8:12]}_{b_bits[12:]}"
    r_bin = f"16'b{r_bits[:4]}_{r_bits[4:8]}_{r_bits[8:12]}_{r_bits[12:]}"
    
    print(f"4'd{y:<2}: begin row_b = {b_bin}; row_r = {r_bin}; end // {row}")
