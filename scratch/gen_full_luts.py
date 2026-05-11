import math

def get_lut(gamma):
    return [int(round(255 * (i / 255.0) ** gamma)) for i in range(256)]

lut = get_lut(0.3)

# VHDL format
print("VHDL:")
for i in range(0, 256, 16):
    row = lut[i:i+16]
    print(", ".join(f"{v:3}" for v in row) + ",")

# Python format
print("\nPython:")
print(lut)
