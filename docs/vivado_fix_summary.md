# AGCWD Vivado — Complete Fix Summary

## Files Changed

| File | What was fixed |
|---|---|
| `vivado/rtl/agcwd_lut_fsm.v` | **Major rewrite** |
| `vivado/rtl/agcwd_rgb_top.v` | **Rewrite** — race condition + pipeline fix |
| `vivado/rtl/agcwd_pow_rom.v` | Changed to xpm_memory_sprom (true ROM) |
| `vivado/rtl/agcwd_hist_accum.v` | Histogram → distributed RAM (saves BRAMs) |
| `vivado/rtl/agcwd_lut_bram.v` | LUT → distributed RAM (saves BRAMs) |
| `vivado/sim/tb_agcwd_rgb_top.v` | **Rewrite** — off-by-one + handshake fix |
| `vivado/constraints/agcwd_rgb_top.xdc` | Added rst_n, IOSTANDARD, pin assignments |
| `vivado/scripts/run_agcwd_vivado.tcl` | Part aligned, error checking added |
| `vivado/scripts/generate_agcwd_pow_lut.py` | Fixed gamma=0 special case |
| `compare_hw_sw.py` | **New** — HW vs SW quality comparison |

---

## Bug Fixes Explained

### Bug 1 — Testbench off-by-one (Critical)
**Problem:** `frame_input_count == FRAME_PIXELS - 1` triggered the inter-frame gap *before* the last pixel was sent, so every frame was 1 pixel short. The histogram was always missing 1 count.

**Fix:** Check `== FRAME_PIXELS` *after* incrementing, so all pixels are sent before the gap.

### Bug 2 — Testbench output capture missed back-pressure (Critical)
**Problem:** Output pixels were captured on `m_axis_tvalid` alone, ignoring `m_axis_tready`. In real AXIS flow, `tuser`/`tlast` are only valid on handshake.

**Fix:** Gate capture on `m_axis_tvalid && m_axis_tready`.

### Bug 3 — Testbench frame counter used wrong variable for tuser
**Problem:** `tuser = (input_index % FRAME_PIXELS == 0)` — `input_index` already incremented each handshake, so the first pixel of frame 2 would get tuser correctly but intermediate re-runs could break due to the modulo.

**Fix:** Use a dedicated `pixels_sent_this_frame` counter reset to 0 each frame. `tuser = (pixels_sent_this_frame == 0)`.

### Bug 4 — Integer overflow in gamma_idx computation (Quality)
**Problem:** `(cdf_accum * 8'd255) / weighted_sum` — both operands are 32-bit, multiplication result silently truncated. For a 512×341 image, `cdf_accum` can reach ~44M; × 255 = ~11.2 billion → overflow.

**Fix:** Used 48-bit intermediate registers for `weighted_sum` and `cdf_accum`.

### Bug 5 — Imprecise sqrt approximation in calc_weight (Quality)
**Problem:** The original `sqrt_frac8` function iterated 256 values looking for the largest `i` where `i*i <= target`. The ratio was only 8-bit, causing severe quantization in the weighting.

**Fix:** Replaced with a non-restoring 16-bit integer sqrt operating on a Q0.16 fixed-point ratio. This gives 256× more precision in the weight values.

### Bug 6 — Missing pipeline stage for pow_rom read latency (Correctness)
**Problem:** The FSM issued `pow_en` and immediately wrote the LUT in the next state. But `xpm_memory_sdpram` has `READ_LATENCY_B=1`, so data arrives 1 cycle after the enable — the LUT was being written with **stale** pow_data.

**Fix:** Added `ST_POW_ISSUE → ST_POW_WAIT → ST_LUT_WRITE` — 2 states after `pow_en` before writing.

### Bug 7 — frame_sum reset bug in agcwd_rgb_top (Correctness)
**Problem:** On `frame_last_pixel`, the code checked `s_axis_tuser ? pixel : (accum + pixel)`. This is wrong: `frame_last_pixel` and `s_axis_tuser` should never coincide for a normal multi-pixel frame. But the guard caused incorrect results if they ever did.

**Fix:** Removed the tuser guard. `frame_sum = sum_accum + current_pixel` always, which is correct for any frame ≥ 1 pixel.

