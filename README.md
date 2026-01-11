# Systolic Tensors

A parametric, synthesizable systolic array for matrix multiplication, written in SystemVerilog, with an automated Python/NumPy golden-model verification flow using Verilator. 

## Highlights
- Parameterized array size: `rows x cols` and stream length `k_dim`.
- Signed INT8-style inputs (configurable via `ip_width`) with wider accumulation (`op_width`).
- Deterministic, file-driven verification: generates input/weight streams + golden output, runs simulation, and checks correctness.
- Designed to scale (same PE replicated across the grid).

## Repo structure
- `systolic_array.sv` — Top-level array (skewing + PE grid + done/cycle logic)
- `mac_unit.sv` — Processing element (pipelined MAC)
- `Systolic_Array_TB.sv` — SystemVerilog testbench (file-driven)
- `Test_generator_script.py` — Generates:
  - `input_matrix.hex`
  - `weight_matrix.hex`
  - `golden_output.hex`

## Prerequisites
- Linux (recommended)
- Verilator (v5+ recommended)
- Python 3
- NumPy

## Quickstart (16x16 demo)
1) Generate vectors:
```python3 Test_generator_script.py```
2) Build + run
```
verilator --binary --timing --top-module systolic_array_tb
Systolic_Array_TB.sv systolic_array.sv mac_unit.sv

./obj_dir/Systolic_Array_TB
```

Expected output:
- `TEST PASSED! ...` on success

## Scaling up (64x64, 256x256)
- For large arrays, avoid printing the full `output_matrix` in `$display` (simulators have output formatting limits).
- If simulation becomes slow, disable tracing/wave dumps and run “blind” for PASS/FAIL.
- Prefer running very large configs on a workstation/server (more RAM + faster CPU).

## Verification methodology
- Inputs/weights are streamed for `k_dim` cycles.
- Golden output is computed in Python (NumPy `matmul`) and packed to match the RTL output layout.
- Testbench compares `output_matrix` vs `golden_output.hex` once `compute_done` asserts.

## Notes
- All arithmetic is signed end-to-end (inputs, product, sign-extension, accumulation).
- The design is written to be tool-friendly for open-source flows (Verilator/Yosys-style discipline).

## Author
- Arjun Tandon
- Github -> https://github.com/Arjun0170
- Linkedin -> https://www.linkedin.com/in/arjun-tandon-5627682b0/overlay/about-this-profile/?lipi=urn%3Ali%3Apage%3Ad_flagship3_profile_view_base%3B8ZgOSSB4SZaajuW%2BPOX%2FIA%3D%3D
