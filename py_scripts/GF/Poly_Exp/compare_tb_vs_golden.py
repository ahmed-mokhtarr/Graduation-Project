"""
compare_tb_vs_golden.py
=======================
Compares the actual RTL simulation (testbench) outputs against:
  1. The Python golden model outputs           (TB vs Golden)
  2. The Python-generated RTL fixed-point model (TB vs RTL-model)
  3. Golden vs RTL-model                       (Golden vs RTL-model)

All inputs are streamed text files (one value per valid pixel, row-major order):

TB files:
  tb_vert_outputs.txt  (v_p0  v_p1  v_p2)
  tb_r_outputs.txt     (r2  r3  r4  r5  r6)

Golden files (float):
  golden_vert_stream.txt
  golden_r_stream.txt

RTL-model files (integer):
  rtl_vert_stream.txt
  rtl_r_stream.txt
"""

import numpy as np
import os

# ─────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────
W, H     = 1280, 720
Q_SHIFT  = 16          # scale factor between RTL V-stage and float
WORK_DIR = os.path.dirname(os.path.abspath(__file__))

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────
def load_stream(filename, ncols, dtype=np.float64):
    """
    Load a streamed TB/Golden/RTL output file.
    Skips the header comment line, returns a 2D numpy array of shape (N, ncols).
    """
    path = os.path.join(WORK_DIR, filename)
    if not os.path.exists(path):
        return None
    rows = []
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            rows.append([float(x) for x in line.split()])
    return np.array(rows, dtype=dtype)


def compare(name, tb_stream, ref_stream, scale=1.0, tol=0):
    """
    Compare two 1D arrays (representing streams).
    """
    n_tb  = len(tb_stream)
    n_ref = len(ref_stream)
    
    # We compare only the aligned prefix up to the length of the shorter stream
    n_cmp = min(n_tb, n_ref)
    
    tb_cmp  = tb_stream[:n_cmp] / scale
    ref_cmp = ref_stream[:n_cmp]

    abs_diff   = np.abs(tb_cmp - ref_cmp)
    max_diff   = float(abs_diff.max())  if abs_diff.size else 0.0
    mean_diff  = float(abs_diff.mean()) if abs_diff.size else 0.0
    mismatches = int(np.sum(abs_diff > tol))
    total      = abs_diff.size
    pct_match  = 100.0 * (total - mismatches) / total if total else 100.0

    print(f"\n{'='*62}")
    print(f"  {name}")
    print(f"{'='*62}")
    print(f"  Stream length : {n_cmp} compared (Target: {W*H})")
    print(f"  Scale applied : / {scale:.0f}")
    print(f"  Tolerance     : +/- {tol}")
    print(f"  Max  |diff|   : {max_diff:.6f}")
    print(f"  Mean |diff|   : {mean_diff:.6f}")
    print(f"  Mismatches    : {mismatches} / {total}  ({100-pct_match:.2f}% bad)")
    print(f"  Match rate    : {pct_match:.4f}%")

    if 0 < mismatches <= 20:
        bad_idx = np.where(abs_diff > tol)[0]
        print(f"\n  Mismatch details:")
        for idx in bad_idx[:20]:
            print(f"    [idx {idx:4d}]  A={tb_cmp[idx]:.4f}  "
                  f"B={ref_cmp[idx]:.4f}  diff={tb_cmp[idx] - ref_cmp[idx]:.4f}")
    elif mismatches > 20:
        worst10 = np.argsort(abs_diff)[::-1][:10]
        print(f"\n  Top-10 worst mismatches:")
        for idx in worst10:
            print(f"    [idx {idx:4d}]  A={tb_cmp[idx]:.4f}  "
                  f"B={ref_cmp[idx]:.4f}  diff={tb_cmp[idx] - ref_cmp[idx]:.4f}")

    return {
        "name": name,
        "coverage": n_cmp,
        "total": W*H,
        "max_diff": max_diff,
        "mean_diff": mean_diff,
        "mismatches": mismatches,
        "match_pct": pct_match,
    }


# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────
def main():
    print("=" * 62)
    print("  PolyExp Testbench vs Golden vs RTL-model Comparison")
    print("=" * 62)

    # ── Load streams ──────────────────────────────────────────
    tb_vert     = load_stream("tb_vert_outputs.txt", 3)
    golden_vert = load_stream("golden_vert_stream.txt", 3)
    rtl_vert    = load_stream("rtl_vert_stream.txt", 3)

    tb_r        = load_stream("tb_r_outputs.txt", 5)
    golden_r    = load_stream("golden_r_stream.txt", 5)
    rtl_r       = load_stream("rtl_r_stream.txt", 5)

    if tb_vert is None or golden_vert is None or rtl_vert is None:
        print("Error: Missing vertical stream files.")
        return
    if tb_r is None or golden_r is None or rtl_r is None:
        print("Error: Missing R stream files.")
        return

    results = []

    # ── Vertical tags
    v_tags = ["v_p0", "v_p1", "v_p2"]
    r_tags = ["r2", "r3", "r4", "r5", "r6"]

    # ─── Section 1: TB vs Golden ──────────────────────────────
    print("\n\n" + "#" * 62)
    print("#  SECTION 1 — TB (simulation) vs Golden (Python float)  #")
    print("#" * 62)

    for i, tag in enumerate(v_tags):
        results.append(compare(f"TB vs Golden | Vert {tag}", tb_vert[:,i], golden_vert[:,i], scale=2**Q_SHIFT, tol=0.5))
    for i, tag in enumerate(r_tags):
        results.append(compare(f"TB vs Golden | Final {tag}", tb_r[:,i], np.round(golden_r[:,i]), scale=1.0, tol=0.0))

    # ─── Section 2: TB vs RTL model ──────────────────────────
    print("\n\n" + "#" * 62)
    print("#  SECTION 2 — TB (simulation) vs RTL-model (Python int) #")
    print("#" * 62)

    for i, tag in enumerate(v_tags):
        results.append(compare(f"TB vs RTL-mdl | Vert {tag}", tb_vert[:,i], rtl_vert[:,i], scale=1.0, tol=0.0))
    for i, tag in enumerate(r_tags):
        results.append(compare(f"TB vs RTL-mdl | Final {tag}", tb_r[:,i], rtl_r[:,i], scale=1.0, tol=0.0))

    # ─── Section 3: RTL model vs Golden ───────────────────────
    print("\n\n" + "#" * 62)
    print("#  SECTION 3 — RTL-model (Python int) vs Golden (Python) #")
    print("#" * 62)

    for i, tag in enumerate(v_tags):
        results.append(compare(f"RTL-mdl vs Golden | Vert {tag}", rtl_vert[:,i], golden_vert[:,i], scale=2**Q_SHIFT, tol=0.5))
    for i, tag in enumerate(r_tags):
        results.append(compare(f"RTL-mdl vs Golden | Final {tag}", rtl_r[:,i], np.round(golden_r[:,i]), scale=1.0, tol=0.0))

    # ─── Summary ─────────────────────────────────────────────
    print("\n\n" + "=" * 90)
    print("  SUMMARY")
    print("=" * 90)
    print(f"  {'Comparison':<40}  {'Compared':>9}  {'Max|diff|':>10}  {'Mismatch%':>10}  {'Match%':>9}")
    print(f"  {'-'*40}  {'-'*9}  {'-'*10}  {'-'*10}  {'-'*9}")
    for r in results:
        mm_pct  = 100.0 - r["match_pct"]
        print(f"  {r['name']:<40}  {r['coverage']:>9d}  "
              f"{r['max_diff']:>10.4f}  {mm_pct:>9.2f}%  {r['match_pct']:>8.4f}%")

    print()

if __name__ == "__main__":
    main()
