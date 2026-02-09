# Systolic Tensors

Parameterized, synthesizable **INT8 GEMM systolic arrays** in **SystemVerilog**, implementing **two dataflows**:
- **Output-Stationary (OS)**
- **Weight-Stationary (WS)**

Both designs are verified using a **Python/NumPy golden model** and **Cadence Xcelium/SimVision**.

---

## What this repo contains

This project implements matrix multiplication:

- **A**: `[rows × k_dim]`  (signed INT8-style inputs, configurable)
- **B**: `[k_dim × cols]`  (signed INT8-style weights, configurable)
- **C = A × B**: `[rows × cols]` (wider accumulation)

The core is written as reusable generators parameterized by:
- `rows`, `cols`  → array size `N×N`
- `ip_width`      → input bit-width (typically 8)
- `op_width`      → accumulator/output width
- `k_dim`         → GEMM K dimension (stream length)
- `pipe_lat`      → pipeline latency inside the PE/MAC

Supported scales (tested): **8×8 → 256×256** (parameterized beyond).

---

## Design overview

### 1) Output-Stationary (OS)
OS keeps the partial sum **inside each PE** while operands stream through.

**Key points**
- **Operand pass-through**: activations/weights propagate across the array.
- **Local accumulation**: each PE accumulates its own output element.
- **Wavefront alignment**: row/column skew buffers ensure correct timing alignment at large `N`.
- Simple streaming interface: `en/clr` token control + packed input/weight vectors.

---

### 2) Weight-Stationary (WS)
WS holds weights stationary inside each PE and streams partial sums vertically.

**Key points**
- **Explicit weight-load phase**:
  - stationary weight register per PE
  - vertical weight shifting during load
- **Vertical PSUM streaming** during compute
- **K-tiling support**:
  - tile size = `rows`
  - partial sums are **re-injected across tiles** via `psum_init_vec`
- Timing-correct behavior maintained via skew-aware injection/capture handling.

---

## Repo structure 

**OS/**
- `mac_unit_os.sv` — pipelined INT8 MAC PE (local accumulation)
- `systolic_array_os.sv` — OS array top (skew + PE grid + done/cycle logic)
- `systolic_array_os_tb.sv` — file-driven OS testbench
- `test_generator_script_os.py` — Python generator for OS inputs/weights/golden

**WS/**
- `mac_unit_ws.sv` — WS PE (stationary weight + vertical psum accumulate)
- `systolic_array_ws.sv` — WS array top (row skew + psum top skew + PE grid)
- `systolic_array_ws_tb.sv` — WS tiled testbench (load/compute/capture per K-tile)
- `test_generator_script_ws.py` — Python generator for WS tiled stimulus + golden

---

## Verification methodology (Xcelium)

Verification is **file-driven and deterministic**:
1. Python generates random signed matrices `A` and `B`.
2. NumPy computes the golden reference:
   - `C_gold = A @ B`
3. Python packs streams into HEX files:
   - `input_matrix.hex`
   - `weight_matrix.hex`
   - `golden_output.hex`
4. Xcelium testbenches load HEX files with `$readmemh`, run the design, and compare:
   - OS compares the full packed output at `compute_done`.
   - WS runs tiled blocks, reinjects partial sums, captures the bottom-row results with skew-aware timing, and compares final packed output.

Debug was performed using **Cadence SimVision** with cycle-level latency accounting and boundary-condition validation.

---

## Notes / Implementation choices

- **Signed arithmetic end-to-end** (inputs, product, sign-extension, accumulation).
- **Explicit pipeline staging** inside PEs for timing-friendly RTL.
- **Wavefront-correct skewing** designed to scale without rewriting RTL.
- **Completion logic** (`compute_done`, `cycles_count`) is designed to be sweep-safe for automated experiments.

---

## Author

**Arjun Tandon**  
GitHub: `github.com/Arjun0170`  
LinkedIn: `linkedin.com/in/arjun-tandon-5627682b0`
