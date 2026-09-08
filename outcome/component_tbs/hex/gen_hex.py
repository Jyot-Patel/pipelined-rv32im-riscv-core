"""Generate test hex files from the directed test program in tb_rv32i_core.sv.

Usage: python gen_hex.py
Output: test_prog.hex (instruction memory contents, one 32-bit hex word per line)

The hex format matches $readmemh expectations and is compatible with what
riscv-gnu-toolchain + objcopy would produce (one word per line, lowercase hex).
"""

OPC_OP      = 0b0110011
OPC_OP_IMM  = 0b0010011
OPC_LUI     = 0b0110111
OPC_AUIPC   = 0b0010111
OPC_LOAD    = 0b0000011
OPC_STORE   = 0b0100011
OPC_BRANCH  = 0b1100011
OPC_JAL     = 0b1101111


def enc_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_i(imm, rs1, funct3, rd, opcode):
    imm = imm & 0xFFF
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_s(imm, rs2, rs1, funct3, opcode):
    imm = imm & 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1F) << 7) | opcode


def enc_b(imm, rs2, rs1, funct3, opcode):
    imm = imm & 0x1FFF  # 13-bit signed
    return ((imm >> 12) << 31) | ((imm >> 5) & 0x3F) << 25 | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm >> 1) & 0xF) << 8 | ((imm >> 11) & 1) << 7 | opcode


def enc_u(imm, rd, opcode):
    return (imm & 0xFFFFF000) | (rd << 7) | opcode


