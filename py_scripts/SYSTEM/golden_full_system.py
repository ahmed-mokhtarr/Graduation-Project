"""
golden_full_system.py — RTL-Accurate Golden Model for Full System Integration

Pipeline: Camera -> CLAHE -> Enhanced -> FAST(corners) + Blur -> Pyramid -> GF -> FAST(tracking)

This model replicates the RTL bit-accurate behavior of the full pipeline
using the same math as the individual golden models:
  1. CLAHE golden (from clahe_golden.py)
  2. FAST corner detection (from golden_model_fast.py)
  3. Gaussian Blur golden (from golden_blur_pyramid.py)
  4. Pyramid subsampling (simple subsampling)
  5. GF optical flow (from golden_pipeline_GF.py)
  6. FAST tracking & merging (from golden_model_fast.py)

Flow for 2 frames:
  Frame 0: CLAHE -> FAST corners (save as prev list) + Blur -> Pyramid -> DDR
  Frame 1: CLAHE -> FAST corners (grid map) + Blur -> Pyramid -> DDR
           GF flow(0->1) -> saturated 5-bit flow -> FAST tracking/merging

Inputs:  data/1.png, data/2.png
Outputs: golden_data/full_system_* files for RTL comparison

Usage:  python golden_full_system.py
"""

import numpy as np
from PIL import Image
import os, sys, time
import golden_model_fast as fast_model

# ==========================================================================
#  Parameters (must match RTL)
# ==========================================================================
IMG_W, IMG_H = 1280, 720

# CLAHE parameters
TILE_H_NUM, TILE_V_NUM = 4, 4
TILE_W = IMG_W // TILE_H_NUM
TILE_H = IMG_H // TILE_V_NUM
NUM_BINS = 256
CLIP_LIMIT = 675
PIXELS_PER_TILE = TILE_W * TILE_H

# Blur kernel (7-tap Gaussian, sum=4096)
KERNEL = np.array([528, 584, 620, 632, 620, 584, 528], dtype=np.int64)

# Pyramid layers
NUM_LAYERS = 5
DIMS = {0:(1280,720), 1:(640,360), 2:(320,180), 3:(160,90), 4:(80,45)}

# GF parameters
WSIZE  = 7
DLIMIT = 12

# Directories
DATA_DIR   = "data"
SIM_DIR    = "sim_data"
GOLDEN_DIR = "golden_data"
os.makedirs(SIM_DIR, exist_ok=True)
os.makedirs(GOLDEN_DIR, exist_ok=True)

