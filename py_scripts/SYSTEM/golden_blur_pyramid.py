"""
Golden Model: Blur + Pyramid (3-way comparison)
================================================
Generates golden data for the CLAHE -> Blur -> Pyramid pipeline.

Three outputs per enhanced frame:
  1. Golden RTL Blur:    Bit-accurate Python model matching RTL kernel math
  2. Golden RTL Pyramid: Subsampled pyramid layers from the RTL blur output
  3. OpenCV Blur/Pyramid: cv2.GaussianBlur + simple decimation for reference

Usage:
  python golden_blur_pyramid.py

Inputs:
  golden_data/enhanced_frame*_pixels.txt  (from clahe_golden.py)

Outputs:
  golden_data/golden_rtl_blur_frame*.txt/.hex/.png
  golden_data/golden_rtl_pyramid_frame*.txt/.hex
  golden_data/opencv_blur_frame*.txt/.png
  golden_data/opencv_pyramid_frame*.txt
"""

import numpy as np
import cv2
import os
from PIL import Image

# ==========================================================================
#  Parameters (must match RTL)
# ==========================================================================
IMG_W, IMG_H = 1280, 720

# 7-tap separable Gaussian kernel coefficients (same as RTL)
# Kernel positions: [-3, -2, -1, 0, +1, +2, +3]
# C0=528 (outermost), C1=584, C2=620, C3=632 (center)
# Full kernel: [528, 584, 620, 632, 620, 584, 528]  (sums to 4096 = 2^12)
KERNEL = np.array([528, 584, 620, 632, 620, 584, 528], dtype=np.int64)

# Pyramid: 5 layers, simple 2x2 decimation (matches RTL subsampler)
NUM_LAYERS = 5

# Directories
GOLDEN_DIR = "golden_data"
os.makedirs(GOLDEN_DIR, exist_ok=True)

NUM_ENHANCED_FRAMES = 4


# ==========================================================================
#  RTL Bit-Accurate Gaussian Blur (Vectorized)
# ==========================================================================
#
# The RTL uses a separable 7-tap Gaussian:
#   1. Vertical pass: 7x1 conv on 8-bit pixels -> 21-bit intermediate
#   2. Horizontal pass: 1x7 conv on 21-bit intermediates -> bits [31:24] = 8-bit
#
# Border: BORDER_REFLECT_101 (numpy 'reflect' mode)
#
# The kernel sums to 4096 per pass. Two passes: total scale = 4096^2 = 2^24.
# Taking bits [31:24] of the horizontal result = right-shift by 24.
# So the final pixel = (input * 2^24) >> 24 ≈ input. Correct.
# ==========================================================================

def rtl_gaussian_blur(img):
    """
    Full RTL-matching separable Gaussian blur using vectorized numpy.
    
    Vertical pass: pad rows with BORDER_REFLECT_101, apply 7-tap kernel.
    Horizontal pass: pad columns with BORDER_REFLECT_101, apply 7-tap kernel,
                     extract bits [31:24] as final 8-bit pixel.
    """
    H, W = img.shape
    img64 = img.astype(np.int64)

    # ── Vertical pass ────────────────────────────────────────────────
    # Pad 3 rows top and bottom with BORDER_REFLECT_101
    # numpy 'reflect' mode = BORDER_REFLECT_101 (no edge duplication)
    v_padded = np.pad(img64, ((3, 3), (0, 0)), mode='reflect')
    
    vert_out = np.zeros((H, W), dtype=np.int64)
    for i in range(7):
        vert_out += KERNEL[i] * v_padded[i:i+H, :]
    # vert_out is ~21 bits: max = 255 * 4096 = 1,044,480

    print("    Vertical pass done.")

    # ── Horizontal pass ──────────────────────────────────────────────
    # Pad 3 columns left and right with BORDER_REFLECT_101
    h_padded = np.pad(vert_out, ((0, 0), (3, 3)), mode='reflect')
    
    horiz_out = np.zeros((H, W), dtype=np.int64)
    for i in range(7):
        horiz_out += KERNEL[i] * h_padded[:, i:i+W]
    # horiz_out is ~33 bits: max = 1,044,480 * 4096 = 4,278,190,080

    # RTL extracts bits [31:24] of the 33-bit result
    pixel_out = (horiz_out >> 24) & 0xFF
    result = np.clip(pixel_out, 0, 255).astype(np.uint8)

    print("    Horizontal pass done.")
    return result


# ==========================================================================
#  Pyramid Generation (simple 2x2 decimation — matches RTL subsampler)
# ==========================================================================

def generate_pyramid_layers(img):
    """Generate 5 pyramid layers by simple 2x2 decimation."""
    layers = [img]
    current = img
    for i in range(1, NUM_LAYERS):
        current = current[::2, ::2]
        layers.append(current)
    return layers


def flatten_pyramid(layers):
    """Flatten all layers into a contiguous 1D array (L0|L1|L2|L3|L4)."""
    return np.concatenate([layer.flatten() for layer in layers])


# ==========================================================================
#  OpenCV Reference
# ==========================================================================

def opencv_gaussian_blur(img):
    """OpenCV Gaussian blur with 7x7 kernel."""
    return cv2.GaussianBlur(img, (7, 7), 5, borderType=cv2.BORDER_REFLECT_101)


# ==========================================================================
#  File I/O Helpers
# ==========================================================================

