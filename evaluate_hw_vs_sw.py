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
SOFTWARE_DIR = ROOT / "output_images" / "agcwd"
HARDWARE_DIR = ROOT / "Hardware results"
OUTPUT_DIR   = ROOT / "output_images" / "metrics"

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Map: original stem → (software_filename, hardware_filename)
# Software: "enhanced_<stem>.png"
# Hardware: "<stem> hardware.png"
IMAGE_MAP: dict[str, tuple[str, str]] = {
    "16_Morozov_study_0003_24": (
        "enhanced_16_Morozov_study_0003_24.png",
        "16_Morozov_study_0003_24 hardware.png",
    ),
    "6_Rahimzadeh_normal2_patient295_SR_4_IM00022": (
        "enhanced_6_Rahimzadeh_normal2_patient295_SR_4_IM00022.png",
        "6_Rahimzadeh_normal2_patient295_SR_4_IM00022 hardware.png",
    ),
    "6_Rahimzadeh_normal2_patient301_SR_4_IM00012": (
        "enhanced_6_Rahimzadeh_normal2_patient301_SR_4_IM00012.png",
        "6_Rahimzadeh_normal2_patient301_SR_4_IM00012 hardware.png",
    ),
    "6_Rahimzadeh_normal2_patient327_SR_4_IM00022": (
        "enhanced_6_Rahimzadeh_normal2_patient327_SR_4_IM00022.png",
        "6_Rahimzadeh_normal2_patient327_SR_4_IM00022 hardware.png",
    ),
    "cap019_115": (
        "enhanced_cap019_115.png",
        "cap019_115 hardware.png",
    ),
    "cp026_96": (
        "enhanced_cp026_96.png",
        "cp026_96 hardware.png",
    ),
}


# ─────────────────────────────────────────────────────────────
# IMAGE UTILITIES
# ─────────────────────────────────────────────────────────────

def load_gray(path: Path) -> np.ndarray:
    with Image.open(path) as img:
        return np.asarray(img.convert("L"), dtype=np.float32)


def match_size(ref: np.ndarray, target: np.ndarray) -> np.ndarray:
    if ref.shape != target.shape:
        h, w = ref.shape[:2]
        pil = Image.fromarray(target.clip(0, 255).astype(np.uint8))
        target = np.asarray(pil.resize((w, h), Image.LANCZOS), dtype=np.float32)
    return target


# ─────────────────────────────────────────────────────────────
# METRICS
# ─────────────────────────────────────────────────────────────

def compute_mse(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.mean((a.astype(np.float64) - b.astype(np.float64)) ** 2))


def compute_psnr(mse: float) -> float:
    return float("inf") if mse < 1e-10 else float(10 * np.log10(255.0 ** 2 / mse))


def compute_ssim(a: np.ndarray, b: np.ndarray) -> float:
    a8 = a.clip(0, 255).astype(np.uint8)
    b8 = b.clip(0, 255).astype(np.uint8)
    score, _ = ssim(a8, b8, full=True, data_range=255)
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
    std = img.std()
    return float("inf") if std < 1e-6 else float(img.mean() / std)


def compute_cnr(img: np.ndarray) -> float:
    h, w = img.shape
    rh, rw = h // 4, w // 4
    tissue = img[rh: h - rh, rw: w - rw]
    border = np.concatenate([
        img[:rh, :].flatten(),
        img[h - rh:, :].flatten(),
        img[rh:h - rh, :rw].flatten(),
        img[rh:h - rh, w - rw:].flatten(),
    ])
    sigma_b = border.std()
    if sigma_b < 1e-6:
        return float("inf")
    return float(abs(tissue.mean() - border.mean()) / sigma_b)


def compute_epi(ref: np.ndarray, enh: np.ndarray) -> float:
    ref8 = ref.clip(0, 255).astype(np.uint8)
    enh8 = enh.clip(0, 255).astype(np.uint8)
    grad_ref = cv2.Laplacian(ref8, cv2.CV_64F)
    grad_enh = cv2.Laplacian(enh8, cv2.CV_64F)
    denom = np.abs(grad_ref).sum()
    return 1.0 if denom < 1e-6 else float(np.abs(grad_enh).sum() / denom)


def compute_correlation(sw: np.ndarray, hw: np.ndarray) -> float:
    """Pearson correlation between software and hardware pixel values.
    1.0 = perfect agreement, 0.0 = no correlation."""
    sw_flat = sw.flatten().astype(np.float64)
    hw_flat = hw.flatten().astype(np.float64)
    if sw_flat.std() < 1e-6 or hw_flat.std() < 1e-6:
        return 1.0 if np.allclose(sw_flat, hw_flat) else 0.0
    corr = np.corrcoef(sw_flat, hw_flat)[0, 1]
    return float(corr)


def compute_hw_sw_mse(sw: np.ndarray, hw: np.ndarray) -> float:
    """MSE directly between hardware output and software output."""
    return compute_mse(sw, hw)


