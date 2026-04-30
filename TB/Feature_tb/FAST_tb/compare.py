import cv2
import numpy as np
import matplotlib.pyplot as plt

# Import your custom FAST implementation from your fast.py file
from fast import detect_fast_features

def save_corners_to_txt(corners, filename):
    """Saves a list of (x, y) tuples to a text file."""
    with open(filename, 'w') as f:
        for x, y in corners:
            # Saving as integer coordinates: x,y
            f.write(f"{int(x)},{int(y)}\n")

def calculate_accuracy(test_corners, ref_corners, distance_threshold=3.0):
    """
    Calculates the matching accuracy between two sets of corners.
    A test corner matches a reference corner if the Euclidean distance is <= distance_threshold.
    """
    if not test_corners or not ref_corners:
        return 0.0, 0.0, 0
        
    test_arr = np.array(test_corners)
    ref_arr = np.array(ref_corners)
    
    matches = 0
    matched_ref_indices = set()
    
    for t_pt in test_arr:
        dists = np.linalg.norm(ref_arr - t_pt, axis=1)
        min_idx = np.argmin(dists)
        
        if dists[min_idx] <= distance_threshold and min_idx not in matched_ref_indices:
            matches += 1
            matched_ref_indices.add(min_idx)
            
    accuracy = (matches / len(test_corners)) * 100.0 if len(test_corners) > 0 else 0.0
    recall = (matches / len(ref_corners)) * 100.0 if len(ref_corners) > 0 else 0.0
    
    return accuracy, recall, matches

def load_corners_from_txt(filename):
    """Loads a list of (x, y) tuples from a text file."""
    corners = []
    try:
        with open(filename, 'r') as f:
            for line in f:
                # Assuming format is "x, y" or "x,y"
                parts = line.strip().replace(' ', '').split(',')
                if len(parts) >= 2:
                    corners.append((float(parts[0]), float(parts[1])))
    except FileNotFoundError:
        print(f"Warning: {filename} not found. Returning empty list.")
    return corners

def main():
    image_path = 'zebra.jpg'
    rtl_txt_path = r'D:\Ahmed\Projects\Graduation_Project\Codes\RTL\fast\rtl_corners.txt'
    
    # 1. Load image
    img_gray = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
    if img_gray is None:
        print(f"Error: Could not load {image_path}. Check the path.")
        return
        
    img_rgb = cv2.cvtColor(cv2.imread(image_path), cv2.COLOR_BGR2RGB)

    # ---> ADD THESE TWO LINES TO FIX THE RESOLUTION MISMATCH <---
    img_gray = cv2.resize(img_gray, (1280, 720), interpolation=cv2.INTER_LINEAR)
    img_rgb = cv2.resize(img_rgb, (1280, 720), interpolation=cv2.INTER_LINEAR)

    # 2. Run Custom Python FAST
    print("Running Custom Python FAST...")
    # Matching the default parameters from your script
    custom_corners = detect_fast_features(img_gray, threshold=35, N=9)
    save_corners_to_txt(custom_corners, 'python_corners.txt')
    print(f"-> Saved {len(custom_corners)} custom corners to python_corners.txt")

    # 3. Run OpenCV FAST
    print("Running OpenCV FAST...")
    # Initialize OpenCV FAST to match your specs: Threshold 35, FAST-9, with NMS
    fast_cv = cv2.FastFeatureDetector_create(
        threshold=35, 
        nonmaxSuppression=True, 
        type=cv2.FAST_FEATURE_DETECTOR_TYPE_9_16
    )
    keypoints = fast_cv.detect(img_gray, None)
    
    # Extract (x,y) from the KeyPoint objects
    opencv_corners = [(kp.pt[0], kp.pt[1]) for kp in keypoints]
    save_corners_to_txt(opencv_corners, 'opencv_corners.txt')
    print(f"-> Saved {len(opencv_corners)} OpenCV corners to opencv_corners.txt")

    # 4. Load RTL Corners
    print("Loading RTL corners...")
    rtl_corners = load_corners_from_txt(rtl_txt_path)
    print(f"-> Loaded {len(rtl_corners)} RTL corners from {rtl_txt_path}")

    # 5. Calculate Accuracy
    print("\n--- Accuracy Metrics (Distance Threshold: 3.0 pixels) ---")
    
    # RTL vs Python
    acc_rtl_py, rec_rtl_py, match_rtl_py = calculate_accuracy(rtl_corners, custom_corners, 3.0)
    print(f"RTL vs Python:")
    print(f"  Matches: {match_rtl_py} / RTL Total: {len(rtl_corners)} / Python Total: {len(custom_corners)}")
    print(f"  RTL Accuracy (Matches/RTL): {acc_rtl_py:.2f}%")
    print(f"  RTL Recall (Matches/Python): {rec_rtl_py:.2f}%\n")
    
    # RTL vs OpenCV
    acc_rtl_cv, rec_rtl_cv, match_rtl_cv = calculate_accuracy(rtl_corners, opencv_corners, 3.0)
    print(f"RTL vs OpenCV:")
    print(f"  Matches: {match_rtl_cv} / RTL Total: {len(rtl_corners)} / OpenCV Total: {len(opencv_corners)}")
    print(f"  RTL Accuracy (Matches/RTL): {acc_rtl_cv:.2f}%")
    print(f"  RTL Recall (Matches/OpenCV): {rec_rtl_cv:.2f}%\n")

    # 6. Visualization
    print("Generating visualization plot...")
    fig, axes = plt.subplots(1, 3, figsize=(18, 6), sharex=True, sharey=True)
    
    titles = [f"RTL Corners ({len(rtl_corners)})", 
              f"Python Corners ({len(custom_corners)})", 
              f"OpenCV Corners ({len(opencv_corners)})"]
              
    corner_sets = [rtl_corners, custom_corners, opencv_corners]
    colors = ['red', 'cyan', 'lime']

    for ax, title, corners, color in zip(axes, titles, corner_sets, colors):
        ax.imshow(img_rgb)
        ax.set_title(title, fontsize=14, fontweight='bold')
        ax.axis('off')
        if corners:
            xs, ys = zip(*corners)
            ax.scatter(xs, ys, c=color, s=15, marker='x', linewidths=1.5)

    plt.tight_layout()
    plt.show()

if __name__ == "__main__":
    main()