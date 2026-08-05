
import numpy as np

from mnist import load_mnist
from quant import quantize_tensor, requantize, QMIN, QMAX
from systolic_gemm import os_tiled_gemm


def quantize_layer(x_f, w_f, b_f, relu, s_out):

    x_q, sx = quantize_tensor(x_f)
    w_q, sw = quantize_tensor(w_f)

    acc = os_tiled_gemm(x_q, w_q)                 # int32, the array's output
    # bias lives at the accumulator scale sx*sw, so quantize it to int32 there
    b_q = np.round(b_f / (sx * sw)).astype(np.int32)
    acc = acc + b_q[None, :]

    if s_out is None:
        # final layer: just return real-valued logits for argmax
        return acc.astype(np.float32) * (sx * sw), None

    m = (sx * sw) / s_out
    lo = 0 if relu else QMIN                       # ReLU folded into the clamp
    out = np.round(acc.astype(np.float64) * m)
    out = np.clip(out, lo, QMAX).astype(np.int8)
    return out, s_out


def main():
    w = np.load("mlp_weights.npz")
    _, _, x_te, y_te = load_mnist()

    # pick per-layer output scales from a small calibration batch, so the
    # requantized int8 covers the real activation range.
    cal = x_te[:512]
    h1_f = np.maximum(cal @ w["w1"] + w["b1"], 0.0)
    s_h1 = float(np.max(np.abs(h1_f))) / QMAX

    # run the full test set in int8
    x = x_te
    h1, _ = quantize_layer(x, w["w1"], w["b1"], relu=True, s_out=s_h1)
    h1_deq = h1.astype(np.float32) * s_h1
    logits, _ = quantize_layer(h1_deq, w["w2"], w["b2"], relu=False, s_out=None)
    acc_int8 = float((logits.argmax(1) == y_te).mean())

    # float reference for comparison
    hf = np.maximum(x_te @ w["w1"] + w["b1"], 0.0)
    lf = hf @ w["w2"] + w["b2"]
    acc_float = float((lf.argmax(1) == y_te).mean())

    print(f"float  test accuracy: {acc_float * 100:.2f}%")
    print(f"int8   test accuracy: {acc_int8 * 100:.2f}%  "
          f"(delta {(acc_int8 - acc_float) * 100:+.2f} pts)")

    # sanity: the array model must equal a plain integer matmul
    from systolic_gemm import gemm_ref
    xq, _ = quantize_tensor(x_te[:100])
    wq, _ = quantize_tensor(w["w1"])
    assert np.array_equal(os_tiled_gemm(xq, wq), gemm_ref(xq, wq))
    print("check: systolic GEMM == plain integer matmul  (bit-exact)")


if __name__ == "__main__":
    main()