def metrics_vs_original(ref: np.ndarray, enh: np.ndarray) -> dict[str, float]:
    mse = compute_mse(ref, enh)
    return {
        "MSE":          mse,
        "PSNR (dB)":    compute_psnr(mse),
        "SSIM":         compute_ssim(ref, enh),
        "Entropy":      compute_entropy(enh),
        "RMS Contrast": compute_rms_contrast(enh),
        "AMBE":         compute_ambe(ref, enh),
        "SNR":          compute_snr(enh),
        "CNR":          compute_cnr(enh),
        "EPI":          compute_epi(ref, enh),
    }


METRIC_NAMES = ["MSE", "PSNR (dB)", "SSIM", "Entropy", "RMS Contrast", "AMBE", "SNR", "CNR", "EPI"]
HIGHER_IS_BETTER = {
    "MSE": False, "PSNR (dB)": True, "SSIM": True,
    "Entropy": True, "RMS Contrast": True, "AMBE": False,
    "SNR": True, "CNR": True, "EPI": True,
}


# ─────────────────────────────────────────────────────────────
# MAIN EVALUATION
# ─────────────────────────────────────────────────────────────

def run_evaluation() -> None:
    sw_results: list[dict]   = []
    hw_results: list[dict]   = []
    agreement_scores: list[float] = []
    hw_sw_mse_scores: list[float] = []
    image_labels: list[str]  = []

    print("\n" + "=" * 80)
    print("  Hardware vs Software AGCWD — CT Scan Image Quality Evaluation")
    print("=" * 80)

    for stem, (sw_fname, hw_fname) in IMAGE_MAP.items():
        orig_path = ORIGINAL_DIR / f"{stem}.png"
        sw_path   = SOFTWARE_DIR / sw_fname
        hw_path   = HARDWARE_DIR / hw_fname

        missing = [p for p in (orig_path, sw_path, hw_path) if not p.exists()]
        if missing:
            print(f"\n[SKIP] {stem}")
            for m in missing:
                print(f"       Missing: {m}")
            continue

        orig = load_gray(orig_path)
        sw   = match_size(orig, load_gray(sw_path))
        hw   = match_size(orig, load_gray(hw_path))

        sw_m  = metrics_vs_original(orig, sw)
        hw_m  = metrics_vs_original(orig, hw)
        corr  = compute_correlation(sw, hw)
        diff_mse = compute_hw_sw_mse(sw, hw)

        sw_results.append(sw_m)
        hw_results.append(hw_m)
        agreement_scores.append(corr)
        hw_sw_mse_scores.append(diff_mse)
        image_labels.append(stem[:30])

        short = stem[:38]
        print(f"\n+-- Image: {short}")
        print(f"|  SW<>HW Correlation: {corr:.4f}   SW<>HW MSE: {diff_mse:.2f}")
        print(f"|  {'Metric':<16} {'Software':>12} {'Hardware':>12}  {'Closer to Original':>20}")
        print(f"|  {'-'*62}")
        for m in METRIC_NAMES:
            sv = sw_m[m]
            hv = hw_m[m]
            if HIGHER_IS_BETTER[m]:
                winner = "Software" if sv >= hv else "Hardware"
            else:
                winner = "Software" if sv <= hv else "Hardware"
            print(f"|  {m:<16} {sv:>12.4f} {hv:>12.4f}  {winner:>20}")

    if not sw_results:
        print("\n[ERROR] No images could be evaluated. Check paths.")
        return

    # ── Summary ─────────────────────────────────────────────
    print("\n\n" + "=" * 80)
    print("  SUMMARY — Mean ± Std across all images")
    print("=" * 80)
    print(f"{'Metric':<16} {'Software Mean':>15} {'Software Std':>13} {'Hardware Mean':>15} {'Hardware Std':>13}  {'Closer to Orig':>15}")
    print("-" * 90)
    for m in METRIC_NAMES:
        sv_arr = np.array([r[m] for r in sw_results])
        hv_arr = np.array([r[m] for r in hw_results])
        sv_f = sv_arr[np.isfinite(sv_arr)]
        hv_f = hv_arr[np.isfinite(hv_arr)]
        sv_mean = sv_f.mean() if len(sv_f) else float("nan")
        hv_mean = hv_f.mean() if len(hv_f) else float("nan")
        sv_std  = sv_f.std()  if len(sv_f) else float("nan")
        hv_std  = hv_f.std()  if len(hv_f) else float("nan")
        if HIGHER_IS_BETTER[m]:
            winner = "Software ✓" if sv_mean >= hv_mean else "Hardware ✓"
        else:
            winner = "Software ✓" if sv_mean <= hv_mean else "Hardware ✓"
        print(f"{m:<16} {sv_mean:>15.4f} {sv_std:>13.4f} {hv_mean:>15.4f} {hv_std:>13.4f}  {winner:>15}")

    avg_corr = np.mean(agreement_scores)
    avg_mse  = np.mean(hw_sw_mse_scores)
    print(f"\n  Hardware↔Software Agreement:")
    print(f"    Mean Pixel Correlation : {avg_corr:.4f}  (1.0 = perfect)")
    print(f"    Mean HW-SW MSE         : {avg_mse:.2f}")

    # ── CSV ─────────────────────────────────────────────────
    csv_path = OUTPUT_DIR / "hw_vs_sw_agcwd.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["Image", "Method"] + METRIC_NAMES + ["HW-SW Correlation", "HW-SW MSE"])
        for i, lbl in enumerate(image_labels):
            writer.writerow([lbl, "Software"] + [f"{sw_results[i][m]:.4f}" for m in METRIC_NAMES]
                            + [f"{agreement_scores[i]:.4f}", f"{hw_sw_mse_scores[i]:.2f}"])
            writer.writerow([lbl, "Hardware"] + [f"{hw_results[i][m]:.4f}" for m in METRIC_NAMES]
                            + [f"{agreement_scores[i]:.4f}", f"{hw_sw_mse_scores[i]:.2f}"])
    print(f"\n✅ CSV saved → {csv_path}")

    _plot_hw_vs_sw(sw_results, hw_results, agreement_scores, image_labels)


