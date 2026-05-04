import os
import matplotlib.pyplot as plt
import matplotlib.image as mpimg

hardware_dir = r"C:\Users\ACER\Downloads\Electronics project\Hardware results"
agcwd_dir = r"C:\Users\ACER\Downloads\Electronics project\output\agcwd"

image_pairs = [
    ("1.png", "Hardware results/1", "output/agcwd/1"),
    ("3.png", "Hardware results/3", "output/agcwd/3"), 
]

for img_name, hw_path, agcwd_path in image_pairs:
    hw_img = os.path.join(hardware_dir, hw_path.split("/")[-1] + ".png")
    agcwd_img = os.path.join(agcwd_dir, agcwd_path.split("/")[-1] + ".png")
    
    fig, axes = plt.subplots(1, 2, figsize=(12, 6))
    fig.suptitle(f"Comparison: {img_name}")
    
    img1 = mpimg.imread(hw_img)
    axes[0].imshow(img1)
    axes[0].set_title("Hardware results")
    axes[0].axis("off")
    
    img2 = mpimg.imread(agcwd_img)
    axes[1].imshow(img2)
    axes[1].set_title("output/agcwd")
    axes[1].axis("off")
    
    fig.canvas.manager.set_window_title(f"Comparison - {img_name}")
    
    plt.show()