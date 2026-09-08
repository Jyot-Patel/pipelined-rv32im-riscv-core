#!/bin/bash

set -e

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