def save_decimal(data, path):
    with open(path, 'w') as f:
        for val in data.flatten():
            f.write(f"{int(val)}\n")


def save_hex(data, path):
    with open(path, 'w') as f:
        for val in data.flatten():
            f.write(f"{int(val):02X}\n")


def load_enhanced_frame(frame_idx):
    path = os.path.join(GOLDEN_DIR, f"enhanced_frame{frame_idx}_pixels.txt")
    print(f"  Loading {path}...")
    pixels = np.loadtxt(path, dtype=np.int32)
    img = pixels.reshape((IMG_H, IMG_W)).astype(np.uint8)
    return img


# ==========================================================================
#  Main
# ==========================================================================

def process_frame(frame_idx):
    print(f"\n{'='*60}")
    print(f"  Processing Enhanced Frame {frame_idx}")
    print(f"{'='*60}")

    img = load_enhanced_frame(frame_idx)

    # ── Golden RTL Blur ──────────────────────────────────────────────
    print("  [Golden RTL] Computing bit-accurate Gaussian blur...")
    rtl_blur = rtl_gaussian_blur(img)

    save_decimal(rtl_blur, os.path.join(GOLDEN_DIR, f"golden_rtl_blur_frame{frame_idx}.txt"))
    save_hex(rtl_blur, os.path.join(GOLDEN_DIR, f"golden_rtl_blur_frame{frame_idx}.hex"))
    Image.fromarray(rtl_blur).save(os.path.join(GOLDEN_DIR, f"golden_rtl_blur_frame{frame_idx}.png"))
    print(f"    Saved golden_rtl_blur_frame{frame_idx}.*")

    # ── Golden RTL Pyramid ───────────────────────────────────────────
    print("  [Golden RTL] Generating pyramid layers (simple decimation)...")
    rtl_layers = generate_pyramid_layers(rtl_blur)
    rtl_pyramid = flatten_pyramid(rtl_layers)

    save_decimal(rtl_pyramid, os.path.join(GOLDEN_DIR, f"golden_rtl_pyramid_frame{frame_idx}.txt"))
    save_hex(rtl_pyramid, os.path.join(GOLDEN_DIR, f"golden_rtl_pyramid_frame{frame_idx}.hex"))
    print(f"    Saved golden_rtl_pyramid_frame{frame_idx}.* ({len(rtl_pyramid)} bytes)")

    for i, layer in enumerate(rtl_layers):
        h, w = layer.shape
        print(f"      Layer {i}: {w}x{h} ({w*h} pixels)")

    # ── OpenCV Reference ─────────────────────────────────────────────
    print("  [OpenCV] Computing reference Gaussian blur...")
    cv_blur = opencv_gaussian_blur(img)

    save_decimal(cv_blur, os.path.join(GOLDEN_DIR, f"opencv_blur_frame{frame_idx}.txt"))
    Image.fromarray(cv_blur).save(os.path.join(GOLDEN_DIR, f"opencv_blur_frame{frame_idx}.png"))
    print(f"    Saved opencv_blur_frame{frame_idx}.*")

    print("  [OpenCV] Generating pyramid layers (simple decimation)...")
    cv_layers = generate_pyramid_layers(cv_blur)
    cv_pyramid = flatten_pyramid(cv_layers)

    save_decimal(cv_pyramid, os.path.join(GOLDEN_DIR, f"opencv_pyramid_frame{frame_idx}.txt"))
    print(f"    Saved opencv_pyramid_frame{frame_idx}.txt ({len(cv_pyramid)} bytes)")

    # ── Comparison ───────────────────────────────────────────────────
    print("\n  [Compare] Golden RTL Blur vs OpenCV Blur:")
    diff_blur = np.abs(rtl_blur.astype(np.int16) - cv_blur.astype(np.int16))
    print(f"    Max diff:  {diff_blur.max()}")
    print(f"    Mean diff: {diff_blur.mean():.4f}")
    print(f"    Exact matches: {np.sum(diff_blur == 0)} / {diff_blur.size} "
          f"({100*np.sum(diff_blur==0)/diff_blur.size:.2f}%)")

    print("  [Compare] Golden RTL Pyramid vs OpenCV Pyramid:")
    diff_pyr = np.abs(rtl_pyramid.astype(np.int16) - cv_pyramid.astype(np.int16))
    print(f"    Max diff:  {diff_pyr.max()}")
    print(f"    Mean diff: {diff_pyr.mean():.4f}")
    print(f"    Exact matches: {np.sum(diff_pyr == 0)} / {diff_pyr.size} "
          f"({100*np.sum(diff_pyr==0)/diff_pyr.size:.2f}%)")

    return rtl_blur, cv_blur


if __name__ == "__main__":
    print("=" * 60)
    print("  Golden Model: Blur + Pyramid (3-Way Comparison)")
    print("=" * 60)

    for idx in range(NUM_ENHANCED_FRAMES):
        process_frame(idx)

    print(f"\n{'='*60}")
    print("  All frames processed. Golden data ready in golden_data/")
    print(f"{'='*60}")
    print("\nFiles generated per frame:")
    print("  golden_rtl_blur_frame*.txt/hex/png    - RTL-accurate blur output")
    print("  golden_rtl_pyramid_frame*.txt/hex      - RTL-accurate pyramid (L0-L4)")
    print("  opencv_blur_frame*.txt/png             - OpenCV reference blur")
    print("  opencv_pyramid_frame*.txt              - OpenCV reference pyramid")