def enc_j(imm, rd, opcode):
    imm = imm & 0x1FFFFF  # 21-bit
    return ((imm >> 20) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | opcode


NOP = 0x00000013


def main():
    imem = []
    pc_idx = 0

    def emit(val):
        nonlocal pc_idx
        imem.append(val)
        pc_idx += 1

    def nops(n):
        for _ in range(n):
            emit(NOP)

    # Phase 1: ALU
    emit(enc_i(5, 0, 0, 1, OPC_OP_IMM))       # ADDI x1, x0, 5
    emit(enc_i(-3, 0, 0, 2, OPC_OP_IMM))       # ADDI x2, x0, -3
    emit(enc_i(0, 0, 0, 3, OPC_OP_IMM))        # ADDI x3, x0, 0
    emit(enc_i(0, 0, 0, 4, OPC_OP_IMM))        # ADDI x4, x0, 0
    emit(enc_i(0, 0, 0, 5, OPC_OP_IMM))        # ADDI x5, x0, 0
    nops(4)

    emit(enc_r(0b0000000, 2, 1, 0, 3, OPC_OP))  # ADD x3, x1, x2
    nops(4)
    emit(enc_r(0b0100000, 2, 1, 0, 4, OPC_OP))  # SUB x4, x1, x2
    nops(4)
    emit(enc_r(0b0000000, 2, 1, 0b111, 5, OPC_OP))  # AND x5, x1, x2
    nops(4)
    emit(enc_r(0b0000000, 2, 1, 0b110, 6, OPC_OP))  # OR x6, x1, x2
    nops(4)
    emit(enc_r(0b0000000, 2, 1, 0b100, 7, OPC_OP))  # XOR x7, x1, x2
    nops(4)
    emit(enc_r(0b0000000, 1, 2, 0b010, 8, OPC_OP))  # SLT x8, x2, x1
    nops(4)
    emit(enc_r(0b0000000, 1, 2, 0b011, 9, OPC_OP))  # SLTU x9, x2, x1
    nops(4)
    emit(enc_r(0b0000000, 2, 1, 0b001, 10, OPC_OP)) # SLL x10, x1, x2
    nops(4)
    emit(enc_r(0b0000000, 2, 1, 0b101, 11, OPC_OP)) # SRL x11, x1, x2
    nops(4)
    emit(enc_i(-1, 0, 0, 12, OPC_OP_IMM))      # ADDI x12, x0, -1
    nops(4)
    emit(enc_r(0b0100000, 2, 12, 0b101, 13, OPC_OP)) # SRA x13, x12, x2
    nops(4)

    # Phase 2: Upper immediates
    emit(enc_u(0xABCDE000, 14, OPC_LUI))
    nops(4)
    emit(enc_u(0x00001000, 15, OPC_AUIPC))
    nops(4)

    # Phase 3: Store/Load
    emit(enc_i(42, 0, 0, 16, OPC_OP_IMM))      # ADDI x16, x0, 42
    nops(4)
    emit(enc_s(0, 16, 0, 0b010, OPC_STORE))     # SW x16, 0(x0)
    nops(4)
    emit(enc_i(0, 0, 0b010, 17, OPC_LOAD))      # LW x17, 0(x0)
    nops(4)
    emit(enc_i(0x0AB, 0, 0, 18, OPC_OP_IMM))    # ADDI x18, x0, 0xAB
    nops(4)
    emit(enc_s(4, 18, 0, 0b000, OPC_STORE))     # SB x18, 4(x0)
    nops(4)
    emit(enc_i(4, 0, 0b000, 19, OPC_LOAD))      # LB x19, 4(x0)
    nops(4)
    emit(enc_i(4, 0, 0b100, 20, OPC_LOAD))      # LBU x20, 4(x0)
    nops(4)
    emit(enc_i(-1, 0, 0, 21, OPC_OP_IMM))       # ADDI x21, x0, -1
    nops(4)
    emit(enc_s(8, 21, 0, 0b001, OPC_STORE))     # SH x21, 8(x0)
    nops(4)
    emit(enc_i(8, 0, 0b001, 22, OPC_LOAD))      # LH x22, 8(x0)
    nops(4)
    emit(enc_i(8, 0, 0b101, 23, OPC_LOAD))      # LHU x23, 8(x0)
    nops(4)

    # Phase 4: Branches
    emit(enc_b(8, 1, 1, 0b000, OPC_BRANCH))     # BEQ x1,x1,8 (taken)
    emit(enc_i(99, 0, 0, 24, OPC_OP_IMM))       # skipped
    emit(enc_i(0, 0, 0, 24, OPC_OP_IMM))        # skipped
    emit(enc_i(42, 0, 0, 24, OPC_OP_IMM))       # target: x24=42
    nops(4)

    emit(enc_b(8, 1, 2, 0b000, OPC_BRANCH))     # BEQ x1,x2,8 (not taken)
    emit(enc_i(77, 0, 0, 25, OPC_OP_IMM))       # x25=77
    nops(4)

    emit(enc_b(4, 1, 2, 0b001, OPC_BRANCH))     # BNE x1,x2,4 (taken)
    emit(enc_i(99, 0, 0, 26, OPC_OP_IMM))       # skipped
    emit(enc_i(55, 0, 0, 26, OPC_OP_IMM))       # target: x26=55
    nops(4)

    emit(enc_b(4, 1, 2, 0b100, OPC_BRANCH))     # BLT x2,x1,4 (taken)
    emit(enc_i(99, 0, 0, 27, OPC_OP_IMM))       # skipped
    emit(enc_i(33, 0, 0, 27, OPC_OP_IMM))       # target: x27=33
    nops(4)

    emit(enc_b(4, 2, 1, 0b101, OPC_BRANCH))     # BGE x1,x2,4 (taken)
    emit(enc_i(99, 0, 0, 28, OPC_OP_IMM))       # skipped
    emit(enc_i(22, 0, 0, 28, OPC_OP_IMM))       # target: x28=22
    nops(4)

    emit(enc_b(4, 1, 2, 0b110, OPC_BRANCH))     # BLTU x2,x1,4 (not taken)
    emit(enc_i(11, 0, 0, 29, OPC_OP_IMM))       # x29=11
    nops(4)

    emit(enc_b(4, 1, 2, 0b111, OPC_BRANCH))     # BGEU x2,x1,4 (taken)
    emit(enc_i(99, 0, 0, 30, OPC_OP_IMM))       # skipped
    emit(enc_i(88, 0, 0, 30, OPC_OP_IMM))       # target: x30=88
    nops(4)

    # Phase 5: JAL
    emit(enc_j(8, 31, OPC_JAL))                  # JAL x31,8
    emit(enc_i(99, 0, 0, 24, OPC_OP_IMM))       # skipped
    emit(enc_i(0, 0, 0, 0, OPC_OP_IMM))         # target (NOP, writes x0)
    nops(16)

    # Write hex file
    with open('test_prog.hex', 'w') as f:
        for v in imem:
            f.write(f'{v:08x}\n')

    # Pad to 1024 words
    with open('test_prog.hex', 'a') as f:
        for _ in range(1024 - len(imem)):
            f.write(f'{NOP:08x}\n')

    print(f'Wrote {len(imem)} instructions + padding = 1024 lines to test_prog.hex')

    # Generate empty data mem hex
    with open('test_data.hex', 'w') as f:
        for _ in range(1024):
            f.write('00000000\n')
    print('Wrote 1024 zeros to test_data.hex')


if __name__ == '__main__':
    main()
