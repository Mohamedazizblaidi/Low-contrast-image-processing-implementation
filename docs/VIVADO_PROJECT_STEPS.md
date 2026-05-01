# Vivado Project Steps for AGCWD Image Processing

## Purpose

This guide shows how to:

1. Convert a low-contrast image to a Vivado input hex file
2. Add all AGCWD RTL, memory, testbench, and constraint files to a Vivado project
3. Run simulation
4. Export the processed image and rebuild it as a PNG

## Required Files

The project keeps Vivado files under a dedicated `vivado` folder:

- `vivado/rtl/*.v`
- `vivado/sim/tb_agcwd_rgb_top.v`
- `vivado/constraints/agcwd_rgb_top.xdc`
- `vivado/mem/agcwd_pow_lut.mem`
- `vivado/scripts/generate_agcwd_pow_lut.py`
- `vivado/scripts/add_agcwd_files_to_project.tcl`
- `png_to_hex.py`
- `hex_to_png.py`

## Step 1. Convert the input image to hex

Run:

```bash
python png_to_hex.py --input "input/image.png" --output "vivado/mem/input_rgb.hex" --metadata "vivado/mem/input_rgb.json" --repeat-frames 2
```

Notes:

- Use `repeat-frames 2`
- Frame 1 is used to build the histogram
- Frame 2 is the first valid processed output frame

## Step 2. Generate the AGCWD power ROM

Run:

```bash
python vivado/scripts/generate_agcwd_pow_lut.py
```

This creates `vivado/mem/agcwd_pow_lut.mem`, which is used by `vivado/rtl/agcwd_pow_rom.v`.

## Step 3. Open Vivado

Open Vivado and either:

1. Create a new RTL project
2. Or open an existing project

Recommended part:

- `xc7a200tfbg484-2`

## Step 4. Set the project folder

In Vivado Tcl Console:

```tcl
cd {C:/Users/ACER/Downloads/Electronics project}
```

## Step 5. Add all AGCWD files directly to the current project

In Vivado Tcl Console:

```tcl
source vivado/scripts/add_agcwd_files_to_project.tcl
```

What this does:

- Adds RTL files to `sources_1`
- Adds the testbench to `sim_1`
- Adds `vivado/mem/agcwd_pow_lut.mem` and `vivado/mem/input_rgb.hex` to `sim_1`
- Adds the XDC file to `constrs_1`
- Sets:
  - design top = `agcwd_rgb_top`
  - simulation top = `tb_agcwd_rgb_top`

## Step 6. Check image resolution parameters

Open these files and make sure the dimensions match your test image:

- `vivado/rtl/agcwd_rgb_top.v`
- `vivado/sim/tb_agcwd_rgb_top.v`

Parameters to verify:

```verilog
parameter integer IMG_W = 1920;
parameter integer IMG_H = 1080;
```

If your image is not `1920x1080`, change both files to the correct width and height.

## Step 7. Run simulation

In Vivado:

1. Go to `Flow Navigator`
2. Click `Run Simulation`
3. Select `Run Behavioral Simulation`

The testbench will:

- Read `vivado/mem/input_rgb.hex`
- Stream 2 frames into the AGCWD design
- Capture frame 2 output
- Write:

```text
hw_out.hex
```

## Step 8. Convert the output hex back to PNG

After simulation completes, run:

```bash
python hex_to_png.py --input hw_out.hex --output hw_out.png --width 1920 --height 1080
```

Replace width and height if you changed the resolution.

## Step 9. Verify the result

You should now have:

- `hw_out.png`

Compare it visually against the original low-contrast image.

## Optional: Build the project from Tcl in batch mode

If you prefer batch mode instead of the GUI, use:

```bash
vivado -mode batch -source vivado/scripts/run_agcwd_vivado.tcl
```

## Important Notes

- This AGCWD implementation is frame-delayed
- Frame 1 builds the histogram and LUT
- Frame 2 is the valid enhanced image
- BRAM is used for:
  - histogram memory
  - output LUT memory
  - AGCWD power ROM

## If simulation fails

Check these first:

1. `vivado/mem/input_rgb.hex` exists
2. `vivado/mem/agcwd_pow_lut.mem` exists
3. `IMG_W` and `IMG_H` match the image
4. The project top is `agcwd_rgb_top`
5. The simulation top is `tb_agcwd_rgb_top`
