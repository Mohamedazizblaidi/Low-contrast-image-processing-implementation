import cv2
import numpy as np
import sys
import os


DEFAULT_INPUT_PATH = r'C:\Users\ACER\Downloads\Electronics project\image.png'

def create_low_luminosity_image(img_path, output_path, factor=0.3):
    """
    Creates a low luminosity version of an image by scaling its pixel intensities.
    
    Args:
        img_path (str): Path to the input image.
        output_path (str): Path to save the low luminosity image.
        factor (float): The factor to multiply pixel values by (0.0 to 1.0).
                        0.3 provides a medium luminosity reduction.
    """
    if not os.path.exists(img_path):
        print(f"Error: File {img_path} not found.")
        return

    # Load the image
    img = cv2.imread(img_path)
    if img is None:
        print(f"Error: Could not load image {img_path}.")
        return

    # Convert to float to avoid clipping during multiplication
    img_float = img.astype(np.float32)

    # Multiply by factor to reduce luminosity
    low_light_img = img_float * factor

    # Clip values to [0, 255] and convert back to uint8
    low_light_img = np.clip(low_light_img, 0, 255).astype(np.uint8)

    # Save the result
    cv2.imwrite(output_path, low_light_img)
    print(f"Low luminosity image saved to {output_path}")

if __name__ == "__main__":
    input_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_INPUT_PATH
    factor = float(sys.argv[2]) if len(sys.argv) > 2 else 0.3
    
    print(f"Using input: {input_path} with factor: {factor} (0.3 is medium luminosity)")
    
    # Generate output path
    base, ext = os.path.splitext(input_path)
    output_path = f"{base}_low_light{ext}"
    
    create_low_luminosity_image(input_path, output_path, factor)
