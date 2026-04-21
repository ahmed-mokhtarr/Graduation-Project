import numpy as np
import cv2
import os

def load_text_image(filename, width=1280, height=720):
    """Helper function to safely load a text file into a 2D image array."""
    if not os.path.exists(filename):
        print(f"ERROR: Could not find '{filename}'.")
        return None
    
    try:
        # Load the flat text file
        flat_data = np.loadtxt(filename, dtype=np.int32)
        
        # Check if the number of pixels matches 720p
        expected_pixels = width * height
        if flat_data.size != expected_pixels:
            print(f"ERROR: '{filename}' has {flat_data.size} pixels, expected {expected_pixels}.")
            return None
            
        # Reshape and convert to 8-bit image
        img = flat_data.reshape((height, width)).astype(np.uint8)
        return img
    except Exception as e:
        print(f"Error reading '{filename}': {e}")
        return None

def analyze_difference(name1, name2, img1, img2):
    """Calculates and prints the exact error between two images."""
    print(f"\n==========================================")
    print(f" COMPARING: {name1} vs {name2} ")
    print(f"==========================================")
    
    # Use int32 to prevent underflow/overflow during subtraction
    diff = np.abs(img1.astype(np.int32) - img2.astype(np.int32))
    
    total_pixels = img1.size
    exact_matches = np.count_nonzero(diff == 0)
    off_by_one = np.count_nonzero(diff == 1)
    off_by_two_or_more = np.count_nonzero(diff >= 2)
    max_err = np.max(diff)
    
    print(f"Total Pixels Evaluated:  {total_pixels:,}")
    print(f"Exact Matches (0 Error): {exact_matches:,} ({(exact_matches/total_pixels)*100:.2f}%)")
    print(f"Off by exactly 1 level:  {off_by_one:,} ({(off_by_one/total_pixels)*100:.2f}%)")
    print(f"Off by 2 or more levels: {off_by_two_or_more:,} ({(off_by_two_or_more/total_pixels)*100:.2f}%)")
    print(f"Maximum Error found:     {max_err} grayscale levels")
    
    if max_err == 0:
        print("\n>>> SUCCESS: FILES ARE A PERFECT BIT-FOR-BIT MATCH! <<<")
    else:
        print("\n>>> NOTE: Differences detected between files. <<<")
    print("==========================================\n")

if __name__ == "__main__":
    # --- 1. Define File Names ---
    verilog_file      = 'python_hw_output.txt'
    python_hw_file    = 'python_hw_output.txt'
    python_ideal_file = 'python_ideal_output.txt'
    python_opencv_file = 'python_opencv_output.txt'  # <-- Added OpenCV File

    print("Loading image data from text files...")

    # --- 2. Load the Data ---
    verilog_img   = load_text_image(verilog_file)
    py_hw_img     = load_text_image(python_hw_file)
    py_ideal_img  = load_text_image(python_ideal_file)
    py_opencv_img = load_text_image(python_opencv_file)  # <-- Load OpenCV data

    # --- 3. Save the Verilog Output as a Real Image ---
    if verilog_img is not None:
        cv2.imwrite('FINAL_VERILOG_OUTPUT.png', verilog_img)
        print("-> Saved Verilog output as 'FINAL_VERILOG_OUTPUT.png'")

    # --- 4. Run Comparisons ---
    if verilog_img is not None and py_hw_img is not None:
        # Test 1: Did your Verilog accurately recreate the +512 integer math?
        analyze_difference("Verilog HW", "Python Fixed-Point HW", verilog_img, py_hw_img)
        
    if verilog_img is not None and py_ideal_img is not None:
        # Test 2: How much error did the FPGA math introduce compared to pure float math?
        analyze_difference("Verilog HW", "Ideal Custom Float", verilog_img, py_ideal_img)

    if verilog_img is not None and py_opencv_img is not None:
        # Test 3: How does the FPGA compare to OpenCV's built-in CLAHE?
        analyze_difference("Verilog HW", "OpenCV Built-in CLAHE", verilog_img, py_opencv_img)