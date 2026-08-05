# Systolic Tensors

**A hardware/software co-design of an INT8 GEMM accelerator:** parameterized,
synthesizable systolic arrays in **SystemVerilog** (two dataflows), plus a
**Python inference layer** that trains a real neural network, quantizes it to
INT8, and runs it through a faithful model of the array — proving the hardware
is not just arithmetically correct, but actually usable for ML inference.

- **Hardware** — Output-Stationary (OS) and Weight-Stationary (WS) INT8 GEMM
  arrays, verified against a NumPy golden model in **Cadence Xcelium/SimVision**.
- **Software** — an INT8 quantization + inference runtime (`systolic_ml/`) that
  maps a trained MNIST classifier onto the array's exact integer math and
  generates real-workload test vectors for the RTL testbench.

The two halves are decoupled by a single interface — the packed INT8 / HEX
tile format — the same way a real NPU is decoupled from its driver stack.

---

## Headline results

```
float  test accuracy: 97.37%
int8   test accuracy: 97.37%     (delta +0.00 pts)   <- INT8 with no accuracy loss
systolic GEMM == plain integer matmul                (bit-exact)
real fc1 layer -> 4 array tiles of 16x16, reassembled (bit-exact)
```

INT8 quantization costs no measurable accuracy on this network, the NumPy array
model is bit-exact against a reference integer matmul, and a real network layer
tiled across a 16×16 array reassembles exactly — so the software model and the
hardware compute the same numbers.

---

## What this repo contains

At its core the project implements matrix multiplication on a systolic array:

- **A**: `[rows × k_dim]`  — signed INT8 inputs (activations)
- **B**: `[k_dim × cols]`  — signed INT8 weights
- **C = A × B**: `[rows × cols]` — wider (INT32) accumulation

The RTL is written as reusable generators parameterized by `rows`, `cols`
(array size), `ip_width` (input bit-width, typically 8), `op_width`
(accumulator/output width), `k_dim` (GEMM K / stream length), and `pipe_lat`
(pipeline latency inside the PE/MAC). Tested from **8×8 up to 256×256**, and
parameterized beyond.

The software layer then wraps that array in the pieces a real accelerator needs
around its MAC engine — quantization, layer tiling, requantization, and
inference — and reuses the repo's own HEX packing to feed the RTL testbench.

---

## Repo structure

```
Systolic-Tensors/
├── OS/                          Output-Stationary RTL + generator
├── WS/                          Weight-Stationary RTL + generator
├── systolic_ml/                 INT8 inference + software model of the array
├── LICENSE
└── README.md
```

