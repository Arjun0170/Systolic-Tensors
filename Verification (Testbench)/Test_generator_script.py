import numpy as np
import sys
import argparse

def gen_systolic_vectors(rows, cols, ip_width, op_width, k_dim):
    print(f"Generating vectors for: {rows}x{cols} Array, K={k_dim}, IP={ip_width}b, OP={op_width}b")
    min_val = -(2**(ip_width-1))
    max_val = (2**(ip_width-1)) - 1
    
    # A = [Rows x K]
    A = np.random.randint(min_val, max_val, (rows, k_dim))
    # B = [K x Cols]
    B = np.random.randint(min_val, max_val, (k_dim, cols))
    
    # 2. Compute Golden Output (Standard Matrix Mult)
    # Result will be signed integers
    C_gold = np.matmul(A, B)
    
    # 3. Write Input Hex (A Transposed for time-step feeding)
    # Each line of hex = One time step (k)
    # Inside each line: Row 0 is LSB, Row N is MSB.
    with open("input_matrix.hex", "w") as fa:
        for k in range(k_dim):
            row_bits = 0
            for r in range(rows):
                # Mask to handle negative numbers in two's complement
                val = int(A[r, k]) & ((1 << ip_width) - 1)
                # Pack: Row 0 at bits [7:0], Row 1 at [15:8]...
                row_bits |= (val << (r * ip_width))
            
            # Format as hex string (width = rows * ip_width / 4)
            hex_chars = (rows * ip_width + 3) // 4
            fa.write(f"{row_bits:0{hex_chars}x}\n")
    
    # 4. Write Weight Hex
    # Each line of hex = One time step (k)
    # Inside each line: Col 0 is LSB, Col N is MSB.
    with open("weight_matrix.hex", "w") as fb:
        for k in range(k_dim):
            col_bits = 0
            for c in range(cols):
                val = int(B[k, c]) & ((1 << ip_width) - 1)
                col_bits |= (val << (c * ip_width))
            
            hex_chars_b = (cols * ip_width + 3) // 4
            fb.write(f"{col_bits:0{hex_chars_b}x}\n")

    # 5. Write Golden Output Hex
    # Single line containing the entire flattened result matrix.
    # Order: (0,0) is LSB, (0,1)... (Rows,Cols) is MSB.
    # Matches output_matrix[(i*cols + j)*op_width +: op_width]
    with open("golden_output.hex", "w") as fc:
        flat_C = 0
        total_bits = rows * cols * op_width
        
        for i in range(rows):
            for j in range(cols):
                # Mask to op_width (32 bits usually)
                val = int(C_gold[i, j]) & ((1 << op_width) - 1)
                # Shift based on flattened index
                shift = (i * cols + j) * op_width
                flat_C |= (val << shift)
        
        hex_chars_c = (total_bits + 3) // 4
        fc.write(f"{flat_C:0{hex_chars_c}x}\n")
        
    print("Files Generated: input_matrix.hex, weight_matrix.hex, golden_output.hex")

if __name__ == "__main__":
    # Default values match your SystemVerilog TB parameters
    parser = argparse.ArgumentParser()
    parser.add_argument("--rows", type=int, default=64)
    parser.add_argument("--cols", type=int, default=64)
    parser.add_argument("--ip_width", type=int, default=8)
    parser.add_argument("--op_width", type=int, default=32)
    parser.add_argument("--k", type=int, default=512, help="K dimension (stream length)")
    args = parser.parse_args()
    
    gen_systolic_vectors(args.rows, args.cols, args.ip_width, args.op_width, args.k)
