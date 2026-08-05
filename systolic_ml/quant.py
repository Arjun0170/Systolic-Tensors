
import numpy as np

QMIN, QMAX = -127, 127


def quantize_tensor(x):
    """Float tensor -> (int8 array, scale). Symmetric, per-tensor."""
    max_abs = float(np.max(np.abs(x)))
    scale = max_abs / QMAX if max_abs > 0 else 1.0
    q = np.round(x / scale)
    q = np.clip(q, QMIN, QMAX).astype(np.int8)
    return q, scale


def dequantize(q, scale):
    return q.astype(np.float32) * scale


def requantize(acc_int32, m, out_zero=0):
    out = np.round(acc_int32.astype(np.float64) * m) + out_zero
    return np.clip(out, QMIN, QMAX).astype(np.int8)
