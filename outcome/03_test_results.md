# 03 — Test Results (frozen, with evidence pointers)

## 3.1 Frozen scoreboard

| Suite | Result | Evidence |
|-------|:------:|----------|
| `tb_soc_final` Phase 1 (correctness) | **33/33 PASS** | `currentStatus.md`, TB phases 1 |
| `tb_soc_final` Phase 2 (hazards) | **8/11 PASS** | fails below |
| `tb_soc_final` Phase 3 (non-blocking M) | **7/11 PASS** | fails below |
| `tb_soc_final` total | **50/55 PASS** | frozen claim |
| Exhaustive lanes `tb_load_store_offsets` | **21/21 PASS** | `bugFixed/load_store_byte.md` |
| SoC smoke `soc_test.log` | **29/29 PASS** | `simulation/soc_test.log` `RESULTS: 29 PASSED, 0 FAILED` |
| Core smoke `core_final.log` | **38/38 PASS** | `simulation/core_final.log` `RESULTS: 38 PASSED, 0 FAILED` |
| M-unit `muldiv_final.log` | **20/21 PASS** | 1 FAIL: MULHSU |
| Elaboration `vlog -sv` + `quartus_map --analysis_and_elaboration` on `soc_top_single.sv` | **0 errors** | `currentStatus.md §7`, `test_soc_single.map.rpt` (analysis stage only) |

Sample frozen PASS lines (representative, not exhaustive):
`x3 ADD=0x02`, `x4 SUB=0x08`, `x10 SLL=0xA0000000`, `x13 SRA=0xFFFFFFFF`,
`x14 LUI=0xABCDE000`, `x17 LW=0x2A`, `x19 LB=0xFFFFFFAB`, `x22 LH=0xFFFFFFFF`,
`x24 BEQ-taken=0x2A`, `x30 BGEU-taken=0x58`, `MUL 10*20=0xC8`, `DIV 100/7=0x0E`,
`DIV/0=-1`, `REM/0=dividend`, `DIV overflow=0x80000000`.

## 3.2 The 5 `tb_soc_final` failures (frozen-open, not lane bugs)

| # | Phase | Check | Got / Want | Note |
|---|-------|-------|------------|------|
| 1 | P2 | `x22` Load→ALU 0 NOP | `0x0` vs `0x2A` | Registered-BRAM load latency vs 1c/2c stall assumption |
| 2 | P2 | `x30` Load→Store | `0x0` vs `0x2A` | same family |
| 3 | P2 | `x25` chain A→B (`5`) | `0xA` vs `0x5` | chain timing |
| 4 | P3 | `x29` REM→ADDI | `0x1E` vs `0x0C` | MULDIV-result forwarding timing |
| 5 | P3 | `x24` MUL→branch | `0x03` vs `0x4D` | scoreboard + branch resolve interaction |

Root cause (per `currentStatus.md`): `instr_mem` is registered (BRAM-like, by design) but the
hazard/stall logic was built on a combinational-IMEM timing assumption (`rv32i_core.sv:127`).
The 2-cycle load-use hold (`hazard_unit.sv:143`) still races `pc_reg`/BRAM addr at `posedge`,
so the held cycle re-fetches a NOP. Fix needs an IF/ID instruction-hold register + hazard
retune (`exmem` check, `idex_pc4` offset) — estimated 1 day (Phase A in `currentStatus.md`).
Kept registered deliberately: combinational-mem variant scored 29/55 (broke MUL/JAL), so the
2-cycle registered design at 50/55 is the frozen reference.

## 3.3 The 1 M-unit failure (frozen-open)

`muldiv_final.log`: `[FAIL] x14 MULHSU 0x8000*0x7FFF = 0x80000000 (expected 0xC0000000)`.
Signed×unsigned upper-half correction in `muldiv_unit.sv` is wrong for that corner.
All other 20 M checks pass, including div-by-zero and overflow per RISC-V spec.

## 3.4 Stale / misleading artifact (do not cite)

`coverage_transcript.txt` claims 8 OP-IMM (SLLI/SLTI/…) + FENCE + SYSTEM "COMPLETELY ABSENT"
(Count A 26 / B 29 / C 18). This predates `core_final.log` (38/38), which explicitly PASSES
SLLI/SLTI/SLTIU/XORI/SRLI/SRAI/ORI/ANDI + FENCE. **Trust the logs; the transcript is stale.**

## 3.5 Synthesis status (honest)

- `soc_top_single.sv` (71,849 B): `vlog -sv` 0 errors, `quartus_map --analysis_and_elaboration` 0 errors, 4 BRAM warnings.
- `test_soc_single.map.rpt/.summary/.flow.rpt`: resource/Fmax fields are `N/A until Partition Merge`
  (analysis-only run). **No LE / register / M9K / Fmax numbers exist for this freeze.**
- `data_mem` uses `always @(posedge clk)` (fixes `vsim-7061`); `instr_mem` uses `always_ff`. Both registered = BRAM-inferable, FPGA intent kept.
