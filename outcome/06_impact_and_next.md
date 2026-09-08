# 06 — Impact, Scope, and Next Steps

## What this core is

A **BRAM-realistic, FPGA-synthesizable RV32IM teaching/bring-up core**: 5-stage pipeline,
full unprivileged integer ISA + M-extension, predictor + forwarding + scoreboarded multicycle
unit, byte-correct memories, self-checking TBs, single-file freeze artifact.

## Impact (proportionate, no hype)

1. **Learning reference that runs on real FPGA flow.** Registered IMEM/DMEM infer to M9K/M20K;
   Quartus II 13.0sp1 analysis+elaboration is clean on `EP2C35F672C6`. Students see true
   load-use latency (2c with registered BRAM), not a simulator-only combinational shortcut.
2. **Hazard lab in a box.** 0/1/2-NOP forwarding distances, `FWD_MULDIV` priority, load-use stall,
   mispredict flush, and a documented 50/55 → 55/55 fix path (`currentStatus.md` Phase A) make the
   failure modes teachable instead of hidden.
3. **M-extension done honestly.** 33-cycle iterative unit with non-blocking scoreboard
   (independent ADD runs behind MUL) + spec-correct div-by-zero/overflow — plus one frozen-open
   `MULHSU` bug as a ready-made exercise.
4. **Verification template.** Phased directed TBs + debug-port observability + `check_reg`
   scoreboard + lane-exhaustive sweep is a reproducible pattern for any small core, without UVM overhead.
5. **Extension platform.** Decoder/`MEM`/WB hooks are placed for `Zbb` (`CLZ`), PMP check, or CSR
   trap without re-pipelining — the listed 1-day next wins.

## Deliberate non-goals (frozen scope)

Unprivileged integer only. No `ECALL/EBREAK`/CSR/trap, no `FENCE.I`, no `C/F/Z*`, no
privilege modes, no caches/coherence/AXI, no OS boot. Anyone claiming "full RISC-V" from this
freeze is misreading it.

## Next steps (ordered, from `currentStatus.md`)

- **Phase Next(optional):** `Zbb`-CLZ *or* PMP *or* full Quartus fit (LE/M9K/Fmax) —
  then riscv-tests compliance sweep as the new headline number.
- **Also can be done:** zicsr, c extension to support gcc compiled c code execution, out-of-order, caches, or privileged spec, Linux compliant by rv64gc, where g = i,m,a,f,d extension. 
- **Fix: ** until 55/55 + `MULHSU` are closed.
