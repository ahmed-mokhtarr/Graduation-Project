def compare_files():
    golden_file = "golden_deltas.txt"
    tb_file = "tb_deltas.txt"

    try:
        with open(golden_file, "r") as fg, open(tb_file, "r") as ft:
            golden_lines = fg.readlines()
            tb_lines = ft.readlines()
    except FileNotFoundError:
        print("Error: Could not find output files.")
        return

    if len(golden_lines) != len(tb_lines):
        print(f"Warning: Line count mismatch! Golden has {len(golden_lines)}, TB has {len(tb_lines)}")

    mismatches = 0
    lines_to_check = min(len(golden_lines), len(tb_lines))

    for i in range(lines_to_check):
        g_vals = golden_lines[i].strip().split()
        t_vals = tb_lines[i].strip().split()

        match = True
        for col in range(len(g_vals)):
            g_int = int(g_vals[col], 16)
            t_int = int(t_vals[col], 16)
            
            if g_int != t_int:
                match = False
                break
        
        if not match:
            mismatches += 1
            print(f"Mismatch at Output Valid Cycle {i+1}:")
            print(f"  Expected (Golden) : {golden_lines[i].strip()}")
            print(f"  Actual   (TB)     : {tb_lines[i].strip()}")
            
            if mismatches >= 10:
                print("... Maximum mismatch display reached.")
                break

    if mismatches == 0:
        print(f"SUCCESS: All {lines_to_check} Flow Updates match the Golden Model perfectly!")
    else:
        print(f"FAILED: Found {mismatches} mismatches.")

if __name__ == "__main__":
    compare_files()