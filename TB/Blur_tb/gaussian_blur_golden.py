"""
Gaussian Blur Golden Reference - Centered with BORDER_REFLECT_101
Matches the RTL centered pipeline output.
"""
import numpy as np
from PIL import Image
import os
import sys

TARGET_WIDTH  = 1280
TARGET_HEIGHT = 720
COEFFS = np.array([528, 584, 620, 632, 620, 584, 528], dtype=np.int64)

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data')

def save_hex(data, filepath):
    with open(filepath, 'w') as f:
        for val in data.flatten():
            f.write(f'{int(val):02X}\n')

def hex_to_image(hex_path, width, height, out_path):
    with open(hex_path, 'r') as f:
        lines = f.readlines()
    pixels = [int(line.strip(), 16) for line in lines]
    img_array = np.array(pixels, dtype=np.uint8).reshape((height, width))
    Image.fromarray(img_array).save(out_path)

def reflect_index(i, size):
    """BORDER_REFLECT_101: dcb|abcdefg|fed"""
    if i < 0:
        return -i
    elif i >= size:
        return 2 * (size - 1) - i
    return i

def main():
    if len(sys.argv) > 1: image_path = sys.argv[1]
    else: print("Usage: python gaussian_blur_golden.py <image_path>"); return

    img = Image.open(image_path).convert('L').resize((TARGET_WIDTH, TARGET_HEIGHT), Image.LANCZOS)
    gray = np.array(img, dtype=np.uint8)
    H, W = gray.shape

    # Centered vertical pass with BORDER_REFLECT_101
    vert = np.zeros((H, W), dtype=np.int64)
    for r in range(H):
        for k in range(7):
            src_row = reflect_index(r - 3 + k, H)
            vert[r, :] += COEFFS[k] * gray[src_row, :].astype(np.int64)

    # Centered horizontal pass with BORDER_REFLECT_101
    horiz = np.zeros((H, W), dtype=np.int64)
    for c in range(W):
        for k in range(7):
            src_col = reflect_index(c - 3 + k, W)
            horiz[:, c] += COEFFS[k] * vert[:, src_col]

    blurred = (horiz >> 24).astype(np.uint8)

    os.makedirs(DATA_DIR, exist_ok=True)

    input_hex = os.path.join(DATA_DIR, 'input_gray.hex')
    output_hex = os.path.join(DATA_DIR, 'expected_output.hex')
    save_hex(gray, input_hex)
    save_hex(blurred, output_hex)

    hex_to_image(input_hex, W, H, os.path.join(DATA_DIR, 'grayscale_input.png'))
    hex_to_image(output_hex, W, H, os.path.join(DATA_DIR, 'verified_golden_from_hex.png'))

    print(f"Generated Centered Golden Reference for {W}x{H}")
    print(f"Saved: {input_hex}")
    print(f"Saved: {output_hex}")

if __name__ == '__main__': main()
