from pathlib import Path
from PIL import Image

# ============================================================
# EDIT PATHS HERE
# ============================================================
INPUT_IMAGE_PATH = r"C:/Users/ACER/Downloads/Mehdi agcwd/AGCWD CLASSIQUE/input.png"
OUTPUT_HEX_PATH   = r"C:/Users/ACER/Downloads/Mehdi agcwd/AGCWD CLASSIQUE/input_image.hex"

# Image size expected by the testbench
WIDTH  = 8
HEIGHT = 8
# For full image use for example:
# WIDTH  = 640
# HEIGHT = 480

def main():
    input_path = Path(INPUT_IMAGE_PATH)
    output_path = Path(OUTPUT_HEX_PATH)

    if not input_path.exists():
        raise FileNotFoundError(f"Input image not found: {input_path}")

    img = Image.open(input_path).convert("RGB")
    img = img.resize((WIDTH, HEIGHT), Image.BILINEAR)

    pixels = list(img.getdata())

    with output_path.open("w", encoding="utf-8") as f:
        for r, g, b in pixels:
            f.write(f"{r:02X}{g:02X}{b:02X}\n")

    print(f"Done: {output_path}")
    print(f"Image size: {WIDTH}x{HEIGHT}")
    print(f"Pixels written: {len(pixels)}")

if __name__ == "__main__":
    main()