# ==========================================================================
#  1. CLAHE Golden Model
# ==========================================================================
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
    CDF_SCALE = 291
    cdf = np.zeros(NUM_BINS, dtype=np.uint8)
    acc = 0
    for i in range(NUM_BINS):
        acc += int(clipped_hist[i])
        val = (acc * CDF_SCALE) >> 16
        cdf[i] = min(val, 255)
    return cdf

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

    out = np.zeros_like(img, dtype=np.uint8)
    cx = [TILE_W // 2 + c * TILE_W for c in range(TILE_H_NUM)]
    cy = [TILE_H // 2 + r * TILE_H for r in range(TILE_V_NUM)]

    for y in range(IMG_H):
        for x in range(IMG_W):
            pixel = int(img[y, x])
            cx_clamped = max(cx[0], min(cx[-1], x))
            cy_clamped = max(cy[0], min(cy[-1], y))

            if cx_clamped < cx[1]:
                left_col, right_col = 0, 1
                dx = cx_clamped - cx[0]
            elif cx_clamped < cx[2]:
                left_col, right_col = 1, 2
                dx = cx_clamped - cx[1]
            else:
                left_col, right_col = 2, 3
                dx = cx_clamped - cx[2]

            if cy_clamped < cy[1]:
                top_row, bot_row = 0, 1
                dy = cy_clamped - cy[0]
            elif cy_clamped < cy[2]:
                top_row, bot_row = 1, 2
                dy = cy_clamped - cy[1]
            else:
                top_row, bot_row = 2, 3
                dy = cy_clamped - cy[2]

            x_weight = (dx * 819 + 512) >> 10
            y_weight = (dy * 1456 + 512) >> 10

            tl = int(cdf_maps[top_row][left_col][pixel])
            tr = int(cdf_maps[top_row][right_col][pixel])
            bl = int(cdf_maps[bot_row][left_col][pixel])
            br = int(cdf_maps[bot_row][right_col][pixel])

            top_val = tl * (256 - x_weight) + tr * x_weight
            bot_val = bl * (256 - x_weight) + br * x_weight
            result = top_val * (256 - y_weight) + bot_val * y_weight

            out[y, x] = min((result >> 16) & 0xFF, 255)

    return out

# ==========================================================================
#  2. FAST Corner Detection (from golden_model_fast.py)
# ==========================================================================
# Handled by fast_model.detect_fast_corners(img)

# ==========================================================================
#  3. FAST Tracking & Merging (from golden_model_fast.py)
# ==========================================================================
# Handled by fast_model.simulate_tracking(prev_features, corners, dx_map, dy_map, id_counter)

# ==========================================================================
#  4. Gaussian Blur Golden Model (RTL bit-accurate)
# ==========================================================================
def rtl_gaussian_blur(img):
    """Separable 7-tap Gaussian blur matching RTL bit-level behavior."""
    H, W = img.shape
    img64 = img.astype(np.int64)
    
    # Vertical pass
    v_padded = np.pad(img64, ((3, 3), (0, 0)), mode='reflect')
    v_out = np.zeros((H, W), dtype=np.int64)
    for i, k in enumerate(KERNEL):
        v_out += v_padded[i:i+H, :] * k
    
    # Horizontal pass
    h_padded = np.pad(v_out, ((0, 0), (3, 3)), mode='reflect')
    h_out = np.zeros((H, W), dtype=np.int64)
    for i, k in enumerate(KERNEL):
        h_out += h_padded[:, i:i+W] * k
    
    # Extract bits [31:24] = >>24, clamp to [0,255]
    result = (h_out >> 24) & 0xFF
    return result.astype(np.uint8)

# ==========================================================================
#  5. Pyramid Golden Model (simple subsampling to match RTL)
# ==========================================================================
def pyramid_subsample(img):
    """Build 5-level pyramid via simple subsampling (match RTL)."""
    layers = [img.copy()]
    current = img.copy()
    for _ in range(NUM_LAYERS - 1):
        H, W = current.shape
        h2, w2 = H // 2, W // 2
        decimated = np.zeros((h2, w2), dtype=np.uint8)
        for y in range(h2):
            for x in range(w2):
                decimated[y, x] = current[2*y, 2*x]
        layers.append(decimated)
        current = decimated
    return layers  # layers[0]=L0 (1280x720), layers[4]=L4 (80x45)

# ==========================================================================
#  6. GF Golden Model (RTL bit-accurate)
# ==========================================================================
def truncate_div(a, b):
    if b == 0: return 0
    sign = -1 if (a < 0) ^ (b < 0) else 1
    return sign * (abs(a) // abs(b))

def sat8(v):
    return int(max(-128, min(127, v)))

def filt_vert(img, h):
    H, W = img.shape
    out = np.zeros((H, W), dtype=object)
    for y in range(H):
        for x in range(W):
            s = 0
            for i, t in enumerate(h):
                yy = y + i - 5
                if yy < 0:    yy = -yy
                elif yy >= H: yy = 2*H - 2 - yy
                s += img[yy, x] * t
            out[y, x] = s
    return out

def filt_horiz(img, h):
    H, W = img.shape
    out = np.zeros((H, W), dtype=object)
    for y in range(H):
        for x in range(W):
            s = 0
            for i, t in enumerate(h):
                xx = x + i - 5
                if xx < 0:    xx = -xx
                elif xx >= W: xx = 2*W - 2 - xx
                s += img[y, xx] * t
            out[y, x] = s
    return out

def box_vert(img, ws=WSIZE):
    H, W = img.shape; r = ws // 2
    out = np.zeros((H, W), dtype=object)
    for y in range(H):
        for x in range(W):
            s = 0
            for dy in range(-r, r+1):
                yy = y + dy
                if yy < 0:    yy = -yy
                elif yy >= H: yy = 2*H - 2 - yy
                s += img[yy, x]
            out[y, x] = s
    return out

def box_horiz(img, ws=WSIZE):
    H, W = img.shape; r = ws // 2
    out = np.zeros((H, W), dtype=object)
    for y in range(H):
        for x in range(W):
            s = 0
            for dx in range(-r, r+1):
                xx = x + dx
                if xx < 0:    xx = -xx
                elif xx >= W: xx = 2*W - 2 - xx
                s += img[y, xx]
            out[y, x] = s
    return out

def run_gf_layer(prev_layer, curr_layer, flow_x, flow_y, wsize=WSIZE):
    """Run GF golden for one pyramid layer."""
    H, W = prev_layer.shape
    prev_img = prev_layer.astype(object)
    curr_img = curr_layer.astype(object)
    
    h0 = [-280,-1054,-1253,4314,17893,26296,17893,4314,-1253,-1054,-280]
    h1 = [-150,-888,-3155,-6389,-6222,0,6222,6389,3155,888,150]
    h2 = [155,692,1610,1272,-1753,-3950,-1753,1272,1610,692,155]
    
    def poly(img):
        V0 = filt_vert(img, h0); V1 = filt_vert(img, h1); V2 = filt_vert(img, h2)
        r2 = filt_horiz(V0, h1) >> 32
        r3 = filt_horiz(V1, h0) >> 32
        r4 = filt_horiz(V0, h2) >> 32
        r5 = filt_horiz(V2, h0) >> 32
        r6 = filt_horiz(V1, h1) >> 32
        return r2, r3, r4, r5, r6
    
    r2p,r3p,r4p,r5p,r6p = poly(prev_img)
    r2c,r3c,r4c,r5c,r6c = poly(curr_img)
    
    def fetch(coef, fx, fy):
        out = np.zeros((H, W), dtype=object)
        for y in range(H):
            for x in range(W):
                rx = max(0, min(W-1, x + int(fx[y,x])))
                ry = max(0, min(H-1, y + int(fy[y,x])))
                out[y,x] = coef[ry, rx]
        return out
    
    r2m = fetch(r2c, flow_x, flow_y)
    r3m = fetch(r3c, flow_x, flow_y)
    r4m = fetch(r4c, flow_x, flow_y)
    r5m = fetch(r5c, flow_x, flow_y)
    r6m = fetch(r6c, flow_x, flow_y)
    
    db_x = (r2p - r2m) >> 1;  db_y = (r3p - r3m) >> 1
    A11  = (r4p + r4m) >> 1;  A22  = (r5p + r5m) >> 1
    A12  = (r6p + r6m) >> 2
    
    G11 = A11*A11 + A12*A12;  G22 = A12*A12 + A22*A22
    G12 = A12*(A11+A22)
    H1  = A11*db_x + A12*db_y;  H2 = A12*db_x + A22*db_y
    
    SG11 = box_horiz(box_vert(G11, wsize), wsize); SG22 = box_horiz(box_vert(G22, wsize), wsize)
    SG12 = box_horiz(box_vert(G12, wsize), wsize)
    Sh1  = box_horiz(box_vert(H1, wsize), wsize);  Sh2  = box_horiz(box_vert(H2, wsize), wsize)
    
    numX = SG22*Sh1 - SG12*Sh2;  numY = SG11*Sh2 - SG12*Sh1
    det  = SG11*SG22 - SG12*SG12
    
    dx_out = np.zeros((H, W), dtype=np.int64)
    dy_out = np.zeros((H, W), dtype=np.int64)
    for y in range(H):
        for x in range(W):
            d = int(det[y,x]); nx = int(numX[y,x]); ny = int(numY[y,x])
            if d == 0:
                dx_out[y,x] = 0; dy_out[y,x] = 0
            else:
                dx_out[y,x] = truncate_div(nx << 3, d)
                dy_out[y,x] = truncate_div(ny << 3, d)
    return dx_out, dy_out

def run_zoom_in(dx_in, dy_in, W, H, dlimit=DLIMIT):
    """Bilinear 2x upsample, >>3, clamp [-dlimit,+dlimit]."""
    W2, H2 = 2*W, 2*H
    dx_z = np.zeros((H2, W2), dtype=np.int64)
    dy_z = np.zeros((H2, W2), dtype=np.int64)
    
    for y in range(H):
        for x in range(W):
            px_dx, px_dy = int(dx_in[y,x]), int(dy_in[y,x])
            rx_dx = px_dx if x == W-1 else int(dx_in[y, x+1])
            rx_dy = px_dy if x == W-1 else int(dy_in[y, x+1])
            bx_dx = px_dx if y == H-1 else int(dx_in[y+1, x])
            bx_dy = px_dy if y == H-1 else int(dy_in[y+1, x])
            if y == H-1 and x == W-1:
                br_dx, br_dy = px_dx, px_dy
            elif y == H-1:
                br_dx, br_dy = int(dx_in[y, x+1]), int(dy_in[y, x+1])
            elif x == W-1:
                br_dx, br_dy = int(dx_in[y+1, x]), int(dy_in[y+1, x])
            else:
                br_dx, br_dy = int(dx_in[y+1, x+1]), int(dy_in[y+1, x+1])
            
            dx_z[2*y,   2*x]   = px_dx * 2
            dy_z[2*y,   2*x]   = px_dy * 2
            dx_z[2*y,   2*x+1] = px_dx + rx_dx
            dy_z[2*y,   2*x+1] = px_dy + rx_dy
            dx_z[2*y+1, 2*x]   = px_dx + bx_dx
            dy_z[2*y+1, 2*x]   = px_dy + bx_dy
            dx_z[2*y+1, 2*x+1] = (px_dx + rx_dx + bx_dx + br_dx) >> 1
            dy_z[2*y+1, 2*x+1] = (px_dy + rx_dy + bx_dy + br_dy) >> 1
    
    dx_z = np.clip(dx_z >> 3, -dlimit, dlimit)
    dy_z = np.clip(dy_z >> 3, -dlimit, dlimit)
    return dx_z, dy_z

# ==========================================================================
#  7. GF-to-FAST Bridge: saturate 8-bit flow to 5-bit (matching RTL)
# ==========================================================================
def saturate_flow_8to5(flow_8bit):
    # Shift by 3 to convert from Q3 (fractional) to integer pixel displacements
    flow_shifted = flow_8bit >> 3
    return np.clip(flow_shifted, -16, 15).astype(np.int8)

# ==========================================================================
#  Main: Full Pipeline
# ==========================================================================
def main():
    print("=" * 70)
    print("  FULL SYSTEM GOLDEN MODEL (RTL bit-accurate)")
    print("  CLAHE -> FAST + Blur -> Pyramid -> GF -> FAST Tracking")
    print("=" * 70)
    
    # -- Step 0: Load and prep images --
    frame_paths = [os.path.join(DATA_DIR, "1.png"), os.path.join(DATA_DIR, "2.png")]
    raw_frames = []
    for idx, fpath in enumerate(frame_paths):
        img = Image.open(fpath).convert("L").resize((IMG_W, IMG_H), Image.BILINEAR)
        arr = np.array(img, dtype=np.uint8)
        raw_frames.append(arr)
        
        # Write hex for TB ($readmemh)
        hex_path = os.path.join(SIM_DIR, f"frame{idx}_raw.hex")
        with open(hex_path, 'w') as f:
            for px in arr.flatten():
                f.write(f"{px:02X}\n")
        print(f"[Step 0] Frame {idx}: {fpath} -> {hex_path}")
    
    # -- Step 1: CLAHE --
    print("\n" + "=" * 70)
    print("  Step 1: CLAHE Enhancement")
    print("=" * 70)
    enhanced_frames = []
    for idx, raw in enumerate(raw_frames):
        t0 = time.time()
        print(f"  Running CLAHE on frame {idx}...")
        enh = clahe_golden(raw)
        enhanced_frames.append(enh)
        
        out_path = os.path.join(GOLDEN_DIR, f"enhanced_frame{idx}.txt")
        with open(out_path, 'w') as f:
            for px in enh.flatten():
                f.write(f"{px}\n")
        print(f"  -> {out_path} ({time.time()-t0:.1f}s)")
    
    # -- Step 2: FAST Corner Detection (on enhanced frames) --
    print("\n" + "=" * 70)
    print("  Step 2: FAST Corner Detection")
    print("=" * 70)
    all_corners = []
    for idx, enh in enumerate(enhanced_frames):
        t0 = time.time()
        corners = fast_model.detect_fast_corners(enh)
        all_corners.append(corners)
        
        out_path = os.path.join(GOLDEN_DIR, f"corners_frame{idx}.txt")
        fast_model.write_corners_txt(out_path, corners)
        print(f"  Frame {idx}: {len(corners)} corners ({time.time()-t0:.1f}s) -> {out_path}")
    
    # -- Step 3: Gaussian Blur --
    print("\n" + "=" * 70)
    print("  Step 3: Gaussian Blur")
    print("=" * 70)
    blurred_frames = []
    for idx, enh in enumerate(enhanced_frames):
        t0 = time.time()
        print(f"  Running blur on frame {idx}...")
        blr = rtl_gaussian_blur(enh)
        blurred_frames.append(blr)
        
        out_path = os.path.join(GOLDEN_DIR, f"blurred_frame{idx}.txt")
        with open(out_path, 'w') as f:
            for px in blr.flatten():
                f.write(f"{px}\n")
        print(f"  -> {out_path} ({time.time()-t0:.1f}s)")
    
    # -- Step 4: Pyramid --
    print("\n" + "=" * 70)
    print("  Step 4: Pyramid Subsampling")
    print("=" * 70)
    pyramids = []
    for idx, blr in enumerate(blurred_frames):
        print(f"  Building pyramid for frame {idx}...")
        layers = pyramid_subsample(blr)
        pyramids.append(layers)
        
        for l, layer in enumerate(layers):
            h, w = layer.shape
            out_path = os.path.join(GOLDEN_DIR, f"pyramid_frame{idx}_L{l}.txt")
            with open(out_path, 'w') as f:
                for px in layer.flatten():
                    f.write(f"{px}\n")
            
            hex_path = os.path.join(GOLDEN_DIR, f"pyramid_frame{idx}_L{l}.hex")
            with open(hex_path, 'w') as f:
                for px in layer.flatten():
                    f.write(f"{px:02X}\n")
            print(f"  L{l} ({w}x{h}) -> {out_path}")
    
    # -- Step 5: GF Optical Flow (frame pair 0->1) --
    print("\n" + "=" * 70)
    print("  Step 5: GF Optical Flow (Frame 0 -> Frame 1)")
    print("=" * 70)
    
    prev_pyr = pyramids[0]
    curr_pyr = pyramids[1]
    
    zoomed_dx = None
    zoomed_dy = None
    
    for layer in [4, 3, 2, 1, 0]:
        W, H = DIMS[layer]
        prev_l = prev_pyr[layer]
        curr_l = curr_pyr[layer]
        
        print(f"\n  --- Layer {layer} ({W}x{H}) ---")
        
        if layer == 4:
            flow_x = np.zeros((H, W), dtype=np.int64)
            flow_y = np.zeros((H, W), dtype=np.int64)
        else:
            flow_x = zoomed_dx.copy()
            flow_y = zoomed_dy.copy()
        
        t0 = time.time()
        print(f"    Running GF golden model...")
        gf_dx, gf_dy = run_gf_layer(prev_l, curr_l, flow_x, flow_y)
        gf_dx = np.vectorize(sat8)(gf_dx)
        gf_dy = np.vectorize(sat8)(gf_dy)
        
        if layer == 4:
            accum_dx = gf_dx.copy()
            accum_dy = gf_dy.copy()
        else:
            accum_dx_raw = gf_dx.astype(np.int64) + (flow_x.astype(np.int64) << 3)
            accum_dy_raw = gf_dy.astype(np.int64) + (flow_y.astype(np.int64) << 3)
            accum_dx = np.vectorize(sat8)(accum_dx_raw)
            accum_dy = np.vectorize(sat8)(accum_dy_raw)
        
        out_path = os.path.join(GOLDEN_DIR, f"golden_gf_L{layer}_deltas.txt")
        with open(out_path, 'w') as f:
            for y in range(H):
                for x in range(W):
                    f.write(f"{accum_dy[y,x]} {accum_dx[y,x]}\n")
        print(f"    -> {out_path} ({time.time()-t0:.1f}s)")
        
        if layer > 0:
            print(f"    Running zoom_in L{layer} -> L{layer-1}...")
            zoomed_dx, zoomed_dy = run_zoom_in(
                accum_dx.astype(np.int64),
                accum_dy.astype(np.int64), W, H)
    
    gf_l0_dx = accum_dx  # signed 8-bit
    gf_l0_dy = accum_dy  # signed 8-bit
    
    # -- Step 6: GF-to-FAST Bridge (8-bit -> 5-bit saturation) --
    print("\n" + "=" * 70)
    print("  Step 6: GF-to-FAST Bridge (8->5 bit saturation)")
    print("=" * 70)
    
    fast_dx = saturate_flow_8to5(gf_l0_dx)
    fast_dy = saturate_flow_8to5(gf_l0_dy)
    
    out_path = os.path.join(GOLDEN_DIR, f"gf_to_fast_flow.txt")
    with open(out_path, 'w') as f:
        for y in range(IMG_H):
            for x in range(IMG_W):
                f.write(f"{fast_dy[y,x]} {fast_dx[y,x]}\n")
    print(f"  5-bit saturated flow -> {out_path}")
    
    # -- Step 7: FAST Tracking & Merging --
    print("\n" + "=" * 70)
    print("  Step 7: FAST Tracking & Merging")
    print("=" * 70)
    
    id_counter = 0
    
    # Frame 0: extraction only -> save corners as prev_features
    corners_f0 = all_corners[0]
    prev_features = []
    for (cx, cy, score) in corners_f0:
        prev_features.append((id_counter, cx, cy))
        id_counter += 1
        if len(prev_features) >= fast_model.MAX_FEATURES:
            break
    
    out_path = os.path.join(GOLDEN_DIR, f"features_frame0.txt")
    with open(out_path, 'w') as f:
        f.write(f"{len(prev_features)}\n")
        for (fid, fx, fy) in prev_features:
            f.write(f"{fid} {fx} {fy}\n")
            
    out_path_hex = os.path.join(GOLDEN_DIR, f"features_frame0.hex")
    fast_model.write_features_hex(out_path_hex, prev_features)
    print(f"  Frame 0: {len(prev_features)} features (extraction only) -> {out_path}")
    
    # Frame 1: tracking using GF flow, then harvest (3x3 window)
    corners_f1 = all_corners[1]
    t0 = time.time()
    new_features, id_counter_3x3, n_tracked, n_harvested = fast_model.simulate_tracking(
        prev_features, corners_f1,
        fast_dx.astype(np.int32), fast_dy.astype(np.int32),
        id_counter
    )
    
    out_path = os.path.join(GOLDEN_DIR, f"features_frame1.txt")
    with open(out_path, 'w') as f:
        f.write(f"{len(new_features)}\n")
        for (fid, fx, fy) in new_features:
            f.write(f"{fid} {fx} {fy}\n")
            
    out_path_hex = os.path.join(GOLDEN_DIR, f"features_frame1.hex")
    fast_model.write_features_hex(out_path_hex, new_features)
    print(f"  Frame 1 (3x3 window): {n_tracked} tracked + {n_harvested} harvested = {len(new_features)} total ({time.time()-t0:.1f}s)")
    print(f"  -> {out_path}")
    
    # Frame 1: tracking using GF flow, then harvest (5x5 window)
    t0 = time.time()
    new_features_5x5, id_counter_5x5, n_tracked_5x5, n_harvested_5x5 = fast_model.simulate_tracking(
        prev_features, corners_f1,
        fast_dx.astype(np.int32), fast_dy.astype(np.int32),
        id_counter, window_half=2
    )
    
    out_path_5x5 = os.path.join(GOLDEN_DIR, f"features_frame1_5x5.txt")
    with open(out_path_5x5, 'w') as f:
        f.write(f"{len(new_features_5x5)}\n")
        for (fid, fx, fy) in new_features_5x5:
            f.write(f"{fid} {fx} {fy}\n")
            
    out_path_hex_5x5 = os.path.join(GOLDEN_DIR, f"features_frame1_5x5.hex")
    fast_model.write_features_hex(out_path_hex_5x5, new_features_5x5)
    print(f"  Frame 1 (5x5 window): {n_tracked_5x5} tracked + {n_harvested_5x5} harvested = {len(new_features_5x5)} total ({time.time()-t0:.1f}s)")
    print(f"  -> {out_path_5x5}")
    
    # -- Summary --
    print("\n" + "=" * 70)
    print("  GOLDEN MODEL COMPLETE")
    print("=" * 70)
    print(f"  Simulation hex:   {SIM_DIR}/frame{{0,1}}_raw.hex")
    print(f"  Golden reference: {GOLDEN_DIR}/")
    print(f"")
    print(f"  Key output files:")
    print(f"    enhanced_frame{{0,1}}.txt        — CLAHE output")
    print(f"    corners_frame{{0,1}}.txt         — FAST corners per frame")
    print(f"    blurred_frame{{0,1}}.txt         — Blur output")
    print(f"    pyramid_frame{{0,1}}_L{{0..4}}.txt — Pyramid layers")
    print(f"    golden_gf_L{{0..4}}_deltas.txt   — GF flow per layer")
    print(f"    gf_to_fast_flow.txt             — 5-bit saturated flow for FAST")
    print(f"    features_frame0.txt             — Frame 0 features (extraction)")
    print(f"    features_frame1.txt             — Frame 1 features (tracked + harvested)")
    print(f"    features_frame{{0,1}}.hex        — Features in hex format")
    print(f"")
    print(f"  Total IDs assigned: {id_counter}")
    print(f"  Frame 0 corners: {len(all_corners[0])}")
    print(f"  Frame 1 corners: {len(all_corners[1])}")

if __name__ == '__main__':
    main()
