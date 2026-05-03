# Hardware information of the AGCWD project

## 1) General description

The project is implemented in VHDL and designed to be synthesized on a Xilinx FPGA using Vivado 2018.2.
It processes RGB images in a streaming architecture, using 24-bit pixel data:

- 8 bits Red
- 8 bits Green
- 8 bits Blue

The design works on one pixel per clock cycle in principle, depending on the enabled stages and pipeline timing.

## 2) Top-level hardware module

The top module of the design is:

`agcwd_top.vhd`

This module connects all processing blocks together and manages:

- input pixel stream
- output pixel stream
- denoising control
- sharpening control
- balance control
- frame status signals

## 3) Main hardware interfaces

### Input signals

The design uses a streaming interface similar to AXI4-Stream:

- `s_axis_tdata[23:0]` — RGB input pixel
- `s_axis_tvalid` — input valid signal
- `s_axis_tready` — input ready signal
- `s_axis_tuser` — start of frame
- `s_axis_tlast` — end of line

### Output signals

The same type of interface is used for the output:

- `m_axis_tdata[23:0]` — enhanced RGB pixel
- `m_axis_tvalid` — output valid
- `m_axis_tready` — output ready
- `m_axis_tuser` — start of frame
- `m_axis_tlast` — end of line

## 4) Control signals

The project includes three control inputs:

- `enable_denoise`
- `enable_sharpen`
- `enable_balance`

These signals allow enabling or disabling specific enhancement stages.

## 5) Processing blocks used in hardware

The design is divided into several hardware blocks:

### a) `channel_stats.vhd`

Computes basic image statistics such as:

- mean intensity
- standard deviation
- dark/bright classification

### b) `bilateral_filter.vhd`

Performs a denoising-like smoothing stage to reduce noise while preserving edges.

### c) `gamma_lut_engine.vhd`

Implements the main enhancement stage used for AGCWD-like brightness/contrast adjustment.

### d) `gray_world_balance.vhd`

Applies white balance correction using the gray-world assumption.

### e) `unsharp_mask.vhd`

Adds a final enhancement step.
In your latest version, this stage has been simplified to avoid the black-line artifact.

## 6) Data format

The hardware works with:

- 24-bit RGB pixels
- 8-bit unsigned values per channel
- integer / fixed-point style processing

No floating-point unit is used, which makes the design more FPGA-friendly.

## 7) Clock and reset

The system uses:

- `clk` — main system clock
- `rst_n` — active-low reset

In simulation, the clock period is:

- 10 ns
- equivalent to 100 MHz

This is a typical FPGA clock frequency for image processing pipelines.

## 8) Memory usage

The design does not use a full frame buffer in the current architecture.
Instead, it uses:

- line-based processing
- local arrays / buffers
- small lookup tables

This is more suitable for FPGA implementation than storing the entire image in RAM.

## 9) Image size used in testing

For simulation, the image size currently used is:

- 960 x 640

This is only for testing and simulation.
The design itself is streaming-based and can be adapted to other resolutions.

## 10) Current hardware status

The project is currently:

- implemented in VHDL
- simulation-tested in Vivado
- organized as a streaming RGB enhancement pipeline
- compatible with FPGA synthesis

## 11) Hardware limitations / notes

A few important notes about the current version:

- The project is still mainly validated through simulation
- The input/output hex files are only for testbench use
- The current enhancement stages were adjusted to give a visible result in Vivado
- The final hardware utilization has not yet been fully reported
  - LUT usage
  - FF usage
  - BRAM usage
  - DSP usage

These values will be available after running full synthesis and implementation in Vivado.

## 12) Summary table

| Item               | Hardware info                    |
| ------------------ | -------------------------------- |
| Language           | VHDL                             |
| Tool               | Vivado 2018.2                    |
| Target             | Xilinx FPGA                      |
| Input format       | 24-bit RGB                       |
| Output format      | 24-bit RGB                       |
| Processing mode    | Streaming                        |
| Clock              | 100 MHz in simulation            |
| Reset              | Active-low                       |
| Main module        | `agcwd_top.vhd`                  |
| Image size tested  | 960 x 640                        |
| Floating point     | Not used                         |
| Full frame buffer  | Not used                         |
| Control signals    | denoise / sharpen / balance      |

## 13) Short report version

