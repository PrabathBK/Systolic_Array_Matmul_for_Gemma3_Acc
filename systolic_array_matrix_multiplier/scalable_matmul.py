import numpy as np

SIZE = 6

# Initialize matrix A (same as Verilog: A[i][j] = i * SIZE + j + 1)
A = np.zeros((SIZE, SIZE), dtype=int)
for i in range(SIZE):
    for j in range(SIZE):
        A[i, j] = i * SIZE + j + 1

# Initialize matrix B (same as Verilog: B[i][j] = (i+1) * (j+1))
B = np.zeros((SIZE, SIZE), dtype=int)
for i in range(SIZE):
    for j in range(SIZE):
        B[i, j] = (i + 1) * (j + 1)

# Matrix multiplication
C = np.dot(A, B)

# Print in Verilog-style output
print("\n=== Python Computed 6x6 Matrix Multiplication Result ===")
for i in range(SIZE):
    for j in range(SIZE):
        print(f"Result[{i}][{j}] = {C[i, j]}")