import math

def generate_lut(gamma, name):
    print(f"constant {name} : lut_array_t := (")
    lut = []
    for i in range(256):
        val = int(round(255 * (i / 255.0) ** gamma))
        lut.append(val)
    
    for i in range(0, 256, 16):
        row = lut[i:i+16]
        line = ", ".join(f"{v:3}" for v in row)
        if i + 16 < 256:
            print(f"      {line},")
        else:
            print(f"      {line}")
    print(");")

generate_lut(0.4, "GAMMA_04_LUT")
