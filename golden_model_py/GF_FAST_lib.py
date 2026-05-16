import cv2
import numpy as np

# -----------------------------------------------------------------------
# Pre-create detectors ONCE — reused every frame
# -----------------------------------------------------------------------
_fast = cv2.FastFeatureDetector_create(threshold=30, nonmaxSuppression=True)
_orb  = cv2.ORB_create()


# =======================================================================
# PREPROCESSING 
# =======================================================================
def preprocess(frame):
    """
    Convert to grayscale -> CLAHE -> Gaussian blur.

    Paper parameters:
      CLAHE : clipLimit=3, tileGridSize=(4,4)
      Blur  : 7x7 kernel, sigma=5
    """
    gray      = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    clahe     = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(4, 4))
    clahe_img = clahe.apply(gray)
    blurred   = cv2.GaussianBlur(clahe_img, (7, 7), 5)
    return clahe_img, blurred


# =======================================================================
# GF DENSE OPTICAL FLOW 
# =======================================================================
def GF(prev_blur, curr_blur):
    """
    Farneback dense optical flow.

    Paper parameters:
      pyr_scale=0.5, levels=5, winsize=15,
      iterations=3, poly_n=11, poly_sigma=1.5
    """
    flow = cv2.calcOpticalFlowFarneback(
        prev_blur,
        curr_blur,
        None,
        0.5,
        5,
        15,
        3,
        11,
        1.5,
        0
    )
    return flow


# =======================================================================
# DESCRIPTOR HELPERS
# =======================================================================
def compute_descriptors(clahe_image, features):
    """
    Compute ORB descriptors at the given feature positions.


    Args:
        clahe_image : Grayscale CLAHE image
        features    : List of (id, x, y)

    Returns:
        desc_map : dict {fid: descriptor (uint8 array, 32 bytes)}
    """
    if not features:
        return {}

    pt_to_fid = {(float(x), float(y)): fid for fid, x, y in features}
    keypoints  = [cv2.KeyPoint(x=float(x), y=float(y), size=15)
                  for _, x, y in features]

    kps, descriptors = _orb.compute(clahe_image, keypoints)

    desc_map = {}
    if descriptors is not None:
        for i, kp in enumerate(kps):
            fid = pt_to_fid.get(kp.pt)
            if fid is not None:
                desc_map[fid] = descriptors[i]
    return desc_map


def check_tracking_with_descriptors(prev_descriptors, curr_clahe,
                                    tracked_features, frame_idx,
                                    threshold=20):
    """
    Checker — compares ORB descriptors of tracked features between frames
    and prints a per-frame summary.


    Args:
        prev_descriptors : {fid: descriptor} from the previous frame
        curr_clahe       : Current CLAHE image
        tracked_features : List of (id, new_x, new_y) after GF+FAST tracking
        frame_idx        : Current frame number (used in the print statement)
        threshold        : Hamming distance below which a match is "good"

    Returns:
        curr_descriptors : {fid: descriptor} for the current frame,
                           so main.py can store them for the next iteration
    """
    curr_descriptors = compute_descriptors(curr_clahe, tracked_features)

    good    = 0
    bad     = 0
    no_desc = 0

    for fid, x, y in tracked_features:
        if fid not in prev_descriptors or fid not in curr_descriptors:
            no_desc += 1
            continue

        dist = cv2.norm(prev_descriptors[fid],
                        curr_descriptors[fid],
                        cv2.NORM_HAMMING)

        if dist <= threshold:
            good += 1
        else:
            bad  += 1

    total = len(tracked_features)
    print(
        f"[Frame {frame_idx:04d}] "
        f"Tracked: {total:4d} | "
        f"Good (dist<{threshold}): {good:4d} | "
        f"Bad: {bad:4d} | "
        f"No descriptor (border): {no_desc:4d}"
    )

    return curr_descriptors


# =======================================================================
# FEATURE EXTRACTION AND TRACKING 
# =======================================================================
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
  fast = cv2.FastFeatureDetector_create(threshold=35, nonmaxSuppression=True)
  keypoints = fast.detect(clahe_image, None)
  
  # Collect all detected positions for efficient distance checks
  detected_positions = np.array([kp.pt for kp in keypoints]) if keypoints else np.empty((0, 2))
  
  # 2. Feature Tracking: Update previous features using GF flow and validate against detections
  tracked_features = []
  threshold = 3.0 # Distance threshold in pixels; tune this (e.g., 2-5) based on your dataset/flow noise
  
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
        continue # Skip: close to a tracked feature
    # If no close match, it's truly new
    new_features.append((next_id, x, y))
    next_id += 1
  
  return tracked_features, new_features