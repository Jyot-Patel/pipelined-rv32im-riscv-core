// =============================================================================
// Singular RTL for RV32IM SoC -- Top: soc_top
// Auto-generated 2026-08-29 13:09
// Top module: soc_top
// Includes fixes: load_store byte lane, tb x24, data_mem always @(posedge clk) for Questa
// =============================================================================

// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\common\rv32i_pkg.sv
// -----------------------------------------------------------------------------
// ============================================================================
// Package: rv32i_pkg
// Description: RV32I ISA constants ? opcodes, ALU ops, control types
// Target: Synthesizable, Intel Quartus / Cyclone-class FPGA
// ============================================================================

package rv32i_pkg;

  // --------------------------------------------------------------------------
  // RV32I Opcodes (inst[6:0])
  // --------------------------------------------------------------------------
  typedef enum logic [6:0] {
    OPC_LUI    = 7'b0110111,
    OPC_AUIPC  = 7'b0010111,
    OPC_JAL    = 7'b1101111,
    OPC_JALR   = 7'b1100111,
    OPC_BRANCH = 7'b1100011,
    OPC_LOAD   = 7'b0000011,
    OPC_STORE  = 7'b0100011,
    OPC_OP_IMM = 7'b0010011,
    OPC_OP     = 7'b0110011,
    OPC_FENCE  = 7'b0001111,
    OPC_SYSTEM = 7'b1110011
  } opcode_t;

  // --------------------------------------------------------------------------
  // ALU operation codes (internal, not ISA-encoded)
  // --------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ALU_ADD  = 4'b0000,
    ALU_SUB  = 4'b0001,
    ALU_AND  = 4'b0010,
    ALU_OR   = 4'b0011,
    ALU_XOR  = 4'b0100,
    ALU_SLL  = 4'b0101,
    ALU_SRL  = 4'b0110,
    ALU_SRA  = 4'b0111,
    ALU_SLT  = 4'b1000,
    ALU_SLTU = 4'b1001,
    ALU_NOP  = 4'b1111   // pass operand A through (for LUI/AUIPC/JAL/JALR PC+4)
  } alu_op_t;

  // --------------------------------------------------------------------------
  // Forwarding source select (for hazard unit)
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    FWD_REGFILE = 2'b00,   // no forward ? use regfile output
    FWD_EX_MEM  = 2'b01,   // forward from EX/MEM pipeline register
    FWD_MEM_WB  = 2'b10,   // forward from WB stage (wb_wdata)
    FWD_MULDIV  = 2'b11    // forward from muldiv_done writeback
  } forward_sel_t;

  // --------------------------------------------------------------------------
  // Immediate types for sign extension
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    IMM_I  = 3'b000,
    IMM_S  = 3'b001,
    IMM_B  = 3'b010,
    IMM_U  = 3'b011,
    IMM_J  = 3'b100,
    IMM_NONE = 3'b111
  } imm_type_t;

  // --------------------------------------------------------------------------
  // Write-back source select
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    WB_ALU   = 2'b00,   // ALU result
    WB_MEM   = 2'b01,   // data memory load
    WB_PC4   = 2'b10,   // PC + 4 (JAL/JALR link)
    WB_IMM   = 2'b11    // upper immediate (LUI/AUIPC handled differently)
  } wb_src_t;

  // --------------------------------------------------------------------------
  // Funct3 encodings for branch comparison
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    BR_BEQ  = 3'b000,
    BR_BNE  = 3'b001,
    BR_BLT  = 3'b100,
    BR_BGE  = 3'b101,
    BR_BLTU = 3'b110,
    BR_BGEU = 3'b111
  } branch_funct3_t;

  // --------------------------------------------------------------------------
  // Funct3 for load byte/half/word sign extension
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    LB  = 3'b000,
    LH  = 3'b001,
    LW  = 3'b010,
    LBU = 3'b100,
    LHU = 3'b101
  } load_funct3_t;

  // --------------------------------------------------------------------------
  // Funct3 for store
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    SB = 3'b000,
    SH = 3'b001,
    SW = 3'b010
  } store_funct3_t;

  // --------------------------------------------------------------------------
  // Pipeline width constants
  // --------------------------------------------------------------------------
  localparam int unsigned XLEN     = 32;
  localparam int unsigned REG_ADDR = 5;   // rd/rs1/rs2 address width
  localparam int unsigned NUM_REGS = 32;

endpackage


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\units\alu.sv
// -----------------------------------------------------------------------------
// ============================================================================
// Module: alu
// Description: RV32I ALU ? all integer operations.
//              alu_op_t selects the operation, combinational output.
// Target: Synthesizable
// ============================================================================

module alu
  import rv32i_pkg::*;
