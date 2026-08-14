"""
golden_model_unified.py — Combined CLAHE + FAST + Tracking golden model.

Pipeline:
  1. Load 4 raw PNG frames from data/
  2. Run CLAHE golden model on each → enhanced images
  3. Run FAST corner detection on each enhanced image → corners
  4. Compute optical flow between consecutive enhanced images
  5. Simulate tracking + merging for each FAST frame

Output (sim_data/):       Input data for RTL testbench
Output (golden_data/):    Golden references for RTL verification
"""

import cv2
import numpy as np
from PIL import Image
import os, sys, glob, time

# =============================================================================
# Parameters (must match RTL)
# =============================================================================
IMG_W, IMG_H    = 1280, 720
TILE_H_NUM      = 4
TILE_V_NUM      = 4
TILE_W          = IMG_W // TILE_H_NUM   # 320
TILE_H          = IMG_H // TILE_V_NUM   # 180
NUM_BINS        = 256
CLIP_LIMIT      = 675
PIXELS_PER_TILE = TILE_W * TILE_H       # 57600
CDF_SCALE       = 291                   # ceil(255 * 2^16 / 57600)

THRESHOLD       = 35
N_CONSEC        = 9
WINDOW_HALF     = 1
MAX_FEATURES    = 2048
DX_BITS         = 5
DY_BITS         = 5

DATA_DIR    = "data"
SIM_DIR     = "sim_data"
GOLDEN_DIR  = "golden_data"

# Circle offsets (matching RTL row_window_extractor)
CIRCLE_OFFSETS = [
    (-3,  0), (-3, +1), (-2, +2), (-1, +3),
    ( 0, +3), (+1, +3), (+2, +2), (+3, +1),
    (+3,  0), (+3, -1), (+2, -2), (+1, -3),
    ( 0, -3), (-1, -3), (-2, -2), (-3, -1),
]


# =============================================================================
# CLAHE Golden Model (matches RTL exactly)
# =============================================================================
def build_histogram(img, tile_row, tile_col):
    y0 = tile_row * TILE_H
    x0 = tile_col * TILE_W
    tile = img[y0:y0+TILE_H, x0:x0+TILE_W]
    hist = np.zeros(NUM_BINS, dtype=np.int32)
    for val in tile.flatten():
        hist[val] += 1
    return hist


def clip_and_redistribute(hist):
    clipped = hist.copy()
    excess = 0
    for i in range(NUM_BINS):
        if clipped[i] > CLIP_LIMIT:
            excess += clipped[i] - CLIP_LIMIT
            clipped[i] = CLIP_LIMIT
    if excess == 0:
        return clipped
    per_bin = excess >> 8
    remainder = excess & 0xFF
    acc = 255
    for i in range(NUM_BINS):
        next_acc = (acc & 0xFF) + remainder
        extra = per_bin + (1 if next_acc >= 256 else 0)
        clipped[i] += extra
        acc = next_acc
    return clipped


def compute_cdf(clipped_hist):
    cdf = np.zeros(NUM_BINS, dtype=np.uint8)
    acc = 0
    for i in range(NUM_BINS):
        acc += int(clipped_hist[i])
        val = (acc * CDF_SCALE) >> 16
        cdf[i] = min(val, 255)
    return cdf


