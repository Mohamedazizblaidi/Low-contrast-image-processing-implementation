import sys
import os
from pathlib import Path
import numpy as np
import cv2
from skimage.metrics import peak_signal_noise_ratio as psnr
from skimage.metrics import structural_similarity as ssim
from skimage.metrics import mean_squared_error as mse
from skimage.measure import shannon_entropy
from prettytable import PrettyTable

# Add the algorithms directory to the path to ensure imports work
algorithms_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'algorithms')
sys.path.insert(0, algorithms_dir)

# Import all the algorithms
from agcwd import load_rgb_image, apply_agcwd_rgb
from clahe import apply_clahe_rgb

def calculate_metrics(original, enhanced):
    """
    Calculate various famous image quality metrics between the original and enhanced images.
    """
    # Ensure images are the same type
    if original.dtype != enhanced.dtype:
        enhanced = enhanced.astype(original.dtype)
        
    data_range = 255 if original.dtype == np.uint8 else (original.max() - original.min())
    if data_range == 0:
        data_range = 1 # Avoid division by zero
        
    # Calculate Mean Squared Error (MSE)
    m_mse = mse(original, enhanced)
    
    # Calculate Peak Signal-to-Noise Ratio (PSNR)
    m_psnr = psnr(original, enhanced, data_range=data_range)
    
    # Calculate Structural Similarity Index (SSIM)
    # Determine the smallest dimension to set window size safely
    min_dim = min(original.shape[0], original.shape[1])
    win_size = min(7, min_dim)
    if win_size % 2 == 0:
        win_size -= 1
        
    if win_size >= 3:
        m_ssim = ssim(original, enhanced, channel_axis=2, data_range=data_range, win_size=win_size)
    else:
        m_ssim = float('nan')
    
    # Calculate AMBE (Absolute Mean Brightness Error)
    original_gray = cv2.cvtColor(original, cv2.COLOR_RGB2GRAY)
    enhanced_gray = cv2.cvtColor(enhanced, cv2.COLOR_RGB2GRAY)
    m_ambe = abs(np.mean(original_gray) - np.mean(enhanced_gray))
    
    # Calculate Shannon Entropy (Information content)
    m_entropy = shannon_entropy(enhanced_gray)
    
    # Calculate RMS Contrast (Standard deviation of pixel intensities)
    m_contrast = np.std(enhanced_gray)

    # Calculate Mean Luminosity
    m_lum = np.mean(enhanced_gray)

    # Calculate Sharpness (Laplacian Variance)
    m_sharpness = cv2.Laplacian(enhanced_gray, cv2.CV_64F).var()

    return {
        "MSE": m_mse,
        "PSNR (dB)": m_psnr,
        "SSIM": m_ssim,
        "AMBE": m_ambe,
        "Entropy": m_entropy,
        "RMS Contrast": m_contrast,
        "Luminosity": m_lum,
        "Sharpness": m_sharpness
    }

