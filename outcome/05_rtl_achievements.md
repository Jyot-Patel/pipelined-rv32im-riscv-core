# 05 — RTL Achievements (frozen design)

RTL totals: hierarchical ~2.5 kL SystemVerilog (21 modules) + frozen singular
`soc_top_single.sv` 2128 L. Target Cyclone II `EP2C35F672C6`, Quartus II 13.0sp1.

## 5-stage pipeline (classic IF-ID-EX-MEM-WB)

- `rtl/core/rv32i_core.sv` (615 L) + `if_id_reg` / `id_ex_reg` (131 L) / `ex_mem_reg` / `mem_wb_reg` stages.
- IF: registered `instr_mem` (BRAM-like latency), predictor-fed PC, stall on `muldiv_busy`, redirect on mispredict.
- ID: combinational `decoder` (202 L), dual-port `regfile` (63 L) + debug port.
- EX: `alu` (38 L, 10 ops), branch-condition + target, M-launch.
- MEM: byte-enabled `data_mem` (37 L) with LB/LH/LW/LBU/LHU sign/zero extend.
- WB: `mux_wb_sel` (ALU / MEM / PC+4 / IMM) + MULDIV direct-writeback bypass on `muldiv_done`.
- Achievement: **BRAM-realistic memories kept registered** (`always_ff` / `always @(posedge clk)`)
  instead of taking the easy combinational-read shortcut that would break FPGA inference.

## Hazard + forwarding network

- `hazard_unit.sv` (181 L): 4-way select per ALU operand —
  `FWD_REGFILE < FWD_MEM_WB < FWD_EX_MEM < FWD_MULDIV`, `x0` never forwards.
- Load-use stall: `idex_mem_read && rd==rs1/rs2` + `d1` flop → 2-cycle `pc/ifid` hold + 2 bubbles
  (needed because IF-registered + MEM-registered = 2c load latency). `MULHSU`-era half-measure at
  50/55 is frozen honestly; full IF/ID-hold fix is scoped in `currentStatus.md`.
- M scoreboard: `mul_active/mul_rd/mul_rd_valid`, RAW/WAW + structural + single-port `wb_conflict` —
  only same-`rd` dependents stall; independent ALU ops flow behind a 33-cycle MUL (proven by `MUL||ALU`).

## Branch predictor (BHT + BTB)

- `branch_predictor.sv` (81 L): 64-entry BHT (2-bit saturating, reset `01`) + BTB (valid/tag/target),
  `PC[7:2]` index, resolve in EX, 2-cycle mispredict penalty. Handles direction + target errors.
- All 6 branch types verified taken + not-taken; taken-with-flush and fall-through covered.

## M-extension unit (non-blocking)

- `muldiv_unit.sv` (182 L): iterative 32-cycle shift-add (MUL) + non-restoring divide,
  signed `MULH/MULHSU` correction, RISC-V div-by-zero/overflow semantics.
- Busy/done handshake, result bypass into forwarding muxes + direct WB. 20/21 unit checks;
  1 open `MULHSU` corner (see 03/04).

## Memory subsystem (frozen fix)

- Store byte-enables from `alu_result[1:0]/[1]` + `data_wdata` replication (`rv32i_core.sv:547`).
- Load `rdata_shifted = data_rdata >> (addr[1:0]*8)` (`mux_wb_sel.sv:13`).
- Before: lanes 1–3 wrote/read zero. After: **21/21 offsets PASS.** Documented in
  `bugFixed/load_store_byte.md`, `bugFixed/tb_soc_final_fix.md`.

## Debug + SoC + freeze hygiene

- Non-intrusive debug: `dbg_pc/instr/valid`, `dbg_regfile_addr/data` — TBs observe without touching DUT.
- `soc_top.sv` (92 L): core + IMEM + DMEM integration used by every TB.
- `soc_top_single.sv`: single-file synthesis/simulation reference (0-error `vlog` + назнача analysis+elab).
- Mux family (`mux_pc_sel/redirect`, `alu_operand_a/b`, `imm_sel`, `wb_sel`) + `rv32i_pkg` ISA constants
  keep datapath control explicit and Quartus-13-compatible (`$signed`/`$unsigned` OK).

## What was NOT done (not achievements)

No CSR/privilege/trap, no caches/MMU/AXI, no full-fit PPA, no formal/coverage closure.
That is scope discipline for a BRAM-friendly teaching core, not a miss — see 06.
