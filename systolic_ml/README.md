# systolic_ml — INT8 inference on the Systolic-Tensors array

A small software layer that runs a real (if tiny) neural network through a
NumPy model of the output-stationary (OS) systolic array from this repo. The
point is co-design: the same integer matmul the Verilog array does, wrapped
around a trained MNIST classifier, so accuracy can be measured and RTL test
vectors can be generated from actual network layers.

## What it does

- Trains a 784->64->10 MLP on MNIST in PyTorch (`train_mlp.py`).
- Quantizes weights and activations to symmetric **INT8** (`quant.py`) --
  symmetric because the PE array does a plain signed multiply-accumulate with
  no zero-point datapath.
- Runs inference where **every matmul goes through the systolic-array model**
  (`systolic_gemm.py`), which computes tile-by-tile the way an output-stationary
  `rows x cols` array does, accumulating an int32 psum.
- Takes a **real network layer**, tiles its GEMM into 16x16 array passes, and
  writes each as an OS testbench case in the same `.hex` format the RTL
  generator uses (`run_on_array.py`) -- then reassembles the result and checks
  it is bit-exact.

## Result

```
float  test accuracy: 97.36%
int8   test accuracy: 97.35%   (delta -0.01 pts)
check: systolic GEMM == plain integer matmul  (bit-exact)

layer fc1:  16x784 @ 784x64  ->  4 array tiles of 16x16 (K=784 streamed each)
reassembled result == plain integer matmul:  True  (bit-exact)
```

INT8 tracks float to within noise, the array model is bit-exact against a plain
integer matmul, and a real layer tiled across the array reassembles exactly --
so the Python model and the hardware compute the same numbers.

## Run it

```bash
pip install -r requirements.txt
python train_mlp.py       # -> mlp_weights.npz  (float accuracy)
python infer_int8.py      # -> int8 accuracy through the array model
python run_on_array.py    # -> rtl_cases/  real layer tiled into 16x16 cases
```

## Files

| file | what it is |
|------|------------|
| `mnist.py` | dependency-free MNIST loader (four `.gz` files) |
| `quant.py` | symmetric INT8 quantize / dequantize / requantize |
| `systolic_gemm.py` | NumPy model of the OS array's INT8 GEMM + reference |
| `train_mlp.py` | PyTorch MLP trainer, exports weights to `.npz` |
| `infer_int8.py` | full INT8 inference through the array model |
| `run_on_array.py` | tile a real layer into 16x16 array cases, reassemble, verify |

## Relationship to the RTL testbench

The `.hex` files under `rtl_cases/` are in the OS testbench format
(`input_matrix.hex`, `weight_matrix.hex`, `golden_output.hex`). Point the OS
testbench at any one tile (rows=16, cols=16, k_dim=784) to replay it in
simulation. The difference from `OS/test_generator_script_os.py` is only the
*source* of the matrices: that generator packs random A/B, this packs A/B from
a real quantized network layer.

### Using your own generator

`run_on_array.py` reuses the repo's own packing. On import it looks for
`WS/test_generator_script_ws.py` (which exposes `write_os_inputs`,
`write_weights`, and `write_golden`) and, when found, writes every tile with
those functions -- so there is no duplicate hex logic in the repo. Run outside
the repo and it falls back to a local packer that is byte-identical to those
functions (verified). Nothing to configure either way.
