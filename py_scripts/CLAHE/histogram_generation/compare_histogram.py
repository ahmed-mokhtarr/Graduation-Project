import os

def compare_histograms(hw_file, golden_file):
    print(f"Comparing {hw_file} against {golden_file}...\n")
    
    if not os.path.exists(hw_file) or not os.path.exists(golden_file):
        print("Error: One or both files are missing!")
        return

    with open(hw_file, 'r') as f1, open(golden_file, 'r') as f2:
        hw_lines = f1.readlines()
        golden_lines = f2.readlines()

    if len(hw_lines) != len(golden_lines):
        print(f"Error: Line counts do not match! HW: {len(hw_lines)}, Golden: {len(golden_lines)}")
        return

    mismatch_count = 0
    for i, (hw_val, gold_val) in enumerate(zip(hw_lines, golden_lines)):
        # Convert text to integer, stripping away any extra spaces or newlines
        hw_int = int(hw_val.strip())
        gold_int = int(gold_val.strip())
        
        if hw_int != gold_int:
            # Print only the first 15 errors to avoid flooding the terminal
            if mismatch_count < 15:
                print(f"Mismatch at Address {i}: Hardware = {hw_int} | Golden = {gold_int}")
            mismatch_count += 1

    print("-" * 40)
    if mismatch_count == 0:
        print("✅ SUCCESS: Hardware perfectly matches the Python Golden Reference!")
    else:
        print(f"❌ FAILED: Found {mismatch_count} total mismatched bins out of 4096.")

# Run the comparison
compare_histograms('hardware_histogram.txt', 'golden_histogram.txt')