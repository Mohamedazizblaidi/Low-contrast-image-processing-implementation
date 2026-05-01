# Advanced Non-DL Image Contrast Enhancement Algorithms

This document provides a detailed technical analysis of the most effective classical (non-deep learning) algorithms for enhancing low-contrast images.

---

## 1. CLAHE (Contrast Limited Adaptive Histogram Equalization)

### Definition
CLAHE is an improvement over standard Adaptive Histogram Equalization (AHE). It divides an image into small, non-overlapping regions called "tiles" and performs histogram equalization on each. To prevent the over-amplification of noise, it clips the histogram at a specific height before computing the Cumulative Distribution Function (CDF).

### Key Information
- **Tile-based:** Processes local neighborhoods rather than the whole image.
- **Bilinear Interpolation:** Used to stitch tiles together to prevent visible boundaries.
- **Contrast Limit:** A user-defined parameter that controls noise suppression.

### Pros & Cons
- **Pros:** Excellent at revealing hidden local details; handles non-uniform lighting; computationally efficient.
- **Cons:** Can produce "blocking" artifacts; may amplify sensor noise in very dark areas.

### Best Used In
- **Medical Imaging:** Enhancing X-rays, CT scans, and MRI results.
- **Underwater Photography:** Correcting light absorption and scattering.
- **Satellite Imagery:** Bringing out terrain details.

---

## 2. MSRCR (Multi-Scale Retinex with Color Restoration)

### Definition
Based on the Retinex theory (a combination of 'Retina' and 'Cortex'), this algorithm assumes an image is the product of illumination and reflectance. It uses multiple Gaussian blurs (scales) to estimate the illumination and subtracts it to isolate the true reflectance.

### Key Information
- **Logarithmic Domain:** Processing happens in the log domain to mimic human visual perception.
- **Color Restoration:** Includes a weighting factor to ensure that the color balance remains natural.

### Pros & Cons
- **Pros:** Exceptional for dynamic range compression; high color constancy; works well in extreme shadows.
- **Cons:** High computational cost; prone to "halo" artifacts around high-contrast edges.

### Best Used In
- **Night-time Surveillance:** Seeing objects in near-total darkness.
- **Forensic Analysis:** Extracting details from poorly lit evidence.
- **Haze Removal:** Improving visibility in foggy or smoky conditions.

---

## 3. AGCWD (Adaptive Gamma Correction with Weighting Distribution)

### Definition
An advanced version of traditional Gamma Correction. Instead of using a fixed exponent, it utilizes the probability distribution of pixel intensities to adaptively transform the luminance.

### Key Information
- **PDF-Based:** Uses the Probability Density Function (PDF) and Cumulative Distribution Function (CDF) to create a smooth transformation curve.
- **Weighting:** Smooths the distribution to avoid drastic jumps in brightness.

### Pros & Cons
- **Pros:** Preserves the natural "feel" of the image; very low risk of artifacts; computationally very fast.
- **Cons:** Less aggressive than CLAHE; may not reveal micro-details in extremely low-contrast regions.

### Best Used In
- **Consumer Electronics:** Real-time enhancement in smartphone cameras or TVs.
- **Video Processing:** Stable frame-to-frame contrast adjustment.

---

## 4. Comparison Analysis

| Feature | CLAHE | MSRCR | AGCWD |
| :--- | :--- | :--- | :--- |
| **Approach** | Local Histogram Modification | Illumination/Reflectance Model | Adaptive Power-Law (Gamma) |
| **Speed** | Fast | Slow | Very Fast |
| **Noise Sensitivity** | Moderate (Controlled) | High | Low |
| **Detail Recovery** | High (Local) | Very High (Global/Local) | Moderate |
| **Artifact Risk** | Blocking / Noise | Halos / Color Shift | Minimal |

---

## Summary of Selection
- Choose **CLAHE** for structural analysis where local texture matters most.
- Choose **MSRCR** for dramatic illumination recovery in low-light environments.
- Choose **AGCWD** for high-speed, natural-looking enhancement.