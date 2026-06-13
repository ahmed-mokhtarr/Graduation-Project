import cv2
import numpy as np
import os
from PIL import Image

# --- Configuration ---
TARGET_WIDTH  = 1280
TARGET_HEIGHT = 720
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data')

def hex_to_image(hex_path, width, height, out_path):
    with open(hex_path, 'r') as f:
        lines = f.readlines()
    pixels = [int(line.strip(), 16) for line in lines]
    img_array = np.array(pixels, dtype=np.uint8).reshape((height, width))
    Image.fromarray(img_array).save(out_path)

def main():
    input_hex = os.path.join(DATA_DIR, 'input_gray.hex')
    if not os.path.exists(input_hex):
        print(f"Error: Run golden script first!")
        return

    with open(input_hex, 'r') as f:
        hex_data = f.readlines()
    pixels = [int(line.strip(), 16) for line in hex_data]
    gray = np.array(pixels, dtype=np.uint8).reshape((TARGET_HEIGHT, TARGET_WIDTH))

    # Apply Standard OpenCV Gaussian Blur
    blurred = cv2.GaussianBlur(gray, (7, 7), sigmaX=5, sigmaY=5)

    # Save expected hex
    output_hex = os.path.join(DATA_DIR, 'expected_opencv.hex')
    with open(output_hex, 'w') as f:
        for val in blurred.flatten():
            f.write(f'{int(val):02X}\n')

    # VERIFICATION: Convert Hex back to Image
    hex_to_image(output_hex, TARGET_WIDTH, TARGET_HEIGHT, 
                 os.path.join(DATA_DIR, 'opencv_blurred.png'))

    print(f"Generated OpenCV Reference and verified hex file as photo in 'data' folder.")

if __name__ == "__main__":
    main()
