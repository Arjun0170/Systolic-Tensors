import numpy as np
import sys

def gen_systolic_vectors(rows, cols, ip_width, k_dim):
    min_val = -(2**(ip_width-1))
    max_val = (2**(ip_width-1)) - 1
    
    A = np.random.randint(min_val, max_val, (rows, k_dim))
    B = np.random.randint(min_val, max_val, (k_dim, cols))
    
    C_gold = np.matmul(A, B)
    
    with open("input_matrix.hex", "w") as fa, \
         open("weight_matrix.hex", "w") as fb:
        
        for k in range(k_dim):
            row_bits = 0
            for r in range(rows):
                val = int(A[r, k]) & ((1 << ip_width) - 1)
                row_bits |= (val << (r * ip_width))
            
            hex_chars = (rows * ip_width + 3) // 4
            fa.write(f"{row_bits:0{hex_chars}x}\n")

            col_bits = 0
            for c in range(cols):
                val = int(B[k, c]) & ((1 << ip_width) - 1)
                col_bits |= (val << (c * ip_width))
            
            hex_chars_b = (cols * ip_width + 3) // 4
            fb.write(f"{col_bits:0{hex_chars_b}x}\n")

    with open("golden_output.hex", "w") as fc:
        flat_C = 0
        total_bits = rows * cols * 48
        
        for i in range(rows):
            for j in range(cols):
                val = int(C_gold[i, j]) & ((1 << 48) - 1)
                shift = (i * cols + j) * 48
                flat_C |= (val << shift)
        
        hex_chars_c = (total_bits + 3) // 4
        fc.write(f"{flat_C:0{hex_chars_c}x}\n")

if __name__ == "__main__":
    gen_systolic_vectors(64, 64, 8, 128)
