"""
CLAHE Golden Model + Data Preparation
--------------------------------------
1. Resizes the 3 input PNGs to 1280x720
2. Converts each to hex files for RTL simulation
3. Runs a Python CLAHE golden model matching the RTL parameters:
     - 4x4 tiles (320x180 each)
     - clip_limit = 675
     - Bilinear interpolation between tiles
4. Saves enhanced outputs for comparison with RTL
"""

import numpy as np
from PIL import Image
import os, sys

# =========================================================================
#  Parameters  (must match RTL)
# =========================================================================
IMG_W, IMG_H = 1280, 720
TILE_H_NUM, TILE_V_NUM = 4, 4
TILE_W = IMG_W // TILE_H_NUM   # 320
TILE_H = IMG_H // TILE_V_NUM   # 180
NUM_BINS = 256
CLIP_LIMIT = 675
PIXELS_PER_TILE = TILE_W * TILE_H  # 57600

# Input / output paths
DATA_DIR  = "data"
SIM_DIR   = "sim_data"
OUT_DIR   = "golden_output"

FRAME_FILES = sorted([
    os.path.join(DATA_DIR, f) for f in os.listdir(DATA_DIR)
    if f.endswith(".png")
])

assert len(FRAME_FILES) == 3, f"Expected 3 PNG frames in {DATA_DIR}, found {len(FRAME_FILES)}"

os.makedirs(SIM_DIR, exist_ok=True)
os.makedirs(OUT_DIR, exist_ok=True)

# =========================================================================
#  Step 1 — Resize images to 1280x720 and save
# =========================================================================
frames = []
for idx, fpath in enumerate(FRAME_FILES):
    img = Image.open(fpath).convert("L")
    img = img.resize((IMG_W, IMG_H), Image.BILINEAR)
    # Overwrite original with resized version
    img.save(fpath)
    arr = np.array(img, dtype=np.uint8)
    frames.append(arr)
    print(f"[Prep] Frame {idx}: resized to {IMG_W}x{IMG_H}, saved to {fpath}")

# =========================================================================
#  Step 2 — Convert to hex files for simulation ($readmemh)
# =========================================================================
for idx, arr in enumerate(frames):
    hex_path = os.path.join(SIM_DIR, f"frame{idx}_hex.txt")
    flat = arr.flatten()
    with open(hex_path, "w") as f:
        for px in flat:
            f.write(f"{px:02X}\n")
    print(f"[Prep] Frame {idx}: hex file -> {hex_path}  ({len(flat)} pixels)")

# =========================================================================
#  Step 3 — CLAHE Golden Model
# =========================================================================

def build_histogram(img, tile_row, tile_col):
    """Build 256-bin histogram for one tile."""
    y0 = tile_row * TILE_H
    x0 = tile_col * TILE_W
    tile = img[y0:y0+TILE_H, x0:x0+TILE_W]
    hist = np.zeros(NUM_BINS, dtype=np.int32)
    for val in tile.flatten():
        hist[val] += 1
    return hist


def clip_and_redistribute(hist):
    """Clip histogram at CLIP_LIMIT and redistribute excess uniformly.
    Matches the RTL: one pass of clipping + one pass of redistribution
    using integer division with remainder accumulation."""
    clipped = hist.copy()

    # Pass 1: clip
    excess = 0
    for i in range(NUM_BINS):
        if clipped[i] > CLIP_LIMIT:
            excess += clipped[i] - CLIP_LIMIT
            clipped[i] = CLIP_LIMIT

    if excess == 0:
        return clipped

    # Pass 2: redistribute (matches RTL integer math)
    per_bin = excess >> 8            # excess_total[15:8]
    remainder = excess & 0xFF       # excess_total[7:0]

    acc = 255  # RTL initialises remainder_acc to 255
    for i in range(NUM_BINS):
        next_acc = (acc & 0xFF) + remainder
        extra = per_bin + (1 if next_acc >= 256 else 0)
        clipped[i] += extra
        acc = next_acc

    return clipped


def compute_cdf(clipped_hist):
    """CDF mapping: cumulative sum scaled to [0, 255].
    Matches RTL: multiply_result = acc_sum * 291, result = multiply_result >> 16."""
    CDF_SCALE = 291  # ceil(255 * 2^16 / 57600)
    cdf = np.zeros(NUM_BINS, dtype=np.uint8)
    acc = 0
    for i in range(NUM_BINS):
        acc += int(clipped_hist[i])
        val = (acc * CDF_SCALE) >> 16
        cdf[i] = min(val, 255)
    return cdf


