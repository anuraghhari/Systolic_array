import numpy as np

# Define image (5x5)
img = np.array([
    [10, 10, 200, 200, 200],
    [10, 10, 200, 200, 200],
    [10, 10, 200, 200, 200],
    [10, 10, 200, 200, 200],
    [10, 10, 200, 200, 200]
], dtype=np.int32)

sobel_vertical = np.array([
    [-1,  0,  1],
    [-2,  0,  2],
    [-1,  0,  1]
], dtype=np.int16)

sobel_horizontal = np.array([
    [-1, -2, -1],
    [ 0,  0,  0],
    [ 1,  2,  1]
], dtype=np.int16)

sharpen = np.array([
    [ 0, -1,  0],
    [-1,  5, -1],
    [ 0, -1,  0]
], dtype=np.int16)


kernel_size = 3
stride = 1
kernel_num =3

H, W = img.shape
out_h = (H - kernel_size) // stride + 1
out_w = (W - kernel_size) // stride + 1

print(out_h)
print(out_w)

im2col_matrix = []
weights_matrix =[]


weights_matrix.append(sobel_horizontal.flatten())
weights_matrix.append(sobel_vertical.flatten())
weights_matrix.append(sharpen.flatten())

weights_matrix = np.array(weights_matrix)




for i in range(out_h):
    for j in range(out_w):
        patch = img[i:i+kernel_size, j:j+kernel_size]
        im2col_matrix.append(patch.flatten())

im2col_matrix = np.array(im2col_matrix)

# Save to mem file (hexa format)
np.savetxt("im2col.mem", im2col_matrix, fmt="%x")
with open("weights.mem", "w") as f:
    for row in weights_matrix:
        for val in row:
            f.write(f"{int(val) & 0xFFFF:04x}\n")