def _plot_hw_vs_sw(
    sw_results: list[dict],
    hw_results: list[dict],
    corrs: list[float],
    labels: list[str],
) -> None:
    metrics_to_plot = ["PSNR (dB)", "SSIM", "Entropy", "RMS Contrast", "AMBE", "CNR", "SNR", "EPI"]
    n = len(metrics_to_plot)
    cols = 4
    rows = (n + cols - 1) // cols

    fig, axes = plt.subplots(rows, cols, figsize=(22, rows * 5))
    fig.suptitle("Hardware vs Software AGCWD — CT Scan Image Quality Metrics",
                 fontsize=16, fontweight="bold", y=1.01)
    axes_flat = axes.flatten()

    x = np.arange(len(labels))
    width = 0.35
    c_sw = "#4CAF50"
    c_hw = "#9C27B0"

    for idx, metric in enumerate(metrics_to_plot):
        ax = axes_flat[idx]
        sv = [r[metric] for r in sw_results]
        hv = [r[metric] for r in hw_results]
        sv_plot = [v if np.isfinite(v) else np.nan for v in sv]
        hv_plot = [v if np.isfinite(v) else np.nan for v in hv]

        bars_s = ax.bar(x - width / 2, sv_plot, width, label="Software", color=c_sw, alpha=0.85)
        bars_h = ax.bar(x + width / 2, hv_plot, width, label="Hardware", color=c_hw, alpha=0.85)

        ax.set_title(metric, fontsize=12, fontweight="bold")
        ax.set_xticks(x)
        ax.set_xticklabels([l[:12] for l in labels], rotation=35, ha="right", fontsize=8)
        ax.legend(fontsize=9)
        ax.grid(axis="y", alpha=0.3)
        direction = "↑ higher better" if HIGHER_IS_BETTER[metric] else "↓ lower better"
        ax.set_xlabel(direction, fontsize=8, color="gray")

        for bar in bars_s:
            h = bar.get_height()
            if np.isfinite(h):
                ax.text(bar.get_x() + bar.get_width() / 2, h * 1.01, f"{h:.2f}",
                        ha="center", va="bottom", fontsize=7, color=c_sw)
        for bar in bars_h:
            h = bar.get_height()
            if np.isfinite(h):
                ax.text(bar.get_x() + bar.get_width() / 2, h * 1.01, f"{h:.2f}",
                        ha="center", va="bottom", fontsize=7, color=c_hw)

    for ax in axes_flat[len(metrics_to_plot):]:
        ax.set_visible(False)

    plt.tight_layout()
    out_path = OUTPUT_DIR / "hw_vs_sw_comparison.png"
    plt.savefig(out_path, dpi=150, bbox_inches="tight")
    print(f"✅ Chart saved → {out_path}")

    # Correlation subplot
    fig2, ax2 = plt.subplots(figsize=(10, 5))
    ax2.bar(np.arange(len(labels)), corrs, color=c_hw, alpha=0.8)
    ax2.axhline(1.0, color="red", linestyle="--", label="Perfect agreement (1.0)")
    ax2.axhline(np.mean(corrs), color="gray", linestyle=":", label=f"Mean = {np.mean(corrs):.4f}")
    ax2.set_xticks(np.arange(len(labels)))
    ax2.set_xticklabels([l[:18] for l in labels], rotation=35, ha="right", fontsize=9)
    ax2.set_title("Hardware ↔ Software Pixel Correlation", fontsize=13, fontweight="bold")
    ax2.set_ylabel("Pearson Correlation")
    ax2.set_ylim(0, 1.15)
    ax2.legend()
    ax2.grid(axis="y", alpha=0.3)
    plt.tight_layout()
    corr_path = OUTPUT_DIR / "hw_sw_correlation.png"
    plt.savefig(corr_path, dpi=150, bbox_inches="tight")
    print(f"✅ Correlation chart saved → {corr_path}")
    plt.show()


if __name__ == "__main__":
    run_evaluation()
