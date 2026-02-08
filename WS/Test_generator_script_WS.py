import numpy as np
import argparse

def pack_vector(vals, lane_width):
    """Pack list/1D array of signed ints into a little-endian bitvector (lane 0 = LSB)."""
    bits = 0
    mask = (1 << lane_width) - 1
    for lane, v in enumerate(vals):
        bits |= (int(v) & mask) << (lane * lane_width)
    return bits

def write_os_inputs(A, rows, ip_width, k_dim, filename="input_matrix.hex"):
    # OS: one line per k, packing A[r,k] across rows r
    hex_chars = (rows * ip_width + 3) // 4
    with open(filename, "w") as f:
        for k in range(k_dim):
            line_bits = pack_vector(A[:, k], ip_width)
            f.write(f"{line_bits:0{hex_chars}x}\n")

def write_ws_inputs(A, rows, ip_width, k_dim, filename="input_matrix.hex"):
    # WS: one line per (block, m). Each line packs A[m, k_block+i] across lanes i (0..rows-1).
    # Total lines = num_blocks * rows, where num_blocks = ceil(k_dim / rows)
    num_blocks = (k_dim + rows - 1) // rows
    hex_chars = (rows * ip_width + 3) // 4

    with open(filename, "w") as f:
        for b in range(num_blocks):
            k_block = b * rows
            for m in range(rows):
                vec = np.zeros(rows, dtype=np.int64)
                for i in range(rows):
                    kk = k_block + i
                    vec[i] = A[m, kk] if kk < k_dim else 0
                line_bits = pack_vector(vec, ip_width)
                f.write(f"{line_bits:0{hex_chars}x}\n")

def write_weights(B, cols, ip_width, k_dim, filename="weight_matrix.hex"):
    # Same for OS and WS: one line per k, packing B[k,c] across columns c
    hex_chars = (cols * ip_width + 3) // 4
    with open(filename, "w") as f:
        for k in range(k_dim):
            line_bits = pack_vector(B[k, :], ip_width)
            f.write(f"{line_bits:0{hex_chars}x}\n")

def write_golden(C_gold, rows, cols, op_width, filename="golden_output.hex"):
    # Single line: flatten (i,j) with (0,0) as LSB, matches output_matrix[(i*cols + j)*op +: op]
    total_bits = rows * cols * op_width
    hex_chars = (total_bits + 3) // 4
    mask = (1 << op_width) - 1

    flat = 0
    for i in range(rows):
        for j in range(cols):
            val = int(C_gold[i, j]) & mask
            shift = (i * cols + j) * op_width
            flat |= (val << shift)

    with open(filename, "w") as f:
        f.write(f"{flat:0{hex_chars}x}\n")

def gen_vectors(rows, cols, ip_width, op_width, k_dim, seed=None):
    if seed is not None:
        np.random.seed(seed)

    min_val = -(2 ** (ip_width - 1))
    max_val = (2 ** (ip_width - 1)) - 1

    A = np.random.randint(min_val, max_val + 1, (rows, k_dim), dtype=np.int64)
    B = np.random.randint(min_val, max_val + 1, (k_dim, cols), dtype=np.int64)
    C_gold = A @ B
    return A, B, C_gold

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--rows", type=int, default=16)
    parser.add_argument("--cols", type=int, default=16)
    parser.add_argument("--ip_width", type=int, default=8)
    parser.add_argument("--op_width", type=int, default=32)
    parser.add_argument("--k", type=int, default=128, help="K dimension")
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--flow", choices=["os", "ws", "both"], default="ws",
                        help="Generate input_matrix for OS, WS, or both (weights+golden always written).")
    args = parser.parse_args()

    rows, cols, ip_w, op_w, k_dim = args.rows, args.cols, args.ip_width, args.op_width, args.k

    print(f"Generating: rows={rows} cols={cols} ip={ip_w} op={op_w} k={k_dim} flow={args.flow}")
    A, B, C_gold = gen_vectors(rows, cols, ip_w, op_w, k_dim, seed=args.seed)

    # Always write shared files
    write_weights(B, cols, ip_w, k_dim, filename="weight_matrix.hex")
    write_golden(C_gold, rows, cols, op_w, filename="golden_output.hex")

    if args.flow == "os":
        write_os_inputs(A, rows, ip_w, k_dim, filename="input_matrix.hex")
        print("Wrote: input_matrix.hex (OS), weight_matrix.hex, golden_output.hex")

    elif args.flow == "ws":
        write_ws_inputs(A, rows, ip_w, k_dim, filename="input_matrix.hex")
        print("Wrote: input_matrix.hex (WS), weight_matrix.hex, golden_output.hex")

    else:  # both
        write_os_inputs(A, rows, ip_w, k_dim, filename="input_matrix_os.hex")
        write_ws_inputs(A, rows, ip_w, k_dim, filename="input_matrix_ws.hex")
        print("Wrote: input_matrix_os.hex, input_matrix_ws.hex, weight_matrix.hex, golden_output.hex")
