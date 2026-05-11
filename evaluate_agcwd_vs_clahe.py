from __future__ import annotations

import io
import sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

import csv
import warnings
from pathlib import Path

import cv2
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image
from skimage.metrics import structural_similarity as ssim

warnings.filterwarnings("ignore")

# ─────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────
ROOT = Path(r"C:\Users\ACER\Downloads\Electronics project")

ORIGINAL_DIR = ROOT / "CT scan images" / "Test"
AGCWD_DIR    = ROOT / "output_images" / "agcwd"
CLAHE_DIR    = ROOT / "output_images" / "clahe"
OUTPUT_DIR   = ROOT / "output_images" / "metrics"

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Map original stem → agcwd file, clahe file
# AGCWD saves as  "enhanced_<original_name>"
# CLAHE saves as  "<original_name_lowercase>"
IMAGE_MAP: dict[str, tuple[str, str]] = {
    "16_Morozov_study_0003_24":                      ("enhanced_16_Morozov_study_0003_24.png",                      "16_morozov_study_0003_24.png"),
    "6_Rahimzadeh_normal2_patient295_SR_4_IM00022":  ("enhanced_6_Rahimzadeh_normal2_patient295_SR_4_IM00022.png",  "6_rahimzadeh_normal2_patient295_sr_4_im00022.png"),
    "6_Rahimzadeh_normal2_patient301_SR_4_IM00012":  ("enhanced_6_Rahimzadeh_normal2_patient301_SR_4_IM00012.png",  "6_rahimzadeh_normal2_patient301_sr_4_im00012.png"),
    "6_Rahimzadeh_normal2_patient327_SR_4_IM00022":  ("enhanced_6_Rahimzadeh_normal2_patient327_SR_4_IM00022.png",  "6_rahimzadeh_normal2_patient327_sr_4_im00022.png"),
    "cap019_115":                                    ("enhanced_cap019_115.png",                                    "cap019_115.png"),
    "cp026_96":                                      ("enhanced_cp026_96.png",                                      "cp026_96.png"),
}


# ─────────────────────────────────────────────────────────────
# IMAGE UTILITIES
# ─────────────────────────────────────────────────────────────

def load_gray(path: Path) -> np.ndarray:
    """Load image as float32 grayscale [0, 255]."""
    with Image.open(path) as img:
        arr = np.asarray(img.convert("L"), dtype=np.float32)
    return arr


def load_rgb(path: Path) -> np.ndarray:
    """Load image as uint8 RGB."""
    with Image.open(path) as img:
        return np.asarray(img.convert("RGB"))


def match_size(ref: np.ndarray, target: np.ndarray) -> np.ndarray:
    """Resize target to ref's spatial dimensions if needed."""
    if ref.shape != target.shape:
        h, w = ref.shape[:2]
        target = np.array(Image.fromarray(target).resize((w, h), Image.LANCZOS))
    return target


# ─────────────────────────────────────────────────────────────
# METRICS
# ─────────────────────────────────────────────────────────────

def compute_mse(ref: np.ndarray, enh: np.ndarray) -> float:
    return float(np.mean((ref.astype(np.float64) - enh.astype(np.float64)) ** 2))


def compute_psnr(mse: float) -> float:
    if mse < 1e-10:
        return float("inf")
    return float(10 * np.log10(255.0 ** 2 / mse))


def compute_ssim(ref: np.ndarray, enh: np.ndarray) -> float:
    r8 = ref.clip(0, 255).astype(np.uint8)
    e8 = enh.clip(0, 255).astype(np.uint8)
    score, _ = ssim(r8, e8, full=True, data_range=255)
    return float(score)


def compute_entropy(img: np.ndarray) -> float:
    img_u8 = img.clip(0, 255).astype(np.uint8)
    hist, _ = np.histogram(img_u8.flatten(), bins=256, range=(0, 256))
    prob = hist / hist.sum()
    prob = prob[prob > 0]
    return float(-np.sum(prob * np.log2(prob)))


def compute_rms_contrast(img: np.ndarray) -> float:
    return float(img.std())


def compute_ambe(ref: np.ndarray, enh: np.ndarray) -> float:
    return float(abs(ref.mean() - enh.mean()))


def compute_snr(img: np.ndarray) -> float:
    """SNR = mean / std of pixel values."""
    std = img.std()
    if std < 1e-6:
        return float("inf")
    return float(img.mean() / std)


