import os
from PIL import Image

"""
Image Resizer Script
--------------------
This script resizes an image to a specific width and height that you choose.
It preserves image quality using high-quality resampling.

Requirements:
pip install Pillow
"""

def resize_image(input_path, output_path, target_width, target_height):
    """
    Resizes the image at input_path and saves it to output_path.
    """
    try:
        if not os.path.exists(input_path):
            print(f"Error: File not found at {input_path}")
            return

        # Open the image
        with Image.open(input_path) as img:
            print(f"Current image: {input_path}")
            print(f"Original resolution: {img.width}x{img.height}")
            
            # Perform the resize
            # Image.Resampling.LANCZOS is best for downscaling quality
            resized_img = img.resize((target_width, target_height), Image.Resampling.LANCZOS)
            
            # Save the result
            resized_img.save(output_path)
            
            print(f"Success! Resized image saved to: {output_path}")
            print(f"New resolution: {target_width}x{target_height}")

    except Exception as e:
        print(f"An unexpected error occurred: {e}")

if __name__ == "__main__":
    # ==========================================
    # CONFIGURATION
    # ==========================================
    # 1. Path to your image
    img_path = r"C:\Users\ACER\Downloads\Electronics project\Jun_coronacases_case4_100.png"
    
    # 2. Choose your target size (Width, Height)
    new_width = 256
    new_height = 256
    # ==========================================

    # Generate output path (e.g., photo_resized.png)
    file_dir = os.path.dirname(img_path)
    file_name = os.path.basename(img_path)
    name, ext = os.path.splitext(file_name)
    
    output_path = os.path.join(file_dir, f"{name}_{new_width}x{new_height}{ext}")
    
    # Run the resizing
    resize_image(img_path, output_path, new_width, new_height)
