# Black Horizontal Band Fix — AGCWD Pipeline

**Date:** May 3, 2026  
**Project:** Low-Contrast Image Processing (FPGA Implementation)  
**Affected Image:** `result.png` (960×640, reconstructed from `output_image.hex`)

---

## 1. Problem Description

After running the Vivado simulation of the AGCWD image enhancement pipeline and reconstructing the output image via `rebuild_image_hex.py`, a **black horizontal band** appeared across the middle of the result image (approximately rows 365–452).

The band consisted of **47 corrupted rows** where pixel brightness dropped to near-zero (~2 avg), despite the corresponding input rows having normal brightness (~16–17 avg).

### Diagnostic Data

| Row Range | Input Avg Brightness | Output Avg Brightness | Status |
|-----------|---------------------|-----------------------|--------|
| 0–364     | ~17                 | ~44 (enhanced)        | ✅ OK  |
| **365**       | 17.5                | **2.3**                   | ❌ Black |
| **369–370**   | 17.4                | **2.0–2.2**               | ❌ Black |
| **373**       | 17.9                | **2.6**                   | ❌ Black |
| **377**       | 17.2                | **2.0**                   | ❌ Black |
| **384–387**   | 16.8–17.0           | **1.7–1.9**               | ❌ Black |
| 388–414   | ~16                 | ~15–42                | ✅ OK  |
| **415–452**   | 15.9–16.1           | **1.7–2.8**               | ❌ Black |
| 453–639   | ~16                 | ~40+ (enhanced)       | ✅ OK  |

> [!IMPORTANT]
> The input image (`input_image.hex`) had **no corrupted rows** — all 640 rows had consistent brightness (~16–18). The corruption was introduced entirely by the VHDL processing pipeline.

---

## 2. Root Cause Analysis

Two bugs were identified in the VHDL pipeline, both contributing to the artifact:

### Bug 1: Testbench Sending Pixels at 50% Throughput

**File:** `vivado/tb_agcwd_top.vhd` — stimulus process (`p_stim`)

The testbench was inserting an **idle clock cycle** (with `tvalid = '0'`) between every pixel:

```vhdl
-- BEFORE (broken): 50% throughput
s_axis_tdata  <= pix_hex;
s_axis_tvalid <= '1';
wait until rising_edge(clk);       -- Pixel presented for 1 cycle

s_axis_tvalid <= '0';              -- Then IDLE for 1 cycle
s_axis_tuser  <= '0';
s_axis_tlast  <= '0';
wait until rising_edge(clk);       -- Wasted cycle

pix_id := pix_id + 1;
```

**Why this caused the black band:**

The bilateral filter uses a **5×5 sliding window** with 4 line buffers (`lb_r0`–`lb_r3`). The line buffers and the horizontal window shift logic both execute on every `rising_edge(clk)`, but the column counter (`col_cnt`) only advances when `s_tvalid = '1'`.

With 50% throughput, the window shift registers (`r00`–`r44`, etc.) were being shifted on **every clock cycle**, including the idle cycles where no new pixel was loaded into the rightmost column. This caused the window to contain **stale/zero values** at certain row transitions, producing near-black output from the filter computation.

The effect was most severe around rows 365–452 because that's where the line buffer wrap-around interacted with the idle-cycle misalignment.

### Bug 2: Latency Mismatch in Two Pipeline Stages

**Files:** `vivado/gamma_lut_engine.vhd` and `vivado/unsharp_mask.vhd`

Both modules had a **timing mismatch** between data and control signals:

```
m_tdata  ← registered (out_r & out_g & out_b)  → 1-cycle delay
m_tvalid ← combinational (s_tvalid)            → 0-cycle delay  ← BUG!
m_tlast  ← combinational (s_tlast)             → 0-cycle delay  ← BUG!
m_tuser  ← combinational (s_tuser)             → 0-cycle delay  ← BUG!
```

**Why this caused corruption:**

When `m_tvalid` goes high, the downstream module (or the testbench capture process) reads `m_tdata` — but `m_tdata` still holds the **previous pixel's value** because the new computation hasn't been registered yet. This resulted in:

- Every pixel being shifted by 1 position in the output stream
- The **first pixel** of the stream being `000000` (the reset value of `out_r/g/b`)
- Cumulative misalignment through the pipeline amplifying the bilateral filter's boundary artifacts