def compute_cnr(img: np.ndarray) -> float:
    """
    CNR computed by splitting image into a central ROI (tissue)
    and a border region (background/noise).
    CNR = |mu_tissue - mu_bg| / sigma_bg
    """
    h, w = img.shape
    # Central 50% as tissue ROI
    rh, rw = h // 4, w // 4
    tissue = img[rh: h - rh, rw: w - rw]
    # Border strip as background
    border = np.concatenate([
        img[:rh, :].flatten(),
        img[h - rh:, :].flatten(),
        img[rh:h - rh, :rw].flatten(),
        img[rh:h - rh, w - rw:].flatten(),
    ])
    mu_t = tissue.mean()
    mu_b = border.mean()
    sigma_b = border.std()
    if sigma_b < 1e-6:
        return float("inf")
    return float(abs(mu_t - mu_b) / sigma_b)


def compute_epi(ref: np.ndarray, enh: np.ndarray) -> float:
    """
    Edge Preservation Index — ratio of edge magnitudes.
    EPI = sum(|grad(enh)|) / sum(|grad(ref)|)
    Values near 1.0 mean edges are well preserved.
    """
    ref8 = ref.clip(0, 255).astype(np.uint8)
    enh8 = enh.clip(0, 255).astype(np.uint8)
    grad_ref = cv2.Laplacian(ref8, cv2.CV_64F)
    grad_enh = cv2.Laplacian(enh8, cv2.CV_64F)
    denom = np.abs(grad_ref).sum()
    if denom < 1e-6:
        return 1.0
    return float(np.abs(grad_enh).sum() / denom)


def compute_all(ref_gray: np.ndarray, enh_gray: np.ndarray) -> dict[str, float]:
    mse = compute_mse(ref_gray, enh_gray)
    return {
        "MSE":          mse,
        "PSNR (dB)":    compute_psnr(mse),
        "SSIM":         compute_ssim(ref_gray, enh_gray),
        "Entropy":      compute_entropy(enh_gray),
        "RMS Contrast": compute_rms_contrast(enh_gray),
        "AMBE":         compute_ambe(ref_gray, enh_gray),
        "SNR":          compute_snr(enh_gray),
        "CNR":          compute_cnr(enh_gray),
        "EPI":          compute_epi(ref_gray, enh_gray),
    }


METRIC_NAMES = ["MSE", "PSNR (dB)", "SSIM", "Entropy", "RMS Contrast", "AMBE", "SNR", "CNR", "EPI"]
# True = higher is better, False = lower is better
HIGHER_IS_BETTER = {
    "MSE": False, "PSNR (dB)": True, "SSIM": True,
    "Entropy": True, "RMS Contrast": True, "AMBE": False,
    "SNR": True, "CNR": True, "EPI": True,
}


# ─────────────────────────────────────────────────────────────
# MAIN EVALUATION
# ─────────────────────────────────────────────────────────────

def run_evaluation() -> None:
    agcwd_results: list[dict] = []
    clahe_results: list[dict] = []
    image_labels: list[str] = []

    print("\n" + "=" * 80)
    print("  AGCWD vs CLAHE — CT Scan Image Quality Evaluation")
    print("=" * 80)

    for stem, (agcwd_fname, clahe_fname) in IMAGE_MAP.items():
        orig_path  = ORIGINAL_DIR / f"{stem}.png"
        agcwd_path = AGCWD_DIR / agcwd_fname
        clahe_path = CLAHE_DIR / clahe_fname

        missing = [p for p in (orig_path, agcwd_path, clahe_path) if not p.exists()]
        if missing:
            print(f"\n[SKIP] {stem}")
            for m in missing:
                print(f"       Missing: {m}")
            continue

        orig_gray  = load_gray(orig_path)
        agcwd_gray = match_size(orig_gray, load_gray(agcwd_path))
        clahe_gray = match_size(orig_gray, load_gray(clahe_path))

        a_metrics = compute_all(orig_gray, agcwd_gray)
        c_metrics = compute_all(orig_gray, clahe_gray)

        agcwd_results.append(a_metrics)
        clahe_results.append(c_metrics)
        image_labels.append(stem[:30])  # truncate for display

        # Per-image table
        short = stem[:35]
        print(f"\n+-- Image: {short}")
        print(f"|  {'Metric':<16} {'AGCWD':>12} {'CLAHE':>12}  {'Winner':>8}")
        print(f"|  {'-'*50}")
        for m in METRIC_NAMES:
            a_val = a_metrics[m]
            c_val = c_metrics[m]
            if HIGHER_IS_BETTER[m]:
                winner = "AGCWD" if a_val >= c_val else "CLAHE"
            else:
                winner = "AGCWD" if a_val <= c_val else "CLAHE"
            print(f"|  {m:<16} {a_val:>12.4f} {c_val:>12.4f}  {winner:>8}")

    if not agcwd_results:
        print("\n[ERROR] No images could be evaluated. Check paths.")
        return

    # ── Summary Table ──────────────────────────────────────────
    print("\n\n" + "=" * 80)
    print("  SUMMARY — Mean ± Std across all images")
    print("=" * 80)
    print(f"{'Metric':<16} {'AGCWD Mean':>14} {'AGCWD Std':>12} {'CLAHE Mean':>14} {'CLAHE Std':>12}  {'Overall Winner':>15}")
    print("-" * 85)
    for m in METRIC_NAMES:
        a_vals = np.array([r[m] for r in agcwd_results])
        c_vals = np.array([r[m] for r in clahe_results])
        a_finite = a_vals[np.isfinite(a_vals)]
        c_finite = c_vals[np.isfinite(c_vals)]
        a_mean = a_finite.mean() if len(a_finite) else float("nan")
        c_mean = c_finite.mean() if len(c_finite) else float("nan")
        a_std  = a_finite.std()  if len(a_finite) else float("nan")
        c_std  = c_finite.std()  if len(c_finite) else float("nan")
        if HIGHER_IS_BETTER[m]:
            winner = "AGCWD ✓" if a_mean >= c_mean else "CLAHE ✓"
        else:
            winner = "AGCWD ✓" if a_mean <= c_mean else "CLAHE ✓"
        print(f"{m:<16} {a_mean:>14.4f} {a_std:>12.4f} {c_mean:>14.4f} {c_std:>12.4f}  {winner:>15}")

    # ── Save CSV ───────────────────────────────────────────────
    csv_path = OUTPUT_DIR / "agcwd_vs_clahe.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["Image", "Method"] + METRIC_NAMES)
        for lbl, a_m, c_m in zip(image_labels, agcwd_results, clahe_results):
            writer.writerow([lbl, "AGCWD"] + [f"{a_m[m]:.4f}" for m in METRIC_NAMES])
            writer.writerow([lbl, "CLAHE"] + [f"{c_m[m]:.4f}" for m in METRIC_NAMES])
    print(f"\n✅ CSV saved → {csv_path}")

    # ── Bar Charts ─────────────────────────────────────────────
    _plot_comparison(agcwd_results, clahe_results, image_labels)


