# RISCV_Minimal — RV32IM 5-Stage Pipelined SoC

<p align="center">
  <img src="https://img.shields.io/badge/RISC--V-RV32IM-283593?style=for-the-badge&logo=riscv&logoColor=white" alt="RISC-V RV32IM"/>
  <img src="https://img.shields.io/badge/SystemVerilog-RTL-EC1628?style=for-the-badge&logo=hardware&logoColor=white" alt="SystemVerilog"/>
  <img src="https://img.shields.io/badge/5--Stage-Pipeline-00838F?style=for-the-badge" alt="5-Stage Pipeline"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/FPGA-Cyclone_II-1976D2?style=flat-square&logo=intel&logoColor=white" alt="Cyclone II"/>
  <img src="https://img.shields.io/badge/Synth-Intel_Quartus-00ACC1?style=flat-square" alt="Quartus"/>
  <img src="https://img.shields.io/badge/BRAM-Inferred-5C6BC0?style=flat-square" alt="BRAM"/>
  <img src="https://img.shields.io/badge/Sim-ModelSim_10.1d-7B1FA2?style=flat-square" alt="ModelSim"/>
  <img src="https://img.shields.io/badge/Sim-Icarus_Verilog-D32F2F?style=flat-square" alt="Icarus"/>
  <img src="https://img.shields.io/badge/Ref-Spike_ISS-388E3C?style=flat-square" alt="Spike"/>
  <img src="https://img.shields.io/badge/Scripting-Python_3-3776AB?style=flat-square&logo=python&logoColor=white" alt="Python"/>
  <img src="https://img.shields.io/badge/ASM-RV32IM_toolchain-455A64?style=flat-square" alt="Toolchain"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Branch_Pred-BHT_%2B_BTB-FF8F00?style=flat-square" alt="Branch Predictor"/>
  <img src="https://img.shields.io/badge/Hazards-Forwarding_%2B_Stall-6A1B9A?style=flat-square" alt="Hazards"/>
  <img src="https://img.shields.io/badge/M--Ext-Non--Blocking_MUL%2FDIV-00695C?style=flat-square" alt="M-Extension"/>
  <img src="https://img.shields.io/badge/Verify-Directed_Self--Checking-2E7D32?style=flat-square" alt="Verification"/>
  <img src="https://img.shields.io/badge/Tests-50%2F55_PASS-43A047?style=flat-square" alt="Tests"/>
</p>

A BRAM-realistic, FPGA-synthesizable **RV32IM** 5-stage pipelined core (IF–ID–EX–MEM–WB) with branch prediction, hazard/forwarding, and a non-blocking M-extension unit, plus self-checking SystemVerilog testbenches and a Spike golden-reference flow.

> **For detailed results, please visit the `outcome/` folder.**
> It is the frozen, evidence-backed showcase: ISA coverage (`01_isa_coverage.md`), verification methodology (`02_...`), pass/fail tables (`03_test_results.md`), corner cases (`04_...`), RTL achievements (`05_...`), impact/next steps (`06_...`), logs, VCDs, and frozen testbenches. Start at [`outcome/README.md`](outcome/README.md).

## Headline status (frozen 2026-09-08)

- `tb_soc_final`: **50/55 PASS** — Phase 1 (correctness) **33/33**, Phase 2 (hazards) 8/11, Phase 3 (non-blocking M) 7/11.
- Byte/halfword lanes (`tb_load_store_offsets`): **21/21 PASS**.
- Core smoke: **38/38 PASS** · SoC smoke: **29/29 PASS** · M-unit: **20/21 PASS** (1 open `MULHSU` corner).
- Singular RTL `soc_top.sv`: `vlog -sv` 0 errors, Quartus analysis+elaboration 0 errors (Cyclone II `EP2C35F672C6`).
- 5 frozen-open fails are load/MUL timing assumptions, not byte-lane bugs. 1 `MULHSU` signed×unsigned bug open. See `outcome/03_test_results.md`.

## Architecture

```
instr_mem ──► IF (PC + BHT/BTB predictor) ──► IF/ID ──► ID (decoder + regfile)
  ──► ID/EX ──► EX (ALU + branch resolve + muldiv launch, forwarding muxes)
  ──► EX/MEM ──► MEM (byte-enabled data_mem) ──► MEM/WB ──► WB (ALU/MEM/PC+4/IMM + MUL bypass)
```

