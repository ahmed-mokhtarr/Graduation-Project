"""
golden_model.py — Reference model for Feature Tracking & Merging RTL verification.

Uses NumPy-vectorized FAST detection for speed. Outputs hex stimulus and
expected results for the Verilog testbench.
"""

import cv2
import numpy as np
import os
import glob
import time

# =============================================================================
# Parameters (must match RTL)
# =============================================================================
IMG_WIDTH   = 1280
IMG_HEIGHT  = 720
THRESHOLD   = 55
N_CONSEC    = 9
WINDOW_HALF = 1       # 1 → 3×3 window
MAX_FEATURES = 2048
DX_BITS     = 5
DY_BITS     = 5

DATA_DIR  = "dataa"
OUT_DIR   = "sim_dataa"

# Circle offsets (matching RTL row_window_extractor)
CIRCLE_OFFSETS = [
    (-3,  0), (-3, +1), (-2, +2), (-1, +3),
    ( 0, +3), (+1, +3), (+2, +2), (+3, +1),
    (+3,  0), (+3, -1), (+2, -2), (+1, -3),
    ( 0, -3), (-1, -3), (-2, -2), (-3, -1),
]


# =============================================================================
# FAST Corner Detection — Vectorized NumPy (matching RTL exactly)
# =============================================================================
def detect_fast_corners(img):
    """Vectorized FAST detection matching RTL logic."""
    h, w = img.shape
    img = img.astype(np.int16)

    # Threshold bounds (matching RTL clamping)
    upper = np.minimum(img + THRESHOLD, 255)
    lower = np.maximum(img - THRESHOLD, 0)

    # Extract 16 circle pixels as shifted images (for valid region: rows 3..h-4, cols 3..w-4)
    r0, r1 = 3, h - 3
    c0, c1 = 3, w - 3
    center = img[r0:r1, c0:c1]
    upper_v = upper[r0:r1, c0:c1]
    lower_v = lower[r0:r1, c0:c1]

    circle = np.zeros((r1-r0, c1-c0, 16), dtype=np.int16)
    for k, (dr, dc) in enumerate(CIRCLE_OFFSETS):
        circle[:, :, k] = img[r0+dr:r1+dr, c0+dc:c1+dc]

    # Classify: bright[k] = circle[k] > upper, dark[k] = circle[k] < lower
    bright = circle > upper_v[:, :, np.newaxis]  # (H, W, 16) bool
    dark   = circle < lower_v[:, :, np.newaxis]

    # Check N_CONSEC consecutive (doubled ring for wraparound)
    bright2 = np.concatenate([bright, bright], axis=2)  # (H, W, 32)
    dark2   = np.concatenate([dark, dark], axis=2)

    # Sliding window sum of length N_CONSEC over the ring dimension
    found_bright = np.zeros((r1-r0, c1-c0), dtype=bool)
    found_dark   = np.zeros((r1-r0, c1-c0), dtype=bool)

    for i in range(16):
        run_b = bright2[:, :, i:i+N_CONSEC].sum(axis=2)
        run_d = dark2[:, :, i:i+N_CONSEC].sum(axis=2)
        found_bright |= (run_b == N_CONSEC)
        found_dark   |= (run_d == N_CONSEC)

    is_corner = found_bright | found_dark

    # Score calculation (matching fast_score_calc.v)
    bc = np.maximum(circle - upper_v[:, :, np.newaxis], 0)  # bright contributions
    dc = np.maximum(lower_v[:, :, np.newaxis] - circle, 0)  # dark contributions
    sum_bright = bc.sum(axis=2)
    sum_dark   = dc.sum(axis=2)
    score = np.maximum(sum_bright, sum_dark)
    score[~is_corner] = 0

    # Build full score map
    score_map = np.zeros((h, w), dtype=np.int32)
    score_map[r0:r1, c0:c1] = score

    # NMS 3×3: center must be strictly greater than all 8 neighbors
    nms_result = []
    for r in range(1, h - 4):
        for c in range(1, w - 1):
            val = score_map[r, c]
            if val == 0:
                continue
            window = score_map[r-1:r+2, c-1:c+2].copy()
            window[1, 1] = 0  # exclude center
            if val > window.max():
                # Subtract 1 from x coordinate to match RTL coordinate pipeline latency
                nms_result.append((c - 1, r, int(val)))

    # Cap at MAX_FEATURES
    if len(nms_result) > MAX_FEATURES:
        nms_result = nms_result[:MAX_FEATURES]

    return nms_result


# =============================================================================
# Optical Flow
# =============================================================================
def compute_flow(prev_gray, curr_gray):
    """Compute dense optical flow, quantize to signed 5-bit."""
    flow = cv2.calcOpticalFlowFarneback(
        prev_gray, curr_gray, None,
        pyr_scale=0.5, levels=3, winsize=15,
        iterations=1, poly_n=11, poly_sigma=1.5, flags=0
    )
    dx = np.clip(np.round(flow[:, :, 0]).astype(np.int32), -16, 15).astype(np.int8)
    dy = np.clip(np.round(flow[:, :, 1]).astype(np.int32), -16, 15).astype(np.int8)
    return dx, dy