def bilinear_interpolation(img, cdf_maps):
    out = np.zeros_like(img, dtype=np.uint8)
    cx = [TILE_W // 2 + c * TILE_W for c in range(TILE_H_NUM)]  # 160, 480, 800, 1120
    cy = [TILE_H // 2 + r * TILE_H for r in range(TILE_V_NUM)]  # 90, 270, 450, 630

    for y in range(IMG_H):
        for x in range(IMG_W):
            pixel = int(img[y, x])
            cx_c = max(cx[0], min(cx[-1], x))
            cy_c = max(cy[0], min(cy[-1], y))

            if cx_c < cx[1]:
                lc, rc, dx = 0, 1, cx_c - cx[0]
            elif cx_c < cx[2]:
                lc, rc, dx = 1, 2, cx_c - cx[1]
            else:
                lc, rc, dx = 2, 3, cx_c - cx[2]

            if cy_c < cy[1]:
                tr, br, dy = 0, 1, cy_c - cy[0]
            elif cy_c < cy[2]:
                tr, br, dy = 1, 2, cy_c - cy[1]
            else:
                tr, br, dy = 2, 3, cy_c - cy[2]

            x_weight = (dx * 819 + 512) >> 10
            y_weight = (dy * 1456 + 512) >> 10

            tl = int(cdf_maps[tr][lc][pixel])
            tr_v = int(cdf_maps[tr][rc][pixel])
            bl = int(cdf_maps[br][lc][pixel])
            br_v = int(cdf_maps[br][rc][pixel])

            top_val = tl * (256 - x_weight) + tr_v * x_weight
            bot_val = bl * (256 - x_weight) + br_v * x_weight
            result = top_val * (256 - y_weight) + bot_val * y_weight
            out[y, x] = min((result >> 16) & 0xFF, 255)

    return out


def clahe_golden(img):
    hists = [[None]*TILE_H_NUM for _ in range(TILE_V_NUM)]
    for r in range(TILE_V_NUM):
        for c in range(TILE_H_NUM):
            hists[r][c] = build_histogram(img, r, c)

    clipped = [[None]*TILE_H_NUM for _ in range(TILE_V_NUM)]
    for r in range(TILE_V_NUM):
        for c in range(TILE_H_NUM):
            clipped[r][c] = clip_and_redistribute(hists[r][c])

    cdf_maps = [[None]*TILE_H_NUM for _ in range(TILE_V_NUM)]
    for r in range(TILE_V_NUM):
        for c in range(TILE_H_NUM):
            cdf_maps[r][c] = compute_cdf(clipped[r][c])

    enhanced = bilinear_interpolation(img, cdf_maps)
    return enhanced, cdf_maps


# =============================================================================
# FAST Corner Detection — Vectorized (matches RTL exactly)
# =============================================================================
def detect_fast_corners(img):
    h, w = img.shape
    img16 = img.astype(np.int16)

    upper = np.minimum(img16 + THRESHOLD, 255)
    lower = np.maximum(img16 - THRESHOLD, 0)

    r0, r1 = 3, h - 3
    c0, c1 = 3, w - 3

    upper_v = upper[r0:r1, c0:c1]
    lower_v = lower[r0:r1, c0:c1]

    circle = np.zeros((r1-r0, c1-c0, 16), dtype=np.int16)
    for k, (dr, dc) in enumerate(CIRCLE_OFFSETS):
        circle[:, :, k] = img16[r0+dr:r1+dr, c0+dc:c1+dc]

    bright = circle > upper_v[:, :, np.newaxis]
    dark   = circle < lower_v[:, :, np.newaxis]

    bright2 = np.concatenate([bright, bright], axis=2)
    dark2   = np.concatenate([dark, dark], axis=2)

    found_bright = np.zeros((r1-r0, c1-c0), dtype=bool)
    found_dark   = np.zeros((r1-r0, c1-c0), dtype=bool)
    for i in range(16):
        run_b = bright2[:, :, i:i+N_CONSEC].sum(axis=2)
        run_d = dark2[:, :, i:i+N_CONSEC].sum(axis=2)
        found_bright |= (run_b == N_CONSEC)
        found_dark   |= (run_d == N_CONSEC)

    is_corner = found_bright | found_dark

    bc = np.maximum(circle - upper_v[:, :, np.newaxis], 0)
    dc = np.maximum(lower_v[:, :, np.newaxis] - circle, 0)
    sum_bright = bc.sum(axis=2)
    sum_dark   = dc.sum(axis=2)
    score = np.maximum(sum_bright, sum_dark)
    score[~is_corner] = 0

    score_map = np.zeros((h, w), dtype=np.int32)
    score_map[r0:r1, c0:c1] = score

    # NMS 3x3 (matches RTL nms_3x3.v coordinate offsets)
    nms_result = []
    for r in range(1, h - 4):
        for c in range(1, w - 1):
            val = score_map[r, c]
            if val == 0:
                continue
            window = score_map[r-1:r+2, c-1:c+2].copy()
            window[1, 1] = 0
            if val > window.max():
                nms_result.append((c - 1, r, int(val)))

    if len(nms_result) > MAX_FEATURES:
        nms_result = nms_result[:MAX_FEATURES]

    return nms_result


# =============================================================================
# Optical Flow
# =============================================================================
def compute_flow(prev_gray, curr_gray):
    flow = cv2.calcOpticalFlowFarneback(
        prev_gray, curr_gray, None,
        pyr_scale=0.5, levels=3, winsize=15,
        iterations=3, poly_n=5, poly_sigma=1.2, flags=0
    )
    dx = np.clip(np.round(flow[:, :, 0]).astype(np.int32), -16, 15).astype(np.int8)
    dy = np.clip(np.round(flow[:, :, 1]).astype(np.int32), -16, 15).astype(np.int8)
    return dx, dy


# =============================================================================
# Tracking & Merging Simulation (matches RTL exactly)
# =============================================================================
def simulate_tracking(prev_features, corners, dx_map, dy_map, id_counter):
    grid_map = np.zeros((IMG_H, IMG_W), dtype=np.uint8)
    for (cx, cy, _) in corners:
        grid_map[cy, cx] = 1

    sorted_prev = sorted(prev_features, key=lambda f: (f[2], f[1]))

    # Two-pointer merge
    matched = []
    ptr = 0
    n_prev = len(sorted_prev)

    for py in range(IMG_H):
        for px in range(IMG_W):
            if ptr >= n_prev:
                break
            while ptr < n_prev:
                _, fx, fy = sorted_prev[ptr]
                if (fy < py) or (fy == py and fx < px):
                    ptr += 1
                else:
                    break
            if ptr >= n_prev:
                break
            _, fx, fy = sorted_prev[ptr]
            if py == fy and px == fx:
                fid = sorted_prev[ptr][0]
                dx_val = int(dx_map[py, px])
                dy_val = int(dy_map[py, px])
                matched.append((fid, px, py, dx_val, dy_val))
                ptr += 1
        if ptr >= n_prev:
            break

    # Track validation
    tracked = []
    for (fid, px, py, dx_val, dy_val) in matched:
        x_new = px + dx_val
        y_new = py + dy_val
        if x_new < 0 or x_new >= IMG_W or y_new < 0 or y_new >= IMG_H:
            continue
        found = False
        for dy_off in range(-WINDOW_HALF, WINDOW_HALF + 1):
            for dx_off in range(-WINDOW_HALF, WINDOW_HALF + 1):
                sx = x_new + dx_off
                sy = y_new + dy_off
                if 0 <= sx < IMG_W and 0 <= sy < IMG_H:
                    if grid_map[sy, sx] == 1:
                        grid_map[sy, sx] = 0
                        tracked.append((fid, sx, sy))
                        found = True
                        break
            if found:
                break
        if len(tracked) >= MAX_FEATURES:
            break

    # Harvest
    harvested = []
    for (cx, cy, _) in corners:
        if grid_map[cy, cx] == 1:
            grid_map[cy, cx] = 0
            harvested.append((id_counter, cx, cy))
            id_counter += 1
            if len(tracked) + len(harvested) >= MAX_FEATURES:
                break

    new_features = tracked + harvested
    return new_features, id_counter, len(tracked), len(harvested)


# =============================================================================
# File I/O Helpers
# =============================================================================
def write_raw_hex(filepath, img):
    """Write raw pixels as 2-digit hex, one per line."""
    with open(filepath, 'w') as f:
        for px in img.flatten():
            f.write(f"{int(px):02X}\n")

def write_flow_hex(filepath, dx_map, dy_map):
    """Write flow as 3-digit hex {dy[4:0], dx[4:0]}, one per pixel."""
    with open(filepath, 'w') as f:
        for r in range(IMG_H):
            for c in range(IMG_W):
                dx_val = int(dx_map[r, c]) & 0x1F
                dy_val = int(dy_map[r, c]) & 0x1F
                word = (dy_val << 5) | dx_val
                f.write(f"{word:03x}\n")

def write_corners_txt(filepath, corners):
    """Write corners: first line = count, then col row score per line."""
    with open(filepath, 'w') as f:
        f.write(f"{len(corners)}\n")
        for (c, r, s) in corners:
            f.write(f"{c} {r} {s}\n")

def write_features_hex(filepath, features):
    """Write features as 16-digit hex words: {11'b0, id[31:0], x[10:0], y[9:0]}."""
    with open(filepath, 'w') as f:
        f.write(f"{len(features)}\n")
        for (fid, fx, fy) in features:
            word = ((fid & 0xFFFFFFFF) << 21) | ((fx & 0x7FF) << 10) | (fy & 0x3FF)
            f.write(f"{word:016x}\n")

def write_enhanced_pixels(filepath, img):
    """Write enhanced pixels as decimal, one per line (for RTL comparison)."""
    with open(filepath, 'w') as f:
        for px in img.flatten():
            f.write(f"{int(px)}\n")


# =============================================================================
# Main
# =============================================================================
def main():
    os.makedirs(SIM_DIR, exist_ok=True)
    os.makedirs(GOLDEN_DIR, exist_ok=True)

    frame_files = sorted(glob.glob(os.path.join(DATA_DIR, "*.png")))
    assert len(frame_files) >= 4, f"Need at least 4 frames in {DATA_DIR}/, found {len(frame_files)}"
    frame_files = frame_files[:4]  # use first 4
    print(f"Using {len(frame_files)} frames from {DATA_DIR}/")

    # ─── Step 1: Load and resize raw frames ───────────────────────────
    raw_frames = []
    for idx, fp in enumerate(frame_files):
        img = Image.open(fp).convert("L")
        img = img.resize((IMG_W, IMG_H), Image.BILINEAR)
        arr = np.array(img, dtype=np.uint8)
        raw_frames.append(arr)
        print(f"  Frame {idx}: {os.path.basename(fp)} -> {IMG_W}x{IMG_H}")

    # ─── Step 2: Generate raw pixel hex files (CLAHE input) ───────────
    for idx, arr in enumerate(raw_frames):
        hex_path = os.path.join(SIM_DIR, f"frame{idx}_raw.hex")
        write_raw_hex(hex_path, arr)
        print(f"  [SIM] {hex_path}")

    # ─── Step 3: Run CLAHE on all frames ──────────────────────────────
    enhanced_frames = []
    all_cdf_maps = []
    for idx, arr in enumerate(raw_frames):
        t0 = time.time()
        enhanced, cdf_maps = clahe_golden(arr)
        enhanced_frames.append(enhanced)
        all_cdf_maps.append(cdf_maps)
        dt = time.time() - t0
        print(f"  [CLAHE] Frame {idx}: {dt:.1f}s")

        # Save enhanced image
        Image.fromarray(enhanced).save(os.path.join(GOLDEN_DIR, f"enhanced_frame{idx}.png"))

        # Save enhanced pixels (decimal, for reference)
        write_enhanced_pixels(
            os.path.join(GOLDEN_DIR, f"enhanced_frame{idx}_pixels.txt"), enhanced
        )

        # Save enhanced pixels (hex, for $readmemh in TB)
        write_raw_hex(
            os.path.join(GOLDEN_DIR, f"enhanced_frame{idx}_pixels.hex"), enhanced
        )

        # Save CDF tables
        cdf_path = os.path.join(GOLDEN_DIR, f"cdf_frame{idx}.txt")
        with open(cdf_path, "w") as f:
            for r in range(TILE_V_NUM):
                for c in range(TILE_H_NUM):
                    for b in range(NUM_BINS):
                        f.write(f"{int(cdf_maps[r][c][b])}\n")

    # ─── Step 4: FAST detection on enhanced frames ────────────────────
    # FAST frame i processes enhanced frame i (during CLAHE frame i+1)
    all_corners = []
    for idx, enh in enumerate(enhanced_frames[:3]):
        t0 = time.time()
        corners = detect_fast_corners(enh)
        all_corners.append(corners)
        dt = time.time() - t0
        print(f"  [FAST] Enhanced frame {idx}: {len(corners)} corners ({dt:.1f}s)")

        write_corners_txt(
            os.path.join(GOLDEN_DIR, f"corners_frame{idx}.txt"), corners
        )

    # ─── Step 5: Compute optical flow between enhanced frames ─────────
    # Flow for FAST frame 0: zero (no prev)
    # Flow for FAST frame i: flow(enhanced i-1 → enhanced i)
    flow_data = []
    for idx in range(3):
        t0 = time.time()
        if idx == 0:
            dx_map = np.zeros((IMG_H, IMG_W), dtype=np.int8)
            dy_map = np.zeros((IMG_H, IMG_W), dtype=np.int8)
        else:
            dx_map, dy_map = compute_flow(enhanced_frames[idx-1], enhanced_frames[idx])
        flow_data.append((dx_map, dy_map))
        dt = time.time() - t0

        flow_path = os.path.join(SIM_DIR, f"frame{idx}_flow.hex")
        write_flow_hex(flow_path, dx_map, dy_map)
        print(f"  [FLOW] FAST frame {idx}: {dt:.1f}s -> {flow_path}")

    # ─── Step 6: Simulate tracking ────────────────────────────────────
    prev_features = []
    id_counter = 0

    for idx in range(3):
        t0 = time.time()
        corners = all_corners[idx]
        dx_map, dy_map = flow_data[idx]

        new_features, id_counter, n_tracked, n_harvested = simulate_tracking(
            prev_features, corners, dx_map, dy_map, id_counter
        )
        dt = time.time() - t0

        print(f"  [TRACK] FAST frame {idx}: {n_tracked} tracked + {n_harvested} harvested"
              f" = {len(new_features)} total ({dt:.1f}s)")

        write_features_hex(
            os.path.join(GOLDEN_DIR, f"features_frame{idx}.hex"), new_features
        )
        prev_features = new_features

    # ─── Summary ──────────────────────────────────────────────────────
    print(f"\n{'='*60}")
    print(f"Done! Total IDs assigned: {id_counter}")
    print(f"\nSimulation inputs:   {SIM_DIR}/")
    print(f"  frame{{0-3}}_raw.hex    — raw pixels for CLAHE")
    print(f"  frame{{0-2}}_flow.hex   — GF optical flow for FAST")
    print(f"\nGolden references:   {GOLDEN_DIR}/")
    print(f"  enhanced_frame{{0-2}}_pixels.txt  — CLAHE output")
    print(f"  corners_frame{{0-2}}.txt          — FAST corners")
    print(f"  features_frame{{0-2}}.hex         — tracked features")
    print(f"  cdf_frame{{0-3}}.txt              — CDF tables")


if __name__ == "__main__":
    main()
