import pydicom
import numpy as np
from PIL import Image
import os

"""
DICOM to PNG Converter (Lossless)
---------------------------------
This script converts DICOM medical images to PNG format without losing quality.
It uses 16-bit depth for PNG to ensure the full dynamic range of the DICOM 
(which is usually 12-bit or 14-bit) is preserved.

Requirements:
pip install pydicom numpy Pillow
"""

def convert_dicom_to_png(dicom_path, output_path):
    """
    Reads a DICOM file and saves it as a 16-bit PNG.
    """
    try:
        print(f"Reading DICOM: {dicom_path}...")
        
        # Load the DICOM file
        ds = pydicom.dcmread(dicom_path)
        
        # Check if pixel data exists
        if not hasattr(ds, 'pixel_array'):
            print("Error: This DICOM file does not contain image pixel data.")
            return

        # Extract pixel array
        pixel_array = ds.pixel_array.astype(np.float32)

        # Apply Rescale Slope and Intercept (Standard for medical imaging)
        # This converts raw values to Hounsfield Units (HU) or physical units
        if 'RescaleSlope' in ds and 'RescaleIntercept' in ds:
            pixel_array = pixel_array * ds.RescaleSlope + ds.RescaleIntercept

        # Normalize to 16-bit (0 - 65535) to maintain maximum precision
        p_min, p_max = pixel_array.min(), pixel_array.max()
        
        if p_max > p_min:
            # Linear normalization to 16-bit range
            pixel_array = (pixel_array - p_min) / (p_max - p_min) * 65535.0
            pixel_array = pixel_array.astype(np.uint16)
        else:
            # If image is a single color
            pixel_array = np.zeros_like(pixel_array, dtype=np.uint16)

        # Create Image object (mode 'I;16' for 16-bit grayscale)
        img = Image.fromarray(pixel_array, mode='I;16')
        
        # Save as PNG (PNG is inherently lossless)
        img.save(output_path)
        print(f"Success! PNG saved at: {output_path}")
        print(f"Original Range: {p_min} to {p_max}")

    except Exception as e:
        print(f"An unexpected error occurred: {e}")

if __name__ == "__main__":
    # ======================================================
    # MANUAL CONFIGURATION
    # Replace the path below with your actual DICOM file path
    # ======================================================
    img_path = r"C:\Users\ACER\Downloads\Electronics project\T2spc_darkfluid_sag_iso_p2_1800000004191557.dcm" 
    # ======================================================

    # Check if the file exists before attempting conversion
    if os.path.exists(img_path):
        # Create output filename by swapping extension
        output_filename = os.path.splitext(img_path)[0] + ".png"
        convert_dicom_to_png(img_path, output_filename)
    else:
        print(f"ERROR: File not found at: {img_path}")
        print("Please update the 'img_path' variable in the script with your DICOM file path.")
