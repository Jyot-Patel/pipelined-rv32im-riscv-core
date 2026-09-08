# RV32IM 5-Stage Pipelined Core — FREEZE / DONE State
**Date (freeze): 2026-09-08 | Project: RV32IM IF-ID-EX-MEM-WB + BHT/BTB + Hazard/Forwarding + Non-blocking M-extension**

This `outcome/` folder is the **frozen showcase**. It contains only claims backed by
files in this repo. Open issues are listed explicitly — nothing is hidden to reach "55/55".

## What is frozen

| Item | File / evidence | Status |
|------|-----------------|--------|
| Singular RTL | `../soc_top_single.sv` (2128 lines, 21 design units, TOP `soc_top`) | `vlog -sv` 0 errors, `quartus_map --analysis_and_elaboration` 0 errors |
| Hierarchical RTL | `../rtl/common/rv32i_pkg.sv`, `../rtl/core/rv32i_core.sv` (615 L), `../rtl/core/soc_top.sv`, `../rtl/units/*`, `../rtl/mux/*`, `../rtl/mem/*`, `../rtl/pipeline/*` | Synthesis-intent, BRAM-registered |
| SoC | Core + `instr_mem` + `data_mem` (1024 x 32 each in TB) | `tb/tb_soc_final.sv` DUT |
| Target | Intel Cyclone II `EP2C35F672C6` (`rv32i_core.qsf`, `soc_top.qsf`) | Analysis/elab clean; **no full-fit Fmax/LE report** (map reports are `N/A until Partition Merge`) |
| Docs in this folder | `00`–`06` + `FREEZE_manifest.txt` | Read in order |

## Headline numbers (honest)

- **Phase 1 (instruction correctness): 33/33 PASS** — R/I/B/U/J + loads/stores + M-ops in `tb_soc_final`.
- **`tb_soc_final` overall: 50/55 PASS** (Phase 2: 8/11, Phase 3: 7/11). 5 fails are timing/hold issues, **not** byte-lane bugs. See `03_test_results.md`.
- **Byte/halfword lanes: 21/21 PASS** (`tb_load_store_offsets.sv`) — SB/SH/LB/LBU/LH/LHU all offsets + SW/LW.
- **Core smoke (`simulation/core_final.log`): 38/38 PASS** incl. SLLI/SLTI/SLTIU/XORI/SRLI/SRAI/ORI/ANDI + FENCE-as-NOP.
- **SoC smoke (`simulation/soc_test.log`): 29/29 PASS.**
- **M-unit (`simulation/muldiv_final.log`): 20/21 PASS** — 1 FAIL: `MULHSU 0x8000*0x7FFF` (`0x80000000` vs `0xC0000000`). Signed×unsigned correction bug, still open.
- **ISA decode supported:** full RV32I unprivileged integer + 8 M-ops; `FENCE` as NOP; no `ECALL/EBREAK/CSR/C/F/Z*`. See `01_isa_coverage.md`.

## Folder map

| File | What it proves |
|------|----------------|
| `01_isa_coverage.md` | Every RV32IM op: supported / tested / checked / absent |
| `02_verification_methodology.md` | TB architecture, debug port, phases, repro commands |
| `03_test_results.md` | Pass/fail tables with log references + the 5+1 known failures |
| `04_corner_cases.md` | Div-by-zero, overflow, lanes, back-to-back, mispredict, x0, stalls |
| `05_rtl_achievements.md` | Pipeline, forwarding, predictor, M-unit, memories, debug infra |
| `06_impact_and_next.md` | What this core is good for + what is deliberately out of scope + next steps |
| `FREEZE_manifest.txt` | File list, line counts, device, tool versions, how to re-run |
| `logs/` | Error-free logs only: `soc_test_PASS29`, `core_final_PASS38`, `load_store_offsets_PASS21` (88 checks, 0 failures) |
| `component_tbs/` | All TB files frozen: unit benches (`muldiv_unit`, `hazards`, `branch_predictor`, `load_store_offsets`, debug) + `soc_final` + `legacy/` + `hex/` |

## How to re-run (canonical)

```bash
# ModelSim-Altera 10.1d (project scripts)
cd simulation/modelsim && do run_soc_final.do     # tb_soc_final, 3 phases
do run_hazards.do                                 # tb_hazards
do run_soc_top.do                                 # tb_soc_top

# Open-source fallback
iverilog -g2012 -I rtl/common rtl/common/rv32i_pkg.sv rtl/pipeline/*.sv \
  rtl/units/*.sv rtl/mux/*.sv rtl/mem/*.sv rtl/core/*.sv tb/tb_soc_final.sv -o tb_soc_final
vvp tb_soc_final
```

## Known-open (do not call done beyond this)

1. `tb_soc_final` 5 fails (Phase 2: Load-ALU 0-NOP, Load-Store, chain A→B; Phase 3: REM+ADDI, MUL-branch). Root cause: registered `instr_mem` vs 1c/2c hazard assumption — see `currentStatus.md` "Gap to final 55/55".
2. `MULHSU` signed×unsigned corner wrong (`muldiv_final.log`).
3. `coverage_transcript.txt` is **stale** (claims SLLI/SLTI/etc absent, but `core_final.log` shows 38/38 with them passing). Trust the logs, not that transcript.
4. No full Quartus fit: no LE/register/M9K/Fmax numbers. Only analysis+elaboration is clean.
5. No privileged ISA, no CSR/trap, no AXI, no caches, no formal/coverage-driven verification.

> Freeze means: RTL + TBs + logs as-is are the reference. Any fix must re-run the above and update `03_test_results.md`.
