"""
golden_full_system_opencv.py — OpenCV Reference Model for Full System

Outputs all OpenCV intermediate results (CLAHE, Blur, Pyramid).
For the GF and Tracking output, it isolates the GF algorithm by feeding it 
the RTL-accurate CLAHE enhanced images, ensuring that "just GF is OpenCV 
and everything else mimics RTL".

Pipeline: 
  - Pure OpenCV: CLAHE(cv2) → GaussianBlur(cv2) → Pyramid(simple decimation)
  - Hybrid GF:   RTL CLAHE → Farneback(cv2) → Custom Tracking

Usage:  python golden_full_system_opencv.py
"""

import cv2
import numpy as np
import os, time
import golden_model_fast as fast_model
import golden_full_system as rtl_model

# ==========================================================================
#  Parameters
# ==========================================================================
IMG_W, IMG_H = 1280, 720

DATA_DIR   = "data"
GOLDEN_DIR = "golden_data"
os.makedirs(GOLDEN_DIR, exist_ok=True)

# ==========================================================================
#  Main
# ==========================================================================
def main():
    print("=" * 70)
    print("  OPENCV REFERENCE MODEL (Hybrid GF isolation)")
    print("=" * 70)

    # -- Load images --
    frame_paths = [os.path.join(DATA_DIR, "1.png"), os.path.join(DATA_DIR, "2.png")]
    raw_frames = []
    for idx, fpath in enumerate(frame_paths):
        img = cv2.imread(fpath, cv2.IMREAD_GRAYSCALE)
        if img is None:
            raise FileNotFoundError(f"Cannot load {fpath}")
        img = cv2.resize(img, (IMG_W, IMG_H))
        raw_frames.append(img)
        print(f"[Load] Frame {idx}: {fpath} -> {img.shape}")

    # ======================================================================
    #  PART 1: Pure OpenCV Pipeline (Outputs only)
    # ======================================================================
    print("\n" + "=" * 70)
    print("  PART 1: Pure OpenCV Pipeline")
    print("=" * 70)

    print("\n  Step 1: OpenCV CLAHE")
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(4, 4))
    cv_enhanced = []
    for idx, raw in enumerate(raw_frames):
        enh = clahe.apply(raw)
        cv_enhanced.append(enh)
        out = os.path.join(GOLDEN_DIR, f"opencv_enhanced_frame{idx}.png")
        cv2.imwrite(out, enh)
        print(f"  Frame {idx} -> {out}")

    print("\n  Step 2: OpenCV Gaussian Blur")
    cv_blurred = []
    for idx, enh in enumerate(cv_enhanced):
        blr = cv2.GaussianBlur(enh, (7, 7), 5)
        cv_blurred.append(blr)
        out = os.path.join(GOLDEN_DIR, f"opencv_blurred_frame{idx}.png")
        cv2.imwrite(out, blr)
        print(f"  Frame {idx} -> {out}")

    print("\n  Step 3: OpenCV Pyramid (simple decimation)")
    for idx, blr in enumerate(cv_blurred):
        current = blr.copy()
        for l in range(5):
            h, w = current.shape
            out = os.path.join(GOLDEN_DIR, f"opencv_pyramid_frame{idx}_L{l}.txt")
            with open(out, 'w') as f:
                for px in current.flatten():
                    f.write(f"{px}\n")
            print(f"  Frame {idx} L{l} ({w}x{h}) -> {out}")
            if l < 4:
                current = current[::2, ::2]

    # ======================================================================
    #  PART 2: Hybrid Pipeline (Just GF is OpenCV, rest is RTL)
    # ======================================================================
    print("\n" + "=" * 70)
    print("  PART 2: Hybrid Pipeline (GF=OpenCV, Rest=RTL)")
    print("=" * 70)

    print("\n  Step 4: RTL CLAHE (Input for OpenCV GF and FAST)")
    rtl_enhanced = []
    for idx, raw in enumerate(raw_frames):
        enh = rtl_model.clahe_golden(raw)
        rtl_enhanced.append(enh)
        print(f"  Generated RTL CLAHE for Frame {idx}")

    print("\n  Step 5: Custom FAST Corners (on RTL CLAHE images)")
    all_corners = []
    for idx, enh in enumerate(rtl_enhanced):
        t0 = time.time()
        corners = fast_model.detect_fast_corners(enh)
        all_corners.append(corners)
        out = os.path.join(GOLDEN_DIR, f"opencv_corners_frame{idx}.txt")
        fast_model.write_corners_txt(out, corners)
        print(f"  Frame {idx}: {len(corners)} corners ({time.time()-t0:.1f}s) -> {out}")

    print("\n  Step 6: OpenCV Farneback Optical Flow (using RTL CLAHE images)")
    t0 = time.time()
    # Using same parameters as the FAST golden model for comparison
    flow_cv = cv2.calcOpticalFlowFarneback(
        rtl_enhanced[0], rtl_enhanced[1], None,
        pyr_scale=0.5, levels=5, winsize=7,
        iterations=1, poly_n=11, poly_sigma=1.5, flags=0
    )
    dx_cv = flow_cv[:, :, 0]
    dy_cv = flow_cv[:, :, 1]
    print(f"  Computed in {time.time()-t0:.1f}s")
    print(f"  dx range: [{dx_cv.min():.2f}, {dx_cv.max():.2f}]")
    print(f"  dy range: [{dy_cv.min():.2f}, {dy_cv.max():.2f}]")

    # Save float flow
    out = os.path.join(GOLDEN_DIR, "opencv_flow_float.txt")
    with open(out, 'w') as f:
        for y in range(IMG_H):
            for x in range(IMG_W):
                f.write(f"{dy_cv[y,x]:.4f} {dx_cv[y,x]:.4f}\n")
    print(f"  Float flow -> {out}")

    # Quantize to signed 5-bit for FAST comparison
    dx_5bit = np.clip(np.round(dx_cv).astype(np.int32), -16, 15).astype(np.int8)
    dy_5bit = np.clip(np.round(dy_cv).astype(np.int32), -16, 15).astype(np.int8)

    out = os.path.join(GOLDEN_DIR, "opencv_flow_5bit.txt")
    with open(out, 'w') as f:
        for y in range(IMG_H):
            for x in range(IMG_W):
                f.write(f"{dy_5bit[y,x]} {dx_5bit[y,x]}\n")
    print(f"  5-bit quantized flow -> {out}")

    # Also save 8-bit quantized flow (to compare with RTL GF output)
    dx_8bit = np.clip(np.round(dx_cv * 8).astype(np.int32), -128, 127).astype(np.int8)
    dy_8bit = np.clip(np.round(dy_cv * 8).astype(np.int32), -128, 127).astype(np.int8)

    out = os.path.join(GOLDEN_DIR, "opencv_flow_8bit.txt")
    with open(out, 'w') as f:
        for y in range(IMG_H):
            for x in range(IMG_W):
                f.write(f"{dy_8bit[y,x]} {dx_8bit[y,x]}\n")
    print(f"  8-bit quantized flow -> {out}")

    print("\n  Step 7: Custom FAST Tracking (using OpenCV Farneback flow)")

    id_counter = 0
    
    # Frame 0: extraction only
    corners_f0 = all_corners[0]
    prev_features = []
    for (cx, cy, score) in corners_f0:
        prev_features.append((id_counter, cx, cy))
        id_counter += 1
        if len(prev_features) >= fast_model.MAX_FEATURES:
            break

    out = os.path.join(GOLDEN_DIR, "opencv_features_frame0.txt")
    with open(out, 'w') as f:
        f.write(f"{len(prev_features)}\n")
        for (fid, fx, fy) in prev_features:
            f.write(f"{fid} {fx} {fy}\n")
    print(f"  Frame 0: {len(prev_features)} features -> {out}")

    # Frame 1: tracking
    corners_f1 = all_corners[1]
    t0 = time.time()
    new_features, id_counter, n_tracked, n_harvested = fast_model.simulate_tracking(
        prev_features, corners_f1,
        dx_5bit.astype(np.int32), dy_5bit.astype(np.int32),
        id_counter
    )

    out = os.path.join(GOLDEN_DIR, "opencv_features_frame1.txt")
    with open(out, 'w') as f:
        f.write(f"{len(new_features)}\n")
        for (fid, fx, fy) in new_features:
            f.write(f"{fid} {fx} {fy}\n")
    print(f"  Frame 1: {n_tracked} tracked + {n_harvested} harvested = {len(new_features)} total ({time.time()-t0:.1f}s)")
    print(f"  -> {out}")

    # -- Summary --
    print("\n" + "=" * 70)
    print("  OPENCV REFERENCE MODEL COMPLETE")
    print("=" * 70)
    print(f"")
    print(f"  Compare RTL golden vs OpenCV:")
    print(f"    diff golden_data/golden_gf_L0_deltas.txt golden_data/opencv_flow_8bit.txt")
    print(f"    diff golden_data/features_frame1.txt golden_data/opencv_features_frame1.txt")
    print(f"")
    print(f"  Key differences to expect:")
    print(f"    - GF flow: OpenCV uses floats, simple decimation for pyramid vs RTL fixed-point + simple subsampling")
    print(f"    - Tracking logic: IDENTICAL")
    print(f"    - Base images for GF: IDENTICAL (both use RTL CLAHE outputs)")

if __name__ == '__main__':
    main()