The AGCWD project is implemented in VHDL as a streaming RGB image enhancement pipeline for FPGA. It uses 24-bit pixel input and output, with separate control signals for denoising, sharpening, and white balance. The top-level module integrates several hardware blocks, including image statistics, filtering, and enhancement stages. The architecture is designed for Vivado synthesis and simulation on Xilinx FPGA platforms, using integer and fixed-point arithmetic instead of floating-point processing.

---

# Hardware architecture diagram

## 1) Hardware architecture diagram text

```text
                        +----------------------+
                        |   Input RGB Stream   |
                        | 24-bit (R,G,B pixel) |
                        |  s_axis_tdata        |
                        |  s_axis_tvalid       |
                        |  s_axis_tuser        |
                        |  s_axis_tlast        |
                        +----------+-----------+
                                   |
                                   v
                        +----------------------+
                        |    agcwd_top.vhd     |
                        |  Top-Level Control   |
                        +----+----+----+-------+
                             |    |    |
           +-----------------+    |    +------------------+
           |                      |                       |
           v                      v                       v
+-------------------+   +--------------------+   +----------------------+
|   channel_stats   |   |  bilateral_filter  |   |  gamma_lut_engine    |
| Mean / Std /      |   | Denoising stage    |   | Brightness / contrast |
| Dark / Bright     |   |                    |   | enhancement stage     |
+-------------------+   +--------------------+   +----------+-----------+
                                                             |
                                                             v
                                                +----------------------+
                                                |  gray_world_balance   |
                                                | White balance adjust  |
                                                +----------+-----------+
                                                             |
                                                             v
                                                +----------------------+
                                                |    unsharp_mask      |
                                                | Final enhancement    |
                                                +----------+-----------+
                                                             |
                                                             v
                        +--------------------------------------+
                        |          Output RGB Stream           |
                        |      24-bit enhanced pixel          |
                        |  m_axis_tdata / m_axis_tvalid        |
                        |  m_axis_tuser / m_axis_tlast         |
                        +--------------------------------------+
```

## 2) Block-by-block explanation

### A. `agcwd_top.vhd` — Top-level module

This is the main controller of the design.

**Role:**

- Connects all processing blocks together
- Receives the input RGB stream
- Sends the enhanced RGB stream out
- Controls optional stages like denoising, sharpening, and balance
- Provides frame status signals

**Why it is important:**

It is the entry point of the FPGA design and defines the full data path.

---

### B. `channel_stats.vhd` — Image statistics block

This block analyzes the image frame.

**Role:**

- Computes mean intensity
- Computes standard deviation
- Detects whether the image is:
  - dark
  - bright
  - normal

**Why it is important:**

It helps the system decide how strongly to enhance the image.

---

### C. `bilateral_filter.vhd` — Denoising block

This block reduces noise while trying to preserve edges.

**Role:**

- Smooths the image
- Keeps strong edges more visible than a normal blur
- Reduces small pixel variations

**Why it is important:**

It improves image quality before enhancement.

---

### D. `gamma_lut_engine.vhd` — Main enhancement block

This is the core enhancement part of the project.

**Role:**

- Adjusts pixel intensity
- Improves brightness and contrast
- Applies enhancement according to the image statistics

**Why it is important:**

It is the main block responsible for making the image look better.

---

### E. `gray_world_balance.vhd` — White balance block

This block tries to correct color imbalance.

**Role:**

- Compares red, green, and blue channel behavior
- Applies correction if one color dominates
- Makes the image look more natural

**Why it is important:**

It avoids unwanted color tint and improves visual realism.

---

### F. `unsharp_mask.vhd` — Final enhancement block

This is the last processing stage.

**Role:**

- Adds a small visual improvement
- Enhances clarity slightly
- In your latest version, it was simplified to avoid artifacts like the black line

**Why it is important:**

It gives a final polish to the image, but must remain carefully controlled.

---

## 3) Short conclusion paragraph

The AGCWD hardware project is designed as a streaming RGB image enhancement pipeline for FPGA implementation. It processes 24-bit color pixels through several hardware blocks, including image statistics, denoising, adaptive enhancement, white balance correction, and final sharpening. The design is implemented in VHDL and tested in Vivado using simulation. Its modular structure allows each enhancement stage to be enabled or disabled, making the system flexible and suitable for FPGA-based image processing applications.

### Optional: Even shorter version for presentation

The AGCWD FPGA project uses a modular streaming architecture to enhance RGB images in real time. It includes blocks for statistics calculation, denoising, adaptive gamma enhancement, white balance correction, and final sharpening. The design is implemented in VHDL and simulated in Vivado.