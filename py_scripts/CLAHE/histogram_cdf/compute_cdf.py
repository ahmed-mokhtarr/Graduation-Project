import os

def compute_and_compare_cdf(input_file):
    print(f"Reading {input_file}...")
    if not os.path.exists(input_file):
        print(f"Error: {input_file} not found. Generate it first!")
        return

    with open(input_file, 'r') as f:
        clipped_bins = [int(line.strip()) for line in f.readlines()]

    ideal_cdf = []
    hw_cdf = []

    pixels_per_tile = 57600
    hw_scale_factor = 291

    max_error = 0
    total_error = 0
    error_count = 0

    print("Computing Ideal Math vs Hardware Fixed-Point Math...")
    for tile in range(16):
        tile_start = tile * 256
        tile_bins = clipped_bins[tile_start : tile_start + 256]

        running_sum = 0
        for val in tile_bins:
            running_sum += val
            
            # 1. Ideal Math (Float mapping scaled to 255)
            ideal_val = (running_sum * 255) // pixels_per_tile
            
            # 2. Hardware Math (Multiply by 291, Bit-shift Right by 16)
            hw_val = (running_sum * hw_scale_factor) >> 16
            
            # Saturation check (Just in case math clips over 8-bit space)
            if ideal_val > 255: ideal_val = 255
            if hw_val > 255: hw_val = 255

            ideal_cdf.append(ideal_val)
            hw_cdf.append(hw_val)

            # Error Calculation
            diff = abs(ideal_val - hw_val)
            if diff > 0:
                error_count += 1
                total_error += diff
                if diff > max_error:
                    max_error = diff

    # Write the outputs to separate files
    with open('golden_cdf_ideal.txt', 'w') as f:
        for val in ideal_cdf:
            f.write(f"{val}\n")
            
    with open('golden_cdf_hw_model.txt', 'w') as f:
        for val in hw_cdf:
            f.write(f"{val}\n")

    print("\n" + "="*50)
    print("   ERROR ESTIMATION (Ideal vs HW Fixed-Point)")
    print("="*50)
    print(f"Total Bins Evaluated : 4096")
    print(f"Bins with Mismatch   : {error_count} ({(error_count/4096)*100:.1f}%)")
    print(f"Maximum Pixel Error  : {max_error} grayscale level(s)")
    if error_count > 0:
        print(f"Average Pixel Error  : {total_error / error_count:.2f} grayscale level(s)")
    print("="*50 + "\n")

# Execute the function
compute_and_compare_cdf('golden_clipped.txt')