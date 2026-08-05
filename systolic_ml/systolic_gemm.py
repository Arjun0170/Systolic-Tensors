
import numpy as np


def gemm_ref(a_int8, b_int8):
    """Plain integer matmul, the ground truth. (M,K) x (K,N) -> (M,N) int32."""
    return a_int8.astype(np.int32) @ b_int8.astype(np.int32)


def os_tiled_gemm(a_int8, b_int8, rows=16, cols=16):
    """Same result as gemm_ref, but computed tile-by-tile the way a
    `rows` x `cols` output-stationary array would.

    For each (row-tile, col-tile) the array holds a rows x cols block of the
    output stationary and streams the full K dimension through it, summing
    into an int32 psum -- exactly the accumulate the PEs do in hardware.
    """
    a = a_int8.astype(np.int32)
    b = b_int8.astype(np.int32)
    M, K = a.shape
    K2, N = b.shape
    assert K == K2, "inner dimensions must match"

    c = np.zeros((M, N), dtype=np.int32)
    for i0 in range(0, M, rows):
        for j0 in range(0, N, cols):
            i1, j1 = min(i0 + rows, M), min(j0 + cols, N)
            # psum for this output tile, held stationary while K streams
            psum = np.zeros((i1 - i0, j1 - j0), dtype=np.int32)
            for k in range(K):
                # one column of A x one row of B = one MAC step, all PEs
                psum += np.outer(a[i0:i1, k], b[k, j0:j1])
            c[i0:i1, j0:j1] = psum
    return c
