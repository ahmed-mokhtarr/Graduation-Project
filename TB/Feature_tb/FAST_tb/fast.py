import numpy as np
import matplotlib.pyplot as plt
from PIL import Image

def detect_fast_features(image, threshold=35, N=9):
    
    rows, cols = image.shape
    
    # 16 pixel offsets on a Bresenham circle of radius 3
    circle_offsets = [
        (0, -3), (1, -3), (2, -2), (3, -1),
        (3, 0), (3, 1), (2, 2), (1, 3),
        (0, 3), (-1, 3), (-2, 2), (-3, 1),
        (-3, 0), (-3, -1), (-2, -2), (-1, -3)
    ]
    
    raw_corners = []
    
    # Create an empty score map for NMS
    score_map = np.zeros((rows, cols), dtype=np.float32)

    # ==========================================
    # STAGE 1 & 2: Circle Test & RTL Scoring
    # ==========================================
    for y in range(3, rows - 3):
        for x in range(3, cols - 3):
            Ip = int(image[y, x])
            
            # RTL hardware clamps bounds at 0 and 255
            upper = min(255, Ip + threshold)
            lower = max(0, Ip - threshold)
            
            # Fetch the brightness of the 16 circle pixels
            circle_pixels = [int(image[y + dy, x + dx]) for dx, dy in circle_offsets]
            
            is_corner = False
            
            # Check for N consecutive points 
            extended_circle = circle_pixels + circle_pixels[:N-1]
            for i in range(16):
                segment = extended_circle[i:i+N]
                if all(p > upper for p in segment):
                    is_corner = True
                    break
                elif all(p < lower for p in segment):
                    is_corner = True
                    break
            
            # Sum differences for ALL 16 pixels
            if is_corner:
                sum_bright = sum(p - upper for p in circle_pixels if p > upper)
                sum_dark = sum(lower - p for p in circle_pixels if p < lower)
                
                score = max(sum_bright, sum_dark)
                
                raw_corners.append((x, y))
                score_map[y, x] = score

    # ==========================================
    # STAGE 3: 3x3 NMS
    # ==========================================
    final_corners = []
    
    for x, y in raw_corners:
        c = score_map[y, x]
        
        if (c > score_map[y-1, x-1] and c > score_map[y-1, x] and c > score_map[y-1, x+1] and
            c > score_map[y,   x-1] and                           c > score_map[y,   x+1] and
            c > score_map[y+1, x-1] and c > score_map[y+1, x] and c > score_map[y+1, x+1]):
            
            final_corners.append((x, y))
            
    return final_corners

if __name__ == "__main__":
    # Ensure this matches the size of the hex file you gave your RTL
    img_pil = Image.open('images.jpg').convert('L').resize((1280, 720))
    img_array = np.array(img_pil)
    
    corners = detect_fast_features(img_array, threshold=35, N=9)
    
    # Visualization
    plt.figure(figsize=(10, 6))
    plt.imshow(img_array, cmap='gray')
    
    if corners:
        xs, ys = zip(*corners)
        plt.scatter(xs, ys, c='cyan', s=15, marker='x')
        
    plt.title(f"Python FAST (Found {len(corners)} points)")
    plt.axis('off')
    plt.tight_layout()
    plt.show()