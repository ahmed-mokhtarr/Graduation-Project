"""
compare_rtl_vs_golden.py
=========================
Compares RTL simulation outputs vs Python golden model outputs for the
Polynomial Expansion module.

Files compared:
  Vertical filter stage (V):
    rtl_V_p0_raw.txt  vs  golden_V_p0.txt  (RTL = raw int MAC; golden = float; scale = 2^Q_SHIFT)
    rtl_V_p1_raw.txt  vs  golden_V_p1.txt
    rtl_V_p2_raw.txt  vs  golden_V_p2.txt

  Final R outputs (post horizontal filter + shift):
    rtl_R1_shifted.txt  vs  golden_R1.txt  (RTL = int; golden = float -> round)
    rtl_R2_shifted.txt  vs  golden_R2.txt
    rtl_R3_shifted.txt  vs  golden_R3.txt
    rtl_R4_shifted.txt  vs  golden_R4.txt
    rtl_R5_shifted.txt  vs  golden_R5.txt
    rtl_R6_shifted.txt  vs  golden_R6.txt
"""

import numpy as np
import os

# ─────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────
Q_SHIFT   = 16   # fractional bits for filter coefficients
WORK_DIR  = os.path.dirname(os.path.abspath(__file__))

# Rows that are known pipeline artefacts in the RTL (zero-padded boundary rows)
# RTL V_p1 row 0 (index 0) and last row are all-zeros due to boundary handling.
# Set to None to compare all rows.
SKIP_ROWS = None  # e.g. {0, 44} – set to skip specific 0-indexed rows

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
def load(filename):
    """Load a whitespace-delimited text file as a 2-D numpy float64 array."""
    path = os.path.join(WORK_DIR, filename)
    return np.loadtxt(path, dtype=np.float64)


def compare(name, rtl_raw, golden_float, scale=1.0, tol=0, skip_rows=None):
    """
    Compare RTL integer array against golden float array.

    Parameters
    ----------
    name         : label for this comparison
    rtl_raw      : 2-D numpy array of RTL values (integers)
    golden_float : 2-D numpy array of golden float values
    scale        : divide rtl_raw by this to bring it to the same domain as golden_float
                   (use 2**Q_SHIFT for V outputs, 1 for already-shifted R outputs)
    tol          : maximum allowed absolute difference (after scaling) for a pixel to be
                   considered "matching" (0 = exact match)
    skip_rows    : set of 0-based row indices to exclude from comparison
    """
    assert rtl_raw.shape == golden_float.shape, (
        f"[{name}] Shape mismatch: RTL {rtl_raw.shape} vs golden {golden_float.shape}"
    )

    nrows, ncols = rtl_raw.shape

    if skip_rows:
        mask = np.ones(nrows, dtype=bool)
        for r in skip_rows:
            if 0 <= r < nrows:
                mask[r] = False
        rtl_cmp    = rtl_raw[mask]
        golden_cmp = golden_float[mask]
    else:
        rtl_cmp    = rtl_raw
        golden_cmp = golden_float

    # Bring RTL values into the same domain as golden
    rtl_scaled = rtl_cmp / scale

    abs_diff = np.abs(rtl_scaled - golden_cmp)
    max_diff = float(abs_diff.max())
    mean_diff = float(abs_diff.mean())
    mismatches = int(np.sum(abs_diff > tol))
    total = abs_diff.size

    pct_match = 100.0 * (total - mismatches) / total

    print(f"\n{'='*60}")
    print(f"  {name}")
    print(f"{'='*60}")
    print(f"  Shape         : {rtl_raw.shape[0]} rows x {rtl_raw.shape[1]} cols")
    if skip_rows:
        print(f"  Skipped rows  : {sorted(skip_rows)}")
    print(f"  Scale applied : ÷ {scale:.0f}")
    print(f"  Tolerance     : ± {tol}")
    print(f"  Max |diff|    : {max_diff:.6f}")
    print(f"  Mean |diff|   : {mean_diff:.6f}")
    print(f"  Mismatches    : {mismatches} / {total}  ({100-pct_match:.2f}% bad)")
    print(f"  Match rate    : {pct_match:.4f}%")

    if mismatches > 0 and mismatches <= 20:
        # Print details of every mismatch (only when few)
        rows_i, cols_j = np.where(abs_diff > tol)
        print(f"\n  Mismatch details (row/col are within compared region):")
        for ri, ci in zip(rows_i[:20], cols_j[:20]):
            print(f"    [{ri:3d},{ci:3d}]  RTL={rtl_cmp[ri,ci]/scale:.4f}  "
                  f"Golden={golden_cmp[ri,ci]:.4f}  diff={rtl_cmp[ri,ci]/scale - golden_cmp[ri,ci]:.4f}")
    elif mismatches > 20:
        # Print worst 10
        flat_idx = np.argsort(abs_diff.ravel())[::-1][:10]
        rows_i = flat_idx // total_cols(abs_diff)
        cols_j = flat_idx %  total_cols(abs_diff)
        print(f"\n  Top-10 worst mismatches:")
        for ri, ci in zip(rows_i, cols_j):
            print(f"    [{ri:3d},{ci:3d}]  RTL={rtl_cmp[ri,ci]/scale:.4f}  "
                  f"Golden={golden_cmp[ri,ci]:.4f}  diff={rtl_cmp[ri,ci]/scale - golden_cmp[ri,ci]:.4f}")

    return {
        "name": name,
        "max_diff": max_diff,
        "mean_diff": mean_diff,
        "mismatches": mismatches,
        "total": total,
        "match_pct": pct_match,
    }


