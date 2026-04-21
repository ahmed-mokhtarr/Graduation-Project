import cv2
import numpy as np

def generate_test_files(image_path):
    # 1. Load the image and convert to grayscale
    img = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
    if img is None:
        print("Error: Could not load image.")
        return

    # 2. Resize to match your FPGA hardware specs (1280x720)
    img = cv2.resize(img, (1280, 720))

    # 3. Create the Hex file for Verilog $readmemh
    print("Writing image_hex.txt...")
    with open('image_hex.txt', 'w') as f:
        # Flatten turns the 2D image into a 1D stream of pixels (raster scan)
        for pixel in img.flatten():
            f.write(f"{pixel:02X}\n") # Format as 2-digit Hex

    # 4. Compute the Golden Histogram (4x4 tiles, 256 bins)
    print("Computing golden histograms...")
    tile_h, tile_w = 720 // 4, 1280 // 4
    golden_hist = np.zeros((16, 256), dtype=int)

    for ty in range(4):
        for tx in range(4):
            tile_idx = ty * 4 + tx
            
            # Extract the specific 320x180 tile
            tile = img[ty*tile_h : (ty+1)*tile_h, tx*tile_w : (tx+1)*tile_w]
            
            # Calculate histogram for this tile
            hist, _ = np.histogram(tile.flatten(), bins=256, range=[0, 256])
            golden_hist[tile_idx] = hist

    # 5. Save the Golden Histogram
    # This will create a 4096-line file.
    # Lines 0-255 are Tile 0, Lines 256-511 are Tile 1, etc.
    print("Writing golden_histogram.txt...")
    with open('golden_histogram.txt', 'w') as f:
        for tile_idx in range(16):
            for bin_idx in range(256):
                f.write(f"{golden_hist[tile_idx, bin_idx]}\n")

    print("Done! Files are ready for your testbench.")

# Run the function (replace with your actual image name)
generate_test_files('IMG_2529.jpg')