import numpy as np
from PIL import Image
from pathlib import Path

# LUT from VHDL
GAMMA_03_LUT = [int(round(255 * (i / 255.0) ** 0.3)) for i in range(256)]

def emulate(hex_path, output_path):
    with open(hex_path, "r") as f:
        lines = f.readlines()
    
    pixels = []
    for line in lines:
        line = line.strip()
        if not line: continue
        r = int(line[0:2], 16)
        g = int(line[2:4], 16)
        b = int(line[4:6], 16)
        pixels.append([r, g, b])
    
    pixels = np.array(pixels, dtype=np.uint8)
    
    # Calculate stats (like channel_stats.vhd)
    mean = np.mean(pixels)
    std = np.std(pixels)
    
    is_dark = (mean < 100) and (std < 50)
    
    print(f"Mean: {mean:.2f}, Std: {std:.2f}, Is Dark: {is_dark}")
    
    # Apply Gamma LUT if dark
    if is_dark or mean < 110:
        print("Applying Gamma 0.3 boost...")
        enhanced = np.zeros_like(pixels)
        for i in range(len(pixels)):
            enhanced[i, 0] = GAMMA_03_LUT[pixels[i, 0]]
            enhanced[i, 1] = GAMMA_03_LUT[pixels[i, 1]]
            enhanced[i, 2] = GAMMA_03_LUT[pixels[i, 2]]
    else:
        # Normal contrast stretch (simplified)
        print("Applying normal stretch...")
        enhanced = ((pixels.astype(np.int32) - 128) * 1.5 + 128).clip(0, 255).astype(np.uint8)
    
    # Rebuild image
    img = Image.fromarray(enhanced.reshape((512, 512, 3)))
    img.save(output_path)
    print(f"Emulated result saved to: {output_path}")

if __name__ == "__main__":
    emulate("input_image.hex", "emulated_result.png")
