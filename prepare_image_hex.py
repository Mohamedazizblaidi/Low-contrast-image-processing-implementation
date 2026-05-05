from pathlib import Path
from PIL import Image

# ============================================================
# INPUT IMAGE PATH
# ============================================================
INPUT_IMAGE_PATH = r"C:\Users\ACER\Downloads\Electronics project\image.png"

# ============================================================
# OUTPUT HEX PATH
# ============================================================
OUTPUT_HEX_PATH = r"C:\Users\ACER\Downloads\Electronics project\input_image.hex"

# ============================================================
# SIZE USED FOR VIVADO TEST
# ============================================================
TARGET_W = 400
TARGET_H = 267

def main():
    input_path = Path(INPUT_IMAGE_PATH)
    output_path = Path(OUTPUT_HEX_PATH)

    if not input_path.exists():
        raise FileNotFoundError(f"Input image not found: {input_path}")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    img = Image.open(input_path).convert("RGB")
    img = img.resize((TARGET_W, TARGET_H), Image.LANCZOS)

    pixels = list(img.getdata())

    with output_path.open("w", encoding="utf-8") as f:
        for r, g, b in pixels:
            f.write(f"{r:02X}{g:02X}{b:02X}\n")

    print("Done!")
    print(f"Input image : {input_path}")
    print(f"Output hex  : {output_path}")
    print(f"Size        : {TARGET_W} x {TARGET_H}")
    print(f"Pixels      : {len(pixels)}")

if __name__ == "__main__":
    main()