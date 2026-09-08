#DEPRICATED
#USED TO LOAD INSTRUCTIONS INSIDE PROGRAM.MEM for initial phase of verification
#THIS IS THE SCRIPT THAT GENERATES THE PROGRAM.MEM (HEX CODES) FILE FROM THE TEST.S FILE
#THIS CONTAINS FUNCTIONS SUCH AS a_addi, a_mul, a_div, a_rem, a_nop, etc. which are used to generate the hex codes for the corresponding assembly instructions.

#CURRENTLY USING :  spike and qemu-riscv32 (gcc riscv tolchain) to run the test.s file and generate the program.mem file.

#!/usr/bin/env python3
"""Generate program.hex / test_program.hex from maximized test.s"""
import sys
sys.path.insert(0,"E:/RISCV_Minimal")
from riscv_enc import *

NOP=0x00000013
F7_M=0b0000001
prog=[]

def a_addi(rd,rs1,imm): prog.append((f"addi x{rd}, x{rs1}, {imm}", enc_i(imm,rs1,0b000,rd,OPC_OP_IMM)))
def a_lui(rd,imm): prog.append((f"lui x{rd}, 0x{imm>>12:x}", enc_u(imm,rd,OPC_LUI)))
def a_mul(rd,rs1,rs2): prog.append((f"mul x{rd}, x{rs1}, x{rs2}", enc_r(F7_M,rs2,rs1,0b000,rd,OPC_OP)))
def a_mulh(rd,rs1,rs2): prog.append((f"mulh x{rd}, x{rs1}, x{rs2}", enc_r(F7_M,rs2,rs1,0b001,rd,OPC_OP)))
def a_mulhsu(rd,rs1,rs2): prog.append((f"mulhsu x{rd}, x{rs1}, x{rs2}", enc_r(F7_M,rs2,rs1,0b010,rd,OPC_OP)))
def a_mulhu(rd,rs1,rs2): prog.append((f"mulhu x{rd}, x{rs1}, x{rs2}", enc_r(F7_M,rs2,rs1,0b011,rd,OPC_OP)))
def a_div(rd,rs1,rs2): prog.append((f"div x{rd}, x{rs1}, x{rs2}", enc_r(F7_M,rs2,rs1,0b100,rd,OPC_OP)))
def a_divu(rd,rs1,rs2): prog.append((f"divu x{rd}, x{rs1}, x{rs2}", enc_r(F7_M,rs2,rs1,0b101,rd,OPC_OP)))
def a_rem(rd,rs1,rs2): prog.append((f"rem x{rd}, x{rs1}, x{rs2}", enc_r(F7_M,rs2,rs1,0b110,rd,OPC_OP)))
def a_remu(rd,rs1,rs2): prog.append((f"remu x{rd}, x{rs1}, x{rs2}", enc_r(F7_M,rs2,rs1,0b111,rd,OPC_OP)))
def a_nop(): prog.append(("nop",NOP))
def a_jal(rd,off): prog.append((f"jal x{rd}, {off}", enc_j(off,rd,OPC_JAL)))

# ---- mirror test.s exactly ----
a_addi(1,0,10); a_addi(2,0,20); a_addi(3,0,-10); a_addi(4,0,-5); a_addi(5,0,7)
a_addi(6,0,12); a_addi(7,0,3); a_addi(8,0,0); a_addi(9,0,-1); a_lui(10,0x80000000)
for _ in range(4): a_nop()

a_mul(13,1,2)
for _ in range(4): a_nop()
a_mul(14,3,2)
for _ in range(4): a_nop()
a_mulh(15,1,2)
for _ in range(4): a_nop()
a_mulh(16,3,2)
for _ in range(4): a_nop()
a_mulh(17,10,10)
for _ in range(4): a_nop()
a_mulhsu(18,1,9)
for _ in range(4): a_nop()
a_mulhsu(19,3,2)
for _ in range(4): a_nop()
a_mulhu(20,1,2)
for _ in range(4): a_nop()
a_mulhu(21,9,9)
for _ in range(4): a_nop()
a_div(22,2,1)
for _ in range(4): a_nop()
a_div(23,3,5)
for _ in range(4): a_nop()
a_div(24,10,9)
for _ in range(4): a_nop()
a_div(25,1,8)
for _ in range(4): a_nop()
a_divu(26,2,5)
for _ in range(4): a_nop()
a_divu(27,2,8)
for _ in range(4): a_nop()
a_rem(28,2,1)
for _ in range(4): a_nop()
a_rem(29,3,5)
for _ in range(4): a_nop()
a_rem(30,1,8)
for _ in range(4): a_nop()
a_rem(31,10,9)
for _ in range(4): a_nop()
a_remu(11,2,5)
for _ in range(4): a_nop()
a_remu(12,2,8)
for _ in range(4): a_nop()

a_addi(6,0,6)
for _ in range(4): a_nop()
a_mul(11,6,5)
a_addi(11,11,1)
for _ in range(4): a_nop()

a_addi(3,0,2); a_addi(4,0,3); a_addi(5,0,4); a_addi(6,0,5)
for _ in range(4): a_nop()
a_mul(11,3,4)
a_mul(12,5,6)
for _ in range(4): a_nop()
a_jal(0,0)

# write
for path in ["E:/RISCV_Minimal/program.hex","E:/RISCV_Minimal/test_program.hex"]:
    with open(path,"w") as f:
        for _,c in prog: f.write(f"{c:08x}\n")

with open("E:/RISCV_Minimal/test.lst","w") as f:
    f.write("# PC      CODE     ASM\n")
    for i,(asm,c) in enumerate(prog):
        f.write(f"{i*4:08x} {c:08x}  {asm}\n")

with open("E:/RISCV_Minimal/data.hex","w") as f:
    for _ in range(16): f.write("00000000\n")
with open("E:/RISCV_Minimal/test_data.hex","w") as f:
    for _ in range(16): f.write("00000000\n")

print(f"Generated {len(prog)} words")
for i,(a,c) in enumerate(prog[:14]): print(f"{i*4:04x}: {c:08x} {a}")
