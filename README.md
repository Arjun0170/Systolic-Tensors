# Systolic Tensors

A parametric, synthesizable systolic-array RTL for matrix multiplication in SystemVerilog, featuring **both**:
- **Output-Stationary (OS)**
- **Weight-Stationary (WS)**

Verification is automated via a **Python/NumPy golden model** + **file-driven SystemVerilog testbenches** using **Verilator**/**Cadence Xcelium**.

---

## Highlights
- Parameterized array size: `rows x cols` and stream length `k_dim`.
- Signed INT8-style operands (configurable via `ip_width`) with wider signed accumulation (`op_width`).
- Deterministic verification:
  - Python generates `input_matrix.hex`, `weight_matrix.hex`, `golden_output.hex`
  - Testbench streams tokens, waits for `compute_done`, then checks the packed output.
- Same PE replicated across the grid (clean scaling from small to large sizes).
- Two dataflow variants (OS + WS) to compare behavior/latency under the same harness.

---

## Dataflows implemented

### Output-Stationary (OS)
- `x` streams left → right  
- `w` streams top → bottom  
- Each PE holds its own accumulator locally (`mac_out`).

**Input protocol**
- For `k = 0 .. k_dim-1`, drive `en=1`
- Assert `clr=1` only on the first token (`k==0`)
- Drop `en` after feed and wait for `compute_done`

### Weight-Stationary (WS)
- Weights are loaded top → bottom, then held in a PE-local register.
- `x` streams left → right
- Partial sums (`psum`) stream top → bottom
- Supports **K-tiling** via `psum_init_vec` injected per output-row token.

**Input protocol (per K-tile block, tile size = `rows`)**
1. **LOAD** phase (`en=1, clr=1`): shift weights down for `rows` cycles (reverse order inside the tile)
2. **COMPUTE** phase (`en=1, clr=0`): feed `rows` tokens and inject `psum_init_vec` per token
3. **DRAIN** phase (`en=0`): drain/capture skewed outputs (handled in the WS TB)

---

## Repo structure
- `OS/`
  - `systolic_array_os.sv` — OS top-level array (skew + PE grid + done/cycle logic)
  - `mac_unit_os.sv` — OS PE (pipelined MAC + local accumulation)
  - `systolic_array_os_tb.sv` — OS testbench (file-driven)
  - `test_generator_script_os.py` (or your OS generator) — generates OS-formatted `input_matrix.hex`

- `WS/`
  - `systolic_array_ws.sv` — WS top-level array (row skew + psum skew + PE grid + done/cycle logic)
  - `mac_unit_ws.sv` — WS PE (stationary weight register + pipelined compute + vertical psum)
  - `systolic_array_ws_tb.sv` — WS testbench (block-wise load + compute + skew-aware capture)
  - `test_generator_script_ws.py` (or your WS generator) — generates WS-formatted `input_matrix.hex`

---

## Prerequisites
- Linux (recommended)
- Verilator (v5+ recommended)
- Python 3
- NumPy

Install NumPy:
```bash
python3 -m pip install numpy
```
#Quickstart — OS (example: 64x64, k=512)
1) Generate vectors

From the OS/ folder:
```
cd OS
python3 test_generator_script_os.py
```
2) Build + run (Verilator)
```
verilator -Wall --binary -sv --timing \
  --top-module systolic_array_os_tb \
  systolic_array_os_tb.sv systolic_array_os.sv mac_unit_os.sv

./obj_dir/systolic_array_os_tb
```

Expected output:
- `TEST PASSED! ...` on success

#Quickstart — WS (example: 64X64, k=512)
1) Generate vectors

From the WS/ folder:
```
cd WS
python3 test_generator_script_ws.py --rows 16 --cols 16 --ip_width 8 --op_width 32 --k 128 --seed 1
```
2) Build + run (Verilator)
```
verilator -Wall --binary -sv --timing \
  --top-module systolic_array_ws_tb \
  systolic_array_ws_tb.sv systolic_array_ws.sv mac_unit_ws.sv

./obj_dir/Vsystolic_array_ws_tb
```
Expected output:
- `TEST PASSED! ...` on success

## Notes on scaling

For large sizes (64×64 and above), avoid $display of the full packed output (console formatting becomes a bottleneck).

Disable waveform dumps unless debugging.

WS uses K-tiling with tile size = rows. Simulation time grows quickly with array size.

If building in a directory with spaces, Verilator+Make may fail. Build/run from a path without spaces.

## Verification methodology

Python generates random signed matrices:

A = [rows x k_dim]

B = [k_dim x cols]

Golden:

C_gold = A @ B (NumPy int64)

Packed into golden_output.hex to match RTL layout:

element (i,j) stored at bit offset (i*cols + j) * op_width

Testbenches:

stream inputs/weights according to the dataflow protocol

wait for compute_done

compare packed outputs against golden
## Notes
- All arithmetic is signed end-to-end (inputs, product, sign-extension, accumulation).
- The design is written to be tool-friendly for open-source flows (Verilator/Yosys-style discipline).

## Author
- Arjun Tandon
- Github -> https://github.com/Arjun0170
- Linkedin ->https://www.linkedin.com/in/arjun-tandon-5627682b0
<img width="1920" height="1080" alt="Screenshot from 2026-01-21 10-45-46" src="https://github.com/user-attachments/assets/cba468cf-5b55-42a7-a4cc-213aec45b4ae" />
<img width="1920" height="1080" alt="Screenshot from 2026-01-21 11-02-46" src="https://github.com/user-attachments/assets/c4af0b99-e70d-4dfe-a8b6-f94cfa7fe8ad" />
