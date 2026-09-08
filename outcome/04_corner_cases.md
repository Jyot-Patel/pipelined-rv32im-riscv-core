# 04 — Corner Cases (what was actually exercised)

Each row is a check that exists in a TB/log, not a claim of "should work".

## Arithmetic / M-unit edges

| Corner | Result | Evidence |
|--------|--------|----------|
| DIV by zero → `-1` (`0xFFFFFFFF`), DIVU/0 → `0xFFFFFFFF` | PASS | `muldiv_final.log` x21/x22 |
| REM/REMU by zero → dividend (`0x2A`, `0x80000000`) | PASS | x23/x24 |
| Signed overflow `0x80000000 / -1` → `0x80000000` | PASS | x25 |
| `DIV 100/200 = 0`, back-to-back `DIV 4/5` | PASS | x27/x28 |
| Back-to-back MUL (`2*3`, `4*5`) | PASS | x5/x26 |
| `MULH 0x8000*0x8000 → 0x40000000` (signed hi) | PASS | x12 |
| `MULHU 5*5 → 0`, `MULHU hi → 0x40000000` | PASS | x15/x16 |
| **`MULHSU 0x8000*0x7FFF` → got `0x80000000`, want `0xC0000000`** | **FAIL (open)** | x14 |
| Shift extremes `SLL 5<<29=0xA0000000`, `SRL 5>>29=0`, `SRA -1>>>29=-1` | PASS | soc/core logs |
| `SLT -3<5=1`, `SLTU u(-3)>u(5)=0` | PASS | x8/x9 |

## Memory lane edges (the frozen bug-fix)

| Corner | Result | Evidence |
|--------|--------|----------|
| SB/LB/LBU every byte offset 0–3 (incl. `0xAB` sign vs zero extend) | 21/21 PASS | `tb_load_store_offsets.sv` |
| SH/LH/LHU offsets 0/2 (incl. `-1` sign, `0xFFFF` zero) | 21/21 PASS | same |
| SW/LW word path, `mem[0]=0x2A` | PASS | Phase 1, soc log |
| `SH mem[8]=0xFFFF` read back via LHU | PASS | `currentStatus.md` |
| Store→load same-address forwarding, load→store data forwarding | PASS (isolated) / FAIL in P2 0-NOP combo | Phase 2 (see 03) |
| Fix pointers: `data_wdata` replication `rv32i_core.sv:547`, `rdata_shifted` `mux_wb_sel.sv:13` | frozen | `bugFixed/load_store_byte.md` |

## Pipeline / hazard edges

| Corner | Result | Evidence |
|--------|--------|----------|
| ALU→ALU forwarding at 0/1/2 NOP distances | PASS | Phase 2, `tb_hazards.sv` |
| Load→ALU at 1/2 NOPs | PASS | Phase 2 |
| Load→ALU at **0 NOPs** | **FAIL (open)** | P2 x22 — needs IF/ID hold fix |
| A→B→C multi-hop chain | **FAIL in P2 combo** (x25) | open, same root |
| MULDIV→ALU (`FWD_MULDIV`, priority over EX/MEM, MEM/WB) | PASS isolated / FAIL in P3 combos | `hazard_unit.sv`, Phase 3 |
| Parallel MUL \|\| independent ADD (non-blocking scoreboard) | PASS | Phase 3 `MUL\|\|ALU` |
| MUL→store→load chain | PASS isolated | Phase 3 |
| Load-use-before-branch (stall + forward + taken) | covered | Phase 2 |
| `x0` hardwired zero: never forwards, writes dropped | by construction | `hazard_unit` (`x0` guard), regfile |
| FENCE as pipeline NOP | PASS (`300`) | `core_final.log` |

## Control / branch edges

| Corner | Result | Evidence |
|--------|--------|----------|
| All 6 branch types taken AND not-taken | PASS | `x24–x30` values above |
| Mispredict → 2-cycle flush (`pipe_flush`+`pipe_flush_d1`) | PASS in isolation | `branch_predictor.sv` (81 L), `tb_branch_predictor.sv` |
| BHT 2-bit saturating (reset weakly-not-taken `01`), 64-entry, `PC[7:2]` index; BTB valid+tag+target | implemented | `branch_predictor.sv` |
| JAL/JALR link (`PC+4`), JALR forwarded-base, `idex_pc4` handling | PASS isolated | Phase 1/2 |
| LUI (`0xABCDE000`), AUIPC→ALU forwarding | PASS | Phase 1/2 |
