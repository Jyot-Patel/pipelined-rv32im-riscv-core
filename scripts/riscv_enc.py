"""RV32I instruction encoding helpers.
Mirrors the enc_* functions in tb_hazards.sv and tb_rv32i_core.sv.
Usage:
    from riscv_enc import *
    instr = enc_i(42, 0, 0, 31, OPC_OP_IMM)  # addi x31, x0, 42
"""

# ---------------------------------------------------------------------------
# RV32I Opcodes (from rv32i_pkg.sv)
# ---------------------------------------------------------------------------
OPC_LUI    = 0b0110111
OPC_AUIPC  = 0b0010111
OPC_JAL    = 0b1101111
OPC_JALR   = 0b1100111
OPC_BRANCH = 0b1100011
OPC_LOAD   = 0b0000011
OPC_STORE  = 0b0100011
OPC_OP_IMM = 0b0010011
OPC_OP     = 0b0110011
OPC_FENCE  = 0b0001111
OPC_SYSTEM = 0b1110011

# ---------------------------------------------------------------------------
# Funct3 aliases
# ---------------------------------------------------------------------------
F3_ADDSUB = 0b000
F3_SLL    = 0b001
F3_SLT    = 0b010
F3_SLTU   = 0b011
F3_XOR    = 0b100
F3_SRL_SRA= 0b101
F3_OR     = 0b110
F3_AND    = 0b111

# Branch funct3
F3_BEQ    = 0b000
F3_BNE    = 0b001
F3_BLT    = 0b100
F3_BGE    = 0b101
F3_BLTU   = 0b110
F3_BGEU   = 0b111

# Load/store funct3
F3_LB     = 0b000
F3_LH     = 0b001
F3_LW     = 0b010
F3_LBU    = 0b100
F3_LHU    = 0b101
F3_SB     = 0b000
F3_SH     = 0b001
F3_SW     = 0b010

# ---------------------------------------------------------------------------
# Funct7 constants
# ---------------------------------------------------------------------------
F7_ADD    = 0b0000000
F7_SUB    = 0b0100000
F7_SLL    = 0b0000000
F7_SLT    = 0b0000000
F7_SLTU   = 0b0000000
F7_XOR    = 0b0000000
F7_SRL    = 0b0000000
F7_SRA    = 0b0100000
F7_OR     = 0b0000000
F7_AND    = 0b0000000

NOP = 0x00000013  # addi x0, x0, 0


def _bit(v: int, pos: int) -> int:
    return (v >> pos) & 1


def _bits(v: int, hi: int, lo: int) -> int:
    """Extract verilog-style bits [hi:lo] (inclusive)."""
    width = hi - lo + 1
    return (v >> lo) & ((1 << width) - 1)