### Bug 8 — tuser/tlast pipeline mismatch (Correctness)
**Problem:** `agcwd_channel` has 2 clock cycles of latency (pixel accepted → pixel out valid). The top module was only delaying `tuser`/`tlast` by 1 cycle, so output sideband signals were 1 cycle early.

**Fix:** Added a proper 2-stage shift register for `tuser_pipe` and `tlast_pipe`.

### Bug 9 — power_rom gamma=0.0 edge case (Quality)
**Problem:** In `generate_agcwd_pow_lut.py`, `gamma_idx=0` → `gamma=0.0` → `0.0**0.0` in Python = 1.0, but `intensity=0` short-circuits to 0. Non-zero intensities with gamma=0 should all map to 255 (x^0 = 1).

**Fix:** Added `elif gamma == 0.0: output = 255` before the general power-law computation.

### Bug 10 — FPGA part mismatch (Implementation)
**Problem:** `AGCWD.xpr` targets `xc7a35tcpg236-1` (Basys3) but `run_agcwd_vivado.tcl` used `xc7a200tfbg484-2` (large Artix-7). This makes batch TCL create a different project than the GUI project.

**Fix:** Aligned both to `xc7a35tcpg236-1`.

### Bug 11 — BRAM resource exhaustion (Implementation)
**Problem:** 3× hist_accum + 3× lut_bram + 3× pow_rom = 9 BRAMs needed. Basys3 has 50 BRAMs total but the 256×256 pow_rom alone uses 4 BRAMs each (32KB) = 12 BRAMs just for 3 channels. Plus hist uses 32-bit×256 = 8KB each.

**Fix:**
- `agcwd_hist_accum.v`: changed to `MEMORY_PRIMITIVE("distributed")` — uses LUTRAM instead (256×32bit = 8KB → ~64 LUTs per channel)
- `agcwd_lut_bram.v`: changed to `MEMORY_PRIMITIVE("distributed")` — uses LUTRAM (256×8bit = 2KB → ~16 LUTs per channel)
- `agcwd_pow_rom.v`: kept as block RAM (true ROM, 64K×8bit = 512Kbit → 8 BRAMs per channel)
- Total BRAMs now: 3×8 = 24 (fits on Basys3's 50 BRAMs with headroom)

---

## Why HW Output Should Now Be Better

| Factor | Before | After |
|---|---|---|
| Pixels per frame | FRAME_PIXELS-1 (missing last pixel) | FRAME_PIXELS ✓ |
| Weight precision | 8-bit sqrt | 16-bit sqrt (256× more precise) |
| CDF overflow | Silently wraps → wrong gamma | 48-bit intermediates ✓ |
| pow_rom timing | Wrong data (1 cycle early) | Correct 2-cycle latency ✓ |
| gamma=0 mapping | Undefined (Python 0.0^0.0=1 but not explicit) | Explicit 255 ✓ |

---

## Complete Workflow

```bash
# Step 1: Convert image (already done for Little girls.png 512x341)
python png_to_hex.py --input "input/Little girls.png" ^
    --output vivado/mem/input_rgb.hex ^
    --metadata vivado/mem/input_rgb.json ^
    --repeat-frames 2

# Step 2: Regenerate power ROM (already done)
python vivado/scripts/generate_agcwd_pow_lut.py

# Step 3: Run Vivado simulation (batch mode)
vivado -mode batch -source vivado/scripts/run_agcwd_vivado.tcl

# Step 4: Convert HW output to PNG
python hex_to_png.py --input hw_out.hex --output hw_out.png --width 512 --height 341

# Step 5: Compare HW vs SW quality
python compare_hw_sw.py --hw hw_out.hex --input "input/Little girls.png" ^
    --width 512 --height 341 --output hw_sw_compare.png
```

> [!IMPORTANT]
> `hw_out.hex` is written to Vivado's simulation working directory.
> For XSim (default), check: `vivado_agcwd_proj/agcwd_vivado.sim/sim_1/behav/xsim/`

> [!NOTE]
> The `xpm_memory_sprom` primitive used in `agcwd_pow_rom.v` requires Vivado 2018.3+.
> If you get an elaboration error on older Vivado, change it back to `xpm_memory_sdpram` with `USE_MEM_INIT(1)`.
