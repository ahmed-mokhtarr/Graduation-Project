import cv2
import numpy as np
import glob
import os
from scipy.ndimage import correlate1d, uniform_filter

# --- Preprocessing Function ---
def preprocess(frame):
    """
    Apply preprocessing to a frame: convert to grayscale, apply CLAHE, and Gaussian blur.
    
    Args:
        frame: Input BGR image
        
    Returns:
        clahe_img: CLAHE-enhanced image
        blurred: Gaussian blurred image
    """
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(4, 4))
    clahe_img = clahe.apply(gray)
    blurred = cv2.GaussianBlur(clahe_img, (7, 7), 5)
    return clahe_img, blurred

# --- GF Function ---
def GF(prev_blur, curr_blur):
    """
    Calculate dense optical flow using Farneback method.
    
    Args:
        prev_blur: Previous frame (preprocessed)
        curr_blur: Current frame (preprocessed)
        
    Returns:
        flow: Dense optical flow field
    """
    # flow = cv2.calcOpticalFlowFarneback(
    #     prev_blur,                  # Previous Image
    #     curr_blur,                  # Current Image
    #     None,                       # Flow placeholder
    #     0.5,                        # Pyramid scale (2:1)
    #     5,                          # Levels (5 layers)
    #     15,                         # Window size
    #     3,                          # Iterations
    #     11,                         # Poly N (neighborhood size) 
    #     1.5,                        # Poly Sigma
    #     0                           # Flags
    # )
    flow = hardware_friendly_warp_free_flow(prev_blur, curr_blur)



    return flow

# --- Feature Extraction and Tracking Function ---

def feature_extraction_and_tracking(clahe_image, gf_flow, prev_features):
    
    """
    Implements the feature extraction and tracking module.
    
    Args:
    - clahe_image: Current CLAHE-processed grayscale image.
    - gf_flow: Dense GF optical flow.
    - prev_features: List of previous features [(id, x, y), ...].
    
    Returns:
    - tracked_features: List of tracked features [(id, new_x, new_y), ...] for output to back-end.
    - new_features: List of new detected features [(id, x, y), ...] to use as prev_features next time.
    """
    h, w = clahe_image.shape
    
    # 1. Feature Extraction: Detect FAST features on current CLAHE image (moved up for validation)
    fast = cv2.FastFeatureDetector_create(threshold=30, nonmaxSuppression=True)
    keypoints = fast.detect(clahe_image, None)
    
    # Collect all detected positions for efficient distance checks
    detected_positions = np.array([kp.pt for kp in keypoints]) if keypoints else np.empty((0, 2))
    
    # 2. Feature Tracking: Update previous features using GF flow and validate against detections
    tracked_features = []
    threshold = 3.0  # Distance threshold in pixels; tune this (e.g., 2-5) based on your dataset/flow noise
    
    for fid, px, py in prev_features:
        # Flow indexing requires integer coordinates
        py_idx, px_idx = int(round(py)), int(round(px)) 
        
        if 0 <= py_idx < h and 0 <= px_idx < w:
            du, dv = gf_flow[py_idx, px_idx]  
            new_x = px + du
            new_y = py + dv
            
            # Check if moved to a valid location within frame
            if 0 <= new_x < w and 0 <= new_y < h:
                # Validate: Check if there's a detected keypoint nearby
                if detected_positions.size > 0:
                    distances = np.linalg.norm(detected_positions - np.array([new_x, new_y]), axis=1)
                    min_dist = np.min(distances)
                    if min_dist < threshold:
                        tracked_features.append((fid, new_x, new_y))
                    # Else: No nearby detection -> likely occluded/lost, discard
                else:
                    # If no detections at all, perhaps skip, but for safety, discard
                    pass
            # Else: Out of bounds -> discard
    
    # 3. Filter New Features: From detected keypoints, add those not close to validated tracked positions
    if prev_features:
        next_id = max([f[0] for f in prev_features]) + 1
    else:
        next_id = 0
        
    new_features = []
    
    # Collect positions of validated tracked features
    tracked_positions = np.array([(x, y) for _, x, y in tracked_features]) if tracked_features else np.empty((0, 2))
    
    for kp in keypoints:
        x, y = kp.pt
        if tracked_positions.size > 0:
            distances = np.linalg.norm(tracked_positions - np.array([x, y]), axis=1)
            min_dist = np.min(distances)
            if min_dist < threshold:
                continue  # Skip: close to a tracked feature
        # If no close match, it's truly new
        new_features.append((next_id, x, y))
        next_id += 1
    
    return tracked_features, new_features