def enc_r(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    """R-type: {funct7[6:0], rs2[4:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]}"""
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_i(imm: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    """I-type: {imm[11:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]}"""
    if imm < 0:
        imm &= 0xFFF
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_s(imm: int, rs2: int, rs1: int, funct3: int, opcode: int) -> int:
    """S-type: {imm[11:5], rs2[4:0], rs1[4:0], funct3[2:0], imm[4:0], opcode[6:0]}"""
    if imm < 0:
        imm &= 0xFFF
    imm_11_5 = (imm >> 5) & 0x7F
    imm_4_0  = imm & 0x1F
    return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_0 << 7) | opcode


def enc_u(imm: int, rd: int, opcode: int) -> int:
    """U-type: {imm[31:12], rd[4:0], opcode[6:0]}"""
    return (imm & 0xFFFFF000) | (rd << 7) | opcode


def enc_b(offset: int, rs2: int, rs1: int, funct3: int, opcode: int) -> int:
    """B-type (branch):
    {offset[12], offset[10:5], rs2[4:0], rs1[4:0], funct3[2:0], offset[4:1], offset[11], opcode[6:0]}
    """
    return (
        (_bit(offset, 12) << 31) |
        (_bits(offset, 10, 5) << 25) |
        (rs2 << 20) |
        (rs1 << 15) |
        (funct3 << 12) |
        (_bits(offset, 4, 1) << 8) |
        (_bit(offset, 11) << 7) |
        opcode
    )


def enc_j(offset: int, rd: int, opcode: int) -> int:
    """J-type (jal):
    {offset[20], offset[10:1], offset[11], offset[19:12], rd[4:0], opcode[6:0]}
    """
    return (
        (_bit(offset, 20) << 31) |
        (_bits(offset, 10, 1) << 21) |
        (_bit(offset, 11) << 20) |
        (_bits(offset, 19, 12) << 12) |
        (rd << 7) |
        opcode
    )


def instr_name(instr: int) -> str:
    """Return a human-readable name for the instruction (basic RV32I)."""
    opcode = instr & 0x7F
    rd     = (instr >> 7) & 0x1F
    funct3 = (instr >> 12) & 0x7
    rs1    = (instr >> 15) & 0x1F
    rs2    = (instr >> 20) & 0x1F
    funct7 = (instr >> 25) & 0x7F

    if opcode == OPC_OP:
        if funct3 == 0b000:
            return "SUB" if funct7[5] else "ADD"
        names = {0b001: "SLL", 0b010: "SLT", 0b011: "SLTU", 0b100: "XOR",
                 0b101: "SRA" if funct7[5] else "SRL", 0b110: "OR", 0b111: "AND"}
        return names.get(funct3, "?")
    if opcode == OPC_OP_IMM:
        if funct3 == 0b000:   return "ADDI"
        if funct3 == 0b010:   return "SLTI"
        if funct3 == 0b011:   return "SLTIU"
        if funct3 == 0b100:   return "XORI"
        if funct3 == 0b110:   return "ORI"
        if funct3 == 0b111:   return "ANDI"
        if funct3 == 0b001:   return "SLLI"
        if funct3 == 0b101:   return "SRLI" if not funct7[5] else "SRAI"
        return "?"
    if opcode == OPC_LUI:     return "LUI"
    if opcode == OPC_AUIPC:   return "AUIPC"
    if opcode == OPC_JAL:     return "JAL"
    if opcode == OPC_JALR:    return "JALR"
    if opcode == OPC_BRANCH:
        return {0b000: "BEQ", 0b001: "BNE", 0b100: "BLT", 0b101: "BGE",
                0b110: "BLTU", 0b111: "BGEU"}.get(funct3, "?")
    if opcode == OPC_LOAD:
        return {0b000: "LB", 0b001: "LH", 0b010: "LW", 0b100: "LBU", 0b101: "LHU"}.get(funct3, "?")
    if opcode == OPC_STORE:
        return {0b000: "SB", 0b001: "SH", 0b010: "SW"}.get(funct3, "?")
    if opcode == 0b0001111:   return "FENCE"
    if opcode == 0b1110011:   return "SYSTEM"
    return "???"


def instr_str(instr: int) -> str:
    """Return a string like 'ADDI x31, x0, 42'."""
    name = instr_name(instr)
    opcode = instr & 0x7F
    rd  = (instr >> 7) & 0x1F
    rs1 = (instr >> 15) & 0x1F
    rs2 = (instr >> 20) & 0x1F
    imm = instr >> 20
    if opcode in (OPC_LUI, OPC_AUIPC):
        return f"{name} x{rd}, 0x{imm << 12:08x}"
    if opcode == OPC_JAL:
        return f"{name} x{rd}, ?"
    if opcode == OPC_BRANCH:
        return f"{name} x{rs1}, x{rs2}, ?"
    if opcode == OPC_STORE:
        return f"{name} x{rs2}, {rs1}(?)"
    if opcode in (OPC_LOAD, OPC_OP_IMM, OPC_JALR):
        return f"{name} x{rd}, x{rs1}, 0x{imm & 0xFFF:x}"
    if opcode == OPC_OP:
        return f"{name} x{rd}, x{rs1}, x{rs2}"
    return f"???"