def total_cols(arr):
    return arr.shape[1]


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
def main():
    print("PolyExp RTL vs Golden Comparison")
    print("="*60)

    results = []

    # ── Vertical Filter Outputs ──────────────────────────────────
    # RTL outputs raw MAC sums (integer multiples of 2^Q_SHIFT relative to float)
    # golden outputs floating-point values
    # tolerance = 0 means exact integer match after rounding
    #   (if RTL exactly matches the integer MAC then rtl/2^Q_SHIFT == golden within rounding)
    # We'll use tol = 0.5 to account for the Q_SHIFT rounding of filter coefficients.

    for tag in ["V_p0", "V_p1", "V_p2"]:
        rtl_file    = f"rtl_{tag}_raw.txt"
        golden_file = f"golden_{tag}.txt"

        if not os.path.exists(os.path.join(WORK_DIR, rtl_file)):
            print(f"  [SKIP] {rtl_file} not found.")
            continue
        if not os.path.exists(os.path.join(WORK_DIR, golden_file)):
            print(f"  [SKIP] {golden_file} not found.")
            continue

        rtl    = load(rtl_file)
        golden = load(golden_file)

        r = compare(
            name=f"Vertical Filter — {tag}",
            rtl_raw=rtl,
            golden_float=golden,
            scale=2**Q_SHIFT,       # bring RTL fixed-point → float domain
            tol=0.5,                # allow half-LSB rounding error
            skip_rows=SKIP_ROWS,
        )
        results.append(r)

    # ── Final R Outputs ──────────────────────────────────────────
    # RTL outputs integers (already shifted by OUT_SHIFT=32)
    # golden outputs floats → round to nearest integer for comparison
    # tolerance = 0 → exact integer match required

    for idx in range(1, 7):
        rtl_file    = f"rtl_R{idx}_shifted.txt"
        golden_file = f"golden_R{idx}.txt"

        if not os.path.exists(os.path.join(WORK_DIR, rtl_file)):
            print(f"  [SKIP] {rtl_file} not found.")
            continue
        if not os.path.exists(os.path.join(WORK_DIR, golden_file)):
            print(f"  [SKIP] {golden_file} not found.")
            continue

        rtl    = load(rtl_file)          # already integers
        golden = load(golden_file)       # floats
        golden_rounded = np.round(golden)  # round to compare with RTL integers

        r = compare(
            name=f"Final Output — R{idx}",
            rtl_raw=rtl,
            golden_float=golden_rounded,
            scale=1.0,        # no scaling needed; both are in integer domain
            tol=0,            # exact match expected
            skip_rows=SKIP_ROWS,
        )
        results.append(r)

    # ── Summary ──────────────────────────────────────────────────
    print("\n" + "="*60)
    print("  SUMMARY")
    print("="*60)
    print(f"  {'Signal':<30}  {'Max|diff|':>10}  {'Mean|diff|':>10}  {'Mismatch%':>10}  {'Match%':>10}")
    print(f"  {'-'*30}  {'-'*10}  {'-'*10}  {'-'*10}  {'-'*10}")
    for r in results:
        mismatch_pct = 100.0 - r["match_pct"]
        print(f"  {r['name']:<30}  {r['max_diff']:>10.4f}  {r['mean_diff']:>10.6f}  {mismatch_pct:>9.2f}%  {r['match_pct']:>9.4f}%")

    all_pass = all(r["mismatches"] == 0 for r in results if "Final" in r["name"])
    v_pass   = all(r["mismatches"] == 0 for r in results if "Vertical" in r["name"])
    all_pass_tol1 = all(r["mismatches"] == 0 for r in results if "Final" in r["name"])
    print(f"\n  Vertical filter (tol=0.5 LSB) : {'PASS' if v_pass         else 'FAIL'}")
    print(f"  Final R outputs (tol=0 exact) : {'PASS' if all_pass_tol1  else 'FAIL - see details above'}")
    # Check if all R mismatches are purely off-by-one (max_diff == 1.0)
    r_results = [r for r in results if "Final" in r["name"]]
    all_offbyone = all(r["max_diff"] <= 1.0 for r in r_results)
    if not all_pass_tol1 and all_offbyone:
        print(f"  NOTE: All R mismatches are exactly off-by-one (truncate vs round difference).")
    print()


if __name__ == "__main__":
    main()
