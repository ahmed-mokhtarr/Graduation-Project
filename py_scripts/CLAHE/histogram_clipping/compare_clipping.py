import os

def compare_clipped_files(hw_file, golden_file):
    print(f"Comparing {hw_file} against {golden_file}...\n")
    
    if not os.path.exists(hw_file) or not os.path.exists(golden_file):
        print("❌ Error: One or both text files are missing! Check your file names.")
        return

    with open(hw_file, 'r') as f1, open(golden_file, 'r') as f2:
        hw_lines = f1.readlines()
        golden_lines = f2.readlines()

    if len(hw_lines) != len(golden_lines):
        print(f"❌ Error: Line counts do not match! HW: {len(hw_lines)}, Golden: {len(golden_lines)}")
        return

    mismatch_count = 0
    for i, (hw_val, gold_val) in enumerate(zip(hw_lines, golden_lines)):
        # Convert text to integer, stripping away any extra spaces or newlines
        try:
            hw_int = int(hw_val.strip())
            gold_int = int(gold_val.strip())
        except ValueError:
            print(f"❌ Error: Non-integer value found at Address {i}")
            continue
        
        if hw_int != gold_int:
            # Print only the first 15 errors to avoid flooding the terminal
            if mismatch_count < 15:
                # Calculate which tile and which bin this address belongs to
                tile_idx = i // 256
                bin_idx = i % 256
                print(f"Mismatch at Address {i} (Tile {tile_idx}, Bin {bin_idx}): Hardware = {hw_int} | Golden = {gold_int}")
            mismatch_count += 1

    print("-" * 50)
    if mismatch_count == 0:
        print("✅ SUCCESS: Hardware perfectly matches the Python Golden Reference!")
        print("Your Verilog Clipping and Redistribution module is flawless.")
    else:
        print(f"❌ FAILED: Found {mismatch_count} total mismatched bins out of 4096.")
        if mismatch_count > 15:
            print(f"... and {mismatch_count - 15} more hidden mismatches.")

# Run the comparison using your exact file names
compare_clipped_files('hardware_histogram_clipped.txt', 'golden_clipped.txt')