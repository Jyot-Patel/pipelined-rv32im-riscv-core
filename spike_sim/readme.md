# RV32IM CPU — Spike & RTL Verification Workflow

## CPU
Custom RV32IM processor:
- 5-stage pipeline
- 32 × 32-bit register file
- Hazard handling
- Bimodal branch prediction
- Non-blocking M-unit execution
- RTL program/data memory initialized from `program.hex` / `data.hex`
- RTL simulation with ModelSim / EDA Playground
- Spike used as the architectural reference

## Verification Flow

The same assembly test is converted into `program.hex` for the RTL and can also be assembled into a binary for inspection/reference.

```text
test.S
  │
  ▼
RISC-V assembler
  │
  ▼
test.o
  │
  ▼
objcopy (.text only)
  │
  ▼
test.bin
  │
  ▼
Python middleware
  │
  ▼
program.hex
  │
  ▼
RTL / EDA Playground
```

### File roles

- `.S` — human-written RISC-V assembly.
- `.o` — assembler object file: machine code plus sections/metadata/symbol information.
- `.bin` — raw machine-code bytes extracted from `.text`.
- `.hex` — text representation of 32-bit instruction words used by the RTL memory.

Example `program.hex`:

```text
00a00093
01400113
002081b3
0000006f
```

## Assembly → `program.hex`

### 1. Assemble

```bash
riscv64-unknown-elf-as -march=rv32im -mabi=ilp32 test.S -o test.o
```

### 2. Extract `.text` as raw binary

```bash
riscv64-unknown-elf-objcopy -O binary -j .text test.o test.bin
```

### 3. Convert binary → 32-bit hex words

```bash
python3 -c "
import struct
d=open('test.bin','rb').read()
with open('program.hex','w') as f:
    for i in range(0,len(d),4):
        f.write(f'{struct.unpack(\"<I\",d[i:i+4])[0]:08x}\n')
"
```

### 4. Check

```bash
cat program.hex
```

Optional instruction verification:

```bash
riscv64-unknown-elf-objdump -d test.o
```

## Spike

Spike is installed natively on Linux. Use RV32IM:

```bash
spike --isa=RV32IM --priv=m test.elf
```

For interactive debugging:

```bash
spike -d --isa=RV32IM --priv=m test.elf
```

Useful Spike debugger commands:

```text
reg 0       # show registers
pc 0        # show PC
insn 0      # show instruction
Enter       # execute one instruction
```

Spike may execute its own startup/machine-environment instructions before reaching the test program. These are not part of the custom RTL design and should not be used as the RTL comparison target.

## Current Known-Good Test

Assembly:

```asm
.section .text
.globl _start

_start:
    addi x1, x0, 10
    addi x2, x0, 20
    add  x3, x1, x2

loop:
    jal x0, loop
```

Expected machine words:

```text
00a00093
01400113
002081b3
0000006f
```

Expected architectural result:

```text
x0 = 0
x1 = 10
x2 = 20
x3 = 30
```

The RTL produced:

```text
r0 : 00000000
r1 : 0000000a
r2 : 00000014
r3 : 0000001e
```

This matches the expected Spike result.

## RTL / EDA Playground

The RTL can be simulated online using EDA Playground.

Upload/include:
- SystemVerilog RTL files
- testbench
- `program.hex`
- `data.hex` when required

The RTL's existing `$readmemh()`-style memory initialization can use `program.hex` directly if the memory module expects that filename.

## Verification Strategy

Do not compare Spike and RTL cycle-by-cycle. Spike is an architectural reference, while the RTL has a specific 5-stage pipeline, hazards, branch prediction, and non-blocking M unit.

Compare architectural results first:

```text
Test instruction/result
        │
   ┌────┴────┐
   ▼         ▼
 Spike      RTL
   │         │
   └────┬────┘
        ▼
      Compare
```

### Planned test progression

1. ADD / SUB / AND / OR / XOR
2. Immediate instructions
3. Shift instructions
4. Load / Store
5. Pipeline data hazards
6. Branch instructions
7. Bimodal branch prediction
8. M-extension instructions
9. Automated Spike ↔ RTL trace comparison

## Important Design Decision

Do **not** manually generate ELF files for this workflow.

The earlier custom ELF approach caused memory-map/ELF compatibility problems. For RTL verification, the required artifact is simply:

```text
assembly → machine-code bytes → program.hex
```

Spike can be used separately as the architectural reference.

## Cross-OS Workflow

Current setup:

```text
Linux
├── RISC-V assembler/toolchain
├── Spike
└── test generation

EDA Playground / Windows
└── RTL simulation
```

The exchange files are:

```text
test.S
program.hex
data.hex
simulation results / traces
```

The two simulators do not need to run simultaneously.
======================================================================================================
## Toolchain Summary (asm to hex) 


# Assembly → object
riscv64-unknown-elf-as -march=rv32im -mabi=ilp32 test.S -o test.o

# Object → raw .text binary
riscv64-unknown-elf-objcopy -O binary -j .text test.o test.bin

# Binary → RTL hex
python3 binToHex.py

========================================
# Inspect instructions
riscv64-unknown-elf-objdump -d test.o

=========================================

#Build elf file , open in debug mode

# 1. Build ELF
riscv64-unknown-elf-gcc \
    -march=rv32im \
    -mabi=ilp32 \
    -nostdlib \
    -nostartfiles \
    -T linker.ld \
    -o test.elf \
    test.S

# 2. open spike in debug mode 
 spike -d --isa=RV32IM --priv=m test.elf
 
 #3. reg 0 and copy paste into spike_output.txt
=====================================================================



#Main

(
./makeHex.sh
./run_spike.sh
)
./run_test.sh

Check:

reg 0

python3 compare_regs.py
