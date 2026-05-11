from pathlib import Path
from PIL import Image

# ============================================================
# INPUT HEX PATH
# ============================================================
INPUT_HEX_PATH = r"C:/Users/ACER/Downloads/Electronics project/output_image.hex"

# ============================================================
# OUTPUT IMAGE PATH
# ============================================================
OUTPUT_IMAGE_PATH = r"C:/Users/ACER/Downloads/Electronics project/result.png"

# Must match prepare_image_hex.py and tb_agcwd_hex.vhd
WIDTH = 512
HEIGHT = 512

def main():
    input_path = Path(INPUT_HEX_PATH)
    output_path = Path(OUTPUT_IMAGE_PATH)

    if not input_path.exists():
        raise FileNotFoundError(f"Hex file not found: {input_path}")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    pixels = []
    with input_path.open("r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s:
                continue
            if len(s) != 6:
                raise ValueError(f"Invalid hex pixel line: '{s}'")
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

    print("Done!")
    print(f"Output image : {output_path}")
    print(f"Size         : {WIDTH} x {HEIGHT}")
    print(f"Pixels       : {len(pixels)}")

if __name__ == "__main__":
    main()