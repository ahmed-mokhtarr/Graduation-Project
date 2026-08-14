"""
golden_pipeline.py  —  Golden model for gf_pipeline_top

Runs all 5 layers (L4 → L0) in sequence, matching the RTL pipeline:
  1. gf_calc golden model  (reuses golden_model.py logic)
  2. Accumulation:  accum = gf_delta + (zoomed_d << 3),  saturate to [-128,+127]
  3. zoom_in on saturated accum  (reuses zoom_in.py logic)

Outputs per layer:
  golden/golden_L{N}_pipeline_accum.txt   — accumulated output (for RTL comparison)
  golden/golden_L{N-1}_pipeline_zoomed.txt — zoomed d-vector    (used by next layer)

Usage:  python golden_pipeline.py
  (runs all layers automatically)
"""
import os, sys, numpy as np

# ── helpers ──────────────────────────────────────────────────────────────────

DIMS = {0:(1280,720), 1:(640,360), 2:(320,180), 3:(160,90), 4:(80,45)}

# ── Design parameters (must match RTL defaults) ─────────────────────────────
WSIZE  = 7    # Averaging window size (was 15)
DLIMIT = 12   # D-vector saturation limit (was 15)

def truncate_div(a, b):
    if b == 0: return 0
    sign = -1 if (a < 0) ^ (b < 0) else 1
    return sign * (abs(a) // abs(b))

def sat8(v):
    """Saturate to signed 8-bit [-128, +127]."""
    return int(max(-128, min(127, v)))

# ── 1-D filters (poly expansion) ────────────────────────────────────────────

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

def read_hex(path, W, H):
    with open(path) as f: vals = f.read().split()
    img = np.zeros((H, W), dtype=object)
    for i, v in enumerate(vals):
        if i >= W*H: break
        img[i // W, i % W] = int(v, 16)
    return img

# ── GF calc golden model (same maths as golden_model.py) ────────────────────

def run_gf_golden(layer, flow_x, flow_y, wsize=WSIZE, dlimit=DLIMIT):
    W, H = DIMS[layer]
    base = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'test_cases')
    prev_img = read_hex(os.path.join(base, f"prev_L{layer}.hex"), W, H)
    curr_img = read_hex(os.path.join(base, f"curr_L{layer}.hex"), W, H)

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

    # map curr coeffs using flow field
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

    SG11 = box_horiz(box_vert(G11, ws=wsize), ws=wsize); SG22 = box_horiz(box_vert(G22, ws=wsize), ws=wsize)
    SG12 = box_horiz(box_vert(G12, ws=wsize), ws=wsize)
    Sh1  = box_horiz(box_vert(H1, ws=wsize), ws=wsize);  Sh2  = box_horiz(box_vert(H2, ws=wsize), ws=wsize)

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

def run_zoom_in(dx_in, dy_in, W, H, dlimit=12):
    """Bilinear 2x upsample, >>>3, clamp [-dlimit,+dlimit].  Returns (dx_z, dy_z)."""
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

# ── main pipeline ────────────────────────────────────────────────────────────

def main():
    base    = os.path.dirname(os.path.abspath(__file__))
    gdir    = os.path.join(base, 'golden')
    os.makedirs(gdir, exist_ok=True)

    # Previous layer's zoomed d-vectors (5-bit integer, for coef_bram_window)
    zoomed_dx = None
    zoomed_dy = None

    for layer in [4, 3, 2, 1, 0]:
        W, H = DIMS[layer]
        print(f"\n--- Layer {layer} ({W}x{H}) ---")

        # Determine flow field for gf_calc
        if layer == 4:
            flow_x = np.zeros((H, W), dtype=np.int64)
            flow_y = np.zeros((H, W), dtype=np.int64)
        else:
            flow_x = zoomed_dx.copy()     # [-15,+15]  int
            flow_y = zoomed_dy.copy()

        # Step 1: GF calc golden model
        print("  Running GF golden model ...")
        gf_dx, gf_dy = run_gf_golden(layer, flow_x, flow_y)
        # gf_dx, gf_dy are in Q3 format — same as RTL update_top output
        # RTL saturates to [-128,+127] per channel; golden_model values
        # should already be in range for the test data.  Apply saturation
        # to stay perfectly aligned with the RTL:
        gf_dx = np.vectorize(sat8)(gf_dx)
        gf_dy = np.vectorize(sat8)(gf_dy)

        # Step 2: Accumulation
        if layer == 4:
            accum_dx = gf_dx.copy()
            accum_dy = gf_dy.copy()
        else:
            # accum = gf_delta + (zoomed_d << 3), saturated to 8-bit
            accum_dx_raw = gf_dx.astype(np.int64) + (flow_x.astype(np.int64) << 3)
            accum_dy_raw = gf_dy.astype(np.int64) + (flow_y.astype(np.int64) << 3)
            accum_dx = np.vectorize(sat8)(accum_dx_raw)
            accum_dy = np.vectorize(sat8)(accum_dy_raw)
            if layer == 2:
                print(f"L2 (0,0): gf_dx={gf_dx[0,0]}, gf_dy={gf_dy[0,0]}, flow_x={flow_x[0,0]}, flow_y={flow_y[0,0]}, accum_dx={accum_dx[0,0]}, accum_dy={accum_dy[0,0]}")

        # Write accumulated output
        accum_path = os.path.join(gdir, f"golden_L{layer}_pipeline_accum.txt")
        print(f"  Writing {accum_path}")
        with open(accum_path, 'w') as f:
            for y in range(H):
                for x in range(W):
                    f.write(f"{accum_dy[y,x]} {accum_dx[y,x]}\n")

        # Step 3: zoom_in on accumulated output  (for next-lower layer)
        if layer > 0:
            print(f"  Running zoom_in  L{layer} -> L{layer-1} ...")
            zoomed_dx, zoomed_dy = run_zoom_in(
                accum_dx.astype(np.int64),
                accum_dy.astype(np.int64),
                W, H)
            zoom_path = os.path.join(gdir, f"golden_L{layer-1}_pipeline_zoomed.txt")
            print(f"  Writing {zoom_path}")
            Wz, Hz = DIMS[layer-1]
            with open(zoom_path, 'w') as f:
                for y in range(Hz):
                    for x in range(Wz):
                        f.write(f"{zoomed_dy[y,x]} {zoomed_dx[y,x]}\n")

    print("\n=== Golden pipeline model complete ===")

if __name__ == '__main__':
    main()