def bilinear_interpolation(img, cdf_maps):
    """Apply CLAHE bilinear interpolation.
    Matches RTL: clamp coordinates, fixed-point weights, 4-corner lookup."""
    out = np.zeros_like(img, dtype=np.uint8)

    # Tile centres
    cx = [TILE_W // 2 + c * TILE_W for c in range(TILE_H_NUM)]  # 160, 480, 800, 1120
    cy = [TILE_H // 2 + r * TILE_H for r in range(TILE_V_NUM)]  # 90, 270, 450, 630

    for y in range(IMG_H):
        for x in range(IMG_W):
            pixel = int(img[y, x])

            # Clamp to center range (matches RTL)
            cx_clamped = max(cx[0], min(cx[-1], x))
            cy_clamped = max(cy[0], min(cy[-1], y))

            # Find surrounding tile centers
            # X zone
            if cx_clamped < cx[1]:
                left_col, right_col = 0, 1
                dx = cx_clamped - cx[0]
            elif cx_clamped < cx[2]:
                left_col, right_col = 1, 2
                dx = cx_clamped - cx[1]
            else:
                left_col, right_col = 2, 3
                dx = cx_clamped - cx[2]

            # Y zone
            if cy_clamped < cy[1]:
                top_row, bot_row = 0, 1
                dy = cy_clamped - cy[0]
            elif cy_clamped < cy[2]:
                top_row, bot_row = 1, 2
                dy = cy_clamped - cy[1]
            else:
                top_row, bot_row = 2, 3
                dy = cy_clamped - cy[2]

            # Weights (matching RTL fixed-point: 819 = 256/320*1024, 1456 = 256/180*1024)
            x_weight = (dx * 819 + 512) >> 10   # 0..256
            y_weight = (dy * 1456 + 512) >> 10   # 0..256

            # Look up CDF maps
            tl = int(cdf_maps[top_row][left_col][pixel])
            tr = int(cdf_maps[top_row][right_col][pixel])
            bl = int(cdf_maps[bot_row][left_col][pixel])
            br = int(cdf_maps[bot_row][right_col][pixel])

            # Horizontal interp
            top_val = tl * (256 - x_weight) + tr * x_weight
            bot_val = bl * (256 - x_weight) + br * x_weight

            # Vertical interp
            result = top_val * (256 - y_weight) + bot_val * y_weight

            # Shift down 16 bits (two stages of 8-bit fixed point = 16 fractional bits)
            out[y, x] = min((result >> 16) & 0xFF, 255)

    return out


def clahe_golden(img):
    """Full CLAHE pipeline for one frame."""
    # Build histograms for all 16 tiles
    hists = [[None]*TILE_H_NUM for _ in range(TILE_V_NUM)]
    for r in range(TILE_V_NUM):
        for c in range(TILE_H_NUM):
            hists[r][c] = build_histogram(img, r, c)

    # Clip & redistribute
    clipped = [[None]*TILE_H_NUM for _ in range(TILE_V_NUM)]
    for r in range(TILE_V_NUM):
        for c in range(TILE_H_NUM):
            clipped[r][c] = clip_and_redistribute(hists[r][c])

    # CDF mapping
    cdf_maps = [[None]*TILE_H_NUM for _ in range(TILE_V_NUM)]
    for r in range(TILE_V_NUM):
        for c in range(TILE_H_NUM):
            cdf_maps[r][c] = compute_cdf(clipped[r][c])

    # Bilinear interpolation
    enhanced = bilinear_interpolation(img, cdf_maps)

    return enhanced, cdf_maps


# =========================================================================
#  Step 4 — Run golden model on all 3 frames
# =========================================================================
for idx, arr in enumerate(frames):
    print(f"\n[Golden] Processing Frame {idx} ...")
    enhanced, cdf_maps = clahe_golden(arr)

    # Save enhanced image
    img_out = Image.fromarray(enhanced)
    img_out.save(os.path.join(OUT_DIR, f"golden_frame{idx}.png"))

    # Save enhanced pixels as decimal (for diff against RTL output)
    dec_path = os.path.join(OUT_DIR, f"golden_frame{idx}_pixels.txt")
    with open(dec_path, "w") as f:
        for px in enhanced.flatten():
            f.write(f"{int(px)}\n")

    # Save CDF tables (for diff against RTL CDF dump)
    cdf_path = os.path.join(OUT_DIR, f"golden_cdf_frame{idx}.txt")
    with open(cdf_path, "w") as f:
        for r in range(TILE_V_NUM):
            for c in range(TILE_H_NUM):
                for b in range(NUM_BINS):
                    f.write(f"{int(cdf_maps[r][c][b])}\n")

    print(f"  Enhanced image  -> {os.path.join(OUT_DIR, f'golden_frame{idx}.png')}")
    print(f"  Pixel reference -> {dec_path}")
    print(f"  CDF reference   -> {cdf_path}")

print(f"\n[Done] All files ready in '{SIM_DIR}/' and '{OUT_DIR}/'")
print(f"  Simulation hex files:  {SIM_DIR}/frame0_hex.txt, frame1_hex.txt, frame2_hex.txt")
print(f"  Golden outputs:        {OUT_DIR}/golden_frame0_pixels.txt, etc.")
