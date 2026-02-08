# Systolic Tensors

A parametric, synthesizable systolic array for matrix multiplication, written in **SystemVerilog**, with an automated **Python/NumPy golden-model verification** flow using **Verilator**.

This repo contains **two dataflows**:
- **OS (Output-Stationary)**
- **WS (Weight-Stationary)**

---

## Highlights
- Parameterized array size: `rows x cols` and stream length `k_dim`.
- Signed INT8-style operands (configurable via `ip_width`) with wider signed accumulation (`op_width`).
- Deterministic, file-driven verification: Python generates vectors + golden output, TB streams them and checks correctness.
- Designed to scale (same PE replicated across the grid).

---

## Repo structure

### OS/
- `systolic_array_os.sv` — OS top-level array (skew + PE grid + done/cycle logic)
- `mac_unit_os.sv` — OS PE (pipelined MAC, local accumulation)
- `systolic_array_os_tb.sv` — OS testbench (file-driven)
- `gen.py` — Python generator (OS format)

### WS/
- `systolic_array_ws.sv` — WS top-level array (weight-load + skew + PE grid + done/cycle logic)
- `mac_unit_ws.sv` — WS PE (stationary weight reg + pipelined compute + vertical psum)
- `systolic_array_ws_tb.sv` — WS testbench (tiling + skew-aware capture)
- `gen.py` — Python generator (WS format)

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

---

## Quickstart — OS (example: 64×64, k=128)

### 1) Generate vectors
Run from the `OS/` directory (script name may differ):
```bash
cd OS
python3 gen.py
```

### 2) Build + run (Verilator)
```bash
verilator -Wall --binary -sv --timing \
  --top-module systolic_array_os_tb \
  systolic_array_os_tb.sv systolic_array_os.sv mac_unit_os.sv

./obj_dir/Vsystolic_array_os_tb
```

**Expected:**
- `TEST PASSED! ...`

---

## Quickstart — WS (example: 16×16, k=128)

### 1) Generate vectors
Run from the `WS/` directory (script name may differ):
```bash
cd WS
python3 gen.py --rows 16 --cols 16 --ip_width 8 --op_width 32 --k 128 --seed 1
```

### 2) Build + run (Verilator)
```bash
verilator -Wall --binary -sv --timing \
  --top-module systolic_array_ws_tb \
  systolic_array_ws_tb.sv systolic_array_ws.sv mac_unit_ws.sv

./obj_dir/Vsystolic_array_ws_tb
```

**Expected:**
- `WS TEST PASSED! ...`

---

## Notes on scaling
- For large sizes (64×64 and above), avoid `$display` of the full packed output (console formatting becomes a bottleneck).
- Disable waveform dumps unless debugging.
- WS uses K-tiling with tile size = `rows`. Simulation time grows quickly with array size.
- If building in a directory with spaces, Verilator+Make may fail. Build/run from a path **without spaces**.

---

## Verification methodology
Python generates random signed matrices:
- `A = [rows x k_dim]`
- `B = [k_dim x cols]`

Golden:
- `C_gold = A @ B`

The generator packs:
- `input_matrix.hex` / `weight_matrix.hex` to match the RTL streaming format
- `golden_output.hex` to match RTL packed output layout  
  (element `(i,j)` stored at bit offset `(i*cols + j) * op_width`)

---

## Author
Arjun Tandon  
GitHub: https://github.com/Arjun0170  
LinkedIn: https://www.linkedin.com/in/arjun-tandon-5627682b0  

<img width="1920" height="1080" alt="Screenshot from 2026-01-21 10-45-46" src="https://github.com/user-attachments/assets/cba468cf-5b55-42a7-a4cc-213aec45b4ae" />
<img width="1920" height="1080" alt="Screenshot from 2026-01-21 11-02-46" src="https://github.com/user-attachments/assets/c4af0b99-e70d-4dfe-a8b6-f94cfa7fe8ad" />

