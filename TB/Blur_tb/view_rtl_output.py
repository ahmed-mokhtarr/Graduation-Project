import numpy as np
from PIL import Image
import os

# --- Configuration ---
TARGET_WIDTH  = 1280
TARGET_HEIGHT = 720
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data')

def main():
    rtl_hex = os.path.join(DATA_DIR, 'rtl_output.hex')
    if not os.path.exists(rtl_hex):
        print(f"Error: {rtl_hex} not found. Run simulation first!")
        return

    print(f"Reading RTL output from {rtl_hex}...")
    with open(rtl_hex, 'r') as f:
        lines = f.readlines()
    
    pixels = [int(line.strip(), 16) for line in lines]
    
    # Check if we have the right number of pixels
    if len(pixels) != TARGET_WIDTH * TARGET_HEIGHT:
        print(f"Warning: Hex file has {len(pixels)} pixels, but image is {TARGET_WIDTH}x{TARGET_HEIGHT} ({TARGET_WIDTH*TARGET_HEIGHT} pixels).")
        # Crop or pad to fit for visualization
        pixels = pixels[:TARGET_WIDTH * TARGET_HEIGHT]

    img_array = np.array(pixels, dtype=np.uint8).reshape((TARGET_HEIGHT, TARGET_WIDTH))
    out_path = os.path.join(DATA_DIR, 'Rtl_blurred.png')
    Image.fromarray(img_array).save(out_path)
    
    print(f"Successfully converted RTL hex to photo: {out_path}")

if __name__ == "__main__":
    main()