import numpy as np
import cv2

# ==========================================
# HARDWARE BLOCK 1 & 2: ROMs and Poly Expander
# (Same as previous version)
# ==========================================
def init_hardware_roms(poly_n, poly_sigma):
    grid_size = poly_n // 2
    x_1d = np.arange(-grid_size, grid_size + 1)
    y_1d = np.arange(-grid_size, grid_size + 1)
    X, Y = np.meshgrid(x_1d, y_1d)
    
    x, y = X.flatten(), Y.flatten()
    B = np.column_stack([np.ones_like(x), x, y, x**2, y**2, x*y])
    
    gaussian_weights = np.exp(-(x**2 + y**2) / (2 * poly_sigma**2))
    Wa = np.diag(gaussian_weights)
    W = Wa @ np.eye(len(x))
    
    B_T = B.T
    core_matrix = B_T @ W @ B
    core_inv = np.linalg.pinv(core_matrix)
    P = core_inv @ B_T @ W
    
    filters_2d = [P[i, :].reshape(poly_n, poly_n).astype(np.float32) for i in range(6)]
    return filters_2d

def hw_compute_polynomial_expansion(image, filters_rom):
    coeffs = []
    for rom_filter in filters_rom:
        coeff = cv2.filter2D(image, cv2.CV_32F, rom_filter, borderType=cv2.BORDER_REFLECT)
        coeffs.append(coeff)
    return coeffs

# ==========================================
# HARDWARE BLOCK 3: Box Filter
# (Same as previous version)
# ==========================================
def hw_box_filter(img, winsize):
    kernel_1d = np.ones((winsize, 1), dtype=np.float32) / winsize
    temp = cv2.filter2D(img, cv2.CV_32F, kernel_1d, borderType=cv2.BORDER_REFLECT)
    out = cv2.filter2D(temp, cv2.CV_32F, kernel_1d.T, borderType=cv2.BORDER_REFLECT)
    return out

# ==========================================
# HARDWARE BLOCK 4: NEW! Integer BRAM Fetch
# ==========================================
def hw_integer_shift_coeffs(coeff_map, map_x, map_y):
    """
    Hardware Equivalent: BRAM Read Pointer Offset.
    No multipliers, no interpolation. Just rounding addresses and fetching.
    """
    h, w = coeff_map.shape[:2]
    
    # 1. Hardware Rounding (Address generation)
    x_int = np.round(map_x).astype(np.int32)
    y_int = np.round(map_y).astype(np.int32)
    
    # 2. Hardware Saturation (Preventing memory out-of-bounds)
    x_int = np.clip(x_int, 0, w - 1)
    y_int = np.clip(y_int, 0, h - 1)
    
    # 3. Direct Memory Read
    return coeff_map[y_int, x_int]

