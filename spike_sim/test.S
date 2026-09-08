# =============================================================================
# test.s — Maximized RV32M directed test for soc_top (RV32IM)
# Maximizes distinct register usage: 30/31 regs hold unique values
# Each M-variant writes to a unique rd; sources also varied
# Target: soc_top via program.hex / test_program.hex (ModelSim Altera)
# Assembler: riscv32-unknown-elf-gcc -march=rv32im -mabi=ilp32
# Encoding: standard RV32M (funct7=0x01, opcode 0x33) — see riscv_enc.py
# Halt: j halt (0x0000006f) — TB detects halt, not fixed 50 cycles
# =============================================================================
    .text
    .option arch, rv32im
    .globl _start
_start:
        # ---- Structural hazard: back-to-back DIV, 0 nops ----
    addi x11, x0, 1000
    addi x12, x0, 3
    div  x13, x11, x12        # long iteration count
    div  x14, x2,  x1         # must wait for m_busy to drop before starting

    # ---- Data hazard: DIV -> immediate dependent use, 0 nops ----
    div  x15, x11, x7
    add  x16, x15, x15        # must stall exactly until m_valid, no earlier/later

    # ---- Independence: DIV -> unrelated ALU stream, 0 nops ----
    div  x17, x11, x12        # long-latency, unrelated to below
    addi x18, x0, 1
    addi x19, x18, 1
    addi x20, x19, 1
    addi x21, x20, 1          # these 4 should retire while x17's divide is still busy
    add  x22, x17, x21        # THIS one stalls, waiting on x17
halt:
    j halt                    # 0x0000006f
