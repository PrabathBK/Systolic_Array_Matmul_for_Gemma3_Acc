import numpy as np

# Define 4x4 input matrices (same as in your Verilog testbench)
A = np.array([
    [1, 2, 3, 4],
    [5, 6, 7, 8],
    [9,10,11,12],
    [13,14,15,16]
])

B = np.array([
    [17,18,19,20],
    [21,22,23,24],
    [25,26,27,28],
    [29,30,31,32]
])

# Perform matrix multiplication
C = np.dot(A, B)

# Print results in Verilog-style
print("=== Python Computed Matrix Multiplication Result ===")
for i in range(C.shape[0]):
    for j in range(C.shape[1]):
        print(f"Result[{i}][{j}] = {C[i, j]}")