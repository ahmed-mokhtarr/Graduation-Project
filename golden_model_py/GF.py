import numpy as np
import cv2
from scipy.ndimage import correlate1d, uniform_filter

# def generate_separable_poly_filters(poly_n, poly_sigma):
#     """
#     Offline calculation to generate the 6 separable 1D filters for polynomial expansion.
#     """
#     grid_size = poly_n // 2
#     x_1d = np.arange(-grid_size, grid_size + 1)
#     y_1d = np.arange(-grid_size, grid_size + 1)
#     X, Y = np.meshgrid(x_1d, y_1d)
    
#     x = X.flatten()
#     y = Y.flatten()
    
#     # 1. Construct Basis Matrix B (size: poly_n^2 x 6)
#     B = np.column_stack([np.ones_like(x), x, y, x**2, y**2, x*y])
    
#     # 2. Construct Gaussian Applicability Weight Wa
#     gaussian_weights = np.exp(-(x**2 + y**2) / (2 * poly_sigma**2))
#     W = np.diag(gaussian_weights) # Wc is assumed to be Identity
    
#     # 3. Compute Projection Matrix P
#     B_T = B.T
#     core_matrix = B_T @ W @ B
#     core_inv = np.linalg.pinv(core_matrix)
#     P = core_inv @ B_T @ W
    
#     # 4. Extract 1D separable filters using SVD
#     filters_1d = []
#     for i in range(6):
#         filter_2d = P[i, :].reshape(poly_n, poly_n)
#         U, S, Vh = np.linalg.svd(filter_2d)
        
#         # Extract the vertical and horizontal components
#         v_filter = U[:, 0] * np.sqrt(S[0])
#         h_filter = Vh[0, :] * np.sqrt(S[0])
#         filters_1d.append((v_filter, h_filter))
        
#     return filters_1d

# def compute_polynomial_expansion(image, filters_1d):
#     """
#     Applies the 6 separable 1D filters to the image to get r1...r6.
#     """
#     coeffs = []
#     for v_filter, h_filter in filters_1d:
#         # Apply horizontal then vertical 1D sliding filters
#         temp = correlate1d(image, h_filter, axis=1, mode='reflect')
#         coeff = correlate1d(temp, v_filter, axis=0, mode='reflect')
#         coeffs.append(coeff)
#     return coeffs # Returns [r1, r2, r3, r4, r5, r6]

