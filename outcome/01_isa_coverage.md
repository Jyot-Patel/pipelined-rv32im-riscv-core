# 01 — ISA Coverage (RV32IM, unprivileged integer subset)

Decoder: `rtl/units/decoder.sv` (202 L). Opcodes: OP-IMM / OP / LOAD / STORE / BRANCH / LUI / AUIPC / JAL / JALR + M-extension (funct7=`0000001`).

Legend: SUP = decoder+datapath support | USED = appears in a TB program | CHK = `check_reg()` asserts the result.
Sources: `tb/tb_soc_final.sv` (777 L, 3 phases), `tb/tb_load_store_offsets.sv` (326 L),
`tb/tb_muldiv_unit.sv` (619 L), `tb/tb_hazards.sv` (576 L),
logs `simulation/soc_test.log` (29/29), `simulation/core_final.log` (38/38),
`simulation/muldiv_final.log` (20/21), `tb/tb_branch_predictor.sv` (460 L).

## OP-IMM (I-type ALU)

| Instr | SUP | USED | CHK | Evidence |
|-------|:---:|:----:|:---:|----------|
| ADDI  | Y | Y | Y | soc 29/29, core 38/38, Phase 1 |
| SLLI  | Y | Y | Y | `core_final.log`: `SLLI 5<<1=10 PASS` (note: stale `coverage_transcript.txt` says absent — log wins) |
| SLTI  | Y | Y | Y | `core_final.log`: `SLTI -3<0=1 PASS` |
| SLTIU | Y | Y | Y | `core_final.log`: `SLTIU PASS` |
| XORI  | Y | Y | Y | `core_final.log`: `XORI PASS` |
| SRLI  | Y | Y | Y | `core_final.log`: `SRLI PASS` |
| SRAI  | Y | Y | Y | `core_final.log`: `SRAI PASS` |
| ORI   | Y | Y | Y | `core_final.log`: `ORI PASS` |
| ANDI  | Y | Y | Y | `core_final.log`: `ANDI PASS` |

## OP (R-type ALU)

| Instr | SUP | USED | CHK | Evidence |
|-------|:---:|:----:|:---:|----------|
| ADD | Y | Y | Y | soc/core logs, Phase 1 |
| SUB | Y | Y | Y | same |
| SLL | Y | Y | Y | `SLL 5<<29 = 0xA0000000` |
| SLT | Y | Y | Y | `SLT -3<5 = 1` |
| SLTU| Y | Y | Y | `SLTU = 0` |
| XOR | Y | Y | Y | `0xFFFFFFF8` |
| SRL | Y | Y | Y | pass |
| SRA | Y | Y | Y | `SRA -1>>>29 = 0xFFFFFFFF` |
| OR  | Y | Y | Y | `0xFFFFFFFD` |
| AND | Y | Y | Y | `0x00000005` |

## M-extension (OP, funct7=0000001) — muldiv_unit.sv (182 L, iterative 32c, ~33 cycles/op)

| Instr | SUP | USED | CHK | Evidence |
|-------|:---:|:----:|:---:|----------|
| MUL    | Y | Y | Y | `MUL 10*20=0xC8`, `MUL 2*3`, b2b `4*5` PASS |
| MULH   | Y | Y | Y | `0x8000*0x8000 → 0x40000000` PASS |
| MULHSU | Y | Y | **FAIL1** | `0x8000*0x7FFF` got `0x80000000`, want `0xC0000000` — signed×unsigned correction bug |
| MULHU  | Y | Y | Y | `0x8000*0x8000 → 0x40000000`, `5*5` PASS |
| DIV    | Y | Y | Y | `100/7=0x0E`, `100/200=0`, b2b `4/5` PASS |
| DIVU   | Y | Y | Y | `0x8000/3=0x2AAAAAAA` PASS |
| REM    | Y | Y | Y | `100%7=2` PASS (but Phase-3 REM+ADDI forwarding FAIL — see 03) |
| REMU   | Y | Y | Y | `0x8000%3=2` PASS |

## Loads / Stores (byte-enabled data_mem.sv, 37 L)

| Instr | SUP | USED | CHK | Evidence |
|-------|:---:|:----:|:---:|----------|
| LW  | Y | Y | Y | `LW mem[0]=0x2A`, exhaustive SW/LW PASS |
| LH  | Y | Y | Y | `LH sign-ext 0xFFFFFFFF`, offsets 0/2 PASS |
| LB  | Y | Y | Y | `LB 0xFFFFFFAB`, offsets 0–3 PASS |
| LHU | Y | Y | Y | `0x0000FFFF`, offsets 0/2 PASS |
| LBU | Y | Y | Y | `0x000000AB`, offsets 0–3 PASS |
| SW  | Y | Y | indirect | `mem[0]=0x2A` via LW; store verified by load-back (no direct `check_reg` on mem in coverage script) |
| SH  | Y | Y | indirect | `mem[8]=0xFFFF` via LHU; same note |
| SB  | Y | Y | indirect | `mem[4]=0xAB` via LB/LBU; same note |

Byte-lane fix (frozen): `rv32i_core.sv:547` `data_wdata` replication + `mux_wb_sel.sv:13`
`rdata_shifted = data_rdata >> (addr[1:0]*8)` — exhaustive 21/21 in `tb_load_store_offsets.sv`.

## Branches / Jumps / Upper-imm

| Instr | SUP | USED | CHK | Evidence |
|-------|:---:|:----:|:---:|----------|
| BEQ/BNE/BLT/BGE/BLTU/BGEU | Y | Y | Y | Taken + not-taken each; `x24=0x2A`, `x25=0x4D`, `x26=0x37`, `x27=0x21`, `x28=0x16`, `x29=0x0B`, `x30=0x58` |
| JAL  | Y | Y | Y | `x31=0x400`-class link checks, Phase 1 |
| JALR | Y | Y | Y | Base+offset, incl. forwarded-base case (Phase 2) |
| LUI   | Y | Y | Y | `0xABCDE000` |
| AUIPC | Y | Y | Y | PC-relative, incl. AUIPC-to-ALU forwarding |
| FENCE | NOP | Y | Y | `core_final.log`: `FENCE no-op=300 PASS` — pipeline NOP by design |

## Deliberately absent (by design, not a bug)

`ECALL/EBREAK`, all CSRs (`CSRRW/CSRRS/CSRRC/I` variants), `FENCE.I`, `C`/`F`/`Z*`,
privileged modes, `Sv32`, PMP, AXI. No trap/exception path. See `06_impact_and_next.md`.
