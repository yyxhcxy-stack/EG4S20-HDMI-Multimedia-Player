strings = [
    "[1:IDLE]",
    "[2:SEEK]",
    "[3:RAM ]",
    "[4:AUTO]",
    "[4:MANU]",
    "[FAIL  ]"
]

for s in strings:
    assert len(s) == 8, f"Length of '{s}' is {len(s)}, expected 8!"
    print(f"'{s}': OK (len=8)")
