# outcome/component_tbs — all testbench files (frozen copies)

Verbatim copies of `tb/` at freeze time (2026-09-08). Nothing edited.
Provenance: `tb/*.sv`, `tb/legacy/*.sv`, `tb/hex/*`.

## Component / unit-level benches (the point of this folder)

| File | DUT / scope | Lines | Frozen status |
|------|-------------|-------|---------------|
| `tb_muldiv_unit.sv` | `muldiv_unit` standalone: all 8 M-ops, div-by-zero, overflow, back-to-back, stall handshake | 619 | 20/21 in SoC context (1 MULHSU corner open — see `../03_test_results.md`) |
| `tb_hazards.sv` | Hazard/forwarding focused: 0/1/2-NOP distances, load-use, branch+forward, JALR/LUI/AUIPC forwarding | 576 | 14/21 in archived `haz_test.log` (fails are the frozen-open timing set) |
| `tb_branch_predictor.sv` | `branch_predictor` (BHT+BTB direction/target) | 460 | Behavior covered; waveforms in `branch_predictor.vcd` |
| `tb_load_store_offsets.sv` | `soc_top` memory lanes: SB/LB/LBU off 0–3, SH/LH/LHU off 0/2, SW/LW | 326 | **21/21 PASS** (log in `../logs/load_store_offsets_PASS21.log`) |
| `tb_debug_load.sv` / `tb_debug_load2.sv` / `tb_debug_chain.sv` | Bring-up / debug scaffolding (register-file observability checks) | 58 / 41 / 51 | Scaffolding, kept for provenance |

## SoC-level bench (included because "all files", not component-level)

| File | Scope | Lines | Frozen status |
|------|-------|-------|---------------|
| `tb_soc_final.sv` | **Primary regression**: 3 phases, ~55 checks on `soc_top` | 777 | **50/55** (P1 33/33, P2 8/11, P3 7/11) |

## Legacy (superseded but kept)

| File | Scope | Lines | Note |
|------|-------|-------|------|
| `legacy/tb_soc_top.sv` | SoC smoke on `soc_top` | 140 | Produces `../logs/soc_test_PASS29.log` (**29/29**) |
| `legacy/tb_rv32i_core.sv` | Core smoke incl. OP-IMM/FENCE | 464 | Produces `../logs/core_final_PASS38.log` (**38/38**) |
| `legacy/tb_muldiv.sv` | Early M-extension bench | 393 | Superseded by `tb_muldiv_unit.sv` |

## Helpers

| File | Role |
|------|------|
| `hex/gen_hex.py` | Generates `test_prog.hex` / `test_data.hex` for mem preload |
| `hex/test_prog.hex`, `hex/test_data.hex` | Hex images used by legacy `tb_soc_top` (`IMEM_INIT_FILE`/`DMEM_INIT_FILE`) |

## Run (ModelSim-Altera 10.1d, from repo root `simulation/modelsim/`)

```tcl
do run_soc_final.do        ;# tb_soc_final (3 phases)
do run_hazards.do          ;# tb_hazards
do run_soc_top.do          ;# tb_soc_top (legacy)
do run_branch_predictor.do ;# tb_branch_predictor
do run_rv32i_core.do       ;# tb_rv32i_core (legacy)
```

Note: Icarus 12.0 on Linux does not compile these TBs as-is
(`return` in tasks, `branch_predictor` elaboration assert) — see `../logs/README.md`.
