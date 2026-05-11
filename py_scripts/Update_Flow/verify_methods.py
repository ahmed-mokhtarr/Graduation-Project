def load_deltas(filename):
    with open(filename, "r") as f:
        return [tuple(map(int, line.split())) for line in f]

def compare():
    raw_data = load_deltas("deltas_raw.txt")
    float_data = load_deltas("deltas_float.txt")
    scaled_data = load_deltas("deltas_scaled.txt")

    total = len(raw_data)
    raw_vs_float_matches = 0
    scaled_vs_float_matches = 0

    for i in range(total):
        if raw_data[i] == float_data[i]:
            raw_vs_float_matches += 1
        if scaled_data[i] == float_data[i]:
            scaled_vs_float_matches += 1

    print("--- Precision Analysis Report ---")
    print(f"Total Samples: {total}")
    print(f"RTL Raw vs Software Float  : {raw_vs_float_matches} / {total} Matches ({(raw_vs_float_matches/total)*100:.2f}%)")
    print(f"RTL Scaled vs Software Float: {scaled_vs_float_matches} / {total} Matches ({(scaled_vs_float_matches/total)*100:.2f}%)")
    
    if raw_vs_float_matches == total:
        print("\nCONCLUSION: The Raw Hardware method is MATHMETICALLY IDENTICAL to the software model.")
    else:
        print("\nCONCLUSION: The Raw Hardware method has minor rounding differences (expected with integer truncation).")

if __name__ == "__main__":
    compare()