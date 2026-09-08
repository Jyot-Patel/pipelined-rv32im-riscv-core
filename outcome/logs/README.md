# outcome/logs — error-free logs only (0 FAILED)

Archived ModelSim-Altera 10.1d runs. Nothing here was edited to remove failures —
suites with any FAIL are **excluded** (see §3).

## Contents

| File | Suite | Result | Original source |
|------|-------|--------|-----------------|
| `soc_test_PASS29.log` | `tb_soc_top` (SoC smoke: R/I/B/U/J + loads/stores) | **29 PASSED, 0 FAILED** | `simulation/soc_test.log` (verbatim copy) |
| `core_final_PASS38.log` | `tb_rv32i_core` (core + OP-IMM/FENCE coverage) | **38 PASSED, 0 FAILED** | `simulation/core_final.log` (verbatim copy) |
| `load_store_offsets_PASS21.log` | `tb_load_store_offsets` (exhaustive lanes) | **21 PASSED, 0 FAILED** | excerpt archived in `bugFixed/load_store_byte.md` §6 (no standalone vsim .log was saved at the time — labeled as excerpt) |

Total error-free evidence: **88 checks, 0 failures** across the three logs.

## How each was produced (ModelSim)

```tcl
# soc_test.log
vsim -do {run -all; exit} -l soc_test.log -c tb_soc_top
# core_final.log
vsim -do {run -all; exit} -l core_final.log -c tb_rv32i_core
# load_store excerpt
vsim -c work.tb_load_store_offsets
```

Scripts: `simulation/run_soc.tcl`, `simulation/run_core.tcl`,
`simulation/modelsim/run_soc_top.do`, `run_soc_final.do`.

## Deliberately EXCLUDED (have failures — see `../03_test_results.md`)

- `simulation/muldiv_final.log` → 20/21 (1 MULHSU FAIL) — not copied.
- `simulation/haz_test.log` → 14/21 (7 FAILs) — not copied.
- `tb_soc_final` full run → 50/55 (5 FAILs) — not copied.
- `coverage_transcript.txt` → stale ad-hoc script output — not a vsim log, not copied.

## Linux / iverilog note (honest)

These logs were **not regenerated** on this machine: Icarus Verilog 12.0 cannot
compile the frozen TBs as-is (`tb_load_store_offsets.sv:95: error: Cannot "return"
from tasks`; `branch_predictor.sv:44` elaboration assert → abort). Re-running
requires ModelSim-Altera 10.1d + Quartus II 13.0sp1 flow above. Do not present
these as fresh Linux runs.
