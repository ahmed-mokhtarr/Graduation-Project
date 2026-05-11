import numpy as np
import scipy.ndimage as ndimage
import os

# ========================================================
# 1. Configuration & Parameters
# ========================================================
LAYER_NUM = 0
RAW_WIDTH = 1280
RAW_HEIGHT = 720

# Derive current layer dimensions
CURRENT_W = RAW_WIDTH >> LAYER_NUM
CURRENT_H = RAW_HEIGHT >> LAYER_NUM

# File Paths
HEX_INPUT_FILE = "output_L0_hex.txt"
FILTER_TXT_FILE = "farneback_1d_p.txt"

# RTL Quantization Parameters
# q_shift is the number of fractional bits (2^X) for the filter coefficients
Q_SHIFT = 16 
# out_shift is the final arithmetic right shift applied to the horizontal output (e.g., r1_raw >>> 32)
OUT_SHIFT = 32 

# ========================================================
# 2. Helper Functions (Loading Data)
# ========================================================
def load_hex_image(filepath, w, h):
    """Reads the hex dump and reshapes it into the image matrix."""
    with open(filepath, 'r') as f:
        lines = f.read().splitlines()
    
    # Convert hex strings to 8-bit unsigned integers
    pixels = [int(line.strip(), 16) for line in lines if line.strip()]
    
    # Ensure the length matches the expected dimensions
    expected_size = w * h
    if len(pixels) != expected_size:
        print(f"Warning: Expected {expected_size} pixels for {w}x{h}, but got {len(pixels)}")
        # Truncate or pad just in case (though it should match)
        pixels = pixels[:expected_size] + [0] * max(0, expected_size - len(pixels))
        
    img = np.array(pixels, dtype=np.uint8).reshape((h, w))
    return img

def load_filters(filepath):
    """Parses the text file to extract p0, p1, p2 as numpy arrays."""
    with open(filepath, 'r') as f:
        content = f.read()
    
    # Quick parser based on the headers
    def extract_array(text, header):
        start = text.find(header)
        if start == -1: return None
        # Find the line after the header
        line_start = text.find('\n', start) + 1
        line_end = text.find('\n', line_start)
        if line_end == -1: line_end = len(text)
        
        values = text[line_start:line_end].split(',')
        return np.array([float(v.strip()) for v in values])
    
    p0 = extract_array(content, "---p0---")
    p1 = extract_array(content, "---p1---")
    p2 = extract_array(content, "---p2---")
    
    return p0, p1, p2

def save_txt(filename, data, fmt):
    """Helper to save 2D arrays to a text file for easy comparison."""
    np.savetxt(filename, data, fmt=fmt, delimiter="\t")

def save_stream(filename, header, arrays, fmt):
    """
    Save multiple 2D arrays as a TB-format stream file.
    Writes one line per pixel (row-major order).
    Each line contains the corresponding pixel value from every array,
    space-separated — matching the format produced by the Verilog testbench.

    Parameters
    ----------
    filename : output file path
    header   : comment string for the first line, e.g. "# v_p0  v_p1  v_p2"
    arrays   : list of 2D numpy arrays (all same shape, H x W)
    fmt      : format string for each value, e.g. "%0d" or "%.6f"
    """
    H, W = arrays[0].shape
    # Stack into (H*W, N_channels) for easy row iteration
    flat = np.stack([a.reshape(-1) for a in arrays], axis=1)
    with open(filename, 'w') as f:
        f.write(header + '\n')
        for row in flat:
            f.write(' '.join(fmt % v for v in row) + '\n')
    print(f"  Stream file saved: {filename}  ({H*W} lines)")

# ========================================================
# 3. Golden Model (Floating Point)
# ========================================================
def golden_model_filtering(img, p0, p1, p2):
    """
    Computes exact floating-point polynomial expansion.
    Matches OpenCV BORDER_REFLECT_101 (which is SciPy's 'mirror' mode).
    """
    print("\n--- Running Golden Model (Float) ---")
    img_f = img.astype(np.float64)
    
    # 1. Vertical Filtering (Axis 0)
    # mode='mirror' creates the abc|cba reflection natively without duplicating the edge
    V_p0 = ndimage.correlate1d(img_f, p0, axis=0, mode='mirror')
    V_p1 = ndimage.correlate1d(img_f, p1, axis=0, mode='mirror')
    V_p2 = ndimage.correlate1d(img_f, p2, axis=0, mode='mirror')
    

    # Save Vertical Outputs — TB stream format (one pixel per line: v_p0  v_p1  v_p2)
    save_stream("golden_vert_stream.txt",
                "# v_p0  v_p1  v_p2",
                [V_p0, V_p1, V_p2],
                fmt="%.6f")

    # 2. Horizontal Filtering (Axis 1)
    r1 = ndimage.correlate1d(V_p0, p0, axis=1, mode='mirror')
    r2 = ndimage.correlate1d(V_p0, p1, axis=1, mode='mirror')
    r3 = ndimage.correlate1d(V_p1, p0, axis=1, mode='mirror')
    r4 = ndimage.correlate1d(V_p0, p2, axis=1, mode='mirror')
    r5 = ndimage.correlate1d(V_p2, p0, axis=1, mode='mirror')
    r6 = ndimage.correlate1d(V_p1, p1, axis=1, mode='mirror')


    # Save Final R Outputs — TB stream format (one pixel per line: r2  r3  r4  r5  r6)
    # Note: r1 is omitted to match the TB log which does not record r1.
    save_stream("golden_r_stream.txt",
                "# r2  r3  r4  r5  r6",
                [r2, r3, r4, r5, r6],
                fmt="%.6f")
    print("Golden Model files saved successfully.")