# =============================================================================
# Tracking & Merging Simulation
# =============================================================================
def simulate_tracking(prev_features, corners, dx_map, dy_map, id_counter, window_half=WINDOW_HALF):
    """Simulate one frame of tracking + harvesting, matching RTL."""
    # Build current grid map
    grid_map = np.zeros((IMG_HEIGHT, IMG_WIDTH), dtype=np.uint8)
    for (cx, cy, _) in corners:
        grid_map[cy, cx] = 1

    # Sort prev_features by raster address (y, then x)
    sorted_prev = sorted(prev_features, key=lambda f: (f[2], f[1]))

    # ── Two-pointer merge ──────────────────────────────────────────
    matched = []
    ptr = 0
    n_prev = len(sorted_prev)

    for py in range(IMG_HEIGHT):
        for px in range(IMG_WIDTH):
            if ptr >= n_prev:
                break

            # Advance past any features we've passed
            while ptr < n_prev:
                _, fx, fy = sorted_prev[ptr]
                if (fy < py) or (fy == py and fx < px):
                    ptr += 1  # lost feature
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

    # ── Track validation ───────────────────────────────────────────
    tracked = []
    for (fid, px, py, dx_val, dy_val) in matched:
        x_new = px + dx_val
        y_new = py + dy_val

        if x_new < 0 or x_new >= IMG_WIDTH or y_new < 0 or y_new >= IMG_HEIGHT:
            continue

        found = False
        for dy_off in range(-window_half, window_half + 1):
            for dx_off in range(-window_half, window_half + 1):
                sx = x_new + dx_off
                sy = y_new + dy_off
                if 0 <= sx < IMG_WIDTH and 0 <= sy < IMG_HEIGHT:
                    if grid_map[sy, sx] == 1:
                        grid_map[sy, sx] = 0
                        tracked.append((fid, sx, sy))
                        found = True
                        break
            if found:
                break

        if len(tracked) >= MAX_FEATURES:
            break

    # ── Harvest ────────────────────────────────────────────────────
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
# File output
# =============================================================================
def write_pixels_hex(filepath, img):
    with open(filepath, 'w') as f:
        for r in range(IMG_HEIGHT):
            for c in range(IMG_WIDTH):
                f.write(f"{img[r, c]:02x}\n")

def write_flow_hex(filepath, dx_map, dy_map):
    with open(filepath, 'w') as f:
        for r in range(IMG_HEIGHT):
            for c in range(IMG_WIDTH):
                dx_val = int(dx_map[r, c]) & 0x1F
                dy_val = int(dy_map[r, c]) & 0x1F
                word = (dy_val << 5) | dx_val
                f.write(f"{word:03x}\n")

def write_corners_txt(filepath, corners):
    with open(filepath, 'w') as f:
        f.write(f"{len(corners)}\n")
        for (c, r, s) in corners:
            f.write(f"{c} {r} {s}\n")

def write_features_hex(filepath, features):
    with open(filepath, 'w') as f:
        f.write(f"{len(features)}\n")
        for (fid, fx, fy) in features:
            word = ((fid & 0xFFFFFFFF) << 21) | ((fx & 0x7FF) << 10) | (fy & 0x3FF)
            f.write(f"{word:016x}\n")


# =============================================================================
# Main
# =============================================================================
def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    frame_files = sorted(glob.glob(os.path.join(DATA_DIR, "*.png")))
    assert len(frame_files) >= 2, f"Need at least 2 frames, found {len(frame_files)}"
    print(f"Found {len(frame_files)} frames")

    frames = []
    for fp in frame_files:
        img = cv2.imread(fp, cv2.IMREAD_GRAYSCALE)
        if img is None:
            raise ValueError(f"Cannot read {fp}")
        img = cv2.resize(img, (IMG_WIDTH, IMG_HEIGHT), interpolation=cv2.INTER_LINEAR)
        frames.append(img)
        print(f"  Loaded {os.path.basename(fp)}: {img.shape}")

    prev_features = []
    id_counter = 0

    for i, img in enumerate(frames):
        print(f"\n{'='*60}")
        print(f"Frame {i}")
        print(f"{'='*60}")

        # Write pixels
        t0 = time.time()
        pix_path = os.path.join(OUT_DIR, f"frame_{i}_pixels.hex")
        write_pixels_hex(pix_path, img)
        print(f"  Pixels written ({time.time()-t0:.1f}s)")

        # FAST corners
        t0 = time.time()
        corners = detect_fast_corners(img)
        print(f"  FAST: {len(corners)} corners ({time.time()-t0:.1f}s)")
        write_corners_txt(os.path.join(OUT_DIR, f"frame_{i}_corners.txt"), corners)

        # Flow
        t0 = time.time()
        if i == 0:
            dx_map = np.zeros((IMG_HEIGHT, IMG_WIDTH), dtype=np.int8)
            dy_map = np.zeros((IMG_HEIGHT, IMG_WIDTH), dtype=np.int8)
        else:
            dx_map, dy_map = compute_flow(frames[i-1], img)
        flow_path = os.path.join(OUT_DIR, f"frame_{i}_flow.hex")
        write_flow_hex(flow_path, dx_map, dy_map)
        print(f"  Flow written ({time.time()-t0:.1f}s)")

        # Tracking
        t0 = time.time()
        new_features, id_counter, n_tracked, n_harvested = simulate_tracking(
            prev_features, corners, dx_map, dy_map, id_counter
        )
        print(f"  Tracking: {n_tracked} tracked + {n_harvested} new = {len(new_features)} total ({time.time()-t0:.1f}s)")

        write_features_hex(os.path.join(OUT_DIR, f"frame_{i}_features.hex"), new_features)
        prev_features = new_features

    print(f"\n{'='*60}")
    print(f"Done! Output in {OUT_DIR}/")
    print(f"Total IDs assigned: {id_counter}")


if __name__ == "__main__":
    main()
