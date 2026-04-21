import matplotlib.pyplot as plt
import numpy as np
import os

def plot_golden_histograms(filename='golden_histogram.txt'):
    # 1. Check if the file exists
    if not os.path.exists(filename):
        print(f"Error: {filename} not found!")
        return

    # 2. Read the data from the text file
    print("Loading histogram data...")
    # This reads all 4096 lines into a single 1D array
    raw_data = np.loadtxt(filename, dtype=int)

    # 3. Reshape the data to match our 4x4 grid of 256 bins
    # Shape becomes: (4 rows, 4 columns, 256 bins)
    histograms = raw_data.reshape((4, 4, 256))

    # 4. Set up the matplotlib 4x4 subplot grid
    print("Drawing the 2D grid...")
    fig, axes = plt.subplots(nrows=4, ncols=4, figsize=(16, 10), sharex=True, sharey=True)
    fig.suptitle('Golden Reference: CLAHE 4x4 Tile Histograms', fontsize=16)

    # 5. Loop through the grid and plot each tile's histogram
    for ty in range(4):
        for tx in range(4):
            ax = axes[ty, tx]
            
            # Plot the 256 bins as a filled line plot
            bins = np.arange(256)
            ax.fill_between(bins, histograms[ty, tx], color='skyblue', alpha=0.7)
            ax.plot(bins, histograms[ty, tx], color='darkblue', linewidth=1)
            
            # Formatting for readability
            ax.set_title(f'Tile ({ty}, {tx})', fontsize=10)
            ax.set_xlim([0, 255])
            ax.grid(True, linestyle='--', alpha=0.5)

            # Only show X-axis labels on the bottom row to keep it clean
            if ty == 3:
                ax.set_xlabel('Gray Level (0-255)')
            # Only show Y-axis labels on the leftmost column
            if tx == 0:
                ax.set_ylabel('Pixel Count')

    # 6. Adjust layout and show the plot
    plt.tight_layout()
    plt.subplots_adjust(top=0.92) # Make room for the main title
    
    # Save the plot as an image file (optional)
    plt.savefig('histogram_grid_visualization.png', dpi=300)
    print("Plot saved as 'histogram_grid_visualization.png'")
    
    # Display the interactive window
    plt.show()

# Run the visualizer
plot_golden_histograms('golden_histogram.txt')