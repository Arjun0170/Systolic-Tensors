
import json
import os

import numpy as np

from mnist import load_mnist
from quant import quantize_tensor
from systolic_gemm import gemm_ref

ROWS = COLS = 16          # array size
N_IMG = 16                # one row-tile of images; raise to tile more
OUT_DIR = "rtl_cases"
OP_WIDTH = 48             # OS accumulator width (matches the OS golden format)

# below, which is byte-identical to those functions (verified).
try:
    import sys
    sys.path.append("../WS")
    from test_generator_script_ws import (
        write_os_inputs as _his_inputs,
        write_weights as _his_weights,
        write_golden as _his_golden,
    )
    _USE_REPO_GEN = True
except Exception:
    _USE_REPO_GEN = False


# --- fallback hex packing: same format as the repo generator ----------------
def _pack(vals, lane_width):
    """Pack signed ints into one little-endian bitvector (lane 0 = LSB)."""
    bits, mask = 0, (1 << lane_width) - 1
    for lane, v in enumerate(vals):
        bits |= (int(v) & mask) << (lane * lane_width)
    return bits


def write_os_case(A, B, case_dir, ip_width=8, op_width=48):
    """A [rows x K] int8, B [K x cols] int8 -> OS testbench .hex files."""
    rows, K = A.shape
    cols = B.shape[1]
    os.makedirs(case_dir, exist_ok=True)

    hc_in = (rows * ip_width + 3) // 4
    with open(f"{case_dir}/input_matrix.hex", "w") as f:
        for k in range(K):
            f.write(f"{_pack(A[:, k], ip_width):0{hc_in}x}\n")

    hc_w = (cols * ip_width + 3) // 4
    with open(f"{case_dir}/weight_matrix.hex", "w") as f:
        for k in range(K):
            f.write(f"{_pack(B[k, :], ip_width):0{hc_w}x}\n")

    C = A.astype(np.int64) @ B.astype(np.int64)
    assert np.abs(C).max() < (1 << (op_width - 1)), "op_width too small"
    mask, flat = (1 << op_width) - 1, 0
    for i in range(rows):
        for j in range(cols):
            flat |= (int(C[i, j]) & mask) << ((i * cols + j) * op_width)
    hc_g = (rows * cols * op_width + 3) // 4
    with open(f"{case_dir}/golden_output.hex", "w") as f:
        f.write(f"{flat:0{hc_g}x}\n")
    return C
# ---------------------------------------------------------------------------


def main():
    w = np.load("mlp_weights.npz")
    _, _, x_te, _ = load_mnist()

    # layer GEMM:  A [N_IMG x 784]  @  W1 [784 x 64]  ->  [N_IMG x 64]
    a_q, _ = quantize_tensor(x_te[:N_IMG])
    w_q, _ = quantize_tensor(w["w1"])
    a_q = a_q.astype(np.int64)
    w_q = w_q.astype(np.int64)

    M, K = a_q.shape
    N = w_q.shape[1]
    gold_full = gemm_ref(a_q, w_q)                 # reference to check against
    recon = np.zeros((M, N), dtype=np.int64)       # rebuilt from the tiles

    os.makedirs(OUT_DIR, exist_ok=True)
    tiles = []
    for i0 in range(0, M, ROWS):
        for j0 in range(0, N, COLS):
            i1, j1 = min(i0 + ROWS, M), min(j0 + COLS, N)

            # build a padded 16x16 array case (zeros are exact under zp=0)
            A_tile = np.zeros((ROWS, K), dtype=np.int64)
            B_tile = np.zeros((K, COLS), dtype=np.int64)
            A_tile[: i1 - i0, :] = a_q[i0:i1, :]
            B_tile[:, : j1 - j0] = w_q[:, j0:j1]

            case_dir = os.path.join(OUT_DIR, f"tile_r{i0}_c{j0}")
            if _USE_REPO_GEN:
                os.makedirs(case_dir, exist_ok=True)
                C_tile = A_tile @ B_tile
                _his_inputs(A_tile, ROWS, 8, K, f"{case_dir}/input_matrix.hex")
                _his_weights(B_tile, COLS, 8, K, f"{case_dir}/weight_matrix.hex")
                _his_golden(C_tile, ROWS, COLS, OP_WIDTH,
                            f"{case_dir}/golden_output.hex")
            else:
                C_tile = write_os_case(A_tile, B_tile, case_dir)

            recon[i0:i1, j0:j1] = C_tile[: i1 - i0, : j1 - j0]
            tiles.append({
                "dir": case_dir, "row0": i0, "col0": j0,
                "valid_rows": i1 - i0, "valid_cols": j1 - j0,
                "k_dim": K, "rows": ROWS, "cols": COLS,
            })

    manifest = {"layer": "fc1", "M": M, "K": K, "N": N,
                "array": [ROWS, COLS], "n_tiles": len(tiles), "tiles": tiles}
    with open(os.path.join(OUT_DIR, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)

    ok = np.array_equal(recon, gold_full)
    print(f"layer fc1:  {M}x{K} @ {K}x{N}  ->  {len(tiles)} array tiles "
          f"of {ROWS}x{COLS} (K={K} streamed each)")
    print(f"wrote {len(tiles)} OS testbench cases under {OUT_DIR}/")
    print(f"reassembled result == plain integer matmul:  {ok}  (bit-exact)")
    if not ok:
        raise SystemExit("MISMATCH -- tiling is wrong")


if __name__ == "__main__":
    main()
