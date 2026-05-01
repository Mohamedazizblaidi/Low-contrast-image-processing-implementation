# Algorithm Evaluation Results

| Algorithm | MSE (v) | PSNR (dB) (^) | SSIM (^) | AMBE (v) | Entropy (^) | Contrast (^) | Luminosity (^) | Sharpness (^) |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Original | 0.00 | inf | 1.0000 | 0.00 | 5.0743 | 58.66 | 31.87 | 20.73 |
| AGCWD | 803.71 | 19.08 | 0.5059 | 20.89 | 6.5478 | 64.19 | 52.76 | 125.34 |
| CLAHE | 327.75 | 22.98 | 0.6102 | 15.35 | 6.2116 | 54.06 | 47.23 | 52.72 |

## Legend & Explanations

### Metrics Description & Grading

#### 1. MSE (Mean Squared Error)
- Measures the average squared difference between the enhanced and original image pixels.
- **Lower score (v)**: Indicates high similarity to the original image (fewer changes).
- **Higher score (^)**: Indicates significant changes have been made to the original image.

#### 2. PSNR (Peak Signal-to-Noise Ratio)
- Evaluates the quality between the original and enhanced image in decibels (dB).
- **Higher score (^)**: Means higher fidelity and similarity to the original image.
- **Lower score (v)**: Means more deviation/enhancement from the original image.

#### 3. SSIM (Structural Similarity Index)
- Measures the structural similarity between the images (ranges from 0 to 1.0).
- **Higher score (^)**: (closer to 1.0) means the structural information (edges, shapes) of the original is well preserved.
- **Lower score (v)**: Means structural information has been altered significantly.
- *Note for MSE, PSNR, SSIM*: In image enhancement, very high fidelity to the original isn't always the goal if the original was poor quality.

#### 4. AMBE (Absolute Mean Brightness Error)
- Measures the absolute difference in mean brightness between the original and enhanced images.
- **Lower score (v)**: Means the overall brightness of the original image is perfectly preserved.
- **Higher score (^)**: Means the overall brightness has significantly increased or decreased.

#### 5. Entropy
- Measures the amount of information, complexity, and details present in the image.
- **Higher score (^)**: Means the image has more details, richer textures, and better information content (generally desirable).
- **Lower score (v)**: Means the image is smoother, flatter, or has lost detail/information.

#### 6. Contrast (RMS Contrast)
- Measures the standard deviation of pixel intensities.
- **Higher score (^)**: Means the image has a wider dynamic range and excellent contrast (usually desirable).
- **Lower score (v)**: Means the image has low contrast and might appear washed out or flat.

#### 7. Luminosity
- Measures the average brightness level of the image (on a scale of 0 to 255).
- **Higher score (^)**: Means the image is brighter overall.
- **Lower score (v)**: Means the image is darker overall.

#### 8. Sharpness (Laplacian Variance)
- Measures the clarity and amount of sharp edges in the image.
- **Higher score (^)**: Means the image is sharper and contains more defined edges.
- **Lower score (v)**: Means the image is blurry or soft.
