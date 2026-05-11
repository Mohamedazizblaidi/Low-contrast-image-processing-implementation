lut_05 = [int((i/255.0)**0.5 * 255.0) for i in range(256)]
lut_20 = [int((i/255.0)**2.0 * 255.0) for i in range(256)]

with open("lut_vhdl.txt", "w") as f:
    f.write("type lut_array_t is array (0 to 255) of integer;\n")
    f.write("constant GAMMA_05_LUT : lut_array_t := (\n")
    for i in range(0, 256, 16):
        f.write("    " + ", ".join(f"{x:3d}" for x in lut_05[i:i+16]) + ("," if i < 240 else "") + "\n")
    f.write(");\n\n")

    f.write("constant GAMMA_20_LUT : lut_array_t := (\n")
    for i in range(0, 256, 16):
        f.write("    " + ", ".join(f"{x:3d}" for x in lut_20[i:i+16]) + ("," if i < 240 else "") + "\n")
    f.write(");\n")
