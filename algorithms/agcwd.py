"""Adaptive Gamma Correction with Weighting Distribution (AGCWD).

This module provides a reference implementation of the AGCWD algorithm
for enhancing low-contrast images, particularly those captured in 
low-light conditions.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image


def load_rgb_image(path: str | Path) -> np.ndarray:
    """Load an image from disk as an RGB numpy array."""
    path_obj = Path(path)
    try:
        with Image.open(path_obj) as img:
            return np.asarray(img.convert("RGB"))
    except Exception as exc:
        raise RuntimeError(f"Failed to load image '{path_obj}': {exc}") from exc

def save_rgb_image(image: np.ndarray, path: str | Path) -> None:
    """Save an RGB numpy array as an image to disk."""
    path_obj = Path(path)
    try:
        # Ensure the parent directory exists
        path_obj.parent.mkdir(parents=True, exist_ok=True)
        img = Image.fromarray(image)
        img.save(path_obj)
    except Exception as exc:
        raise RuntimeError(f"Failed to save image '{path_obj}': {exc}") from exc


def apply_agcwd_rgb(
    image: np.ndarray,
    alpha: float = 0.5,
    denoise: bool = False,
    sharpen: bool = False,
) -> np.ndarray:
    """Enhance an RGB image using AGCWD.

    Args:
        image: RGB image with shape (H, W, 3).
        alpha: Weighting parameter (typically 0.5).
        denoise: Apply bilateral filtering before enhancement.
        sharpen: Apply unsharp masking after enhancement.

    Returns:
        Enhanced RGB image.
    """
    # 1. Preprocessing
    if denoise:
        image = _apply_bilateral_filter(image)

    # 2. Convert to YCrCb to process luminance (Y)
    ycrcb = cv2.cvtColor(image, cv2.COLOR_RGB2YCrCb)
    y_channel = ycrcb[:, :, 0]

    # 3. Apply AGCWD on Y channel
    y_enhanced = _agcwd_core(y_channel, alpha=alpha)
    ycrcb[:, :, 0] = y_enhanced

    # 4. Convert back to RGB
    enhanced = cv2.cvtColor(ycrcb, cv2.COLOR_YCrCb2RGB)

    # 5. Postprocessing
    if sharpen:
        enhanced = _apply_unsharp_mask(enhanced)

    return enhanced


def _agcwd_core(image: np.ndarray, alpha: float = 0.5) -> np.ndarray:
    """Core AGCWD algorithm implementation on a single channel."""
    # Compute histogram
    hist, _ = np.histogram(image.flatten(), bins=256, range=(0, 256))
    prob = hist / image.size
    
    prob_min = prob.min()
    prob_max = prob.max()
    
    # Weighted PDF
    prob_w = prob_max * (((prob - prob_min) / (prob_max - prob_min)) ** alpha)
    prob_w /= prob_w.sum()  # Normalize
    
    # CDF
    cdf = np.cumsum(prob_w)
    
    # Mapping
    # I_out = 255 * (I_in / 255) ^ (1 - cdf)
    bins = np.arange(256)
    gamma = 1.0 - cdf
    
    lut = np.array([255 * ((i / 255.0) ** gamma[i]) for i in bins])
    lut = np.clip(lut, 0, 255).astype(np.uint8)
    
    return cv2.LUT(image, lut)


def _apply_bilateral_filter(image: np.ndarray) -> np.ndarray:
    """Apply bilateral filtering to reduce noise while preserving edges."""
    return cv2.bilateralFilter(image, d=5, sigmaColor=35, sigmaSpace=35)


def _apply_unsharp_mask(image: np.ndarray) -> np.ndarray:
    """Apply unsharp masking to enhance edges."""
    gaussian_3 = cv2.GaussianBlur(image, (0, 0), 2.0)
    return cv2.addWeighted(image, 1.5, gaussian_3, -0.5, 0)


if __name__ == "__main__":
    # Test script
    import sys
    import matplotlib.pyplot as plt

    img_path = r"C:\Users\ACER\Downloads\Electronics project\CT scan images\cap019_115.png"
    if len(sys.argv) > 1:
        img_path = sys.argv[1]

    img = load_rgb_image(img_path)
    enhanced = apply_agcwd_rgb(img, alpha=0.5, denoise=True, sharpen=True)

    # 6. Save the output
    output_dir = Path(r"C:\Users\ACER\Downloads\Electronics project\output_images\agcwd")
    output_filename = f"enhanced_{Path(img_path).name}"
    save_path = output_dir / output_filename
    
    save_rgb_image(enhanced, save_path)
    print(f"Enhanced image saved to: {save_path}")

    plt.figure(figsize=(12, 6))
    plt.subplot(1, 2, 1)
    plt.imshow(img)
    plt.title("Original")
    plt.axis("off")
    plt.subplot(1, 2, 2)
    plt.imshow(enhanced)
    plt.title("AGCWD Enhanced")
    plt.axis("off")
    plt.show()
