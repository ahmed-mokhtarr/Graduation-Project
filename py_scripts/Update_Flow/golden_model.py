import random

def verilog_div(num, den):
    """Mimics Verilog '/' operator (truncation towards zero)."""
    if den == 0: return 0
    res = abs(num) // abs(den)
    if (num < 0) ^ (den < 0): return -res
    return res

def get_reflected_val(arr, r, c, H, W):
    def mirror(x, max_val):
        if x < 0: return -x
        if x >= max_val: return 2 * max_val - 2 - x
        return x
    return arr[mirror(r, H)][mirror(c, W)]

def get_box_sum(arr, r, c, H, W):
    total = 0
    for dy in range(-7, 8):
        for dx in range(-7, 8):
            total += get_reflected_val(arr, r + dy, c + dx, H, W)
    return total

def generate_comparison_data(width, height):
    # Generate random input matrices
    G11_img = [[random.randint(-2**40, 2**40) for _ in range(width)] for _ in range(height)]
    G22_img = [[random.randint(-2**40, 2**40) for _ in range(width)] for _ in range(height)]
    G12_img = [[random.randint(-2**40, 2**40) for _ in range(width)] for _ in range(height)]
    h1_img  = [[random.randint(-2**40, 2**40) for _ in range(width)] for _ in range(height)]
    h2_img  = [[random.randint(-2**40, 2**40) for _ in range(width)] for _ in range(height)]

    # Open three output files for decimal results (easier to read than hex)
    with open("deltas_raw.txt", "w") as f_raw, \
         open("deltas_float.txt", "w") as f_float, \
         open("deltas_scaled.txt", "w") as f_scaled:
        
        for r in range(height):
            for c in range(width):
                # 15x15 Sums
                S_G11 = get_box_sum(G11_img, r, c, height, width)
                S_G22 = get_box_sum(G22_img, r, c, height, width)
                S_G12 = get_box_sum(G12_img, r, c, height, width)
                S_h1  = get_box_sum(h1_img, r, c, height, width)
                S_h2  = get_box_sum(h2_img, r, c, height, width)

                # --- Method 1: Hardware RAW (Optimized) ---
                numX_raw = (S_G22 * S_h1) - (S_G12 * S_h2)
                numY_raw = (S_G11 * S_h2) - (S_G12 * S_h1)
                det_raw  = (S_G11 * S_G22) - (S_G12 * S_G12)
                dx_raw = verilog_div(numX_raw, det_raw)
                dy_raw = verilog_div(numY_raw, det_raw)
                f_raw.write(f"{dx_raw} {dy_raw}\n")

                # --- Method 2: Software FLOAT (Ideal) ---
                f_G11, f_G22, f_G12 = S_G11/225.0, S_G22/225.0, S_G12/225.0
                f_h1, f_h2 = S_h1/225.0, S_h2/225.0
                det_f = (f_G11 * f_G22) - (f_G12 * f_G12)
                dx_f = int(((f_G22 * f_h1) - (f_G12 * f_h2)) / det_f) if det_f != 0 else 0
                dy_f = int(((f_G11 * f_h2) - (f_G12 * f_h1)) / det_f) if det_f != 0 else 0
                f_float.write(f"{dx_f} {dy_f}\n")

                # --- Method 3: Hardware SCALED (Sub-optimal Integer) ---
                i_G11, i_G22, i_G12 = S_G11//225, S_G22//225, S_G12//225
                i_h1, i_h2 = S_h1//225, S_h2//225
                det_i = (i_G11 * i_G22) - (i_G12 * i_G12)
                dx_i = verilog_div((i_G22 * i_h1) - (i_G12 * i_h2), det_i)
                dy_i = verilog_div((i_G11 * i_h2) - (i_G12 * i_h1), det_i)
                f_scaled.write(f"{dx_i} {dy_i}\n")

    print("Success: Generated deltas_raw.txt, deltas_float.txt, and deltas_scaled.txt")

if __name__ == "__main__":
    generate_comparison_data(80, 45)