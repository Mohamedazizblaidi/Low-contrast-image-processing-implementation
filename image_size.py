from pathlib import Path
from PIL import Image

# ============================================================
# EDIT PATH HERE
# ============================================================
IMAGE_PATH = r"C:\Users\ACER\Downloads\Electronics project\Inputs\Black Jar.jpg"

def main():
    path = Path(IMAGE_PATH)

    if not path.exists():
        raise FileNotFoundError(f"Image not found: {path}")

    # Open image and get dimensions
    with Image.open(path) as img:
        width, height = img.size
        mode = img.mode
        format_name = img.format

    total_pixels = width * height
    file_size_bytes = path.stat().st_size

    print("=== Image Information ===")
    print(f"Path          : {path}")
    print(f"Format        : {format_name}")
    print(f"Mode          : {mode}")
    print(f"Width         : {width} pixels")
    print(f"Height        : {height} pixels")
    print(f"Total pixels  : {total_pixels}")
    print(f"File size     : {file_size_bytes} bytes")

if __name__ == "__main__":
    main()