import cv2
import numpy as np

def generate_hex_from_image(input_path, output_path, width=1280, height=720):
    """
    Reads an image, converts to grayscale, resizes, and writes out a hex file 
    suitable for Verilog $readmemh.
    """
    # 1. Read the image directly in grayscale mode
    img_gray = cv2.imread(input_path, cv2.IMREAD_GRAYSCALE)
    if img_gray is None:
        print(f"Error: Could not open {input_path}. Check the path.")
        return

    # 2. Resize the image (OpenCV expects a tuple of (width, height))
    img_resized = cv2.resize(img_gray, (width, height), interpolation=cv2.INTER_LINEAR)

    # 3. Flatten the 2D array into a 1D array of pixels
    pixel_data = img_resized.flatten()

    # 4. Write the pixel values to a text file in hexadecimal format
    print(f"Generating {output_path}...")
    with open(output_path, 'w') as f:
        for pixel in pixel_data:
            # {:02X} formats the integer as a 2-digit uppercase hex value (e.g., 0A, FF)
            f.write(f"{pixel:02X}\n")

    print(f"Done! Wrote {len(pixel_data)} pixels ({width}x{height}) to {output_path}.")

if __name__ == "__main__":
    # Update these filenames as needed
    input_image_file = 'zebra.jpg'
    output_hex_file = 'image_pixels.hex'
    
    generate_hex_from_image(input_image_file, output_hex_file, width=1280, height=720)