def _plot_comparison(
    agcwd_results: list[dict],
    clahe_results: list[dict],
    labels: list[str],
) -> None:
    metrics_to_plot = ["PSNR (dB)", "SSIM", "Entropy", "RMS Contrast", "AMBE", "CNR", "SNR", "EPI"]
    n = len(metrics_to_plot)
    cols = 4
    rows = (n + cols - 1) // cols

    fig, axes = plt.subplots(rows, cols, figsize=(22, rows * 5))
    fig.suptitle("AGCWD vs CLAHE — CT Scan Image Quality Metrics", fontsize=16, fontweight="bold", y=1.01)
    axes_flat = axes.flatten()

    x = np.arange(len(labels))
    width = 0.35

    colors_agcwd = "#2196F3"
    colors_clahe = "#FF5722"

    for idx, metric in enumerate(metrics_to_plot):
        ax = axes_flat[idx]
        a_vals = [r[metric] for r in agcwd_results]
        c_vals = [r[metric] for r in clahe_results]

        # Replace inf with NaN for plotting
        a_plot = [v if np.isfinite(v) else np.nan for v in a_vals]
        c_plot = [v if np.isfinite(v) else np.nan for v in c_vals]

        bars_a = ax.bar(x - width / 2, a_plot, width, label="AGCWD", color=colors_agcwd, alpha=0.85)
        bars_c = ax.bar(x + width / 2, c_plot, width, label="CLAHE",  color=colors_clahe, alpha=0.85)

        ax.set_title(metric, fontsize=12, fontweight="bold")
        ax.set_xticks(x)
        ax.set_xticklabels([l[:12] for l in labels], rotation=35, ha="right", fontsize=8)
        ax.legend(fontsize=9)
        ax.grid(axis="y", alpha=0.3)
        direction = "↑ higher better" if HIGHER_IS_BETTER[metric] else "↓ lower better"
        ax.set_xlabel(direction, fontsize=8, color="gray")

        # Value labels on bars
        for bar in bars_a:
            h = bar.get_height()
            if np.isfinite(h):
                ax.text(bar.get_x() + bar.get_width() / 2, h * 1.01, f"{h:.2f}",
                        ha="center", va="bottom", fontsize=7, color=colors_agcwd)
        for bar in bars_c:
            h = bar.get_height()
            if np.isfinite(h):
                ax.text(bar.get_x() + bar.get_width() / 2, h * 1.01, f"{h:.2f}",
                        ha="center", va="bottom", fontsize=7, color=colors_clahe)

    for ax in axes_flat[len(metrics_to_plot):]:
        ax.set_visible(False)

    plt.tight_layout()
    out_path = OUTPUT_DIR / "agcwd_vs_clahe_comparison.png"
    plt.savefig(out_path, dpi=150, bbox_inches="tight")
    print(f"✅ Chart saved → {out_path}")
    plt.show()


if __name__ == "__main__":
    run_evaluation()