(
  input  logic [XLEN-1:0]     op_a,
  input  logic [XLEN-1:0]     op_b,
  input  alu_op_t             alu_op,
  output logic [XLEN-1:0]     result,
  output logic                zero
);

  always_comb begin
    result = '0;
    unique case (alu_op)
      ALU_ADD:  result = op_a + op_b;
      ALU_SUB:  result = op_a - op_b;
      ALU_AND:  result = op_a & op_b;
      ALU_OR:   result = op_a | op_b;
      ALU_XOR:  result = op_a ^ op_b;
      ALU_SLL:  result = op_a << op_b[4:0];
      ALU_SRL:  result = $unsigned(op_a) >> op_b[4:0];
      ALU_SRA:  result = $signed(op_a) >>> op_b[4:0];
      ALU_SLT:  result = {31'b0, $signed(op_a) < $signed(op_b)};
      ALU_SLTU: result = {31'b0, $unsigned(op_a) < $unsigned(op_b)};
      ALU_NOP:  result = op_a;  // pass-through (LUI, AUIPC, JAL/JALR link addr)
      default:  result = '0;
    endcase
  end

  assign zero = (result == '0);

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\units\decoder.sv
// -----------------------------------------------------------------------------
// ============================================================================
// Module: decoder
// Description: RV32I instruction decoder.
//              Extracts fields (rd, rs1, rs2, funct3, funct7, immediate)
//              and produces control signals for the pipeline.
//              Combinational ? no state.
// Target: Synthesizable
// ============================================================================

module decoder
  import rv32i_pkg::*;
(
  input  logic [XLEN-1:0]     instr,
  // Decoded fields
  output logic [REG_ADDR-1:0] rd,
  output logic [REG_ADDR-1:0] rs1,
  output logic [REG_ADDR-1:0] rs2,
  output logic [2:0]          funct3,
  output logic [6:0]          funct7,
  output opcode_t             opcode,
  output logic [XLEN-1:0]     imm,
  // Control signals
  output logic                reg_write,
  output logic                mem_read,
  output logic                mem_write,
  output logic [1:0]          wb_src,       // 00=ALU, 01=MEM, 10=PC4
  output logic                alu_src,      // 0=rs2, 1=imm
  output logic                branch,
  output logic                jump,         // JAL
  output logic                jump_reg,     // JALR
  output logic                upper_imm,    // LUI/AUIPC
  output logic                auipc_src,    // 0=LUI(imm), 1=AUIPC(imm+PC)
  output alu_op_t             alu_op,
  output logic [2:0]          mem_funct3,   // load/store size/signedness
  // M-extension
  output logic                is_muldiv,
  output logic [2:0]          muldiv_op
);

  // --------------------------------------------------------------------------
  // Field extraction
  // --------------------------------------------------------------------------
  assign opcode = opcode_t'(instr[6:0]);
  assign rd     = instr[11:7];
  assign funct3 = instr[14:12];
  assign rs1    = instr[19:15];
  assign rs2    = instr[24:20];
  assign funct7 = instr[31:25];

  // --------------------------------------------------------------------------
  // Immediate generation (all sign-extended to 32 bits)
  // --------------------------------------------------------------------------
  logic [XLEN-1:0] imm_i, imm_s, imm_b, imm_u, imm_j;

  assign imm_i = {{20{instr[31]}}, instr[31:20]};
  assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
  assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
  assign imm_u = {instr[31:12], 12'b0};
  assign imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

  always_comb begin
    imm = '0;
    unique case (opcode)
      OPC_OP_IMM, OPC_LOAD, OPC_JALR: imm = imm_i;
      OPC_STORE:                       imm = imm_s;
      OPC_BRANCH:                      imm = imm_b;
      OPC_LUI, OPC_AUIPC:             imm = imm_u;
      OPC_JAL:                         imm = imm_j;
      default:                         imm = '0;
    endcase
  end

  // --------------------------------------------------------------------------
  // Control signal generation
  // --------------------------------------------------------------------------
  always_comb begin
    // Defaults ? NOP / bubble
    reg_write  = 1'b0;
    mem_read   = 1'b0;
    mem_write  = 1'b0;
    wb_src     = WB_ALU;
    alu_src    = 1'b0;
    branch     = 1'b0;
    jump       = 1'b0;
    jump_reg   = 1'b0;
    upper_imm  = 1'b0;
    auipc_src  = 1'b0;
    alu_op     = ALU_NOP;
    mem_funct3 = 3'b010; // LW default
    is_muldiv  = 1'b0;
    muldiv_op  = 3'b0;

    unique case (opcode)
      // ----- R-type: register-register ALU -----
      OPC_OP: begin
        reg_write = 1'b1;
        alu_src   = 1'b0;   // rs2
        if (funct7 == 7'b0000001) begin
          // M-extension: MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU
          is_muldiv = 1'b1;
          muldiv_op = funct3;
          alu_op    = ALU_NOP;
        end else begin
          unique case (funct3)
            3'b000: alu_op = (funct7[5]) ? ALU_SUB : ALU_ADD;
            3'b001: alu_op = ALU_SLL;
            3'b010: alu_op = ALU_SLT;
            3'b011: alu_op = ALU_SLTU;
            3'b100: alu_op = ALU_XOR;
            3'b101: alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL;
            3'b110: alu_op = ALU_OR;
            3'b111: alu_op = ALU_AND;
          endcase
        end
      end

      // ----- I-type ALU: register-immediate ALU -----
      OPC_OP_IMM: begin
        reg_write = 1'b1;
        alu_src   = 1'b1;   // immediate
        unique case (funct3)
          3'b000: alu_op = ALU_ADD;                         // ADDI
          3'b010: alu_op = ALU_SLT;                         // SLTI
          3'b011: alu_op = ALU_SLTU;                        // SLTIU
          3'b100: alu_op = ALU_XOR;                         // XORI
          3'b110: alu_op = ALU_OR;                          // ORI
          3'b111: alu_op = ALU_AND;                         // ANDI
          3'b001: alu_op = ALU_SLL;                         // SLLI
          3'b101: alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL; // SRLI/SRAI
        endcase
      end

      // ----- Load -----
      OPC_LOAD: begin
        reg_write = 1'b1;
        mem_read  = 1'b1;
        alu_src   = 1'b1;   // rs1 + imm
        alu_op    = ALU_ADD;
        wb_src    = WB_MEM;
        mem_funct3 = funct3;
      end

      // ----- Store -----
      OPC_STORE: begin
        mem_write = 1'b1;
        alu_src   = 1'b1;   // rs1 + imm
        alu_op    = ALU_ADD;
        mem_funct3 = funct3;
      end

      // ----- Branch -----
      OPC_BRANCH: begin
        branch = 1'b1;
        alu_op = ALU_NOP;   // branch comparison done separately in EX
        mem_funct3 = funct3; // branch condition type (BEQ/BNE/BLT/BGE/BLTU/BGEU)
      end

      // ----- LUI -----
      OPC_LUI: begin
        reg_write = 1'b1;
        upper_imm = 1'b1;
        alu_op    = ALU_NOP;  // imm passed through
      end

      // ----- AUIPC -----
      OPC_AUIPC: begin
        reg_write = 1'b1;
        upper_imm = 1'b1;
        auipc_src = 1'b1;   // PC + imm
        alu_src   = 1'b1;   // imm as operand B
        alu_op    = ALU_ADD; // PC + imm
      end

      // ----- JAL -----
      OPC_JAL: begin
        reg_write = 1'b1;
        jump      = 1'b1;
        wb_src    = WB_PC4;
      end

      // ----- FENCE / FENCE.I (pipeline no-ops) -----
      OPC_FENCE: begin
        // Single-hart, no-cache: no ordering or cache-flush needed.
        // All control signals remain at default (all 0s) ? NOP behavior.
      end

      // ----- JALR -----
      OPC_JALR: begin
        reg_write = 1'b1;
        jump_reg  = 1'b1;
        alu_src   = 1'b1;
        alu_op    = ALU_ADD;  // rs1 + imm for target
        wb_src    = WB_PC4;
      end

      default: begin
        // Illegal / unsupported ? emit NOP-like control
      end
    endcase
  end

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\units\regfile.sv
// -----------------------------------------------------------------------------
module regfile
  import rv32i_pkg::*;
(
  input  logic                    clk,
  input  logic                    rst_n,
  // Read port A
  input  logic [REG_ADDR-1:0]     raddr_a,
  output logic [XLEN-1:0]         rdata_a,
  // Read port B
  input  logic [REG_ADDR-1:0]     raddr_b,
  output logic [XLEN-1:0]         rdata_b,
  // Write port
  input  logic                    we,
  input  logic [REG_ADDR-1:0]     waddr,
  input  logic [XLEN-1:0]         wdata,
  // Debug read port (combinational, non-intrusive)
  input  logic [REG_ADDR-1:0]     dbg_addr,
  output logic [XLEN-1:0]         dbg_data
);

  logic [XLEN-1:0] regs [1:NUM_REGS-1];

  always_comb begin
    if (raddr_a == 5'b0) begin
      rdata_a = '0;
    end else if (we && raddr_a == waddr) begin
      rdata_a = wdata;
    end else begin
      rdata_a = regs[raddr_a];
    end
  end

  always_comb begin
    if (raddr_b == 5'b0) begin
      rdata_b = '0;
    end else if (we && raddr_b == waddr) begin
      rdata_b = wdata;
    end else begin
      rdata_b = regs[raddr_b];
    end
  end

  always_comb begin
    if (dbg_addr == 5'b0) begin
      dbg_data = '0;
    end else if (we && dbg_addr == waddr) begin
      dbg_data = wdata;
    end else begin
      dbg_data = regs[dbg_addr];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 1; i < NUM_REGS; i++) begin
        regs[i] <= '0;
      end
    end else if (we && waddr != 5'b0) begin
      regs[waddr] <= wdata;
    end
  end

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\units\hazard_unit.sv
// -----------------------------------------------------------------------------
module hazard_unit
  import rv32i_pkg::*;
(
  input  logic                clk,
  input  logic                rst_n,
  // ID stage ? instruction being decoded
  input  logic [REG_ADDR-1:0] id_rs1,
  input  logic [REG_ADDR-1:0] id_rs2,
  input  logic [REG_ADDR-1:0] id_rd,
  input  logic                id_is_muldiv,
  // ID/EX stage ? instruction currently in execution
  input  logic [REG_ADDR-1:0] idex_rd,
  input  logic [REG_ADDR-1:0] idex_rs1,
  input  logic [REG_ADDR-1:0] idex_rs2,
  input  logic                idex_mem_read,
  input  logic                idex_is_muldiv,
  // EX/MEM stage ? result available for forwarding
  input  logic [REG_ADDR-1:0] exmem_rd,
  input  logic                exmem_reg_write,
  input  logic                exmem_mem_read,
  // MEM/WB stage ? result available for forwarding
  input  logic [REG_ADDR-1:0] memwb_rd,
  input  logic                memwb_reg_write,
  // External/global control inputs for stall policy
  input  logic                ext_stall,
  input  logic                pipe_flush,
  input  logic                pipe_flush_d1,
  // M-extension: stall while muldiv_unit is busy
  input  logic                muldiv_busy,
  // M-extension: muldiv_done writeback forwarding
  input  logic                muldiv_done,
  input  logic [REG_ADDR-1:0] muldiv_result_rd,
  // Outputs
  output forward_sel_t        forward_a_sel,
  output forward_sel_t        forward_b_sel,
  output logic                stall,            // load-use stall
  output logic                load_use_stall,
  output logic                muldiv_stall,
  output logic                ifid_stall,
  output logic                pc_stall,
  output logic                downstream_stall,
  output logic                wb_conflict
);

  // ==========================================================================
  // Scoreboard for in-flight MUL/DIV
  // ==========================================================================
  logic        mul_active;
  logic [4:0]  mul_rd;
  logic        mul_rd_valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mul_active   <= 1'b0;
      mul_rd       <= '0;
      mul_rd_valid <= 1'b0;
    end else begin
      // Flush: discard in-flight MUL (speculative mispredict)
      if (pipe_flush && mul_active) begin
        mul_active   <= 1'b0;
        mul_rd_valid <= 1'b0;
      end
      // Done: clear scoreboard
      if (muldiv_done) begin
        mul_active   <= 1'b0;
        mul_rd_valid <= 1'b0;
      end
      // New MUL entering: only when not simultaneously completing
      if (idex_is_muldiv && !muldiv_busy && !muldiv_done && !pipe_flush) begin
        mul_active   <= 1'b1;
        mul_rd       <= idex_rd;
        mul_rd_valid <= 1'b1;
      end
    end
  end

  // ==========================================================================
  // Dependency detection ? RAW + WAW
  // ==========================================================================
  logic raw_dep;
  logic waw_dep;
  logic muldiv_structural;

  // RAW dependency: instruction in IF/ID reads a register written by in-flight MUL/DIV
  assign raw_dep = mul_rd_valid && !muldiv_done &&
                   (mul_rd != 5'b0) &&
                   (mul_rd == id_rs1 || mul_rd == id_rs2);

  // WAW dependency: instruction in IF/ID writes same register as in-flight MUL/DIV
  // Without this, a younger ADD could complete first, then MUL overwrites it.
  assign waw_dep = mul_rd_valid && !muldiv_done &&
                   (mul_rd != 5'b0) &&
                   (mul_rd == id_rd);

  // Structural hazard: new MUL/DIV cannot enter while one is already active
  // Gated by !muldiv_done: on the done cycle, scoreboard clears same posedge,
  // so combinational check must not block (the done pulse IS the completion).
  // Structural hazard: new MUL/DIV cannot enter while one is already active
  // Also stall 1 cycle when a new MUL/DIV first enters (muldiv_entry) so the
  // scoreboard can latch before dependent instructions flow past it.
  logic muldiv_entry;
  assign muldiv_entry = idex_is_muldiv && !muldiv_busy && !muldiv_done && !pipe_flush;
  assign muldiv_structural = (idex_is_muldiv && mul_active && !muldiv_done) || muldiv_entry;

  // ==========================================================================
  // Writeback conflict: MUL result and MEM/WB both need the single write port
  // ==========================================================================
  assign wb_conflict = muldiv_done && memwb_reg_write;

  // ==========================================================================
  // Forwarding: muldiv_done has highest priority (writeback bypass),
  // EX/MEM second, MEM/WB third.
  // Never forward to x0 (rs1/rs2 == 0).  Never forward a load's address
  // from EX/MEM (load data isn't ready until MEM/WB).
  // ==========================================================================
  always_comb begin
    // Forward A (rs1)
    if (muldiv_done && muldiv_result_rd != 5'b0 && muldiv_result_rd == idex_rs1)
      forward_a_sel = FWD_MULDIV;
    else if (exmem_reg_write && !exmem_mem_read && exmem_rd != 5'b0 && exmem_rd == idex_rs1)
      forward_a_sel = FWD_EX_MEM;
    else if (memwb_reg_write && memwb_rd != 5'b0 && memwb_rd == idex_rs1)
      forward_a_sel = FWD_MEM_WB;
    else
      forward_a_sel = FWD_REGFILE;

    // Forward B (rs2)
    if (muldiv_done && muldiv_result_rd != 5'b0 && muldiv_result_rd == idex_rs2)
      forward_b_sel = FWD_MULDIV;
    else if (exmem_reg_write && !exmem_mem_read && exmem_rd != 5'b0 && exmem_rd == idex_rs2)
      forward_b_sel = FWD_EX_MEM;
    else if (memwb_reg_write && memwb_rd != 5'b0 && memwb_rd == idex_rs2)
      forward_b_sel = FWD_MEM_WB;
    else
      forward_b_sel = FWD_REGFILE;
  end

  // ==========================================================================
  // Stall policy ? NON-BLOCKING M-EXTENSION
  // ==========================================================================

  // Load-use stall: same as before
  assign load_use_stall = idex_mem_read &&
                           idex_rd != 5'b0 &&
                           (idex_rd == id_rs1 || idex_rd == id_rs2);

  // MUL/DIV stall: RAW or WAW dependency, or structural hazard
  assign muldiv_stall = raw_dep || waw_dep || muldiv_structural;

  // Legacy 'stall' ? only load-use (muldiv no longer blocks globally)
  assign stall = load_use_stall;

  // IF/ID stalls for external stalls, load-use, selective muldiv interlock,
  // AND writeback conflict (1-cycle backpressure when MUL and MEM/WB collide)
  assign ifid_stall = ext_stall ||
                       load_use_stall ||
                       muldiv_stall ||
                       wb_conflict;

  // PC stalls when ID stage is stalled
  assign pc_stall = ext_stall ||
                     load_use_stall ||
                     muldiv_stall ||
                     wb_conflict;

  // Downstream stages stall on writeback conflict (freeze MEM/WB so it retries)
  assign downstream_stall = ext_stall || wb_conflict;

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\units\branch_predictor.sv
// -----------------------------------------------------------------------------
module branch_predictor
  import rv32i_pkg::*;
(
  input  logic             clk,
  input  logic             rst_n,

  // Fetch interface (IF stage) ? combinational read
  input  logic [XLEN-1:0]  fetch_pc,
  output logic             pred_taken,
  output logic [XLEN-1:0]  pred_target,

  // Resolve interface (EX stage) ? update at posedge
  input  logic             resolve_valid,
  input  logic [XLEN-1:0]  resolve_pc,
  input  logic             resolve_taken,
  input  logic [XLEN-1:0]  resolve_target
);

  // --------------------------------------------------------------------------
  // Internal state
  // --------------------------------------------------------------------------
  localparam int unsigned BHT_ENTRIES = 64;
  localparam int unsigned BTB_ENTRIES = 64;

  typedef struct packed {
    logic                valid;
    logic [XLEN-1:0]     target;
    logic [3:0]          tag;
  } btb_entry_t;

  // BHT: 2-bit saturating counters, indexed PC[7:2]
  logic [1:0] bht [0:BHT_ENTRIES-1];

  // BTB: valid bit + full target address, indexed PC[7:2]
  btb_entry_t btb [0:BTB_ENTRIES-1];

  // --------------------------------------------------------------------------
  // Prediction (combinational, read in IF stage)
  // --------------------------------------------------------------------------
  always_comb begin
    logic [5:0] idx;
    logic       tag_match;
    idx = fetch_pc[7:2];
    tag_match = (btb[idx].tag == fetch_pc[11:8]);
    pred_taken  = btb[idx].valid && tag_match && bht[idx][1];
    pred_target = btb[idx].target;
  end

  // --------------------------------------------------------------------------
  // Update (at posedge, from EX stage resolve)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < BHT_ENTRIES; i++) begin
        bht[i] <= 2'b01;  // weakly not-taken (warm start)
      end
      for (int i = 0; i < BTB_ENTRIES; i++) begin
        btb[i].valid <= 1'b0;
        btb[i].target <= '0;
        btb[i].tag <= '0;
      end
    end else if (resolve_valid) begin
      logic [5:0] idx;
      idx = resolve_pc[7:2];

      // BHT: increment on taken, decrement on not-taken (saturating)
      if (resolve_taken) begin
        if (bht[idx] != 2'b11) bht[idx] <= bht[idx] + 1'b1;
      end else begin
        if (bht[idx] != 2'b00) bht[idx] <= bht[idx] - 1'b1;
      end

      // BTB: allocate/update only on taken branches/jumps
      if (resolve_taken) begin
        btb[idx].valid  <= 1'b1;
        btb[idx].target <= resolve_target;
        btb[idx].tag    <= resolve_pc[11:8];
      end
    end
  end

endmodule

// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\units\muldiv_unit.sv
// -----------------------------------------------------------------------------
module muldiv_unit
  import rv32i_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        flush,
  input  logic [XLEN-1:0] operand_a,
  input  logic [XLEN-1:0] operand_b,
  input  logic [2:0]  op_sel,
  input  logic        valid,
  input  logic [4:0]  rd_in,
  input  logic        reg_write_in,
  output logic [XLEN-1:0] result,
  output logic        busy,
  output logic        done,
  output logic [4:0]  result_rd,
  output logic        result_we
);

  typedef enum logic [1:0] { IDLE, BUSY, DONE } state_t;
  state_t state;
  logic [5:0] cnt;

  logic [31:0] a_reg, b_reg;
  logic [2:0]  op_reg;
  logic [4:0]  muldiv_rd;
  logic        muldiv_we;

  logic [32:0] mul_hi;
  logic [31:0] mul_lo, mul_mplier, mul_mcand_reg;

  logic [31:0] div_rem, div_quot, div_divisor_reg;

  logic        is_mul;
  logic        is_signed_div;

  assign is_mul   = (op_reg <= 3'b011);
  assign is_signed_div = (op_reg == 3'b100) || (op_reg == 3'b110);

  assign busy = (state != IDLE);

  assign result_rd = muldiv_rd;
  assign result_we = muldiv_we;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      cnt   <= '0;
      mul_hi  <= '0;
      mul_lo  <= '0;
      mul_mplier <= '0;
      mul_mcand_reg <= '0;
      div_rem   <= '0;
      div_quot  <= '0;
      div_divisor_reg <= '0;
      a_reg   <= '0;
      b_reg   <= '0;
      op_reg  <= '0;
      muldiv_rd <= '0;
      muldiv_we <= 1'b0;
      done    <= 1'b0;
    end else begin
      done <= 1'b0;

      // Flush: kill in-flight operation, suppress writeback
      if (flush && state != IDLE) begin
        state      <= IDLE;
        cnt        <= '0;
        muldiv_we  <= 1'b0;
        done       <= 1'b0;
      end else begin
        case (state)
          IDLE: begin
            if (valid && !done) begin
              a_reg <= operand_a;
              b_reg <= operand_b;
              op_reg <= op_sel;
              muldiv_rd <= rd_in;
              muldiv_we <= reg_write_in;
              state <= BUSY;
              cnt <= 6'd1;
              if (op_sel <= 3'b011) begin
                mul_hi <= 33'b0;
                mul_lo <= 32'b0;
                mul_mplier <= operand_b;
                mul_mcand_reg <= operand_a;
              end else begin
                div_rem <= 32'b0;
                if (operand_b == 32'b0) begin
                  state <= DONE;
                end else if (op_sel == 3'b100 || op_sel == 3'b110) begin
                  div_quot <= operand_a[31] ? (-operand_a) : operand_a;
                  div_divisor_reg <= operand_b[31] ? (-operand_b) : operand_b;
                end else begin
                  div_quot <= operand_a;
                  div_divisor_reg <= operand_b;
                end
              end
            end
          end

          BUSY: begin
            if (is_mul) begin
              if (mul_mplier[0]) begin
                logic [32:0] sum;
                sum = mul_hi + mul_mcand_reg;
                mul_hi <= {1'b0, sum[32:1]};
                mul_lo <= {sum[0], mul_lo[31:1]};
              end else begin
                mul_hi <= {1'b0, mul_hi[32:1]};
                mul_lo <= {mul_hi[0], mul_lo[31:1]};
              end
              mul_mplier <= {1'b0, mul_mplier[31:1]};
              if (cnt == 6'd32) begin
                state <= DONE;
                cnt <= '0;
              end else begin
                cnt <= cnt + 6'd1;
              end
            end else begin
              logic [31:0] n_rem, n_quot;
              n_rem = {div_rem[30:0], div_quot[31]};
              n_quot = {div_quot[30:0], 1'b0};
              if (n_rem >= div_divisor_reg) begin
                n_rem = n_rem - div_divisor_reg;
                n_quot[0] = 1'b1;
              end
              div_rem <= n_rem;
              div_quot <= n_quot;
              if (cnt == 6'd32) begin
                state <= DONE;
                cnt <= '0;
              end else begin
                cnt <= cnt + 6'd1;
              end
            end
          end

          DONE: begin
            done <= 1'b1;
            state <= IDLE;
          end
        endcase
      end
    end
  end

  always_comb begin
    result = '0;
    if (is_mul) begin
      case (op_reg)
        3'b000: result = mul_lo;
        3'b001: begin
          result = mul_hi[31:0];
          if (a_reg[31]) result = result - b_reg;
          if (b_reg[31]) result = result - a_reg;
        end
        3'b010: begin
          result = mul_hi[31:0];
          if (a_reg[31]) result = result - b_reg;
        end
        3'b011: result = mul_hi[31:0];
        default: result = '0;
      endcase
    end else if (op_reg == 3'b110 || op_reg == 3'b111) begin
      if (b_reg == 32'b0)
        result = a_reg;
      else if (a_reg[31] && is_signed_div)
        result = -div_rem;
      else
        result = div_rem;
    end else begin
      if (b_reg == 32'b0)
        result = 32'hFFFFFFFF;
      else if ((a_reg[31] ^ b_reg[31]) && is_signed_div)
        result = -div_quot;
      else
        result = div_quot;
    end
  end

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\mux\mux_alu_operand_a.sv
// -----------------------------------------------------------------------------
module mux_alu_operand_a
  import rv32i_pkg::*;
(
  input  forward_sel_t    forward_a_sel,
  input  logic            idex_auipc_src,
  input  logic [XLEN-1:0] idex_rs1_data,
  input  logic [XLEN-1:0] exmem_alu_result,
  input  logic [XLEN-1:0] wb_wdata,
  input  logic [XLEN-1:0] muldiv_result,
  input  logic [XLEN-1:0] idex_pc4,
  output logic [XLEN-1:0] ex_alu_op_a,
  output logic [XLEN-1:0] fwd_rs1_data
);

  always_comb begin
    unique case (forward_a_sel)
      FWD_EX_MEM:  fwd_rs1_data = exmem_alu_result;
      FWD_MEM_WB:  fwd_rs1_data = wb_wdata;
      FWD_MULDIV:  fwd_rs1_data = muldiv_result;
      default:     fwd_rs1_data = idex_rs1_data;
    endcase
  end

  assign ex_alu_op_a = idex_auipc_src ? (idex_pc4 - 32'd4) : fwd_rs1_data;

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\mux\mux_alu_operand_b.sv
// -----------------------------------------------------------------------------
module mux_alu_operand_b
  import rv32i_pkg::*;
(
  input  forward_sel_t    forward_b_sel,
  input  logic            idex_alu_src,
  input  logic [XLEN-1:0] idex_rs2_data,
  input  logic [XLEN-1:0] exmem_alu_result,
  input  logic [XLEN-1:0] wb_wdata,
  input  logic [XLEN-1:0] muldiv_result,
  input  logic [XLEN-1:0] idex_imm,
  output logic [XLEN-1:0] ex_alu_op_b,
  output logic [XLEN-1:0] fwd_rs2_data
);

  always_comb begin
    unique case (forward_b_sel)
      FWD_EX_MEM:  fwd_rs2_data = exmem_alu_result;
      FWD_MEM_WB:  fwd_rs2_data = wb_wdata;
      FWD_MULDIV:  fwd_rs2_data = muldiv_result;
      default:     fwd_rs2_data = idex_rs2_data;
    endcase
  end

  assign ex_alu_op_b = idex_alu_src ? idex_imm : fwd_rs2_data;

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\mux\mux_imm_sel.sv
// -----------------------------------------------------------------------------
module mux_imm_sel
  import rv32i_pkg::*;
(
  input  logic            idex_jump,
  input  logic            idex_jump_reg,
  input  logic            idex_upper_imm,
  input  logic            idex_auipc_src,
  input  logic [XLEN-1:0] idex_pc4,
  input  logic [XLEN-1:0] idex_imm,
  input  logic [XLEN-1:0] ex_alu_result,
  output logic [XLEN-1:0] ex_wb_value
);

  always_comb begin
    if (idex_jump || idex_jump_reg)
      ex_wb_value = idex_pc4;
    else if (idex_upper_imm && !idex_auipc_src)
      ex_wb_value = idex_imm;
    else
      ex_wb_value = ex_alu_result;
  end

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\mux\mux_pc_sel.sv
// -----------------------------------------------------------------------------
module mux_pc_sel
  import rv32i_pkg::*;
(
  input  logic            ex_bp_mispredict,
  input  logic            muldiv_done,
  input  logic            haz_stall,
  input  logic            pipe_flush,
  input  logic            pipe_flush_d1,
  input  logic            bp_pred_taken,
  input  logic            ifid_stall,
  input  logic            flush,
  input  logic [XLEN-1:0] redirect_pc,
  input  logic [XLEN-1:0] ifid_pc4,
  input  logic [XLEN-1:0] bp_pred_target,
  input  logic [XLEN-1:0] pc_plus4,
  output logic [XLEN-1:0] pc_next
);

  always_comb begin
    if (ex_bp_mispredict)
      pc_next = redirect_pc;
    else if (muldiv_done)
      pc_next = ifid_pc4;
    else if (haz_stall && !pipe_flush && !pipe_flush_d1)
      pc_next = ifid_pc4;
    else if (bp_pred_taken && !ifid_stall && !flush)
      pc_next = bp_pred_target;
    else
      pc_next = pc_plus4;
  end

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\mux\mux_pc_redirect.sv
// -----------------------------------------------------------------------------
module mux_pc_redirect
  import rv32i_pkg::*;
(
  input  logic [XLEN-1:0] ex_jump_target,
  input  logic [XLEN-1:0] ifid_pc4,
  input  logic            ex_branch_taken,
  input  logic            idex_jump,
  input  logic            idex_jump_reg,
  output logic [XLEN-1:0] redirect_pc
);

  assign redirect_pc = (ex_branch_taken || idex_jump || idex_jump_reg) ?
                       ex_jump_target : (ifid_pc4 - 32'd4);

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\mux\mux_wb_sel.sv
// -----------------------------------------------------------------------------
module mux_wb_sel
  import rv32i_pkg::*;
(
  input  logic [1:0]      memwb_wb_src,
  input  logic [2:0]      memwb_mem_funct3,
  input  logic [XLEN-1:0] memwb_alu_result,
  input  logic [XLEN-1:0] data_rdata,
  output logic [XLEN-1:0] wb_wdata
);

  // FIX Bug 2: shift rdata by byte offset before sign/zero extension
  logic [XLEN-1:0] rdata_shifted;
  assign rdata_shifted = data_rdata >> (memwb_alu_result[1:0] * 8);

  always_comb begin
    unique case (memwb_wb_src)
      WB_ALU: wb_wdata = memwb_alu_result;
      WB_MEM: begin
        unique case (memwb_mem_funct3)
          3'b000: wb_wdata = {{24{rdata_shifted[7]}},  rdata_shifted[7:0]};
          3'b001: wb_wdata = {{16{rdata_shifted[15]}}, rdata_shifted[15:0]};
          3'b010: wb_wdata = data_rdata;
          3'b100: wb_wdata = {24'b0, rdata_shifted[7:0]};
          3'b101: wb_wdata = {16'b0, rdata_shifted[15:0]};
          default: wb_wdata = data_rdata;
        endcase
      end
      WB_PC4: wb_wdata = memwb_alu_result;
      default: wb_wdata = memwb_alu_result;
    endcase
  end

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\pipeline\if_id_reg.sv
// -----------------------------------------------------------------------------
module if_id_reg
  import rv32i_pkg::*;
(
  input  logic             clk,
  input  logic             rst_n,
  input  logic             stall,
  input  logic             flush,
  input  logic [XLEN-1:0]  pc4_in,
  input  logic             pred_taken_in,
  input  logic [XLEN-1:0]  pred_target_in,
  output logic [XLEN-1:0]  pc4_out,
  output logic             pred_taken_out,
  output logic [XLEN-1:0]  pred_target_out
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc4_out        <= '0;
      pred_taken_out <= 1'b0;
      pred_target_out<= '0;
    end else if (flush) begin
      pc4_out        <= '0;
      pred_taken_out <= 1'b0;
      pred_target_out<= '0;
    end else if (!stall) begin
      pc4_out        <= pc4_in;
      pred_taken_out <= pred_taken_in;
      pred_target_out<= pred_target_in;
    end
  end

endmodule

// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\pipeline\id_ex_reg.sv
// -----------------------------------------------------------------------------
module id_ex_reg
  import rv32i_pkg::*;
(
  input  logic             clk,
  input  logic             rst_n,
  input  logic             stall,
  input  logic             flush,
  input  logic [REG_ADDR-1:0] rd_in,
  input  logic [REG_ADDR-1:0] rs1_in,
  input  logic [REG_ADDR-1:0] rs2_in,
  input  logic             reg_write_in,
  input  logic             mem_read_in,
  input  logic             mem_write_in,
  input  logic [1:0]       wb_src_in,
  input  logic             alu_src_in,
  input  logic             branch_in,
  input  logic             jump_in,
  input  logic             jump_reg_in,
  input  logic             upper_imm_in,
  input  logic             auipc_src_in,
  input  alu_op_t          alu_op_in,
  input  logic             is_muldiv_in,
  input  logic [2:0]       muldiv_op_in,
  input  logic [2:0]       mem_funct3_in,
  input  logic [XLEN-1:0]  rs1_data_in,
  input  logic [XLEN-1:0]  rs2_data_in,
  input  logic [XLEN-1:0]  imm_in,
  input  logic [XLEN-1:0]  pc4_in,
  input  logic             pred_taken_in,
  input  logic [XLEN-1:0]  pred_target_in,
  output logic [REG_ADDR-1:0] rd_out,
  output logic [REG_ADDR-1:0] rs1_out,
  output logic [REG_ADDR-1:0] rs2_out,
  output logic             reg_write_out,
  output logic             mem_read_out,
  output logic             mem_write_out,
  output logic [1:0]       wb_src_out,
  output logic             alu_src_out,
  output logic             is_muldiv_out,
  output logic [2:0]       muldiv_op_out,
  output logic             branch_out,
  output logic             jump_out,
  output logic             jump_reg_out,
  output logic             upper_imm_out,
  output logic             auipc_src_out,
  output alu_op_t          alu_op_out,
  output logic [2:0]       mem_funct3_out,
  output logic [XLEN-1:0]  rs1_data_out,
  output logic [XLEN-1:0]  rs2_data_out,
  output logic [XLEN-1:0]  imm_out,
  output logic [XLEN-1:0]  pc4_out,
  output logic             pred_taken_out,
  output logic [XLEN-1:0]  pred_target_out
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_out         <= '0;
      rs1_out        <= '0;
      rs2_out        <= '0;
      reg_write_out  <= 1'b0;
      mem_read_out   <= 1'b0;
      mem_write_out  <= 1'b0;
      wb_src_out     <= WB_ALU;
      alu_src_out    <= 1'b0;
      branch_out     <= 1'b0;
      jump_out       <= 1'b0;
      jump_reg_out   <= 1'b0;
      upper_imm_out  <= 1'b0;
      auipc_src_out  <= 1'b0;
      alu_op_out     <= ALU_NOP;
      is_muldiv_out  <= 1'b0;
      muldiv_op_out  <= 3'b0;
      mem_funct3_out <= 3'b0;
      rs1_data_out   <= '0;
      rs2_data_out   <= '0;
      imm_out        <= '0;
      pc4_out        <= '0;
      pred_taken_out <= 1'b0;
      pred_target_out<= '0;
    end else if (flush) begin
      rd_out         <= '0;
      rs1_out        <= '0;
      rs2_out        <= '0;
      reg_write_out  <= 1'b0;
      mem_read_out   <= 1'b0;
      mem_write_out  <= 1'b0;
      wb_src_out     <= WB_ALU;
      alu_src_out    <= 1'b0;
      branch_out     <= 1'b0;
      jump_out       <= 1'b0;
      jump_reg_out   <= 1'b0;
      upper_imm_out  <= 1'b0;
      auipc_src_out  <= 1'b0;
      alu_op_out     <= ALU_NOP;
      is_muldiv_out  <= 1'b0;
      muldiv_op_out  <= 3'b0;
      mem_funct3_out <= 3'b0;
      rs1_data_out   <= '0;
      rs2_data_out   <= '0;
      imm_out        <= '0;
      pc4_out        <= '0;
      pred_taken_out <= 1'b0;
      pred_target_out<= '0;
    end else if (!stall) begin
      rd_out         <= rd_in;
      rs1_out        <= rs1_in;
      rs2_out        <= rs2_in;
      reg_write_out  <= reg_write_in;
      mem_read_out   <= mem_read_in;
      mem_write_out  <= mem_write_in;
      wb_src_out     <= wb_src_in;
      alu_src_out    <= alu_src_in;
      branch_out     <= branch_in;
      jump_out       <= jump_in;
      jump_reg_out   <= jump_reg_in;
      upper_imm_out  <= upper_imm_in;
      auipc_src_out  <= auipc_src_in;
      alu_op_out     <= alu_op_in;
      is_muldiv_out  <= is_muldiv_in;
      muldiv_op_out  <= muldiv_op_in;
      mem_funct3_out <= mem_funct3_in;
      rs1_data_out   <= rs1_data_in;
      rs2_data_out   <= rs2_data_in;
      imm_out        <= imm_in;
      pc4_out        <= pc4_in;
      pred_taken_out <= pred_taken_in;
      pred_target_out<= pred_target_in;
    end
  end

endmodule

// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\pipeline\ex_mem_reg.sv
// -----------------------------------------------------------------------------
module ex_mem_reg
  import rv32i_pkg::*;
(
  input  logic             clk,
  input  logic             rst_n,
  input  logic             stall,
  input  logic [REG_ADDR-1:0] rd_in,
  input  logic             reg_write_in,
  input  logic             mem_read_in,
  input  logic             mem_write_in,
  input  logic [1:0]       wb_src_in,
  input  logic [2:0]       mem_funct3_in,
  input  logic [XLEN-1:0]  alu_result_in,
  input  logic [XLEN-1:0]  rs2_data_in,
  output logic [REG_ADDR-1:0] rd_out,
  output logic             reg_write_out,
  output logic             mem_read_out,
  output logic             mem_write_out,
  output logic [1:0]       wb_src_out,
  output logic [2:0]       mem_funct3_out,
  output logic [XLEN-1:0]  alu_result_out,
  output logic [XLEN-1:0]  rs2_data_out
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_out         <= '0;
      reg_write_out  <= 1'b0;
      mem_read_out   <= 1'b0;
      mem_write_out  <= 1'b0;
      wb_src_out     <= WB_ALU;
      mem_funct3_out <= 3'b0;
      alu_result_out <= '0;
      rs2_data_out   <= '0;
    end else if (!stall) begin
      rd_out         <= rd_in;
      reg_write_out  <= reg_write_in;
      mem_read_out   <= mem_read_in;
      mem_write_out  <= mem_write_in;
      wb_src_out     <= wb_src_in;
      mem_funct3_out <= mem_funct3_in;
      alu_result_out <= alu_result_in;
      rs2_data_out   <= rs2_data_in;
    end
  end

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\pipeline\mem_wb_reg.sv
// -----------------------------------------------------------------------------
module mem_wb_reg
  import rv32i_pkg::*;
(
  input  logic             clk,
  input  logic             rst_n,
  input  logic             stall,
  input  logic [REG_ADDR-1:0] rd_in,
  input  logic             reg_write_in,
  input  logic [1:0]       wb_src_in,
  input  logic [2:0]       mem_funct3_in,
  input  logic [XLEN-1:0]  alu_result_in,
  output logic [REG_ADDR-1:0] rd_out,
  output logic             reg_write_out,
  output logic [1:0]       wb_src_out,
  output logic [2:0]       mem_funct3_out,
  output logic [XLEN-1:0]  alu_result_out
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_out           <= '0;
      reg_write_out    <= 1'b0;
      wb_src_out       <= WB_ALU;
      mem_funct3_out   <= 3'b0;
      alu_result_out   <= '0;
    end else if (!stall) begin
      rd_out           <= rd_in;
      reg_write_out    <= reg_write_in;
      wb_src_out       <= wb_src_in;
      mem_funct3_out   <= mem_funct3_in;
      alu_result_out   <= alu_result_in;
    end
  end

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\mem\instr_mem.sv
// -----------------------------------------------------------------------------
module instr_mem
  import rv32i_pkg::*;
#(
  parameter int unsigned MEM_DEPTH = 1024,
  parameter         INIT_FILE = ""
)
(
  input  logic        clk,
  input  logic [XLEN-1:0] addr,
  output logic [XLEN-1:0] rdata
);

  logic [XLEN-1:0] mem [0:MEM_DEPTH-1];

  always_ff @(posedge clk) begin
    rdata <= mem[addr[31:2]];
  end

  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end else begin
      for (int i = 0; i < MEM_DEPTH; i++) mem[i] = 32'h0000_0013;
    end
  end

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\mem\data_mem.sv
// -----------------------------------------------------------------------------
module data_mem
  import rv32i_pkg::*;
#(
  parameter int unsigned MEM_DEPTH = 1024,
  parameter         INIT_FILE = ""
)
(
  input  logic        clk,
  input  logic [XLEN-1:0] addr,
  input  logic [XLEN-1:0] wdata,
  output logic [XLEN-1:0] rdata,
  input  logic        we,
  input  logic        re,
  input  logic [3:0]  be
);

  logic [XLEN-1:0] mem [0:MEM_DEPTH-1];

  always @(posedge clk) begin
    if (we) begin
      if (be[0]) mem[addr[31:2]][7:0]   <= wdata[7:0];
      if (be[1]) mem[addr[31:2]][15:8]  <= wdata[15:8];
      if (be[2]) mem[addr[31:2]][23:16] <= wdata[23:16];
      if (be[3]) mem[addr[31:2]][31:24] <= wdata[31:24];
    end
    rdata <= mem[addr[31:2]];
  end

  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end else begin
      for (int i = 0; i < MEM_DEPTH; i++) mem[i] = '0;
    end
  end

endmodule


// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\core\rv32i_core.sv
// -----------------------------------------------------------------------------
module rv32i_core
  import rv32i_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  output logic [XLEN-1:0] instr_addr,
  input  logic [XLEN-1:0] instr_rdata,

  output logic [XLEN-1:0] data_addr,
  output logic [XLEN-1:0] data_wdata,
  input  logic [XLEN-1:0] data_rdata,
  output logic            data_we,
  output logic [3:0]      data_be,
  output logic            data_re,

  input  logic        stall,
  input  logic        flush,

  // Debug / observability ports (read-only, non-intrusive)
  output logic [XLEN-1:0] dbg_pc,
  output logic [31:0]     dbg_instr,
  output logic            dbg_valid,
  input  logic [REG_ADDR-1:0] dbg_regfile_addr,
  output logic [XLEN-1:0]     dbg_regfile_data
);

  // =========================================================================
  // Internal signals
  // =========================================================================

  // IF stage
  logic [XLEN-1:0] pc_next, pc_plus4, pc_reg, redirect_pc;

  // Branch predictor
  logic       bp_pred_taken;
  logic [XLEN-1:0] bp_pred_target;
  logic       ex_bp_mispredict;

  // Pipeline flush: from branch mispredict OR external flush
  logic pipe_flush;
  logic pipe_flush_d1;

  // Hazard unit
  forward_sel_t forward_a_sel, forward_b_sel;
  logic         haz_stall;
  logic         load_use_stall;
  logic         ifid_stall;
  logic         pc_stall;
  logic         muldiv_stall;
  logic         downstream_stall;
  logic         id_ex_flush_signal;
  logic         wb_conflict;


  // IF/ID pipeline register
  logic [XLEN-1:0] ifid_pc4;
  logic            ifid_pred_taken;
  logic [XLEN-1:0] ifid_pred_target;
  logic [XLEN-1:0] ifid_instr;

  // ID stage ? decoder outputs
  logic [REG_ADDR-1:0] id_rd, id_rs1, id_rs2;
  logic [2:0]          id_funct3;
  logic [6:0]          id_funct7;
  opcode_t             id_opcode;
  logic [XLEN-1:0]     id_imm;
  logic                id_reg_write, id_mem_read, id_mem_write;
  logic [1:0]          id_wb_src;
  logic                id_alu_src, id_branch, id_jump, id_jump_reg;
  logic                id_upper_imm, id_auipc_src;
  alu_op_t             id_alu_op;
  logic [2:0]          id_mem_funct3;
  logic                id_is_muldiv;
  logic [2:0]          id_muldiv_op;
  logic [XLEN-1:0]     id_rs1_data, id_rs2_data;

  // ID/EX pipeline register
  logic [REG_ADDR-1:0] idex_rd, idex_rs1, idex_rs2;
  logic                idex_reg_write, idex_mem_read, idex_mem_write;
  logic [1:0]          idex_wb_src;
  logic                idex_alu_src, idex_branch, idex_jump, idex_jump_reg;
  logic                idex_upper_imm, idex_auipc_src;
  alu_op_t             idex_alu_op;
  logic [2:0]          idex_mem_funct3;
  logic [XLEN-1:0]     idex_rs1_data, idex_rs2_data, idex_imm, idex_pc4;
  logic                idex_pred_taken;
  logic [XLEN-1:0]     idex_pred_target;
  logic                idex_is_muldiv;
  logic [2:0]          idex_muldiv_op;

  // EX stage
  logic [XLEN-1:0] ex_alu_result, ex_alu_op_a, ex_alu_op_b;
  logic [XLEN-1:0] fwd_rs1_data, fwd_rs2_data;
  logic [XLEN-1:0] ex_branch_target, ex_jump_target;
  logic             ex_branch_taken, ex_is_branch_jump;
  logic [XLEN-1:0] ex_wb_value;
  // M-extension
  logic             muldiv_busy, muldiv_done;
  logic [XLEN-1:0]  muldiv_result;
  logic [4:0]       muldiv_result_rd;
  logic             muldiv_result_we;
  logic [XLEN-1:0]  ex_result;

  // EX/MEM pipeline register
  logic [REG_ADDR-1:0] exmem_rd;
  logic                exmem_reg_write, exmem_mem_read, exmem_mem_write;
  logic [1:0]          exmem_wb_src;
  logic [2:0]          exmem_mem_funct3;
  logic [XLEN-1:0]     exmem_alu_result, exmem_rs2_data;

  // MEM/WB pipeline register
  logic [REG_ADDR-1:0] memwb_rd;
  logic                memwb_reg_write;
  logic [1:0]          memwb_wb_src;
  logic [2:0]          memwb_mem_funct3;
  logic [XLEN-1:0]     memwb_alu_result;

  // WB stage
  logic [XLEN-1:0] wb_wdata;
  logic             wb_we;
  logic [4:0]       wb_waddr;

  // =========================================================================
  // HAZARD UNIT ? forwarding + load-use stall detection
  // =========================================================================

  // (no decode-load stall needed ? the hazard unit's EX-vs-ID detection
  // works correctly with a combinational instruction memory read)

  // Debug
  // logic [31:0] cycle_cnt;
  // always_ff @(posedge clk or negedge rst_n) begin
  //   if (!rst_n) cycle_cnt <= 0;
  //   else cycle_cnt <= cycle_cnt + 1;
  // end
  // always @(posedge clk) begin
  //   if (haz_stall)
  //     $display("[HAZ] C=%0d STALL idex_rd=%0d id_rs1=%0d id_rs2=%0d inst=0x%08x",
  //              cycle_cnt, idex_rd, id_rs1, id_rs2, instr_rdata);
  //   if (ex_bp_mispredict)
  //     $display("[BP] C=%0d MISPREDICT branch_taken=%0b pred_taken=%0b pred_target=0x%08x actual_target=0x%08x idex_pc4=0x%08x idex_imm=0x%08x inst=0x%08x",
  //              cycle_cnt, ex_branch_taken, idex_pred_taken, idex_pred_target, ex_jump_target,
  //              idex_pc4, idex_imm, instr_rdata);
  //   if (ex_is_branch_jump && !ex_bp_mispredict)
  //     $display("[BP] C=%0d CORRECT   branch_taken=%0b pred_taken=%0b pred_target=0x%08x actual_target=0x%08x idex_pc4=0x%08x",
  //              cycle_cnt, ex_branch_taken, idex_pred_taken, idex_pred_target, ex_jump_target,
  //              idex_pc4);
  //   if (ex_is_branch_jump)
  //     $display("[BP2] C=%0d %s pc4=0x%08x pred_t=%0b pred_ta=0x%08x act_ta=0x%08x taken=%0b",
  //              cycle_cnt, ex_bp_mispredict ? "MIS" : "COR",
  //              idex_pc4, idex_pred_taken, idex_pred_target, ex_jump_target, ex_branch_taken);
  // end

  // always @(posedge clk) begin
  //   if (muldiv_done)
  //     $display("[MULDIV] C=%0d DONE write rd=x%0d result=0x%08x busy=%0b idex_is_muldiv=%0b",
  //              cycle_cnt, muldiv_result_rd, muldiv_result, muldiv_busy, idex_is_muldiv);
  //   if (wb_we && wb_waddr != 5'b0)
  //     $display("[WB] C=%0d WRITE rd=x%0d data=0x%08x (memwb_rd=x%0d memwb_alu=0x%08x memwb_reg_write=%0b muldiv_done=%0b)",
  //              cycle_cnt, wb_waddr, wb_wdata, memwb_rd, memwb_alu_result, memwb_reg_write, muldiv_done);
  //   if (idex_is_muldiv)
  //     $display("[MULIDEX] C=%0d MUL/S in ID/EX rd=x%0d a=0x%08x b=0x%08x op=%0d start=%0d",
  //              cycle_cnt, idex_rd, fwd_rs1_data, fwd_rs2_data, idex_muldiv_op, idex_is_muldiv);
  // end

  // always @(posedge clk) begin
  //   if (instr_rdata == 32'h00140413 || instr_rdata == 32'h00000013)
  //     $display("[IDEC] C=%0d instr_rdata=0x%08x id_rs1=%0d id_rs2=%0d id_is_muldiv=%0d muldiv_decode=%0d haz_stall=%0d muldiv_stall=%0d pc_stall=%0d",
  //              cycle_cnt, instr_rdata, id_rs1, id_rs2, id_is_muldiv, muldiv_decode, haz_stall, muldiv_stall, pc_stall);
  // end
  // // MUL?ADDI trace: show every ID/EX capture around the MUL test region (cycles 210-280)
  // always @(posedge clk) begin
  //   if (cycle_cnt >= 210 && cycle_cnt <= 280) begin
  //     $display("[PIPE] C=%0d pc=0x%08x ifid_pc4=0x%08x instr=0x%08x id_is_mul=%0d idex_is_mul=%0d idex_rs1=%0d fwd_a=%0d fwd_rs1=0x%08x muldiv_done=%0d muldiv_busy=%0d pc_stall=%0d ifid_stall=%0d ds_stall=%0d",
  //              cycle_cnt, pc_reg, ifid_pc4, instr_rdata, id_is_muldiv, idex_is_muldiv, idex_rs1, forward_a_sel, fwd_rs1_data, muldiv_done, muldiv_busy, pc_stall, ifid_stall, downstream_stall);
  //   end
  // end

  hazard_unit u_hazard (
    .clk            (clk),
    .rst_n          (rst_n),
    .id_rs1         (id_rs1),
    .id_rs2         (id_rs2),
    .id_rd          (id_rd),
    .id_is_muldiv   (id_is_muldiv),
    .idex_rd        (idex_rd),
    .idex_rs1       (idex_rs1),
    .idex_rs2       (idex_rs2),
    .idex_mem_read  (idex_mem_read),
    .idex_is_muldiv (idex_is_muldiv),
    .exmem_rd       (exmem_rd),
    .exmem_reg_write(exmem_reg_write),
    .exmem_mem_read (exmem_mem_read),
    .memwb_rd       (memwb_rd),
    .memwb_reg_write(memwb_reg_write),
    .ext_stall      (stall),
    .pipe_flush     (pipe_flush),
    .pipe_flush_d1  (pipe_flush_d1),
    .muldiv_busy    (muldiv_busy),
    .muldiv_done    (muldiv_done),
    .muldiv_result_rd (muldiv_result_rd),
    .forward_a_sel  (forward_a_sel),
    .forward_b_sel  (forward_b_sel),
    .stall          (haz_stall),
    .load_use_stall (load_use_stall),
    .muldiv_stall   (muldiv_stall),
    .ifid_stall     (ifid_stall),
    .pc_stall       (pc_stall),
    .downstream_stall(downstream_stall),
    .wb_conflict    (wb_conflict)
  );

  // muldiv_unit



  // =========================================================================
  // BRANCH PREDICTOR ? BHT + BTB, 64 entries
  // =========================================================================

  branch_predictor u_bp (
    .clk            (clk),
    .rst_n          (rst_n),
    .fetch_pc       (pc_reg),
    .pred_taken     (bp_pred_taken),
    .pred_target    (bp_pred_target),
    .resolve_valid  (ex_is_branch_jump),
    .resolve_pc     (idex_pc4 - 4),
    .resolve_taken  (ex_branch_taken),
    .resolve_target (ex_jump_target)
  );

  // =========================================================================
  // PIPELINE FLUSH ? from branch mispredict OR external flush
  // =========================================================================

  // Mispredict detection
  always_comb begin
    ex_bp_mispredict = 1'b0;
    if (ex_is_branch_jump) begin
      if (idex_jump || idex_jump_reg) begin
        // JAL/JALR always taken ? mispredict if not predicted or wrong target
        if (!idex_pred_taken || idex_pred_target != ex_jump_target)
          ex_bp_mispredict = 1'b1;
      end else if (idex_branch) begin
        if (idex_pred_taken != ex_branch_taken)
          ex_bp_mispredict = 1'b1;  // wrong direction
        else if (idex_pred_taken && ex_branch_taken &&
                 idex_pred_target != ex_jump_target)
          ex_bp_mispredict = 1'b1;  // right direction, wrong target
      end
    end
  end

  assign pipe_flush = flush | ex_bp_mispredict;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      pipe_flush_d1 <= 1'b0;
    else
      pipe_flush_d1 <= pipe_flush;
  end

  // ID/EX flush: branch mispredict (2-cycle) OR load-use bubble
  assign id_ex_flush_signal = pipe_flush | pipe_flush_d1 | load_use_stall;

  // =========================================================================
  // IF STAGE ? Instruction Fetch
  // =========================================================================

  assign pc_plus4 = pc_reg + 32'd4;

  mux_pc_redirect u_mux_pc_redirect (
    .ex_jump_target (ex_jump_target),
    .ifid_pc4       (ifid_pc4),
    .ex_branch_taken(ex_branch_taken),
    .idex_jump      (idex_jump),
    .idex_jump_reg  (idex_jump_reg),
    .redirect_pc    (redirect_pc)
  );

  mux_pc_sel u_mux_pc_sel (
    .ex_bp_mispredict(ex_bp_mispredict),
    .muldiv_done     (muldiv_done),
    .haz_stall       (haz_stall),
    .pipe_flush      (pipe_flush),
    .pipe_flush_d1   (pipe_flush_d1),
    .bp_pred_taken   (bp_pred_taken),
    .ifid_stall      (ifid_stall),
    .flush           (flush),
    .redirect_pc     (redirect_pc),
    .ifid_pc4        (ifid_pc4),
    .bp_pred_target  (bp_pred_target),
    .pc_plus4        (pc_plus4),
    .pc_next         (pc_next)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      pc_reg <= 32'h0000_0000;
    else if (!pc_stall)
      pc_reg <= pc_next;
  end

  assign instr_addr = pc_reg;

  // =========================================================================
  // IF/ID PIPELINE REGISTER
  // =========================================================================
  if_id_reg u_if_id (
    .clk          (clk),
    .rst_n        (rst_n),
    .stall        (ifid_stall),
    .flush        (pipe_flush),
    .pc4_in       (pc_plus4),
    .pred_taken_in (bp_pred_taken),
    .pred_target_in(bp_pred_target),
    .pc4_out      (ifid_pc4),
    .pred_taken_out(ifid_pred_taken),
    .pred_target_out(ifid_pred_target)
  );

  // Instr hold register: hold ID instruction during muldiv stalls.
  // Fixes wiring mismatch where decoder's instruction was overwritten during
  // muldiv stalls due to registered IMEM. The registered IMEM means rdata
  // advances one cycle after PC holds, so ID would see NOP and lose the
  // waiting MUL/DIV. We hold the instruction that was present at stall entry.
  logic ifid_stall_q;
  logic [XLEN-1:0] instr_hold;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ifid_stall_q <= 1'b0;
      instr_hold   <= 32'h00000013;
    end else begin
      ifid_stall_q <= ifid_stall;
      if (pipe_flush) instr_hold <= 32'h00000013;
      else if (!ifid_stall || (!ifid_stall_q && ifid_stall)) instr_hold <= instr_rdata;
    end
  end
  // Use live rdata when not stalled or first cycle of stall; hold thereafter
  // and also hold through the done cycle (when q=1 but stall=0) to keep ID
  assign ifid_instr = ifid_stall_q ? instr_hold : instr_rdata;

  // =========================================================================
  // ID STAGE ? Instruction Decode + Register File Read
  // =========================================================================

  decoder u_decoder (
    .instr       (ifid_instr),
    .rd          (id_rd),
    .rs1         (id_rs1),
    .rs2         (id_rs2),
    .funct3      (id_funct3),
    .funct7      (id_funct7),
    .opcode      (id_opcode),
    .imm         (id_imm),
    .reg_write   (id_reg_write),
    .mem_read    (id_mem_read),
    .mem_write   (id_mem_write),
    .wb_src      (id_wb_src),
    .alu_src     (id_alu_src),
    .branch      (id_branch),
    .jump        (id_jump),
    .jump_reg    (id_jump_reg),
    .upper_imm   (id_upper_imm),
    .auipc_src   (id_auipc_src),
    .alu_op      (id_alu_op),
    .mem_funct3  (id_mem_funct3),
    .is_muldiv   (id_is_muldiv),
    .muldiv_op   (id_muldiv_op)
  );

  regfile u_regfile (
    .clk     (clk),
    .rst_n   (rst_n),
    .raddr_a (id_rs1),
    .rdata_a (id_rs1_data),
    .raddr_b (id_rs2),
    .rdata_b (id_rs2_data),
    .we      (wb_we),
    .waddr   (wb_waddr),
    .wdata   (muldiv_done ? muldiv_result : wb_wdata),
    .dbg_addr(dbg_regfile_addr),
    .dbg_data(dbg_regfile_data)
  );

  // =========================================================================
  // ID/EX PIPELINE REGISTER
  // =========================================================================
  id_ex_reg u_id_ex (
    .clk          (clk),
    .rst_n        (rst_n),
    .stall        (ifid_stall),
    .flush        (id_ex_flush_signal),
    .rd_in        (id_rd),
    .rs1_in       (id_rs1),
    .rs2_in       (id_rs2),
    .reg_write_in (id_reg_write),
    .mem_read_in  (id_mem_read),
    .mem_write_in (id_mem_write),
    .wb_src_in    (id_wb_src),
    .alu_src_in   (id_alu_src),
    .branch_in    (id_branch),
    .jump_in      (id_jump),
    .jump_reg_in  (id_jump_reg),
    .upper_imm_in (id_upper_imm),
    .auipc_src_in (id_auipc_src),
    .alu_op_in    (id_alu_op),
    .is_muldiv_in (id_is_muldiv),
    .muldiv_op_in (id_muldiv_op),
    .mem_funct3_in(id_mem_funct3),
    .rs1_data_in  (id_rs1_data),
    .rs2_data_in  (id_rs2_data),
    .imm_in       (id_imm),
    .pc4_in       (ifid_pc4),
    .pred_taken_in (ifid_pred_taken),
    .pred_target_in(ifid_pred_target),
    .rd_out       (idex_rd),
    .rs1_out      (idex_rs1),
    .rs2_out      (idex_rs2),
    .reg_write_out(idex_reg_write),
    .mem_read_out (idex_mem_read),
    .mem_write_out(idex_mem_write),
    .wb_src_out   (idex_wb_src),
    .alu_src_out  (idex_alu_src),
    .branch_out   (idex_branch),
    .jump_out     (idex_jump),
    .jump_reg_out (idex_jump_reg),
    .upper_imm_out(idex_upper_imm),
    .auipc_src_out(idex_auipc_src),
    .alu_op_out   (idex_alu_op),
    .is_muldiv_out(idex_is_muldiv),
    .muldiv_op_out(idex_muldiv_op),
    .mem_funct3_out(idex_mem_funct3),
    .rs1_data_out (idex_rs1_data),
    .rs2_data_out (idex_rs2_data),
    .imm_out      (idex_imm),
    .pc4_out      (idex_pc4),
    .pred_taken_out(idex_pred_taken),
    .pred_target_out(idex_pred_target)
  );

  // =========================================================================
  // EX STAGE ? Execute
  // =========================================================================

  mux_alu_operand_a u_mux_alu_op_a (
    .forward_a_sel   (forward_a_sel),
    .idex_auipc_src  (idex_auipc_src),
    .idex_rs1_data   (idex_rs1_data),
    .exmem_alu_result(exmem_alu_result),
    .wb_wdata        (wb_wdata),
    .muldiv_result   (muldiv_result),
    .idex_pc4        (idex_pc4),
    .ex_alu_op_a     (ex_alu_op_a),
    .fwd_rs1_data    (fwd_rs1_data)
  );

  mux_alu_operand_b u_mux_alu_op_b (
    .forward_b_sel   (forward_b_sel),
    .idex_alu_src    (idex_alu_src),
    .idex_rs2_data   (idex_rs2_data),
    .exmem_alu_result(exmem_alu_result),
    .wb_wdata        (wb_wdata),
    .muldiv_result   (muldiv_result),
    .idex_imm        (idex_imm),
    .ex_alu_op_b     (ex_alu_op_b),
    .fwd_rs2_data    (fwd_rs2_data)
  );

  alu u_alu (
    .op_a   (ex_alu_op_a),
    .op_b   (ex_alu_op_b),
    .alu_op (idex_alu_op),
    .result (ex_alu_result),
    .zero   ()
  );

  // M-extension: multiply/divide unit
  muldiv_unit u_muldiv (
    .clk           (clk),
    .rst_n         (rst_n),
    .flush         (pipe_flush),
    .operand_a     (fwd_rs1_data),
    .operand_b     (fwd_rs2_data),
    .op_sel        (idex_muldiv_op),
    .valid         (idex_is_muldiv),
    .rd_in         (idex_rd),
    .reg_write_in  (idex_reg_write),
    .result        (muldiv_result),
    .busy          (muldiv_busy),
    .done          (muldiv_done),
    .result_rd     (muldiv_result_rd),
    .result_we     (muldiv_result_we)
  );

  // Mux: select muldiv result when in EX, else ALU result
  assign ex_result = idex_is_muldiv ? muldiv_result : ex_alu_result;

  // With registered instruction memory (real BRAM), the pipeline adds 2
  // fetch cycles, so idex_pc4 = actual_PC + 8 (not +4).
  assign ex_branch_target = (idex_pc4 - 32'd4) + idex_imm;
  assign ex_jump_target   = idex_jump_reg ?
                            ((fwd_rs1_data + idex_imm) & ~32'h1) :
                            ex_branch_target;

  always_comb begin
    ex_branch_taken = 1'b0;
    if (idex_jump || idex_jump_reg) begin
      ex_branch_taken = 1'b1;
    end else if (idex_branch) begin
      unique case (idex_mem_funct3)
        3'b000: ex_branch_taken = (fwd_rs1_data == fwd_rs2_data);
        3'b001: ex_branch_taken = (fwd_rs1_data != fwd_rs2_data);
        3'b100: ex_branch_taken = ($signed(fwd_rs1_data) < $signed(fwd_rs2_data));
        3'b101: ex_branch_taken = ($signed(fwd_rs1_data) >= $signed(fwd_rs2_data));
        3'b110: ex_branch_taken = ($unsigned(fwd_rs1_data) < $unsigned(fwd_rs2_data));
        3'b111: ex_branch_taken = ($unsigned(fwd_rs1_data) >= $unsigned(fwd_rs2_data));
        default: ex_branch_taken = 1'b0;
      endcase
    end
  end

  assign ex_is_branch_jump = idex_branch | idex_jump | idex_jump_reg;

  mux_imm_sel u_mux_imm_sel (
    .idex_jump     (idex_jump),
    .idex_jump_reg (idex_jump_reg),
    .idex_upper_imm(idex_upper_imm),
    .idex_auipc_src(idex_auipc_src),
    .idex_pc4      (idex_pc4),
    .idex_imm      (idex_imm),
    .ex_alu_result (ex_result),
    .ex_wb_value   (ex_wb_value)
  );

  // =========================================================================
  // EX/MEM PIPELINE REGISTER
  // =========================================================================
  ex_mem_reg u_ex_mem (
    .clk          (clk),
    .rst_n        (rst_n),
    .stall        (downstream_stall),
    .rd_in        (idex_rd),
    .reg_write_in (idex_is_muldiv ? 1'b0 : idex_reg_write),
    .mem_read_in  (idex_mem_read),
    .mem_write_in (idex_mem_write),
    .wb_src_in    (idex_wb_src),
    .mem_funct3_in(idex_mem_funct3),
    .alu_result_in(ex_wb_value),
    .rs2_data_in  (fwd_rs2_data),
    .rd_out       (exmem_rd),
    .reg_write_out(exmem_reg_write),
    .mem_read_out (exmem_mem_read),
    .mem_write_out(exmem_mem_write),
    .wb_src_out   (exmem_wb_src),
    .mem_funct3_out(exmem_mem_funct3),
    .alu_result_out(exmem_alu_result),
    .rs2_data_out (exmem_rs2_data)
  );

  // =========================================================================
  // MEM STAGE ? Data Memory Access
  // =========================================================================

  assign data_addr  = exmem_alu_result;
  // FIX Bug 1: align store data to byte lane so BE selects correct value
  assign data_wdata = (exmem_mem_funct3 == 3'b000) ? {4{exmem_rs2_data[7:0]}}  :
                      (exmem_mem_funct3 == 3'b001) ? {2{exmem_rs2_data[15:0]}} :
                      exmem_rs2_data;
  assign data_re   = exmem_mem_read;
  assign data_we   = exmem_mem_write;

  always_comb begin
    data_be = 4'b0000;
    if (exmem_mem_write) begin
      unique case (exmem_mem_funct3)
        3'b000: begin
          unique case (exmem_alu_result[1:0])
            2'b00: data_be = 4'b0001;
            2'b01: data_be = 4'b0010;
            2'b10: data_be = 4'b0100;
            2'b11: data_be = 4'b1000;
          endcase
        end
        3'b001: data_be = exmem_alu_result[1] ? 4'b1100 : 4'b0011;
        3'b010: data_be = 4'b1111;
        default: data_be = 4'b0000;
      endcase
    end
  end

  // =========================================================================
  // MEM/WB PIPELINE REGISTER
  // =========================================================================
  mem_wb_reg u_mem_wb (
    .clk            (clk),
    .rst_n          (rst_n),
    .stall          (downstream_stall),
    .rd_in          (exmem_rd),
    .reg_write_in   (exmem_reg_write),
    .wb_src_in      (exmem_wb_src),
    .mem_funct3_in  (exmem_mem_funct3),
    .alu_result_in  (exmem_alu_result),
    .rd_out         (memwb_rd),
    .reg_write_out  (memwb_reg_write),
    .wb_src_out     (memwb_wb_src),
    .mem_funct3_out (memwb_mem_funct3),
    .alu_result_out (memwb_alu_result)
  );

  // =========================================================================
  // WB STAGE ? Write Back to Register File
  // =========================================================================

  mux_wb_sel u_mux_wb_sel (
    .memwb_wb_src     (memwb_wb_src),
    .memwb_mem_funct3 (memwb_mem_funct3),
    .memwb_alu_result (memwb_alu_result),
    .data_rdata       (data_rdata),
    .wb_wdata         (wb_wdata)
  );

  // M-extension: when muldiv is done, bypass normal WB and write directly
  assign wb_we    = muldiv_done ? muldiv_result_we  : memwb_reg_write;
  assign wb_waddr = muldiv_done ? muldiv_result_rd   : memwb_rd;

  // =========================================================================
  // DEBUG PORTS ? tap decode stage
  // =========================================================================
  assign dbg_pc     = ifid_pc4 - 4;
  assign dbg_instr  = instr_rdata;
  assign dbg_valid  = rst_n && !id_ex_flush_signal && !ifid_stall;

endmodule

// -----------------------------------------------------------------------------
// File: E:\RISCV\rtl\core\soc_top.sv
// -----------------------------------------------------------------------------
// SoC top: connects RV32I core to on-chip instruction/data BRAM.
// No cache, no hit/miss logic, no MMU.  Bare-metal, single clock domain.
//
// The instruction memory's registered read doubles as the IF/ID pipeline
// register; the data memory's registered read doubles as the MEM/WB pipeline
// register.  No additional register stages are inserted between core and
// memory ? adding one would break the timing the pipeline was built around.

module soc_top
  import rv32i_pkg::*;
#(
  parameter int unsigned IMEM_DEPTH = 1024,
  parameter int unsigned DMEM_DEPTH = 1024,
  parameter         IMEM_INIT_FILE = "",
  parameter         DMEM_INIT_FILE = ""
)
(
  input  logic        clk,
  input  logic        rst_n,

  // Debug / observability (passed straight through from rv32i_core)
  output logic [XLEN-1:0]     dbg_pc,
  output logic [31:0]         dbg_instr,
  output logic                dbg_valid,
  input  logic [REG_ADDR-1:0] dbg_regfile_addr,
  output logic [XLEN-1:0]     dbg_regfile_data
);

  // ---------------------------------------------------------------------------
  // Core-to-memory wiring
  // ---------------------------------------------------------------------------
  logic [XLEN-1:0] instr_addr;
  logic [XLEN-1:0] instr_rdata;

  logic [XLEN-1:0] data_addr;
  logic [XLEN-1:0] data_wdata;
  logic [XLEN-1:0] data_rdata;
  logic            data_we;
  logic [3:0]      data_be;
  logic            data_re;

  // ---------------------------------------------------------------------------
  // rv32i_core
  // ---------------------------------------------------------------------------
  rv32i_core u_core (
    .clk         (clk),
    .rst_n       (rst_n),
    .instr_addr  (instr_addr),
    .instr_rdata (instr_rdata),
    .data_addr   (data_addr),
    .data_wdata  (data_wdata),
    .data_rdata  (data_rdata),
    .data_we     (data_we),
    .data_be     (data_be),
    .data_re     (data_re),
    .stall       (1'b0),
    .flush       (1'b0),
    .dbg_pc      (dbg_pc),
    .dbg_instr   (dbg_instr),
    .dbg_valid   (dbg_valid),
    .dbg_regfile_addr(dbg_regfile_addr),
    .dbg_regfile_data(dbg_regfile_data)
  );

  // ---------------------------------------------------------------------------
  // instr_mem
  // ---------------------------------------------------------------------------
  instr_mem #(
    .MEM_DEPTH (IMEM_DEPTH),
    .INIT_FILE (IMEM_INIT_FILE)
  ) u_instr_mem (
    .clk   (clk),
    .addr  (instr_addr),
    .rdata (instr_rdata)
  );

  // ---------------------------------------------------------------------------
  // data_mem
  // ---------------------------------------------------------------------------
  data_mem #(
    .MEM_DEPTH (DMEM_DEPTH),
    .INIT_FILE (DMEM_INIT_FILE)
  ) u_data_mem (
    .clk    (clk),
    .addr   (data_addr),
    .wdata  (data_wdata),
    .rdata  (data_rdata),
    .we     (data_we),
    .re     (data_re),
    .be     (data_be)
  );

endmodule
