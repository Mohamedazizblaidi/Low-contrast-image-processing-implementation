"""Contrast-Limited Adaptive Histogram Equalization for RGB images.

This module provides a production-ready CLAHE reference implementation for
low-contrast RGB images. It is kept separate from the MSRCR and AGCWD
implementations so the project can compare enhancement methods cleanly.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image


@dataclass(frozen=True)
class NormalizationMetadata:
    """Metadata used to restore non-uint8 inputs after enhancement."""

    original_dtype: np.dtype[Any]
    original_min: float
    original_max: float
    preserve_input_range: bool


def load_rgb_image(path: str | Path) -> np.ndarray:
    """Load an image from disk as an RGB numpy array."""

    path_obj = Path(path)
    try:
        with Image.open(path_obj) as img:
            return np.asarray(img.convert("RGB"))
    except Exception as exc:
        raise RuntimeError(f"Failed to load image '{path_obj}': {exc}") from exc


def save_rgb_image(
    image: np.ndarray,
    path: str | Path,
    jpeg_quality: int = 95,
) -> None:
    """Save an RGB image to disk as PNG or JPEG."""

    rgb_u8 = ensure_uint8_rgb(image)
    path_obj = Path(path)
    suffix = path_obj.suffix.lower()

    try:
        pil_image = Image.fromarray(rgb_u8)
        if suffix in {".jpg", ".jpeg"}:
            pil_image.save(path_obj, quality=jpeg_quality, subsampling=0)
        else:
            pil_image.save(path_obj)
    except Exception as exc:
        raise RuntimeError(f"Failed to save image '{path_obj}': {exc}") from exc


def export_rgb_raw(image: np.ndarray, path: str | Path) -> None:
    """Export an image as interleaved RGB raw bytes."""

    rgb_u8 = ensure_uint8_rgb(image)
    path_obj = Path(path)
    try:
        rgb_u8.tofile(path_obj)
    except Exception as exc:
        raise RuntimeError(f"Failed to export raw image '{path_obj}': {exc}") from exc


def ensure_uint8_rgb(image: np.ndarray) -> np.ndarray:
    """Validate and convert an image into a contiguous RGB uint8 array."""

    if image.ndim != 3 or image.shape[2] != 3:
        raise ValueError(
            f"Expected an RGB image with shape (H, W, 3), got {image.shape!r}."
        )

    if image.dtype == np.uint8:
        return np.ascontiguousarray(image)

    clipped = np.clip(np.rint(image), 0.0, 255.0).astype(np.uint8)
    return np.ascontiguousarray(clipped)


def apply_clahe_rgb(
    image: np.ndarray,
    clip_limit: float = 2.0,
    tile_grid: tuple[int, int] = (8, 8),
    denoise: bool = False,
    sharpen: bool = False,
    preserve_input_range: bool = False,
    near_uniform_std_threshold: float = 15.0,
    color_balance_mean_threshold: float = 30.0,
    dark_mean_threshold: float = 5.0,
    bright_mean_threshold: float = 250.0,
) -> np.ndarray:
    """Enhance an RGB image using per-channel CLAHE.

    Args:
        image: RGB image with shape ``(H, W, 3)``.
        clip_limit: CLAHE clip limit.
        tile_grid: CLAHE tile grid as ``(cols, rows)``.
        denoise: Apply bilateral denoising before CLAHE.
        sharpen: Apply unsharp masking after enhancement.
        preserve_input_range: Scale the result back to the original dtype/range.
        near_uniform_std_threshold: Threshold for reducing clip limit on
            near-uniform channels.
        color_balance_mean_threshold: Threshold for triggering gray-world white
            balance correction.
        dark_mean_threshold: Threshold for classifying a frame as near-black.
        bright_mean_threshold: Threshold for classifying a frame as near-white.

    Returns:
        Enhanced image in ``uint8`` or restored input dtype.
    """

    if clip_limit <= 0.0:
        raise ValueError(f"clip_limit must be > 0, got {clip_limit}.")
    if len(tile_grid) != 2 or tile_grid[0] <= 0 or tile_grid[1] <= 0:
        raise ValueError(
            f"tile_grid must be a 2-tuple of positive integers, got {tile_grid!r}."
        )

    working_u8, metadata = _normalize_to_uint8(
        image=image,
        preserve_input_range=preserve_input_range,
    )
    frame_mean = float(working_u8.reshape(-1, 3).mean())
    frame_std = float(working_u8.reshape(-1, 3).std())

    effective_clip_limit = float(clip_limit)
    if frame_mean <= dark_mean_threshold or frame_mean >= bright_mean_threshold:
        if frame_std < 3.0:
            return _restore_input_range(working_u8.copy(), metadata)
        effective_clip_limit = min(effective_clip_limit, 1.0)

    preprocessed = _preprocess_rgb(working_u8, denoise=denoise)
    channels = cv2.split(preprocessed)
    enhanced_channels: list[np.ndarray] = []

    for channel in channels:
        channel_clip_limit = effective_clip_limit
        if float(channel.std()) < near_uniform_std_threshold:
            channel_clip_limit = min(channel_clip_limit, 1.0)

        clahe = cv2.createCLAHE(
            clipLimit=float(channel_clip_limit),
            tileGridSize=tile_grid,
        )
        enhanced_channels.append(clahe.apply(channel))

    enhanced = cv2.merge(enhanced_channels)

    if _should_apply_gray_world(
        image=enhanced,
        mean_diff_threshold=color_balance_mean_threshold,
    ):
        enhanced = _apply_gray_world_balance(enhanced)

    if sharpen:
        enhanced = _apply_unsharp_mask(enhanced)

    output_u8 = np.clip(enhanced, 0, 255).astype(np.uint8)
    return _restore_input_range(output_u8, metadata)


def _normalize_to_uint8(
    image: np.ndarray,
    preserve_input_range: bool,
) -> tuple[np.ndarray, NormalizationMetadata]:
    """Normalize an image into RGB uint8 format."""

    if image.ndim != 3 or image.shape[2] != 3:
        raise ValueError(
            f"Expected an RGB image with shape (H, W, 3), got {image.shape!r}."
        )

    original_dtype = image.dtype
    image_f32 = image.astype(np.float32, copy=False)
    original_min = float(np.nanmin(image_f32))
    original_max = float(np.nanmax(image_f32))

    if not np.isfinite(original_min) or not np.isfinite(original_max):
        raise ValueError("Input image contains NaN or Inf values.")

    if original_dtype == np.uint8:
        normalized = np.ascontiguousarray(image)
    else:
        if original_max == original_min:
            normalized = np.zeros_like(image_f32)
        elif np.issubdtype(original_dtype, np.floating) and (
            original_min >= 0.0 and original_max <= 1.0
        ):
            normalized = np.clip(np.rint(image_f32 * 255.0), 0.0, 255.0)
        elif original_min >= 0.0 and original_max <= 255.0:
            normalized = np.clip(np.rint(image_f32), 0.0, 255.0)
        else:
            scale = 255.0 / (original_max - original_min)
            normalized = np.clip(
                np.rint((image_f32 - original_min) * scale),
                0.0,
                255.0,
            )
        normalized = normalized.astype(np.uint8)

    metadata = NormalizationMetadata(
        original_dtype=original_dtype,
        original_min=original_min,
        original_max=original_max,
        preserve_input_range=preserve_input_range,
    )
    return np.ascontiguousarray(normalized), metadata


def _restore_input_range(
    image_u8: np.ndarray,
    metadata: NormalizationMetadata,
) -> np.ndarray:
    """Restore the enhanced image to the original dtype/range if requested."""

    if not metadata.preserve_input_range or metadata.original_dtype == np.uint8:
        return image_u8

    image_f32 = image_u8.astype(np.float32) / 255.0
    if metadata.original_max == metadata.original_min:
        restored = np.full_like(image_f32, fill_value=metadata.original_min)
    elif np.issubdtype(metadata.original_dtype, np.floating) and (
        metadata.original_min >= 0.0 and metadata.original_max <= 1.0
    ):
        restored = image_f32
    else:
        restored = (
            image_f32 * (metadata.original_max - metadata.original_min)
            + metadata.original_min
        )

    if np.issubdtype(metadata.original_dtype, np.integer):
        info = np.iinfo(metadata.original_dtype)
        return np.clip(np.rint(restored), info.min, info.max).astype(
            metadata.original_dtype
        )

    return restored.astype(metadata.original_dtype)


def _preprocess_rgb(image: np.ndarray, denoise: bool) -> np.ndarray:
    """Apply optional bilateral denoising before enhancement."""

    if not denoise:
        return image.copy()

    channels = cv2.split(image)
    filtered_channels = [
        cv2.bilateralFilter(
            src=channel,
            d=5,
            sigmaColor=35,
            sigmaSpace=35,
        )
        for channel in channels
    ]
    return cv2.merge(filtered_channels)


def _should_apply_gray_world(
    image: np.ndarray,
    mean_diff_threshold: float,
) -> bool:
    """Return true when gray-world correction should be applied."""

    means = image.reshape(-1, 3).mean(axis=0)
    return float(np.max(means) - np.min(means)) > mean_diff_threshold


def _apply_gray_world_balance(image: np.ndarray) -> np.ndarray:
    """Apply gray-world white balance correction."""

    image_f32 = image.astype(np.float32)
    means = image_f32.reshape(-1, 3).mean(axis=0)
    safe_means = np.where(means < 1e-6, 1.0, means)
    gray_mean = float(np.mean(means))
    gains = gray_mean / safe_means
    balanced = image_f32 * gains.reshape(1, 1, 3)
    return np.clip(np.rint(balanced), 0.0, 255.0).astype(np.uint8)


def _apply_unsharp_mask(image: np.ndarray) -> np.ndarray:
    """Apply the required unsharp mask stage."""

    image_f32 = image.astype(np.float32)
    blurred = cv2.GaussianBlur(image_f32, ksize=(0, 0), sigmaX=2.0, sigmaY=2.0)
    sharpened = cv2.addWeighted(image_f32, 1.4, blurred, -0.4, 0.0)
    return np.clip(np.rint(sharpened), 0.0, 255.0).astype(np.uint8)


__all__ = [
    "apply_clahe_rgb",
    "ensure_uint8_rgb",
    "export_rgb_raw",
    "load_rgb_image",
    "save_rgb_image",
]


def main() -> None:
    """Run the CLAHE enhancement on a specific image."""
    import sys

    # Default path
    image_path = r"C:\Users\ACER\Downloads\Electronics project\CT scan images\Test\cp026_96.png"

    # Use command line argument if provided
    if len(sys.argv) > 1:
        image_path = sys.argv[1]

    path_obj = Path(image_path)
    if not path_obj.exists():
        print(f"Error: Image not found at '{image_path}'")
        print("Usage: python algorithms/clahe.py <path_to_image>")
        return

    try:
        print(f"Loading '{image_path}'...")
        img = load_rgb_image(path_obj)

        print("Applying CLAHE enhancement...")
        enhanced = apply_clahe_rgb(
            img,
            clip_limit=2.0,
            tile_grid=(8, 8),
            denoise=True,
            sharpen=True
        )

        output_dir = Path(__file__).resolve().parent.parent / "output_images" / "clahe"
        output_dir.mkdir(parents=True, exist_ok=True)
        output_path = output_dir / f"{path_obj.stem.lower().replace(' ', '_')}.png"
        save_rgb_image(enhanced, output_path)
        print(f"Done! Enhanced image saved to: {output_path}")

        import matplotlib.pyplot as plt
        fig, axes = plt.subplots(1, 2, figsize=(12, 6))
        axes[0].imshow(img)
        axes[0].set_title("Input Image")
        axes[0].axis("off")
        axes[1].imshow(enhanced)
        axes[1].set_title("Enhanced Image (CLAHE)")
        axes[1].axis("off")
        plt.tight_layout()
        plt.show()

    except Exception as exc:
        print(f"An error occurred: {exc}")


if __name__ == "__main__":
    main()
