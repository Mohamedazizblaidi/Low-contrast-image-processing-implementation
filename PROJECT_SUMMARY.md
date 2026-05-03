# Project Overview: Advanced Image Enhancement System

This project is an **Advanced Image Enhancement System** designed to improve the visibility and quality of low-contrast images (such as medical scans, surveillance footage, or satellite photos). It features a hybrid implementation across both software (Python) and hardware (VHDL/FPGA).

## 1. Core Objectives
The project focuses on implementing and comparing two state-of-the-art enhancement techniques:
*   **AGCWD (Adaptive Gamma Correction with Weighting Distribution):** A sophisticated method that uses image statistics to adaptively adjust brightness and contrast.
*   **CLAHE (Contrast-Limited Adaptive Histogram Equalization):** A classic algorithm that enhances contrast locally in small regions (tiles) of the image.

## 2. Project Structure
The repository is organized into three main functional areas:

### A. Software Framework (Python)
Located in `algorithms/` and `Python/`, this part of the project is used for:
*   **Implementation:** Clean Python code for both AGCWD and CLAHE.
*   **Pre/Post Processing:** Includes Bilateral Denoising, Gray-World White Balance, and Unsharp Masking.
*   **Evaluation:** Tools to calculate objective metrics like PSNR (Fidelity), SSIM (Structural Similarity), and Information Entropy (Detail richness).

### B. Hardware Architecture (VHDL/Vivado)
Located in the `vivado/` folder, this is a real-time hardware pipeline designed for FPGAs:
*   **Streaming Pipeline:** Processes 24-bit RGB pixels one-by-one at 100MHz.
*   **Modular Blocks:** Individual VHDL modules for `histogram_engine`, `bilateral_filter`, `gamma_lut_engine`, and `gray_world_balance`.
*   **Simulation Tools:** Scripts (`prepare_image_hex.py`) to convert images into `.hex` files so the hardware can "process" them in a Vivado simulation environment.

### C. Documentation & Results
*   **`docs/Academic_Project_Report.md`:** A full report detailing the methodology, math behind the algorithms, and a comparative analysis.
*   **`output/` and `Python/Results/`:** Side-by-side comparisons showing how much more detail is revealed in low-light images after processing.

## 3. The Processing Pipeline
The image processing flow (implemented in both software and hardware) follows these stages:
1.  **Denoise:** Remove sensor noise using a Bilateral Filter.
2.  **Analyze:** Calculate the histogram or mean intensity of the image.
3.  **Enhance:** Apply AGCWD or CLAHE to stretch the dynamic range.
4.  **Balance:** Correct any color shifts using White Balance logic.
5.  **Sharpen:** Use an Unsharp Mask to make fine details pop.

## 4. Hardware/Software Hybrid Approach
This project demonstrates a complete ecosystem for researching image enhancement in Python and then accelerating those same algorithms in hardware for real-time applications.
