import numpy as np
import cv2

# =====================================================================
# MODEL 1: The Golden Float Model (OpenCV Style)
# =====================================================================
def ideal_float_interpolation(image, cdfs):
    height, width = image.shape
    out_img = np.zeros_like(image, dtype=np.uint8)
    image_int = image.astype(np.int32)
    
    for y in range(height):
        for x in range(width):
            # Clamping
            calc_x = min(max(x, 160), 1120)
            calc_y = min(max(y, 90), 630)
            
            # Zones and Float Weights
            if calc_x < 480:
                left, right, dx = 0, 1, calc_x - 160
            elif calc_x < 800:
                left, right, dx = 1, 2, calc_x - 480
            else:
                left, right, dx = 2, 3, calc_x - 800
                
            if calc_y < 270:
                top, bot, dy = 0, 1, calc_y - 90
            elif calc_y < 450:
                top, bot, dy = 1, 2, calc_y - 270
            else:
                top, bot, dy = 2, 3, calc_y - 450
                
            wx = dx / 320.0
            wy = dy / 180.0
            
            # Fetch CDF Data
            pixel_val = image_int[y, x]
            TL = float(cdfs[top, left, pixel_val])
            TR = float(cdfs[top, right, pixel_val])
            BL = float(cdfs[bot, left, pixel_val])
            BR = float(cdfs[bot, right, pixel_val])
            
            # Float Math
            top_mix = TL * (1.0 - wx) + TR * wx
            bot_mix = BL * (1.0 - wx) + BR * wx
            final_mix = top_mix * (1.0 - wy) + bot_mix * wy
            
            out_img[y, x] = np.clip(np.round(final_mix), 0, 255).astype(np.uint8)
            
    return out_img

# =====================================================================
# MODEL 2: The Verilog Hardware Model (Fixed-Point)
# =====================================================================
def hardware_accurate_interpolation(image, cdfs):
    height, width = image.shape
    out_img = np.zeros_like(image, dtype=np.uint8)
    image_int = image.astype(np.int32)
    
    for y in range(height):
        for x in range(width):
            # Clamping
            calc_x = min(max(x, 160), 1120)
            calc_y = min(max(y, 90), 630)
            
            # Zones and Distances
            if calc_x < 480:
                left, right, dx = 0, 1, calc_x - 160
            elif calc_x < 800:
                left, right, dx = 1, 2, calc_x - 480
            else:
                left, right, dx = 2, 3, calc_x - 800
                
            if calc_y < 270:
                top, bot, dy = 0, 1, calc_y - 90
            elif calc_y < 450:
                top, bot, dy = 1, 2, calc_y - 270
            else:
                top, bot, dy = 2, 3, calc_y - 450
                
            # Hardware weights with +512 rounding trick
            x_weight = ((dx * 819) + 512) >> 10
            y_weight = ((dy * 1456) + 512) >> 10
            
            # Fetch CDF Data
            pixel_val = image_int[y, x]
            TL = cdfs[top, left, pixel_val]
            TR = cdfs[top, right, pixel_val]
            BL = cdfs[bot, left, pixel_val]
            BR = cdfs[bot, right, pixel_val]
            
            # Fixed-Point Math
            top_mix = TL * (256 - x_weight) + TR * x_weight
            bot_mix = BL * (256 - x_weight) + BR * x_weight
            final_mix = top_mix * (256 - y_weight) + bot_mix * y_weight
            
            out_img[y, x] = final_mix >> 16
            
    return out_img

# =====================================================================
# EXECUTION & COMPARISON
# =====================================================================
if __name__ == "__main__":
    # 1. Load the Input Image
    img_path = 'IMG_2529.jpg' # Change to your image
    img = cv2.imread(img_path, cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise FileNotFoundError(f"Could not find {img_path}")
    
    img = cv2.resize(img, (1280, 720)) 
    
    # Save the resized and grayscaled original image
    cv2.imwrite('original_resized_grayscale.png', img)
    np.savetxt('original_resized_grayscale.txt', img.flatten(), fmt='%d')
    print("Saved 'original_resized_grayscale.png' and '.txt'.\n")
    
    # 2. Load the Pre-computed CDFs
    cdf_file_path = 'golden_cdf_hw_model.txt'
    try:
        flat_cdfs = np.loadtxt(cdf_file_path, dtype=np.int32)
        cdfs = flat_cdfs.reshape((4, 4, 256))
        print("Loaded CDFs successfully.\n")
    except Exception as e:
        print(f"Error loading CDFs: {e}")
        exit(1)
        
    # 3. Compute All Models
    print("Computing Golden Float Model...")
    ideal_output = ideal_float_interpolation(img, cdfs)
    
    print("Computing Verilog Hardware Model...")
    hw_output = hardware_accurate_interpolation(img, cdfs)
    
    print("Computing OpenCV Built-in CLAHE...")
    # Hardware clip limit of 675 equals OpenCV clipLimit of 3.0
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(4, 4))
    opencv_output = clahe.apply(img)
    
    # 4. Save Outputs
    np.savetxt('python_ideal_output.txt', ideal_output.flatten(), fmt='%d')
    np.savetxt('python_hw_output.txt', hw_output.flatten(), fmt='%d')
    np.savetxt('python_opencv_output.txt', opencv_output.flatten(), fmt='%d')
    
    cv2.imwrite('result_ideal.png', ideal_output)
    cv2.imwrite('result_hw.png', hw_output)
    cv2.imwrite('result_opencv_builtin.png', opencv_output)
    
    # 5. Analyze the Hardware Quantization Error
    print("\n==========================================")
    print("       HW QUANTIZATION ERROR ANALYSIS     ")
    print("==========================================")
    
    # Calculate absolute difference between Custom Float and HW Fixed Point
    diff = np.abs(ideal_output.astype(np.int32) - hw_output.astype(np.int32))
    
    total_pixels = 1280 * 720
    exact_matches = np.count_nonzero(diff == 0)
    off_by_one = np.count_nonzero(diff == 1)
    off_by_two_or_more = np.count_nonzero(diff >= 2)
    
    print(f"Total Pixels Evaluated: {total_pixels:,}")
    print(f"Exact Matches (0 Error): {exact_matches:,} ({(exact_matches/total_pixels)*100:.2f}%)")
    print(f"Off by exactly 1 level:  {off_by_one:,} ({(off_by_one/total_pixels)*100:.2f}%)")
    print(f"Off by 2 or more levels: {off_by_two_or_more:,} ({(off_by_two_or_more/total_pixels)*100:.2f}%)")
    print(f"Maximum Error found:     {np.max(diff)} grayscale levels")
    print("==========================================\n")