# Full Academic Report: Low-Contrast Image Enhancement Implementation

**Project Title:** Evaluation and Implementation of Advanced Image Enhancement Algorithms for Low-Contrast Imagery  
**Date:** May 2, 2026  
**Authors:** Project Development Team  
**Subject:** Digital Image Processing / Electronics Project  

---

## 1. Abstract
Low-contrast images, often found in medical imaging, surveillance, and satellite photography, pose significant challenges for automated analysis and human interpretation. This project implements and evaluates two prominent enhancement techniques: **Adaptive Gamma Correction with Weighting Distribution (AGCWD)** and **Contrast-Limited Adaptive Histogram Equalization (CLAHE)**. We provide a comparative analysis based on objective image quality metrics including PSNR, SSIM, Information Entropy, and RMS Contrast. Our results demonstrate that while both methods significantly improve visibility, AGCWD offers superior preservation of structural integrity (SSIM) and higher information gain (Entropy) in extremely low-light scenarios.

## 2. Introduction
### 2.1 Problem Statement
In many real-world applications, image acquisition conditions are suboptimal, leading to "low-contrast" images where the dynamic range of pixel intensities is poorly utilized. This results in "washed-out" appearances and loss of detail. Traditional methods like Global Histogram Equalization (GHE) often lead to over-enhancement, noise amplification, and unnatural artifacts.

### 2.2 Objectives
The primary objectives of this project are:
1.  To implement a robust, production-ready Python framework for image enhancement.
2.  To evaluate the performance of AGCWD and CLAHE on diverse test datasets.
3.  To provide a quantifiable comparison using standard image processing metrics.
4.  To develop a modular architecture that supports further integration (e.g., hardware acceleration).

## 3. Background and Literature Review
### 3.1 Contrast-Limited Adaptive Histogram Equalization (CLAHE)
CLAHE is an extension of Adaptive Histogram Equalization (AHE). It operates on small regions (tiles) rather than the entire image. To prevent over-amplification of noise in homogeneous regions, CLAHE introduces a **clip limit**. If a histogram bin exceeds this limit, the pixels are redistributed equally across all bins, effectively limiting the slope of the transformation function.

### 3.2 Adaptive Gamma Correction with Weighting Distribution (AGCWD)
AGCWD is a more sophisticated approach that utilizes the statistical properties of the image histogram to adaptively adjust the gamma parameter. The key steps include:
1.  **Weighting Distribution**: Smoothing the histogram using an alpha parameter to prevent aggressive changes.
2.  **Gamma Derivation**: Calculating a unique gamma value for each pixel intensity based on the cumulative distribution function (CDF) of the weighted histogram.
3.  **Power-Law Transformation**: Applying the derived gamma values to map input intensities to enhanced output intensities.

## 4. Methodology
### 4.1 System Architecture
The project is structured into three main modules:
-   `algorithms/`: Core implementation of AGCWD and CLAHE logic.
-   `Python/`: Evaluation scripts and result generation tools.
-   `Inputs/`: Standardized test images (including medical and natural scenes).

### 4.2 Implementation Details
Both algorithms follow a standardized processing pipeline:
1.  **Normalization**: Converting input images to a consistent 8-bit RGB format.
2.  **Preprocessing**: Applying **Bilateral Denoising** to preserve edges while reducing sensor noise.
3.  **Enhancement Core**:
    -   *CLAHE*: Utilizes a tile grid (default 8x8) and clip limit (default 2.0).
    -   *AGCWD*: Uses an alpha weighting factor (default 0.5) to smooth the histogram.
4.  **Post-processing**:
    -   **Gray-World White Balance**: Correcting color shifts introduced during enhancement.
    -   **Unsharp Masking**: Final sharpening stage to enhance fine details and edges.

## 5. Experimental Results
### 5.1 Evaluation Metrics
We utilized the following metrics for objective assessment:
-   **PSNR (Peak Signal-to-Noise Ratio)**: Measures fidelity to the original.
-   **SSIM (Structural Similarity Index)**: Measures preservation of shapes and textures.
-   **Entropy**: Measures the information content/detail richness.
-   **RMS Contrast**: Measures the dynamic range utilization.
-   **AMBE (Absolute Mean Brightness Error)**: Measures brightness preservation.

### 5.2 Comparative Analysis (Sample Data)
Based on our latest evaluation run (Essay 7) on a low-contrast test image:

| Algorithm | MSE (v) | PSNR (dB) (^) | SSIM (^) | AMBE (v) | Entropy (^) | Contrast (^) |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| **Original** | 0.00 | inf | 1.0000 | 0.00 | 4.4563 | 32.98 |
| **AGCWD** | 1223.79 | 17.25 | **0.8194** | 17.69 | **5.2422** | **60.13** |
| **CLAHE** | 259.67 | 23.99 | 0.5977 | 10.89 | 5.1096 | 40.62 |

*Note: (^) indicates higher is better, (v) indicates lower is better.*

### 5.3 Visual Observations
-   **AGCWD** produced images with significantly higher contrast and better visibility in shadow regions. The high Entropy score (5.24) indicates it revealed more hidden details.
-   **CLAHE** maintained higher PSNR (23.99), indicating it stays "closer" to the original image intensities, but provided less dramatic enhancement in very dark areas compared to AGCWD.
-   **Structural Integrity**: AGCWD achieved a much higher SSIM (0.8194) than CLAHE (0.5977), suggesting it produces fewer blocking artifacts and better preserves the original geometry.

## 6. Discussion
The performance gap between AGCWD and CLAHE can be attributed to their fundamental logic. CLAHE is spatially localized, which can sometimes lead to "blocking" artifacts if the tile size is not perfectly tuned. AGCWD, by using a global weighted histogram for gamma derivation, provides a smoother transition across the intensity spectrum while still being adaptive to the local distribution through its weighting mechanism.

The inclusion of **Bilateral Filtering** and **Gray-World Balancing** proved critical. Without these, enhancement often led to "salt and pepper" noise amplification and unnatural yellow/blue tints.

## 7. Conclusion and Future Work
### 7.1 Conclusion
This project successfully implemented and validated two state-of-the-art image enhancement algorithms. AGCWD emerged as the superior choice for applications requiring maximum detail extraction and structural preservation in low-light conditions. CLAHE remains a viable, lower-computational-cost alternative for moderate enhancement needs.

### 7.2 Future Work
-   **Hardware Acceleration**: Implementing the AGCWD core on an FPGA (e.g., Digilent Basys 3) to achieve real-time 60 FPS processing.
-   **Deep Learning Integration**: Exploring hybrid models that use AGCWD as a preprocessing step for CNN-based object detection.
-   **Video Processing**: Extending the current frame-based logic to handle temporal consistency in video streams.

## 8. References
1.  Huang, S. C., Cheng, F. C., & Chiu, Y. S. (2013). Efficient Contrast Enhancement Using Adaptive Gamma Correction With Weighting Distribution. *IEEE Transactions on Image Processing*.
2.  Zuiderveld, K. (1994). Contrast Limited Adaptive Histogram Equalization. *Graphics Gems IV*.
3.  Reza, A. M. (2004). Realization of the contrast limited adaptive histogram equalization (CLAHE) for real-time image enhancement. *Journal of VLSI signal processing systems*.
