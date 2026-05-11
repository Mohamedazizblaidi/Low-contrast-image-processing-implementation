# AGCWD-CT: Dual-Platform Image Enhancement Pipeline

![Python](https://img.shields.io/badge/Python-3.9+-blue.svg)
![VHDL](https://img.shields.io/badge/VHDL-2008-orange.svg)
![Vivado](https://img.shields.io/badge/Xilinx-Vivado-red.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

A professional implementation of **Adaptive Gamma Correction with Weighting Distribution (AGCWD)** designed for low-contrast medical CT scan enhancement. This project features a high-precision Python reference pipeline and a real-time streaming VHDL hardware architecture, with a proposed hybrid FPGA+Memristor acceleration model.

---

##  Key Features

- **Software Platform:** Full Python pipeline with Bilateral Denoising, YCrCb color space conversion, and AGCWD core.
- **Hardware Platform:** Modular VHDL architecture operating at **100 MHz** using AXI4-Stream, optimized for real-time surgical imaging.
- **Advanced Architecture:** Hybrid FPGA + Memristor proposal utilizing analog crossbar arrays for $O(1)$ parallel histogramming and CDF accumulation.
- **Clinical Validation:** Tested on the Kaggle COVID-19 CT Scan dataset with high fidelity to diagnostic features.

---

##  Performance Metrics

The AGCWD algorithm outperforms standard CLAHE benchmarks in structural preservation and information richness.

| Metric | Original | **AGCWD (Ours)** | CLAHE |
| :--- | :---: | :---: | :---: |
| **SSIM** | 1.000 | **0.8194** | 0.5977 |
| **Entropy** | 4.456 | **5.242** | 5.110 |
| **PSNR (dB)** | $\infty$ | 17.25 | 23.99 |
| **RMS Contrast** | 32.98 | **60.13** | 40.62 |

> **Note:** The higher SSIM confirms that AGCWD preserves anatomical structures significantly better than CLAHE, which often introduces blocking artifacts.

---

##  Hardware Characteristics (Post-Synthesis)

Synthesized for high-performance FPGA targets:

- **Latency:** 12.4 $\mu$s (at 100 MHz)
- **Throughput:** >380 FPS (512x512 resolution)
- **Power Consumption:** 2.656 W (Total), 0.804 W (Dynamic)
- **Resource Utilization:**
  - LUTs: 2.93%
  - DSP Slices: 0.50%
  - BRAM: 0.04%

---

##  Repository Structure

```text
├── vivado agcwd/             # VHDL Source files and Vivado Project
│   ├── agcwd_top.vhd         # Top-level streaming module
│   ├── gamma_lut_engine.vhd  # Adaptive LUT transformation
│   └── bilateral_filter.vhd  # Spatial-domain denoising
├── agcwd.py                  # Python "Golden Reference" implementation
├── output_images/            # Visual comparisons and difference maps
├── paper_article.pdf         # Finalized IEEE-style research paper
└── README.md                 # Project documentation
```

---

##  Getting Started

### Software Setup
1. Install dependencies:
   ```bash
   pip install opencv-python numpy scikit-image matplotlib
   ```
2. Run the enhancement:
   ```bash
   python agcwd.py --input path/to/ct_scan.png
   ```

### Hardware Setup
1. Open Xilinx Vivado (2020.1 or later).
2. Create a new project and add files from the `vivado agcwd/` directory.
3. Run **Synthesis** and **Implementation** to view resource and power reports.

---

##  Proposed Hybrid Architecture

The project concludes with a formal proposal for a **Hybrid FPGA + Memristor** system. This architecture solves the "sequential bottleneck" of digital histogramming by using analog memristor crossbars to perform in-memory parallel computation, potentially reducing power consumption by up to 40%.

---

##  License
This project is licensed under the MIT License - see the LICENSE file for details.

##  Acknowledgments
Supported by the **Biomedical Engineering Department** at the National Institute of Technologies and Sciences of Kef.