def custom_dense_optical_flow(prev, curr, pyr_scale=0.5, levels=5, winsize=15, iterations=3, poly_n=11, poly_sigma=1.5):
    """
    Computes dense optical flow using the Gunnar Farnebäck algorithm.
    Uses exact 2D filtering, Image Warping, and Residual Iterations.
    """
    prev = prev.astype(np.float64)
    curr = curr.astype(np.float64)
    
    # 1. Use the new 2D filter generator
    filters_2d = generate_exact_2d_poly_filters(poly_n, poly_sigma)
    
    prev_pyr, curr_pyr = [prev], [curr]
    for _ in range(1, levels):
        prev_pyr.insert(0, cv2.resize(prev_pyr[0], None, fx=pyr_scale, fy=pyr_scale))
        curr_pyr.insert(0, cv2.resize(curr_pyr[0], None, fx=pyr_scale, fy=pyr_scale))
        
    h_top, w_top = prev_pyr[0].shape
    d = np.zeros((h_top, w_top, 2), dtype=np.float64)
    
    for i in range(levels):
        img1 = prev_pyr[i]
        img2 = curr_pyr[i]
        h, w = img1.shape
        
        if i > 0:
            d = cv2.resize(d, (w, h), interpolation=cv2.INTER_LINEAR)
            d *= (1.0 / pyr_scale) 
            
        # Pass the 2D filters into the expansion function
        r_prev = compute_polynomial_expansion(img1, filters_2d)
        b1_x, b1_y = r_prev[1], r_prev[2]
        A1_11, A1_22, A1_12 = r_prev[3], r_prev[4], r_prev[5] / 2.0
        
        X, Y = np.meshgrid(np.arange(w), np.arange(h))
        
        for _ in range(iterations):
            map_x = (X + d[..., 0]).astype(np.float32)
            map_y = (Y + d[..., 1]).astype(np.float32)
            
            img2_warped = cv2.remap(img2, map_x, map_y, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
            
            # Pass the 2D filters into the expansion function for the warped image
            r_curr = compute_polynomial_expansion(img2_warped, filters_2d)
            b2_x, b2_y = r_curr[1], r_curr[2]
            A2_11, A2_22, A2_12 = r_curr[3], r_curr[4], r_curr[5] / 2.0
            
            A_11 = (A1_11 + A2_11) / 2.0
            A_22 = (A1_22 + A2_22) / 2.0
            A_12 = (A1_12 + A2_12) / 2.0
            
            res_b_x = -0.5 * (b2_x - b1_x)
            res_b_y = -0.5 * (b2_y - b1_y)
            
            G_11 = A_11**2 + A_12**2
            G_22 = A_12**2 + A_22**2
            G_12 = A_11 * A_12 + A_12 * A_22
            
            res_h_1 = A_11 * res_b_x + A_12 * res_b_y
            res_h_2 = A_12 * res_b_x + A_22 * res_b_y
            
            G_11_sm = uniform_filter(G_11, size=winsize)
            G_22_sm = uniform_filter(G_22, size=winsize)
            G_12_sm = uniform_filter(G_12, size=winsize)
            res_h_1_sm = uniform_filter(res_h_1, size=winsize)
            res_h_2_sm = uniform_filter(res_h_2, size=winsize)
            
            det = G_11_sm * G_22_sm - G_12_sm**2 + 1e-6 
            
            delta_d_x = (G_22_sm * res_h_1_sm - G_12_sm * res_h_2_sm) / det
            delta_d_y = (G_11_sm * res_h_2_sm - G_12_sm * res_h_1_sm) / det
            
            d[..., 0] += delta_d_x
            d[..., 1] += delta_d_y
            
    return d








def GF(prev_blur, curr_blur):
    """
    Calculate dense optical flow using Farneback method.
    
    Args:
        prev_blur: Previous frame (preprocessed)
        curr_blur: Current frame (preprocessed)
        
    Returns:
        flow: Dense optical flow field
    """
    flow = cv2.calcOpticalFlowFarneback(
        prev_blur,                  # Previous Image
        curr_blur,                  # Current Image
        None,                       # Flow placeholder
        0.5,                        # Pyramid scale (2:1)
        5,                          # Levels (5 layers)
        15,                         # Window size
        1,                          # Iterations
        11,                         # Poly N (neighborhood size) 
        1.5,                        # Poly Sigma
        0                           # Flags
    )
    return flow
















def generate_exact_2d_poly_filters(poly_n, poly_sigma):
    """
    Computes P = (B^T * Wa * Wc * B)^-1 * B^T * Wa * Wc
    and returns the 6 rows reshaped as 2D filters.
    """
    grid_size = poly_n // 2
    x_1d = np.arange(-grid_size, grid_size + 1)
    y_1d = np.arange(-grid_size, grid_size + 1)
    X, Y = np.meshgrid(x_1d, y_1d)
    
    x = X.flatten()
    y = Y.flatten()
    
    # B: Basis matrix (N^2 x 6)
    B = np.column_stack([np.ones_like(x), x, y, x**2, y**2, x*y])
    
    # Wa: Applicability weight (Gaussian)
    gaussian_weights = np.exp(-(x**2 + y**2) / (2 * poly_sigma**2))
    Wa = np.diag(gaussian_weights)
    
    # Wc: Certainty weight (Identity matrix, assuming all pixels are valid)
    Wc = np.eye(len(x))
    
    # W = Wa * Wc
    W = Wa @ Wc
    
    # Calculate P = (B^* W B)^dagger B^* W
    # Note: B^* is B.T for real numbers
    B_T = B.T
    core_matrix = B_T @ W @ B
    core_inv = np.linalg.pinv(core_matrix) # The pseudo-inverse dagger
    P = core_inv @ B_T @ W
    
    # Extract the 6 rows of P and reshape them into 2D N x N filters
    filters_2d = []
    for i in range(6):
        filter_2d = P[i, :].reshape(poly_n, poly_n)
        filters_2d.append(filter_2d)
        
    return filters_2d

def compute_polynomial_expansion(image, filters_2d):
    """
    Applies the equation r = P * f across the entire image.
    Returns the 6 coefficient maps [r1, r2, r3, r4, r5, r6].
    """
    coeffs = []
    for P_row_2d in filters_2d:
        # cv2.filter2D performs the correlation of the 2D filter with the image f
        # cv2.CV_64F ensures we maintain double precision
        coeff = cv2.filter2D(image, cv2.CV_64F, P_row_2d, borderType=cv2.BORDER_REFLECT)
        coeffs.append(coeff)
        
    return coeffs