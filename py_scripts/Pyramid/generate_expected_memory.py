import cv2
import numpy as np

def generate_expected_memory(input_filename="image_hex.txt", image_width=1280, image_height=720, output_filename="expected_pyramid.txt"):
    # 1. Read the Layer 0 image from the text file
    try:
        print(f"Loading {input_filename}...")
        # Load the hex strings from the text file
        hex_data = np.loadtxt(input_filename, dtype=str)
        
        # Convert hex strings to unsigned 8-bit integers
        pixel_data = np.array([int(x, 16) for x in hex_data], dtype=np.uint8)
        
        # Reshape the 1D array into a 2D image matrix (Layer 0)
        layer0 = pixel_data.reshape((image_height, image_width))
        print(f"Successfully loaded {input_filename} ({image_width}x{image_height}).")
        
    except FileNotFoundError:
        print(f"ERROR: {input_filename} not found. Ensure it is in the same directory.")
        return
    except ValueError as e:
        print(f"ERROR parsing hex data or dimension mismatch: {e}")
        print(f"Expected {image_width * image_height} pixels, but got {len(pixel_data)}.")
        return

    layers = [layer0]
    
    # 2. Generate Layer 1 through Layer 4
    current_layer = layer0
    for i in range(1, 5):
        # NOTE: You MUST match this to your RTL 'sub_sampler' logic!
        # If your RTL drops every other pixel (simple decimation):
        next_layer = current_layer[::2, ::2] 
        
        # Or, if your RTL does a Gaussian Blur (cv2.pyrDown):
        # next_layer = cv2.pyrDown(current_layer)
        
        layers.append(next_layer)
        current_layer = next_layer

    # 3. Flatten each layer into a 1D array
    flattened_layers = [layer.flatten() for layer in layers]

    # 4. Concatenate them contiguously: L0 -> L1 -> L2 -> L3 -> L4
    expected_memory = np.concatenate(flattened_layers)

    # 5. Write to a text file in Hex format for comparison
    with open(output_filename, 'w') as f:
        for pixel in expected_memory:
            # Format as 2-digit uppercase hexadecimal (e.g., "A5", "00", "FF")
            f.write(f"{pixel}\n")

    # Print a summary of the memory map
    print("\nMemory Map Generated Successfully:")
    start_idx = 0
    for i, layer in enumerate(layers):
        h, w = layer.shape
        size = h * w
        end_idx = start_idx + size - 1
        print(f"  Layer {i}: {w}x{h} \t| Size: {size} bytes \t| Array Indices: [{start_idx} : {end_idx}]")
        start_idx += size
        
    print(f"\nTotal Expected Memory Size: {len(expected_memory)} bytes.")
    print(f"Data written to {output_filename}")

if __name__ == "__main__":
    # Ensure these dimensions match your testbench exactly
    generate_expected_memory(input_filename="image_hex.txt", image_width=1280, image_height=720)