- **Core:** `soc_top.sv` (singular, synthesis/single-file reference, TOP `soc_top`; ~2128 lines, 21 design units).
- **Units:** `alu`, `decoder` (RV32I + M funct7=`0000001`), `regfile` (2R1W + debug port), `hazard_unit` (4-way forward `REGFILE < MEM_WB < EX_MEM < MULDIV`, load-use stall, M scoreboard RAW/WAW/structural + `wb_conflict`), `branch_predictor` (64-entry BHT 2-bit saturating + BTB, `PC[7:2]`), `muldiv_unit` (iterative 32-cycle shift-add MUL + non-restoring DIV, busy/done handshake, RISC-V div-by-zero/overflow semantics).
- **Memories:** registered `instr_mem` / `data_mem` (BRAM-inferable, byte enables, `rdata_shifted` load alignment). Deliberately kept registered — no combinational-read shortcut.
- **Debug:** non-intrusive `dbg_pc/instr/valid`, `dbg_regfile_addr/data` — TBs observe without touching the DUT.
- **ISA:** full RV32I unprivileged integer + 8 M-ops (`MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU`); `FENCE` as NOP. No `ECALL/EBREAK`/CSR/trap, no `C/F/Z*`, no privileged modes/caches/AXI (by design).

## Repo layout

| Path | What it is |
|------|------------|
| `soc_top.sv` | Singular/frozen RTL (TOP `soc_top`) — simulate or synthesize from this one file |
| `tb_soc_final.sv` | Primary regression (777 L, 3 phases, ~55 checks) |
| `tb_minimal.sv`, `tb_soc_hex.sv`, `tb_soc_m_ext.sv`, `tb_branch_predictor_minimal.sv` | Smoke / hex-init / M-ext / predictor benches |
| `program.hex`, `data.hex` | Hex memory images for hex-init TBs |
| `scripts/riscv_enc.py` | RV32I instruction-encoder library (R/I/S/B/U/J) |
| `scripts/gen_hex.py` | Deprecated program.hex generator (kept for provenance; current flow uses toolchain, below) |
| `spike_sim/` | Spike golden-reference flow: `test.S`, `linker.ld`, `makeHex.sh`, `run_spike.sh`, `run_test.sh`, `binToHex.py`, `compare_regs.py`, sample tests in `rv32im_spike_tests_until_now/` |
| `outcome/` | **Detailed results — start here.** Docs `01`–`06`, `FREEZE_manifest.txt`, `logs/` (PASS-only logs), `component_tbs/` (frozen TBs), `vcd/` (waveforms) |
| `idk/`, `work/` | Scratch / tool transcripts, not part of the frozen reference |

## Verification

- **Directed, self-checking SV TBs** — programs loaded into `instr_mem`, executed on `soc_top`, checked via `check_reg(name, actual, expected)` over the debug port. No UVM/formal.
- `tb_soc_final` phases: P1 isolated correctness (~33) → P2 hazards/forwarding 0/1/2-NOP distances, load-use, chains, JALR/branch interactions (~11) → P3 non-blocking M, b2b M-ops, MUL‖ALU (~11).
- **Spike flow** (`spike_sim/`): same `test.S` assembled to `program.hex` for RTL and to ELF for Spike (`--isa=RV32IM`); compare architectural registers, not cycle-by-cycle (see `spike_sim/readme.md`).
- Frozen evidence: `outcome/logs/{soc_test_PASS29,core_final_PASS38,load_store_offsets_PASS21}.log`, waveforms in `outcome/vcd/`.

## Quick start

```bash
# 1. Primary regression (ModelSim-Altera 10.1d)
# load soc_top.sv + tb_soc_final.sv and run; see outcome/02_verification_methodology.md for .do scripts

# 2. Open-source fallback (Icarus)
iverilog -g2012 soc_top.sv tb_soc_final.sv -o tb_soc_final && vvp tb_soc_final

# 3. Hex-init variant
iverilog -g2012 soc_top.sv tb_soc_hex.sv -o tb_hex && vvp tb_hex
# (uses program.hex / data.hex)

# 4. Spike golden reference (needs riscv toolchain + spike)
cd spike_sim && ./makeHex.sh && ./run_spike.sh && ./run_test.sh
# details: spike_sim/readme.md

# 5. Encode instructions in Python
python3 -c "import sys; sys.path.insert(0,'scripts'); from riscv_enc import *; print(f'{enc_i(42,0,0,31,OPC_OP_IMM):08x}')"
```

Requirements: ModelSim/Questa **or** Icarus Verilog; Quartus II 13.0sp1 for analysis/elaboration (Cyclone II target); `riscv64-unknown-elf-*` + `spike` only for the `spike_sim/` flow.

---
*Full claims, tables, repro commands, and log pointers live in [`outcome/`](outcome/) — please read [`outcome/README.md`](outcome/README.md) first.*