# ========================================================
# 4. RTL Model (Quantized Fixed Point)
# ========================================================
def rtl_model_filtering(img, p0, p1, p2, q_shift, out_shift):
    """
    Computes exact fixed-point polynomial expansion matching the Verilog.
    Quantizes filters, performs integer math, and shifts outputs.
    """
    print("\n--- Running RTL Model (Fixed-Point) ---")
    
    # 1. Quantize Filters (Multiply by 2^X and round to nearest int)
    scale = 2 ** q_shift
    p0_q = np.round(p0 * scale).astype(np.int64)
    p1_q = np.round(p1 * scale).astype(np.int64)
    p2_q = np.round(p2 * scale).astype(np.int64)
    
    # Zero-extend image to signed 64-bit integer to prevent overflow during MAC operations
    img_int = img.astype(np.int64)
    
    # 2. Vertical Filtering (Axis 0)
    V_p0_q = ndimage.correlate1d(img_int, p0_q, axis=0, mode='mirror')
    V_p1_q = ndimage.correlate1d(img_int, p1_q, axis=0, mode='mirror')
    V_p2_q = ndimage.correlate1d(img_int, p2_q, axis=0, mode='mirror')
    

    # Save Vertical Outputs — TB stream format (one pixel per line: v_p0  v_p1  v_p2)
    save_stream("rtl_vert_stream.txt",
                "# v_p0  v_p1  v_p2",
                [V_p0_q, V_p1_q, V_p2_q],
                fmt="%d")

    # 3. Horizontal Filtering (Axis 1) -> Generates the wide MAC results (e.g., 42-bit)
    r1_raw = ndimage.correlate1d(V_p0_q, p0_q, axis=1, mode='mirror')
    r2_raw = ndimage.correlate1d(V_p0_q, p1_q, axis=1, mode='mirror')
    r3_raw = ndimage.correlate1d(V_p1_q, p0_q, axis=1, mode='mirror')
    r4_raw = ndimage.correlate1d(V_p0_q, p2_q, axis=1, mode='mirror')
    r5_raw = ndimage.correlate1d(V_p2_q, p0_q, axis=1, mode='mirror')
    r6_raw = ndimage.correlate1d(V_p1_q, p1_q, axis=1, mode='mirror')

    # 4. Final Output Shift (Matches 'assign r1_out = r1_raw >>> 32;')
    # Python's >> operator performs an Arithmetic Right Shift on signed ints.
    r1_out = r1_raw >> out_shift
    r2_out = r2_raw >> out_shift
    r3_out = r3_raw >> out_shift
    r4_out = r4_raw >> out_shift
    r5_out = r5_raw >> out_shift
    r6_out = r6_raw >> out_shift


    # Save Final Quantized R Outputs — TB stream format (one pixel per line: r2  r3  r4  r5  r6)
    # Note: r1 is omitted to match the TB log which does not record r1.
    save_stream("rtl_r_stream.txt",
                "# r2  r3  r4  r5  r6",
                [r2_out, r3_out, r4_out, r5_out, r6_out],
                fmt="%d")
    print("RTL Model files saved successfully.")

# ========================================================
# 5. Main Execution
# ========================================================
if __name__ == "__main__":
    print(f"Initializing PolyExp Testbench (Layer {LAYER_NUM}: {CURRENT_W}x{CURRENT_H})")

    # Verify input files exist
    if not os.path.exists(HEX_INPUT_FILE) or not os.path.exists(FILTER_TXT_FILE):
        print("Error: Input files not found in the directory. Please check the paths.")
    else:
        # Load raw data
        img = load_hex_image(HEX_INPUT_FILE, CURRENT_W, CURRENT_H)
        p0, p1, p2 = load_filters(FILTER_TXT_FILE)

        # Execute Models
        golden_model_filtering(img, p0, p1, p2)
        rtl_model_filtering(img, p0, p1, p2, Q_SHIFT, OUT_SHIFT)