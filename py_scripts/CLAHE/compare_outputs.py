import os
import numpy as np

PIXELS_PER_FRAME = 921600

hw_output_file = "hardware_interp_output.txt"
golden_files = [
    "golden_output/golden_frame0_pixels.txt",
    "golden_output/golden_frame1_pixels.txt",
    "golden_output/golden_frame2_pixels.txt"
]

def read_txt(filepath):
    with open(filepath, "r") as f:
        # read lines, strip whitespace, handle 'x' and 'z' by mapping to 0 or keeping them to catch errors
        lines = f.read().split()
        data = []
        for v in lines:
            try:
                data.append(int(v))
            except ValueError:
                data.append(-1) # For x or z states
        return np.array(data, dtype=np.int32)

print(f"Reading {hw_output_file}...")
hw_data = read_txt(hw_output_file)
print(f"Total hardware pixels read: {len(hw_data)}")

# Expected length: 3 * 921600 = 2764800
expected_len = len(golden_files) * PIXELS_PER_FRAME
if len(hw_data) != expected_len:
    print(f"WARNING: Expected {expected_len} pixels, but got {len(hw_data)}!")

for i, gfile in enumerate(golden_files):
    print(f"--- Comparing Frame {i} ---")
    start_idx = i * PIXELS_PER_FRAME
    end_idx = start_idx + PIXELS_PER_FRAME
    
    if start_idx >= len(hw_data):
        print(f"Skipping frame {i}: HW data ended early.")
        continue
    
    hw_frame = hw_data[start_idx:end_idx]
    
    if len(hw_frame) < PIXELS_PER_FRAME:
        print(f"WARNING: HW frame {i} incomplete! Expected {PIXELS_PER_FRAME}, got {len(hw_frame)}")
    
    print(f"Reading {gfile}...")
    golden_frame = read_txt(gfile)
    
    if len(golden_frame) != len(hw_frame):
        print(f"Size mismatch: Golden ({len(golden_frame)}) != HW ({len(hw_frame)})")
        # Pad with zeros or truncate to compare
        min_len = min(len(golden_frame), len(hw_frame))
        golden_frame = golden_frame[:min_len]
        hw_frame = hw_frame[:min_len]
    
    diff = np.abs(golden_frame - hw_frame)
    max_diff = np.max(diff)
    mean_diff = np.mean(diff)
    
    print(f"Max Difference: {max_diff}")
    print(f"Mean Difference: {mean_diff:.4f}")
    
    exact_matches = np.sum(diff == 0)
    print(f"Exact Matches: {exact_matches}/{len(hw_frame)} ({(exact_matches/len(hw_frame))*100:.2f}%)")
    
    if max_diff == 0:
        print("RESULT: PERFECT MATCH!")
    else:
        print("RESULT: MISMATCH.")
        # Find first mismatch
        idx = np.argmax(diff > 0)
        print(f"First mismatch at index {idx}: Golden={golden_frame[idx]}, HW={hw_frame[idx]}")

