from pathlib import Path
from PIL import Image

# ============================================================
# EDIT PATHS HERE
# ============================================================
INPUT_HEX_PATH   = r"C:/Users/ACER/Downloads/Mehdi agcwd/AGCWD CLASSIQUE/output_image.hex"
OUTPUT_IMAGE_PATH = r"C:/Users/ACER/Downloads/Mehdi agcwd/AGCWD CLASSIQUE/enhanced_output.png"

# Must match the image size used in the testbench
WIDTH  = 8
HEIGHT = 8
# For full image use for example:
# WIDTH  = 640
# HEIGHT = 480

def main():
    input_path = Path(INPUT_HEX_PATH)
    output_path = Path(OUTPUT_IMAGE_PATH)

    if not input_path.exists():
        raise FileNotFoundError(f"Hex file not found: {input_path}")

    pixels = []
    with input_path.open("r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s:
                continue
            if len(s) != 6:
                raise ValueError(f"Invalid hex pixel: '{s}'")
            r = int(s[0:2], 16)
            g = int(s[2:4], 16)
            b = int(s[4:6], 16)
            pixels.append((r, g, b))

    expected = WIDTH * HEIGHT
    if len(pixels) != expected:
        raise ValueError(f"Pixel count mismatch: got {len(pixels)}, expected {expected}")

    img = Image.new("RGB", (WIDTH, HEIGHT))
    img.putdata(pixels)
    img.save(output_path)

    print(f"Done: {output_path}")
    print(f"Pixels read: {len(pixels)}")

if __name__ == "__main__":
    main()