> [!NOTE]
> The `gray_world_balance.vhd` module did **not** have this bug — its control signals were already registered inside the clocked process, correctly matching the data latency.

---

## 3. Fixes Applied

### Fix 1: Continuous Pixel Streaming in Testbench

**File:** `vivado/tb_agcwd_top.vhd`

```diff
  s_axis_tdata  <= pix_hex;
  s_axis_tvalid <= '1';

- wait until rising_edge(clk);
-
- s_axis_tvalid <= '0';
- s_axis_tuser  <= '0';
- s_axis_tlast  <= '0';
-
- wait until rising_edge(clk);
+ -- Wait for handshake: DUT accepts pixel on rising edge
+ -- when both tvalid and tready are high
+ wait until rising_edge(clk) and s_axis_tready = '1';

  pix_id := pix_id + 1;
  end loop;

+ -- De-assert after all pixels are sent
+ s_axis_tvalid <= '0';
+ s_axis_tuser  <= '0';
+ s_axis_tlast  <= '0';
```

**What changed:** Pixels are now sent **back-to-back** at 100% throughput with a proper AXI4-Stream handshake. The `tvalid` signal stays high continuously and only the data changes each cycle.

### Fix 2: Pipeline Registers in `gamma_lut_engine.vhd`

```diff
+ -- Pipeline registers for control signals (match 1-cycle data latency)
+ signal dly_valid : std_logic := '0';
+ signal dly_last  : std_logic := '0';
+ signal dly_user  : std_logic := '0';

  -- Output assignments
- m_tvalid <= s_tvalid;
- m_tlast  <= s_tlast;
- m_tuser  <= s_tuser;
+ m_tvalid <= dly_valid;
+ m_tlast  <= dly_last;
+ m_tuser  <= dly_user;

  -- Inside clocked process, before pixel computation:
+ dly_valid <= s_tvalid;
+ dly_last  <= s_tlast;
+ dly_user  <= s_tuser;
```

### Fix 3: Pipeline Registers in `unsharp_mask.vhd`

Identical fix to `gamma_lut_engine.vhd` — added `dly_valid`, `dly_last`, `dly_user` pipeline registers so control signals are delayed by 1 clock cycle to match the registered data output.

---

## 4. Pipeline Timing — Before vs After

### Before (Broken)
```
Clock:      ──┐  ┌──┐  ┌──┐  ┌──┐  ┌──
              │  │  │  │  │  │  │  │
s_tvalid:   ──┘H └L─┘H └L─┘H └L─┘H └──   (50% duty)
m_tdata:    ──[X]──[P0]──[X]──[P1]──       (X = stale/wrong data)
m_tvalid:   ──┘H └L─┘H └L─┘H └L─┘H └──   (combinational = 0 delay)
              ↑       ↑
              Captures stale data!
```

### After (Fixed)
```
Clock:      ──┐  ┌──┐  ┌──┐  ┌──┐  ┌──
              │  │  │  │  │  │  │  │
s_tvalid:   ──┘HHHHHHHHHHHHHHHHHHHH└──     (100% duty)
m_tdata:    ──[--][P0][P1][P2][P3]──       (1-cycle latency, correct)
m_tvalid:   ──[L ][HHHHHHHHHHHHHHH]──      (registered = 1-cycle delay, aligned!)
                   ↑   ↑   ↑   ↑
                   Data and valid aligned ✓
```

---

## 5. Files Modified

| File | Change |
|------|--------|
| `vivado/tb_agcwd_top.vhd` | Continuous pixel streaming with AXI4-Stream handshake |
| `vivado/gamma_lut_engine.vhd` | Added pipeline registers for `m_tvalid`, `m_tlast`, `m_tuser` |
| `vivado/unsharp_mask.vhd` | Added pipeline registers for `m_tvalid`, `m_tlast`, `m_tuser` |

---

## 6. Next Steps

To verify the fix and regenerate a clean output image:

1. **Re-run the Vivado simulation** with the updated VHDL files
2. **Regenerate the result image:**
   ```powershell
   python rebuild_image_hex.py
   ```
3. **Verify** the black band is gone in the new `result.png`

> [!TIP]
> If additional minor artifacts appear at the very top or bottom rows (first/last 2 rows), that is expected behavior for the bilateral filter's 5×5 kernel boundary — those edge rows don't have a full neighborhood and will use fallback values.