def main():
    # Default image path
    image_path = r"C:\Users\ACER\Downloads\Electronics project\Inputs\ross-sneddon-m8Csc9Vp6iM-unsplash.jpg"
    
    # Use command line argument if provided
    if len(sys.argv) > 1:
        image_path = sys.argv[1]

    path_obj = Path(image_path)
    if not path_obj.exists():
        print(f"Error: Image not found at '{image_path}'")
        print("Usage: python evaluate_algorithms.py <path_to_image>")
        return

    print(f"Loading '{image_path}'...")
    try:
        img = load_rgb_image(path_obj)
    except Exception as exc:
        print(f"Failed to load image: {exc}")
        return

    base_results_dir = Path(__file__).resolve().parent / "Results"
    base_results_dir.mkdir(parents=True, exist_ok=True)
    
    run_num = 1
    while True:
        results_dir = base_results_dir / f"essay_{run_num}"
        if not results_dir.exists():
            results_dir.mkdir()
            break
        run_num += 1

    print("Running algorithms and calculating metrics... This may take a moment.")
    
    results = {}
    
    import matplotlib.pyplot as plt
    from PIL import Image
    
    # Helper function to run an algorithm and evaluate it
    def evaluate(name, func, *args, **kwargs):
        print(f"Processing: {name}...")
        try:
            enhanced = func(*args, **kwargs)
            
            if name != "Original":
                out_path = results_dir / f"{name.replace(' ', '_')}.jpg"
                Image.fromarray(enhanced).save(out_path)
                
            metrics = calculate_metrics(img, enhanced)
            results[name] = metrics
        except Exception as e:
            print(f"  Error processing {name}: {e}")

    # Evaluate the original image to get baseline metrics
    evaluate("Original", lambda x: x, img)

    # Apply all algorithms
    evaluate("AGCWD", apply_agcwd_rgb, img, alpha=0.5, denoise=True, sharpen=True)
    evaluate("CLAHE", apply_clahe_rgb, img, clip_limit=2.0, tile_grid=(8, 8), denoise=True, sharpen=True)

    # Write Results to Markdown File
    output_md = results_dir / "evaluation_results.md"
    
    with open(output_md, "w", encoding="utf-8") as f:
        f.write("# Algorithm Evaluation Results\n\n")
        f.write("| Algorithm | MSE (v) | PSNR (dB) (^) | SSIM (^) | AMBE (v) | Entropy (^) | Contrast (^) | Luminosity (^) | Sharpness (^) |\n")
        f.write("| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n")
        
        for name, metrics in results.items():
            f.write(f"| {name} | {metrics['MSE']:.2f} | {metrics['PSNR (dB)']:.2f} | {metrics['SSIM']:.4f} | {metrics['AMBE']:.2f} | {metrics['Entropy']:.4f} | {metrics['RMS Contrast']:.2f} | {metrics['Luminosity']:.2f} | {metrics['Sharpness']:.2f} |\n")
            
        f.write("\n## Legend & Explanations\n\n")
        f.write("### Metrics Description & Grading\n\n")
        
        f.write("#### 1. MSE (Mean Squared Error)\n")
        f.write("- Measures the average squared difference between the enhanced and original image pixels.\n")
        f.write("- **Lower score (v)**: Indicates high similarity to the original image (fewer changes).\n")
        f.write("- **Higher score (^)**: Indicates significant changes have been made to the original image.\n\n")
        
        f.write("#### 2. PSNR (Peak Signal-to-Noise Ratio)\n")
        f.write("- Evaluates the quality between the original and enhanced image in decibels (dB).\n")
        f.write("- **Higher score (^)**: Means higher fidelity and similarity to the original image.\n")
        f.write("- **Lower score (v)**: Means more deviation/enhancement from the original image.\n\n")
        
        f.write("#### 3. SSIM (Structural Similarity Index)\n")
        f.write("- Measures the structural similarity between the images (ranges from 0 to 1.0).\n")
        f.write("- **Higher score (^)**: (closer to 1.0) means the structural information (edges, shapes) of the original is well preserved.\n")
        f.write("- **Lower score (v)**: Means structural information has been altered significantly.\n")
        f.write("- *Note for MSE, PSNR, SSIM*: In image enhancement, very high fidelity to the original isn't always the goal if the original was poor quality.\n\n")
        
        f.write("#### 4. AMBE (Absolute Mean Brightness Error)\n")
        f.write("- Measures the absolute difference in mean brightness between the original and enhanced images.\n")
        f.write("- **Lower score (v)**: Means the overall brightness of the original image is perfectly preserved.\n")
        f.write("- **Higher score (^)**: Means the overall brightness has significantly increased or decreased.\n\n")
        
        f.write("#### 5. Entropy\n")
        f.write("- Measures the amount of information, complexity, and details present in the image.\n")
        f.write("- **Higher score (^)**: Means the image has more details, richer textures, and better information content (generally desirable).\n")
        f.write("- **Lower score (v)**: Means the image is smoother, flatter, or has lost detail/information.\n\n")
        
        f.write("#### 6. Contrast (RMS Contrast)\n")
        f.write("- Measures the standard deviation of pixel intensities.\n")
        f.write("- **Higher score (^)**: Means the image has a wider dynamic range and excellent contrast (usually desirable).\n")
        f.write("- **Lower score (v)**: Means the image has low contrast and might appear washed out or flat.\n\n")
        
        f.write("#### 7. Luminosity\n")
        f.write("- Measures the average brightness level of the image (on a scale of 0 to 255).\n")
        f.write("- **Higher score (^)**: Means the image is brighter overall.\n")
        f.write("- **Lower score (v)**: Means the image is darker overall.\n\n")
        
        f.write("#### 8. Sharpness (Laplacian Variance)\n")
        f.write("- Measures the clarity and amount of sharp edges in the image.\n")
        f.write("- **Higher score (^)**: Means the image is sharper and contains more defined edges.\n")
        f.write("- **Lower score (v)**: Means the image is blurry or soft.\n")

    # Generate Graphs
    print("Generating performance graphs...")
    metrics_to_plot = ["PSNR (dB)", "SSIM", "Entropy", "RMS Contrast", "Luminosity", "Sharpness"]
    
    fig, axes = plt.subplots(2, 3, figsize=(18, 10))
    axes = axes.flatten()
    
    for idx, metric in enumerate(metrics_to_plot):
        ax = axes[idx]
        names = list(results.keys())
        values = [results[n][metric] for n in names]
        
        clean_values = [0 if (np.isnan(v) or np.isinf(v)) else v for v in values]
        
        bars = ax.bar(names, clean_values, color=['#4C72B0', '#DD8452', '#55A868'][:len(names)])
        ax.set_title(metric, fontsize=14, fontweight='bold')
        ax.set_ylabel("Score")
        
        for bar, val, orig_val in zip(bars, clean_values, values):
            if val != 0:
                ax.text(bar.get_x() + bar.get_width()/2, bar.get_height(), f'{val:.2f}', ha='center', va='bottom')
            elif np.isinf(orig_val):
                ax.text(bar.get_x() + bar.get_width()/2, 0, 'INF', ha='center', va='bottom')
                
    plt.tight_layout()
    plt.savefig(results_dir / "metrics_comparison.png")
    
    print(f"\nEvaluation complete! All outputs have been saved to the '{results_dir}' folder.")

if __name__ == "__main__":
    main()
