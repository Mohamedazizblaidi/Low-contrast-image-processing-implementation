import sys
import os
from pathlib import Path

# Add the algorithms directory to the path to ensure imports work
algorithms_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'algorithms')
sys.path.insert(0, algorithms_dir)

import matplotlib.pyplot as plt

from agcwd import load_rgb_image, apply_agcwd_rgb
from clahe import apply_clahe_rgb

def main():
    # Default image path
    image_path = r"C:\Users\ACER\Downloads\Electronics project\Jun_coronacases_case1_128.png"
    
    # Use command line argument if provided
    if len(sys.argv) > 1:
        image_path = sys.argv[1]

    path_obj = Path(image_path)
    if not path_obj.exists():
        print(f"Error: Image not found at '{image_path}'")
        print("Usage: python compare_algorithms.py <path_to_image>")
        return

    print(f"Loading '{image_path}'...")
    try:
        img = load_rgb_image(path_obj)
    except Exception as exc:
        print(f"Failed to load image: {exc}")
        return

    print("Running algorithms... This may take a moment.")

    # Apply algorithms
    results = {}

    print("1/2: AGCWD...")
    results["AGCWD"] = apply_agcwd_rgb(img, alpha=0.5, denoise=True, sharpen=True)

    print("2/2: CLAHE...")
    results["CLAHE"] = apply_clahe_rgb(img, clip_limit=2.0, tile_grid=(8, 8), denoise=True, sharpen=True)

    print("All algorithms applied. Plotting results...")

    # Plot all results in a 1x3 grid
    fig, axes = plt.subplots(1, 3, figsize=(18, 6))
    axes = axes.flatten()

    # Original Image
    axes[0].imshow(img)
    axes[0].set_title("Original Image")
    axes[0].axis('off')

    # Enhanced Images
    for idx, (title, enhanced_img) in enumerate(results.items(), start=1):
        axes[idx].imshow(enhanced_img)
        axes[idx].set_title(title)
        axes[idx].axis('off')

    # Hide unused subplots
    for i in range(len(results) + 1, len(axes)):
        axes[i].axis('off')
        axes[i].set_visible(False)

    plt.tight_layout()
    
    # IMPORTANT: output_base must be a directory, not a file path.
    output_base = Path(r"C:\Users\ACER\Downloads\Electronics project\output")
    
    # 1. Save comparison plot to 'Both' folder
    both_dir = output_base / "Both"
    both_dir.mkdir(parents=True, exist_ok=True)
    comparison_path = both_dir / f"comparison_{path_obj.stem}.png"
    fig.savefig(comparison_path)
    print(f"Comparison plot saved to: {comparison_path}")
    
    # 2. Save individual results to their respective algorithm folders
    for title, enhanced_img in results.items():
        algo_dir = output_base / title.lower()
        algo_dir.mkdir(parents=True, exist_ok=True)
        algo_path = algo_dir / f"{title}_{path_obj.stem}.png"
        plt.imsave(algo_path, enhanced_img)
        print(f"{title} result saved to: {algo_path}")

    plt.show()

if __name__ == "__main__":
    main()