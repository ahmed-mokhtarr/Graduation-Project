import os

def compare_files(file_hw, file_golden, test_name):
    print(f"--- {test_name} ---")
    if not os.path.exists(file_hw) or not os.path.exists(file_golden):
        print(f"Error: Could not find files for comparison.\n")
        return

    with open(file_hw, 'r') as f1, open(file_golden, 'r') as f2:
        hw_lines = f1.readlines()
        golden_lines = f2.readlines()

    if len(hw_lines) != len(golden_lines):
        print(f"FAILED: Length mismatch! HW={len(hw_lines)}, Golden={len(golden_lines)}\n")
        return

    mismatches = 0
    for i, (l_hw, l_gold) in enumerate(zip(hw_lines, golden_lines)):
        val_hw = int(l_hw.strip())
        val_gold = int(l_gold.strip())
        
        if val_hw != val_gold:
            # Print only the first 5 mismatches so it doesn't flood your console
            if mismatches < 5:  
                print(f"  Mismatch at Index {i} | Hardware: {val_hw} | Python: {val_gold}")
            mismatches += 1

    if mismatches == 0:
        print("✅ SUCCESS: Files match perfectly 100%!\n")
    else:
        print(f"❌ FAILED: Found {mismatches} mismatches out of {len(hw_lines)} lines.\n")


# 1. Verify RTL logic against the Bit-Accurate Fixed-Point Math
compare_files(
    file_hw='hardware_cdf.txt', 
    file_golden='golden_cdf_hw_model.txt', 
    test_name="VERIFY RTL vs HARDWARE FIXED-POINT MATH"
)

# 2. Verify RTL logic against the Ideal Floating-Point Math
compare_files(
    file_hw='hardware_cdf.txt', 
    file_golden='golden_cdf_ideal.txt', 
    test_name="VERIFY RTL vs IDEAL FLOATING-POINT MATH"
)