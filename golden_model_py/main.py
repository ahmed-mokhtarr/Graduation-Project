import cv2
import numpy as np
import glob
import os
import csv
from collections import defaultdict

from GF_FAST_lib import (
    preprocess,
    GF,
    feature_extraction_and_tracking,
    compute_descriptors,
    check_tracking_with_descriptors
)

# =======================================================================
# CONFIGURATION
# =======================================================================
folder_path          = r"D:\GP\EuRoc_dataset\vicon_room1\V1_01_easy\mav0\cam0\data"
output_csv           = "feature_trajectories.csv"
DESCRIPTOR_THRESHOLD = 25   # Hamming distance: <50 good, >100 bad

# =======================================================================
# 1. Load and sort image files
# =======================================================================
image_files = sorted(glob.glob(os.path.join(folder_path, "*.png")))

if not image_files:
    print(f"No images found in {folder_path}. Check path.")
    exit()

# =======================================================================
# 2. Initialization — first frame
# =======================================================================

# Track the position history of one specific feature for debugging
WATCH_ID    = 24296       
watch_trail = []       # stores (x, y) positions across frames

first_frame = cv2.imread(image_files[0])
if first_frame is None:
    print("Could not read the first image.")
    exit()

prev_clahe, prev_blur = preprocess(first_frame)

# Detect initial features on the first frame
# Pass zero flow (no previous frame) and empty feature list
_, initial_features = feature_extraction_and_tracking(
    prev_clahe,
    np.zeros((prev_clahe.shape[0], prev_clahe.shape[1], 2), dtype=np.float32),
    []
)
prev_features_list = initial_features

# Compute descriptors for the initial features so we can start
# comparing from frame 1 onwards
prev_desc = compute_descriptors(prev_clahe, prev_features_list)

# Trajectory log: {fid: [(frame_idx, x, y), ...]}
feature_paths = defaultdict(list)
for fid, x, y in prev_features_list:
    feature_paths[fid].append((0, x, y))

print(f"Initialized with {len(prev_features_list)} features on frame 0.")
print(f"Processing {len(image_files)} frames...\n")

# =======================================================================
# 3. Main loop
# =======================================================================
for i in range(1, len(image_files)):

    frame = cv2.imread(image_files[i])
    if frame is None:
        continue

    # ── A. Preprocess ────────────────────────────────────────────────
    current_clahe, current_blur = preprocess(frame)

    # ── B. GF Dense Optical Flow ─────────────────────────────────────
    flow = GF(prev_blur, current_blur)

    # ── C. Feature Extraction and Tracking (GF + FAST validation) ────
    #   tracked_out : previous features updated via GF, validated by FAST
    #   new_detected: fresh FAST corners not near any tracked feature
    tracked_out, new_detected = feature_extraction_and_tracking(
        current_clahe, flow, prev_features_list
    )

    # ── D. Descriptor Checker (print only — does NOT filter features) ─
    #   Compares ORB patch at the old position (prev frame) with the
    #   patch at the new GF-predicted position (current frame).
    #   Prints a summary line every frame so you can see tracking quality.
    #   curr_desc is returned so we can store it for the next iteration.
    curr_desc = check_tracking_with_descriptors(
        prev_desc, current_clahe, tracked_out,
        frame_idx=i,
        threshold=DESCRIPTOR_THRESHOLD
    )

    # ── E. Build current active feature list ─────────────────────────
    #   All tracked features pass through (descriptor check is info only)
    current_features = tracked_out + new_detected

    # ── F. Update trajectory log ─────────────────────────────────────
    for fid, x, y in current_features:
        feature_paths[fid].append((i, x, y))

    # ── G. Update descriptors for next frame ─────────────────────────
    #   We also need descriptors for new_detected so next frame can
    #   check them too — merge curr_desc with new features' descriptors
    new_desc  = compute_descriptors(current_clahe, new_detected)
    prev_desc = {**curr_desc, **new_desc}

    # ── H. Visualisation ─────────────────────────────────────────────────
    vis_img = frame.copy()

    # Draw all tracked features -> GREEN
    for fid, x, y in tracked_out:
        cv2.circle(vis_img, (int(x), int(y)), 2, (0, 255, 0), -1)

    # Draw all new features -> RED
    for fid, x, y in new_detected:
        cv2.circle(vis_img, (int(x), int(y)), 2, (0, 0, 255), -1)

    # --- Debug: highlight the watched feature ---
    watched = {fid: (x, y) for fid, x, y in current_features}

    if WATCH_ID in watched:
        wx, wy = watched[WATCH_ID]
        watch_trail.append((int(wx), int(wy)))

        # Draw trail — line connecting all past positions
        if len(watch_trail) > 1:
            for t in range(1, len(watch_trail)):
                cv2.line(vis_img, watch_trail[t-1], watch_trail[t],
                         (128, 0, 128), 1)   

        # Draw a bigger distinct circle on the watched feature
        cv2.circle(vis_img, (int(wx), int(wy)), 6, (128, 0, 128), 2) 

        # Draw the feature ID as text next to it
        cv2.putText(vis_img,
                    f"ID={WATCH_ID} ({wx:.1f},{wy:.1f})",
                    (int(wx) + 8, int(wy) - 8),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, (128, 0, 128), 1)

        # Also print to console every frame
        print(f"  [Watch ID={WATCH_ID}] Frame {i}: pos=({wx:.2f}, {wy:.2f})")

    else:
        # Feature was lost — print once
        if watch_trail:   # means it existed before
            print(f"  [Watch ID={WATCH_ID}] LOST at frame {i}")

    # Counters on screen
    cv2.putText(vis_img, f"Tracked: {len(tracked_out)}",
                (10, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
    cv2.putText(vis_img, f"New:     {len(new_detected)}",
                (10, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 1)
    cv2.putText(vis_img, f"Frame:   {i}/{len(image_files)-1}",
                (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 0, 0), 1)

    cv2.imshow("FAST + GF Tracking", vis_img)

    # ── I. Carry state forward ────────────────────────────────────────
    prev_blur          = current_blur
    prev_features_list = current_features

    if cv2.waitKey(20) & 0xFF == ord('q'):
        break

cv2.destroyAllWindows()

# =======================================================================
# 4. Save trajectories to CSV
# =======================================================================
print(f"\nSaving trajectories to {output_csv} ...")
with open(output_csv, mode='w', newline='') as csv_file:
    writer = csv.writer(csv_file)
    writer.writerow(['feature_id', 'frame_index', 'x', 'y'])
    for fid in sorted(feature_paths.keys()):
        for frame_idx, x, y in feature_paths[fid]:
            writer.writerow([fid, frame_idx, x, y])

print(f"Done. Saved {len(feature_paths)} unique feature trajectories.")