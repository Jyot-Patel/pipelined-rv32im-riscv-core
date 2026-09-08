#!/usr/bin/env python3
import re
from pathlib import Path

SPIKE_FILE = "spike_output.txt"
TB_FILE = "tb_output.txt"
CLEAN_FILE = "spike_regs.txt"

ABI_TO_X = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7,
    "s0": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13,
    "a4": 14, "a5": 15, "a6": 16, "a7": 17,
    "s2": 18, "s3": 19, "s4": 20, "s5": 21,
    "s6": 22, "s7": 23, "s8": 24, "s9": 25,
    "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
}

def parse_spike(filename):
    text = Path(filename).read_text()
    regs = {}
    for name, value in re.findall(
        r'([A-Za-z][A-Za-z0-9]*):\s*0x([0-9a-fA-F]+)', text
    ):
        if name in ABI_TO_X:
            regs[ABI_TO_X[name]] = value.upper().zfill(8)
    return regs

def parse_rtl(filename):
    text = Path(filename).read_text()
    regs = {}
    for reg, value in re.findall(
        r'#?\s*r(\d+)\s*:\s*([0-9a-fA-F]+)', text, re.I
    ):
        reg = int(reg)
        if 0 <= reg < 32:
            regs[reg] = value.upper().zfill(8)
    return regs

spike = parse_spike(SPIKE_FILE)
rtl = parse_rtl(TB_FILE)

# Clean Spike output in exactly the same format as the RTL TB.
with open(CLEAN_FILE, "w") as f:
    for i in range(32):
        f.write(f"# r{i} : {spike.get(i, '00000000')}\n")

print(f"Created {CLEAN_FILE}")

# Compare all 32 registers.
differences = []
for i in range(32):
    s = spike.get(i, "00000000")
    r = rtl.get(i, "00000000")
    if s != r:
        differences.append((i, r, s))

print("\n========== REGISTER COMPARISON ==========")

for i in range(32):
    rtl_val = rtl.get(i, "00000000")
    spike_val = spike.get(i, "00000000")

    if rtl_val == spike_val:
        print(f"PASS : r{i} matches")
    else:
        print(f"FAIL : r{i} is not matching")
        print(f"       Spike   : {spike_val}")
        print(f"       TB      : {rtl_val}")

print("==========================================")