**OS/**
- `mac_unit_os.sv` — pipelined INT8 MAC PE (local accumulation)
- `systolic_array_os.sv` — OS array top (skew + PE grid + done/cycle logic)
- `systolic_array_os_tb.sv` — file-driven OS testbench
- `test_generator_script_os.py` — generator for OS inputs/weights/golden

**WS/**
- `mac_unit_ws.sv` — WS PE (stationary weight + vertical psum accumulate)
- `systolic_array_ws.sv` — WS array top (row skew + psum top skew + PE grid)
- `systolic_array_ws_tb.sv` — WS tiled testbench (load/compute/capture per K-tile)
- `test_generator_script_ws.py` — generator for WS tiled stimulus + golden

**systolic_ml/**
- `quant.py` — symmetric INT8 quantize / dequantize / requantize
- `systolic_gemm.py` — NumPy model of the OS array's INT8 GEMM + reference
- `train_mlp.py` — PyTorch MLP trainer (784→64→10), exports weights to `.npz`
- `infer_int8.py` — full INT8 inference through the array model
- `run_on_array.py` — tile a real layer into 16×16 array cases, reassemble, verify
- `mnist.py` — dependency-free MNIST loader

---

## Design overview (hardware)

### 1) Output-Stationary (OS)

OS keeps the partial sum **inside each PE** while operands stream through.

- **Operand pass-through**: activations/weights propagate across the array.
- **Local accumulation**: each PE accumulates its own output element.
- **Wavefront alignment**: row/column skew buffers keep timing correct at large `N`.
- Simple streaming interface: `en`/`clr` token control + packed input/weight vectors.

### 2) Weight-Stationary (WS)

WS holds weights stationary inside each PE and streams partial sums vertically.

- **Explicit weight-load phase**: a stationary weight register per PE, filled by
  vertical weight shifting during load.
- **Vertical PSUM streaming** during compute.
- **K-tiling**: tile size = `rows`; partial sums are **re-injected across tiles**
  via `psum_init_vec`.
- Skew-aware injection/capture keeps timing correct across tiles.

---

## The software layer (`systolic_ml/`)

The RTL proves the array multiplies matrices correctly. It says nothing about
whether that array can run a neural network — whether INT8 quantization holds
accuracy, whether the accumulator is wide enough, or how a real layer maps onto
a fixed grid. The software layer answers exactly those questions, and doubles as
the runtime that would drive the array in a real system.

**Symmetric INT8, because the hardware is signed.** The PEs do a plain signed
multiply-accumulate with no zero-point datapath, so activations and weights are
quantized *symmetrically* (`scale = max(|x|)/127`, zero maps to integer 0). That
keeps every layer a clean integer matmul — precisely what the array computes.

**Inference through the array model.** `systolic_gemm.py` reproduces the OS
array's computation in NumPy: each output element is held stationary while the K
dimension streams through, accumulating an INT32 psum, tiled the way a physical
`rows × cols` array tiles a larger matmul. `infer_int8.py` runs a trained MLP
end to end through this model — quantize, integer matmul, requantize between
layers — and asserts the result is **bit-exact** against a plain integer matmul.

**Real layers → RTL test vectors.** `run_on_array.py` takes an actual quantized
layer, tiles its GEMM into 16×16 array passes, reassembles the result
(bit-exact), and writes each tile as an OS testbench case. It reuses the repo's
own packing functions, so the vectors are **byte-identical** to those from
`test_generator_script_*.py` — the only difference is the *source*: a real MNIST
layer instead of random matrices.

---

## How the two halves fit together

```
   PyTorch train ──► INT8 quantize ──► tile to array size ──► INT8 GEMM ──► requant
        (software runtime: systolic_ml/)                          │
                                                                  │  packed INT8 / HEX
                                                                  ▼
                                              OS / WS RTL array  (SystemVerilog)
                                              verified in Xcelium vs golden HEX
```

The array is the **compute engine**; the software is the **quantization + tiling
runtime**. They meet only at the INT8/HEX tile interface — the same separation
a real NPU has from its driver. Because of that clean boundary, each side is
verified independently: the software self-checks against a golden model in pure
Python, and the RTL is checked against golden HEX in Xcelium.

---

## Verification

**Hardware (Xcelium).** File-driven and deterministic:
1. Python generates signed matrices `A`, `B` (random, or a real network layer).
2. NumPy computes the golden reference `C_gold = A @ B`.
3. Python packs streams into `input_matrix.hex`, `weight_matrix.hex`,
   `golden_output.hex`.
4. Xcelium testbenches load the HEX with `$readmemh`, run the design, and
   compare — OS at `compute_done`; WS across tiled blocks with skew-aware
   capture. Debug via **SimVision** with cycle-level latency accounting.

**Software (pure Python).** `infer_int8.py` and `run_on_array.py` self-verify
against a NumPy reference — INT8 accuracy vs float, and bit-exactness of the
tiled array model — with no RTL simulator required. This makes the software
independently testable, then able to emit workload-representative vectors that
close the loop with the hardware in Xcelium.

---

## How to run

### Hardware vectors + simulation
```bash
# from OS/ or WS/, generate stimulus (random matrices)
python test_generator_script_os.py            # or: python test_generator_script_ws.py --flow ws
# then run the matching testbench in Xcelium against the generated .hex
```

### Software layer
```bash
cd systolic_ml
python3 -m venv venv && source venv/bin/activate      # (fish: source venv/bin/activate.fish)
pip install numpy
pip install torch --index-url https://download.pytorch.org/whl/cpu

python train_mlp.py       # trains the MLP, saves mlp_weights.npz, prints float accuracy
python infer_int8.py      # INT8 inference through the array model (bit-exact check)
python run_on_array.py    # tiles a real layer into 16x16 OS testbench cases
```

`run_on_array.py` writes `rtl_cases/tile_r*_c*/` — real MNIST-layer vectors in
the OS testbench format, ready to replay through the RTL.

---

## Implementation choices

- **Signed arithmetic end-to-end** in hardware (inputs, product, sign-extension,
  accumulation); **symmetric INT8** in software to match it.
- **INT32 accumulation**: products of two INT8 values sum over K, so the psum bus
  is widened to avoid overflow — the software model carries the same width.
- **Explicit pipeline staging** inside PEs for timing-friendly RTL.
- **Wavefront-correct skewing** designed to scale with `N` without rewriting RTL.
- **Sweep-safe completion logic** (`compute_done`, `cycles_count`) for automated
  experiments.

## Roadmap

- Fixed-point (integer-only) requantization to match CMSIS-NN / Ethos-U exactly.
- WS-format vector export from real layers (currently OS).
- RTL/software co-simulation (drive the actual RTL from the Python runtime).
- Convolutional layers via im2col (each conv lowered to one GEMM).

---

## Author

**Arjun Tandon**
GitHub: `github.com/Arjun0170`
LinkedIn: `linkedin.com/in/arjun-tandon-5627682b0`
