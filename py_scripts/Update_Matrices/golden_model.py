import random

def to_hex(val, bits):
    """Converts a signed integer to a 2's complement hex string of fixed width."""
    hex_str = hex(val & ((1 << bits) - 1))[2:]
    chars_needed = (bits + 3) // 4
    return hex_str.zfill(chars_needed)

def generate_golden_model(width, height):
    num_pixels = width * height
    
    with open("input_frame1.txt", "w") as f_in1, \
         open("input_frame2.txt", "w") as f_in2, \
         open("golden_outputs.txt", "w") as f_out:
         
        for _ in range(num_pixels):
            # Generate random signed inputs within the bit-width constraints
            r2_1 = random.randint(-2**45, 2**45 - 1)
            r3_1 = random.randint(-2**47, 2**47 - 1)
            r4_1 = random.randint(-2**44, 2**44 - 1)
            r5_1 = random.randint(-2**47, 2**47 - 1)
            r6_1 = random.randint(-2**45, 2**45 - 1)

            r2_2 = random.randint(-2**45, 2**45 - 1)
            r3_2 = random.randint(-2**47, 2**47 - 1)
            r4_2 = random.randint(-2**44, 2**44 - 1)
            r5_2 = random.randint(-2**47, 2**47 - 1)
            r6_2 = random.randint(-2**45, 2**45 - 1)

            # Write inputs to separate frame files
            f_in1.write(f" {to_hex(r2_1, 47)} {to_hex(r3_1, 49)} {to_hex(r4_1, 46)} {to_hex(r5_1, 49)} {to_hex(r6_1, 47)}\n")
            f_in2.write(f" {to_hex(r2_2, 47)} {to_hex(r3_2, 49)} {to_hex(r4_2, 46)} {to_hex(r5_2, 49)} {to_hex(r6_2, 47)}\n")

            # --- Golden Math (Replicating RTL exactly) ---
            dbx = (r2_1 - r2_2) >> 1
            dby = (r3_1 - r3_2) >> 1
            A11 = (r4_1 + r4_2) >> 1
            A22 = (r5_1 + r5_2) >> 1
            A12 = (r6_1 + r6_2) >> 2

            A11_sq = A11 * A11
            A22_sq = A22 * A22
            A12_sq = A12 * A12

            Asum = A11 + A22

            G11 = A11_sq + A12_sq
            G22 = A12_sq + A22_sq
            G12 = A12 * Asum

            h1 = (A11 * dbx) + (A12 * dby)
            h2 = (A12 * dbx) + (A22 * dby)

            # Write outputs
            f_out.write(f"{to_hex(G11, 97)} {to_hex(G12, 99)} {to_hex(G22, 101)} ")
            f_out.write(f"{to_hex(h1, 99)} {to_hex(h2, 101)}\n")

    print(f"Generated stimulus files (Frame 1 & Frame 2) and golden outputs  ({width}x{height} = {num_pixels} cycles).")

if __name__ == "__main__":
    # Configure for Layer 4 (80x45)
    generate_golden_model(width=80, height=45)