# ==========================================
# TOP LEVEL ARCHITECTURE: Warp-Free
# ==========================================
def hardware_friendly_warp_free_flow(prev, curr, pyr_scale=0.5, levels=5, winsize=15, iterations=1, poly_n=11, poly_sigma=1.5):
    
    filters_rom = init_hardware_roms(poly_n, poly_sigma)
    
    prev_pyr, curr_pyr = [prev.astype(np.float32)], [curr.astype(np.float32)]
    for _ in range(1, levels):
        prev_pyr.insert(0, cv2.resize(prev_pyr[0], None, fx=pyr_scale, fy=pyr_scale))
        curr_pyr.insert(0, cv2.resize(curr_pyr[0], None, fx=pyr_scale, fy=pyr_scale))
        
    h_top, w_top = prev_pyr[0].shape
    d = np.zeros((h_top, w_top, 2), dtype=np.float32)
    
    for i in range(levels):
        img1 = prev_pyr[i]
        img2 = curr_pyr[i]
        h, w = img1.shape
        
        if i > 0:
            d = cv2.resize(d, (w, h), interpolation=cv2.INTER_LINEAR)
            d *= (1.0 / pyr_scale) 
            
        # ---------------------------------------------------------
        # PIPELINE STAGE 1: Compute Poly Expansions ONCE per level
        # Both images are processed directly from memory, no warping.
        # ---------------------------------------------------------
        r_prev = hw_compute_polynomial_expansion(img1, filters_rom)
        b1_x, b1_y = r_prev[1], r_prev[2]
        A1_11, A1_22, A1_12 = r_prev[3], r_prev[4], r_prev[5] / 2.0
        
        r_curr = hw_compute_polynomial_expansion(img2, filters_rom)
        b2_x_base, b2_y_base = r_curr[1], r_curr[2]
        A2_11_base, A2_22_base, A2_12_base = r_curr[3], r_curr[4], r_curr[5] / 2.0
        
        X, Y = np.meshgrid(np.arange(w), np.arange(h))
        
        for _ in range(iterations):
            map_x = X + d[..., 0]
            map_y = Y + d[..., 1]
            
            # ---------------------------------------------------------
            # PIPELINE STAGE 2: BRAM Integer Shifting
            # Fetch the pre-calculated coefficients at the shifted coordinates.
            # ---------------------------------------------------------
            b2_x = hw_integer_shift_coeffs(b2_x_base, map_x, map_y)
            b2_y = hw_integer_shift_coeffs(b2_y_base, map_x, map_y)
            A2_11 = hw_integer_shift_coeffs(A2_11_base, map_x, map_y)
            A2_22 = hw_integer_shift_coeffs(A2_22_base, map_x, map_y)
            A2_12 = hw_integer_shift_coeffs(A2_12_base, map_x, map_y)
            
            # ---------------------------------------------------------
            # PIPELINE STAGE 3: Standard ALU Math & Smoothing
            # ---------------------------------------------------------
            A_11 = (A1_11 + A2_11) * 0.5
            A_22 = (A1_22 + A2_22) * 0.5
            A_12 = (A1_12 + A2_12) * 0.5
            # dx, dy = d[..., 0], d[..., 1]
            res_b_x = -0.5 * (b2_x - b1_x) 
            res_b_y = -0.5 * (b2_y - b1_y) 

            G_11 = A_11**2 + A_12**2
            G_22 = A_12**2 + A_22**2
            G_12 = A_11 * A_12 + A_12 * A_22
            
            res_h_1 = A_11 * res_b_x + A_12 * res_b_y
            res_h_2 = A_12 * res_b_x + A_22 * res_b_y
            
            G_11_sm = hw_box_filter(G_11, winsize)
            G_22_sm = hw_box_filter(G_22, winsize)
            G_12_sm = hw_box_filter(G_12, winsize)
            res_h_1_sm = hw_box_filter(res_h_1, winsize)
            res_h_2_sm = hw_box_filter(res_h_2, winsize)
            
            det = G_11_sm * G_22_sm - G_12_sm**2 + 1e-6 
            
            delta_d_x = (G_22_sm * res_h_1_sm - G_12_sm * res_h_2_sm) / det
            delta_d_y = (G_11_sm * res_h_2_sm - G_12_sm * res_h_1_sm) / det
            
            # Update the flow vector
            d[..., 0] += delta_d_x
            d[..., 1] += delta_d_y
            
    return d

