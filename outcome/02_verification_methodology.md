# 02 — Verification Methodology
Verified Final core with spike riscv-tests suite as a golden reference model. for individual components and step by step testing, implemented various directed sv based testbenches. 
-----------------------------------------------
## Strategy: directed, self-checking, phased


No UVM / no formal. Every TB is a directed SystemVerilog
program loaded into `instr_mem`, executed on `soc_top`, and self-checked with:

```systemverilog
task automatic check_reg(string name, logic [31:0] actual, logic [31:0] expected);
  if (actual === expected) $display("  [PASS] ...");
  else                     $display("  [FAIL] ... (expected ...)");
```

Reads go through a **non-intrusive debug port** (`dbg_regfile_addr/data`, `dbg_pc/instr/valid`)
so the DUT is never modified for observability (`rv32i_core.sv`, `regfile.sv` 63 L, `soc_top.sv` 92 L).

## Testbenches (all in `tb/`)

| TB | Lines | Role |
|----|-------|------|
| `tb_soc_final.sv` | 777 | **Primary regression.** 3 isolated phases, fresh mem+reset each. ~55 `check_reg` calls. |
| `tb_load_store_offsets.sv` | 326 | Exhaustive lane sweep: SB/LB/LBU offsets 0–3, SH/LH/LHU 0/2, SW/LW. 21/21. |
| `tb_muldiv_unit.sv` | 619 | Unit-level M-ops, div-by-zero, overflow, back-to-back, stall handshake. |
| `tb_hazards.sv` | 576 | Forwarding distances, load-use, branch+forward interactions. |
| `tb_branch_predictor.sv` | 460 | BHT/BTB direction + target behavior. |
| `tb_debug_load*.sv`, `tb_debug_chain.sv` | ~150 | Bring-up / debug scaffolding (kept for provenance). |
| `tb/hex/gen_hex.py` + `test_prog.hex/test_data.hex` | — | Hex-init path for mem preload. |
| `scripts/riscv_enc.py` | — | Instruction encoder library. |

## The 3 phases of `tb_soc_final` (frozen regression)

- **Phase 1 (~33 checks): instruction correctness.** Each RV32I/M op in isolation with NOP padding.
  Result: **33/33 PASS.**
- **Phase 2 (~11 checks): hazards & forwarding.** ALU→ALU at 0/1/2 NOPs, load→ALU at 0/1/2 NOPs,
  MULDIV→ALU (`FWD_MULDIV`), A→B→C chain, store→load, load→store, LUI/AUIPC→ALU, JALR forwarded base,
  branch taken (mispredict flush) / not-taken, branch on forwarded data, load-use-before-branch.
  Result: **8/11 PASS.**
- **Phase 3 (~11 checks): non-blocking M-extension.** MUL/DIV/REM→ADDI 0-NOP forwarding,
  back-to-back MUL/DIV, MUL→branch, parallel MUL||ALU, MUL→store→load.
  Result: **7/11 PASS.**

Total frozen: **50/55.** Failing 5 detailed in `03_test_results.md`.

## Corner-case method

Each risky behavior gets a dedicated check, not just "it ran":
div-by-zero (DIV→-1, REM→dividend), overflow (`0x80000000/-1`), all store/load lane offsets,
back-to-back M-ops, 0/1/2-NOP forwarding distances, taken/not-taken × 6 branch types,
mispredict flush occupancy, x0 write-drop + no-forward, FENCE-as-NOP. See `04_corner_cases.md`.

## Simulation & synthesis flow

| Step | Tool | Script / file |
|------|------|---------------|
| Sim | Altera ModelSim-ASE 10.1d | `simulation/modelsim/run_soc_final.do`, `run_hazards.do`, `run_soc_top.do`, `run_branch_predictor.do` |
| Sim logs (frozen evidence) | — | `simulation/soc_test.log`, `core_final.log`, `muldiv_final.log`, `simulation/run_soc_final.do` transcript |
| Synth (analysis+elab) | Quartus II 13.0sp1 | `rv32i_core.qsf`, `soc_top.qsf`, `test_soc_single.qsf`, `soc_top_single.sv` |
| Open fallback | Icarus | `iverilog -g2012 … && vvp` (see README) |

Waveforms kept: `soc_final.vcd`, `hazards.vcd`, `branch_predictor.vcd`, `soc_top.vcd`, `rv32i_core.vcd`.

## What this methodology does NOT claim

No constrained-random, no functional coverage model, no riscv-compliance suite
(`riscv-tests`/`riscv-arch-test`), no formal property proofs, no gate-level/SDF timing sim,
no full-fit PPA. `coverage_transcript.txt` is a stale ad-hoc script output — do not cite it
as coverage; cite the `.log` PASS/FAIL lines instead.
