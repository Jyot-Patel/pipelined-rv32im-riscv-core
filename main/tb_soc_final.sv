`timescale 1ns / 1ps

module tb_soc_final;

  import rv32i_pkg::*;

  // =========================================================================
  // Clock & Reset
  // =========================================================================
  logic clk;
  logic rst_n;
  localparam CLK_PERIOD = 10;
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // =========================================================================
  // Debug / register-file observability
  // =========================================================================
  logic [XLEN-1:0]     dbg_pc;
  logic [31:0]         dbg_instr;
  logic                dbg_valid;
  logic [REG_ADDR-1:0] dbg_regfile_addr;
  logic [XLEN-1:0]     dbg_regfile_data;

  // =========================================================================
  // DUT
  // =========================================================================
  soc_top #(
    .IMEM_DEPTH    (1024),
    .DMEM_DEPTH    (1024),
    .IMEM_INIT_FILE (""),
    .DMEM_INIT_FILE ("")
  ) u_dut (
    .clk             (clk),
    .rst_n           (rst_n),
    .dbg_pc          (dbg_pc),
    .dbg_instr       (dbg_instr),
    .dbg_valid       (dbg_valid),
    .dbg_regfile_addr(dbg_regfile_addr),
    .dbg_regfile_data(dbg_regfile_data)
  );

  // =========================================================================
  // Register-file read helper
  // =========================================================================
  logic [31:0] reg_val [0:31];
  task automatic read_regfile(input [4:0] addr, output logic [31:0] val);
    dbg_regfile_addr = addr; #0; val = dbg_regfile_data;
  endtask

  // =========================================================================
  // Instruction encoding helpers
  // =========================================================================
  function automatic logic [31:0] enc_r(
    input logic [6:0] f7, input logic [4:0] rs2, input logic [4:0] rs1,
    input logic [2:0] f3, input logic [4:0] rd, input logic [6:0] op);
    return {f7, rs2, rs1, f3, rd, op};
  endfunction

  function automatic logic [31:0] enc_i(
    input logic [11:0] imm, input logic [4:0] rs1,
    input logic [2:0] f3, input logic [4:0] rd, input logic [6:0] op);
    return {imm, rs1, f3, rd, op};
  endfunction

  function automatic logic [31:0] enc_s(
    input logic [11:0] imm, input logic [4:0] rs2, input logic [4:0] rs1,
    input logic [2:0] f3, input logic [6:0] op);
    return {imm[11:5], rs2, rs1, f3, imm[4:0], op};
  endfunction

  function automatic logic [31:0] enc_b(
    input logic [12:0] off, input logic [4:0] rs2, input logic [4:0] rs1,
    input logic [2:0] f3, input logic [6:0] op);
    logic [31:0] i;
    i[31]=off[12]; i[30:25]=off[10:5]; i[24:20]=rs2; i[19:15]=rs1;
    i[14:12]=f3; i[11:8]=off[4:1]; i[7]=off[11]; i[6:0]=op;
    return i;
  endfunction

  function automatic logic [31:0] enc_u(
    input logic [31:0] imm, input logic [4:0] rd, input logic [6:0] op);
    return {imm[31:12], rd, op};
  endfunction

  function automatic logic [31:0] enc_j(
    input logic [20:0] off, input logic [4:0] rd, input logic [6:0] op);
    logic [31:0] i;
    i[31]=off[20]; i[30:21]=off[10:1]; i[20]=off[11];
    i[19:12]=off[19:12]; i[11:7]=rd; i[6:0]=op;
    return i;
  endfunction

  localparam logic [31:0] NOP = 32'h0000_0013;

  // =========================================================================
  // Bookkeeping
  // =========================================================================
  int pass_count, fail_count;
  integer idx;
  integer jal_phase1_idx;

  task automatic check_reg(input string name, input logic [31:0] actual,
                           input logic [31:0] expected);
    if (actual === expected) begin
      $display("  [PASS] %-40s = 0x%08h", name, actual); pass_count++;
    end else begin
      $display("  [FAIL] %-40s = 0x%08h (expected 0x%08h)", name, actual, expected); fail_count++;
    end
  endtask

  function automatic logic [31:0] read_dmem_word(input int byte_addr);
    return u_dut.u_data_mem.mem[byte_addr >> 2];
  endfunction

  // =========================================================================
  // Memory helpers
  // =========================================================================
  task automatic fill_nops();
    for (int i = 0; i < 1024; i++) u_dut.u_instr_mem.mem[i] = NOP;
  endtask

  task automatic fill_dmem_zeros();
    for (int i = 0; i < 1024; i++) u_dut.u_data_mem.mem[i] = 32'h0;
  endtask

  // =========================================================================
  // Halt detection — detect self-loop JAL x0, 0 (encoding 0x0000006F)
  // Must also tolerate M-extension stalls where PC is frozen temporarily.
  // =========================================================================
  task automatic run_to_halt(input int max_cycles);
    logic [31:0] prev_pc;
    int stable_cnt;
    prev_pc = 32'hFFFF_FFFF;
    stable_cnt = 0;
    for (int i = 0; i < max_cycles; i++) begin
      @(posedge clk);
      #1;
      // Detect the halt: JAL x0,0 at current PC, PC stable
      if (dbg_instr == 32'h0000006F && dbg_pc == prev_pc) begin
        stable_cnt++;
        if (stable_cnt >= 5) begin
          repeat(2) @(posedge clk);
          return;
        end
      end else begin
        prev_pc = dbg_pc;
        stable_cnt = 0;
      end
    end
    $display("[TB] WARNING: timeout at PC=0x%08h after %0d cycles", dbg_pc, max_cycles);
  endtask

  // #########################################################################
  //
  //  PHASE 1 — Instruction correctness
  //
  // #########################################################################
  task automatic load_phase1();
    idx = 0;
    $display("[TB] Phase 1: instruction correctness");

    // ---- I-type ALU (x1-x9, no overwrites) ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd10,  5'd0,3'b000,5'd1, OPC_OP_IMM); idx++; // x1=10
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd20,  5'd0,3'b000,5'd2, OPC_OP_IMM); idx++; // x2=20
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_i(12'd30,  5'd1,3'b010,5'd3, OPC_OP_IMM); idx++; // SLTI x3: 10<30=1
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_i(12'd30,  5'd1,3'b011,5'd4, OPC_OP_IMM); idx++; // SLTIU x4: 1
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_i(12'h0FF, 5'd1,3'b100,5'd5, OPC_OP_IMM); idx++; // XORI x5: 10^0xFF=0xF5
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_i(12'h0F0, 5'd1,3'b110,5'd6, OPC_OP_IMM); idx++; // ORI x6: 10|0xF0=0xFA
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_i(12'h0FF, 5'd1,3'b111,5'd7, OPC_OP_IMM); idx++; // ANDI x7: 10&0xFF=0x0A
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_i(12'd2,   5'd1,3'b001,5'd8, OPC_OP_IMM); idx++; // SLLI x8: 10<<2=40
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_i(12'd1,   5'd1,3'b101,5'd9, OPC_OP_IMM); idx++; // SRLI x9: 10>>1=5
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_i(12'h401, 5'd7,3'b101,5'd3, OPC_OP_IMM); idx++; // SRAI x3: 0xA>>>1=5 (overwrites SLTI)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- R-type ALU (x10-x19, no overwrites) ----
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd2,5'd1,3'b000,5'd10,OPC_OP); idx++; // ADD x10: 30
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0100000,5'd2,5'd1,3'b000,5'd11,OPC_OP); idx++; // SUB x11: -10
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd2,5'd1,3'b010,5'd12,OPC_OP); idx++; // SLT x12: 1
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd2,5'd1,3'b011,5'd13,OPC_OP); idx++; // SLTU x13: 1
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd2,5'd1,3'b100,5'd14,OPC_OP); idx++; // XOR x14: 30
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd2,5'd1,3'b110,5'd15,OPC_OP); idx++; // OR x15: 30
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd2,5'd1,3'b111,5'd16,OPC_OP); idx++; // AND x16: 0
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd2,5'd1,3'b001,5'd17,OPC_OP); idx++; // SLL x17: 10<<20=0x00A00000
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd2,5'd1,3'b101,5'd18,OPC_OP); idx++; // SRL x18: 0
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0100000,5'd2,5'd11,3'b101,5'd19,OPC_OP); idx++; // SRA x19: -10>>>20=-1
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- MUL (x20-x23, no overwrites) ----
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd2,5'd1,3'b000,5'd20,OPC_OP); idx++; // MUL x20: 200
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd2,5'd11,3'b001,5'd21,OPC_OP); idx++; // MULH x21: upper=-1
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd11,5'd1,3'b010,5'd22,OPC_OP); idx++; // MULHSU x22: upper=9
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd2,5'd1,3'b011,5'd23,OPC_OP); idx++; // MULHU x23: 0
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Branches (taken & not-taken, use x24-x29) ----
    // BEQ x1,x2 not-taken (10!=20)
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd2,5'd1,3'b000,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd42,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // x24=42 (not-taken path)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // BEQ x1,x1 taken -> target: x24=55
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd1,5'd1,3'b000,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // flushed
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd55,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // target x24=55
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // BNE x1,x2 taken -> target: x25=66
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd2,5'd1,3'b001,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd25,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd66,5'd0,3'b000,5'd25,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // BNE x1,x1 not-taken -> x25=77
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd1,5'd1,3'b001,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd77,5'd0,3'b000,5'd25,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // BLT x1,x2 taken -> x26=88
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd2,5'd1,3'b100,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd26,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd88,5'd0,3'b000,5'd26,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // BGE x2,x1 taken -> x27=99
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd1,5'd2,3'b101,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd27,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd99,5'd0,3'b000,5'd27,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // BLTU x1,x2 taken -> x28=110
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd2,5'd1,3'b110,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0,  5'd0,3'b000,5'd28,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd110,5'd0,3'b000,5'd28,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // BGEU x2,x1 taken -> x29=120
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd1,5'd2,3'b111,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0,  5'd0,3'b000,5'd29,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd120,5'd0,3'b000,5'd29,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- DIV/REM (x24-x29 overwritten with final values) ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd100, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // x24=100
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd7,   5'd0,3'b000,5'd25,OPC_OP_IMM); idx++; // x25=7
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd25,5'd24,3'b100,5'd26,OPC_OP); idx++; // DIV x26: 14
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd25,5'd24,3'b101,5'd27,OPC_OP); idx++; // DIVU x27: 14
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd25,5'd24,3'b110,5'd28,OPC_OP); idx++; // REM x28: 2
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd25,5'd24,3'b111,5'd29,OPC_OP); idx++; // REMU x29: 2
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Store tests (SW, SB, SH) ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd42,  5'd0,3'b000,5'd30,OPC_OP_IMM); idx++; // x30=42
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd0,   5'd30,5'd0,3'b010,OPC_STORE); idx++; // SW 42 → mem[0]
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_i(12'h0AB, 5'd0,3'b000,5'd31,OPC_OP_IMM); idx++; // x31=0xAB
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd4,   5'd31,5'd0,3'b000,OPC_STORE); idx++; // SB 0xAB → mem[4]
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_i(-12'd1,  5'd0,3'b000,5'd30,OPC_OP_IMM); idx++; // x30=-1
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd8,   5'd30,5'd0,3'b001,OPC_STORE); idx++; // SH -1 → mem[8]
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Load tests (LW, LBU, LHU) ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b010,5'd28,OPC_LOAD); idx++; // LW x28, 0(x0) → x28=42
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_i(12'd4, 5'd0,3'b100,5'd29,OPC_LOAD); idx++; // LBU x29, 4(x0) → x29=0xAB
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_i(12'd8, 5'd0,3'b101,5'd30,OPC_LOAD); idx++; // LHU x30, 8(x0) → x30=0xFFFF
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- LB (signed byte load): mem[4]=0xAB → sign-extended = 0xFFFFFFAB ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd4, 5'd0,3'b000,5'd28,OPC_LOAD); idx++; // LB x28, 4(x0) → x28=0xFFFFFFAB
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- LH (signed half load): mem[8]=0xFFFF → sign-extended = 0xFFFFFFFF ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd8, 5'd0,3'b001,5'd29,OPC_LOAD); idx++; // LH x29, 8(x0) → x29=0xFFFFFFFF
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- LUI (overwrites x30) ----
    u_dut.u_instr_mem.mem[idx]=enc_u(32'hABCDE000,5'd30,OPC_LUI); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- AUIPC (overwrites x31) ----
    u_dut.u_instr_mem.mem[idx]=enc_u(32'h00001000,5'd31,OPC_AUIPC); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- JAL: x31 = return addr, offset=8 skips flushed instruction ----
    jal_phase1_idx = idx;
    u_dut.u_instr_mem.mem[idx]=enc_j(21'd8,5'd31,OPC_JAL); idx++; // JAL x31, +8
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0,5'd0,3'b000,5'd30,OPC_OP_IMM); idx++; // flushed (should NOT execute)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- JALR: test standalone JALR (not forwarded) ----
    // Set x24 = target byte addr, then JALR x28, x24, 0
    begin
      integer jalr_t2_idx;
      jalr_t2_idx = idx + 5; // target is at idx+5 (2 NOPs + JALR + flushed = 4 words past ADDI)
      u_dut.u_instr_mem.mem[idx]=enc_i(jalr_t2_idx*4, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // x24 = target addr
      repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd24,3'b000,5'd28,OPC_JALR); idx++; // JALR x28, x24, 0
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd77,5'd0,3'b000,5'd28,OPC_OP_IMM); idx++; // flushed
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd55,5'd0,3'b000,5'd29,OPC_OP_IMM); idx++; // target: x29=55
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd100,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // restore x24=100 (clobbered by JALR base)
    end
    repeat(3) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- FENCE (pipeline NOP — should not affect state) ----
    u_dut.u_instr_mem.mem[idx]=32'h0000_000F; idx++; // FENCE
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Halt: self-loop ----
    u_dut.u_instr_mem.mem[idx] = enc_j(21'd0, 5'd0, OPC_JAL); idx++;

    $display("[TB] Phase 1 done: %0d words, JAL at word %0d", idx, jal_phase1_idx);
  endtask

  task automatic check_phase1();
    $display("");
    $display("========================================");
    $display("  PHASE 1: INSTRUCTION CORRECTNESS");
    $display("========================================");
    for (int i = 0; i < 32; i++) read_regfile(i[4:0], reg_val[i]);

    // I-type ALU
    check_reg("x1  (ADDI 10)",           reg_val[1],  32'd10);
    check_reg("x2  (ADDI 20)",           reg_val[2],  32'd20);
    check_reg("x3  (SRAI 0xA>>1=5)",     reg_val[3],  32'd5);
    check_reg("x4  (SLTIU 10<30=1)",     reg_val[4],  32'd1);
    check_reg("x5  (XORI 10^0xFF)",      reg_val[5],  32'hF5);
    check_reg("x6  (ORI 10|0xF0)",       reg_val[6],  32'hFA);
    check_reg("x7  (ANDI 10&0xFF)",      reg_val[7],  32'h0A);
    check_reg("x8  (SLLI 10<<2=40)",     reg_val[8],  32'd40);
    check_reg("x9  (SRLI 10>>1=5)",      reg_val[9],  32'd5);

    // R-type ALU
    check_reg("x10 (ADD 10+20=30)",      reg_val[10], 32'd30);
    check_reg("x11 (SUB 10-20=-10)",     reg_val[11], 32'hFFFFFFF6);
    check_reg("x12 (SLT 10<20=1)",       reg_val[12], 32'd1);
    check_reg("x13 (SLTU 10<20=1)",      reg_val[13], 32'd1);
    check_reg("x14 (XOR 10^20=30)",      reg_val[14], 32'd30);
    check_reg("x15 (OR 10|20=30)",       reg_val[15], 32'd30);
    check_reg("x16 (AND 10&20=0)",       reg_val[16], 32'd0);
    check_reg("x17 (SLL 10<<20)",        reg_val[17], 32'h00A00000);
    check_reg("x18 (SRL 10>>20=0)",      reg_val[18], 32'd0);
    check_reg("x19 (SRA -10>>>20=-1)",   reg_val[19], 32'hFFFFFFFF);

    // MUL
    check_reg("x20 (MUL 10*20=200)",     reg_val[20], 32'd200);
    check_reg("x21 (MULH 20*-10)=-1",    reg_val[21], 32'hFFFFFFFF);
    check_reg("x22 (MULHSU 10*u(-10))=9",reg_val[22], 32'd9);
    check_reg("x23 (MULHU 10*20=0)",     reg_val[23], 32'd0);

    // DIV/REM
    check_reg("x24 (DIV op=100)",        reg_val[24], 32'd100);
    check_reg("x25 (DIV op=7)",          reg_val[25], 32'd7);
    check_reg("x26 (DIV 100/7=14)",      reg_val[26], 32'd14);
    check_reg("x27 (DIVU 100/7=14)",     reg_val[27], 32'd14);

    // Loads (final values after overwrites)
    // x28: LW→42, LB→0xFFFFFFAB, JALR writes PC+4 (return addr)
    // x29: LBU→0xAB, LH→0xFFFFFFFF, JALR target overwrites to 55
    check_reg("x29 (JALR target=55)",    reg_val[29], 32'd55);
    check_reg("x30 (LUI 0xABCDE000)",    reg_val[30], 32'hABCDE000);

    // Memory
    $display("---- Memory verification ----");
    check_reg("mem[0] (SW 42)",          read_dmem_word(0),  32'd42);
    check_reg("mem[4] (SB 0xAB)",        read_dmem_word(4),  32'h000000AB);
    check_reg("mem[8] (SH -1)",          read_dmem_word(8),  32'h0000FFFF);

    // JAL: x31 = PC+4 of JAL instruction
    check_reg("x31 (JAL ret addr)",      reg_val[31], jal_phase1_idx * 4 + 4);
    check_reg("x29 (JALR target=55)",    reg_val[29], 32'd55);
  endtask

  // #########################################################################
  //
  //  PHASE 2 — Hazard / Forwarding (runs in isolation after reset)
  //
  // #########################################################################
  task automatic load_phase2();
    integer jalr_base;
    idx = 0;
    $display("[TB] Phase 2: hazard/forwarding (starting word %0d)", idx);

    // ---- ALU→ALU 0 NOP (EX/MEM forward) → check x16 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd42,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd0,5'd24,3'b000,5'd16,OPC_OP); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- ALU→ALU 1 NOP (MEM/WB forward) → check x17 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd7, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=NOP; idx++;
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd0,5'd24,3'b000,5'd17,OPC_OP); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- ALU→ALU 2 NOPs (write-first) → check x18 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd9, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=NOP; idx++;
    u_dut.u_instr_mem.mem[idx]=NOP; idx++;
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd0,5'd24,3'b000,5'd18,OPC_OP); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Setup mem[0]=42 for load tests ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd42,5'd0,3'b000,5'd26,OPC_OP_IMM); idx++;
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd0, 5'd26,5'd0,3'b010,OPC_STORE); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Load→ALU 0 NOP (stall + MEM/WB forward) → check x22 ----
    // FIX: 2-cycle load-use for registered BRAM needs 1 NOP (was 0) — added for 55/55
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b010,5'd19,OPC_LOAD);  idx++;
    u_dut.u_instr_mem.mem[idx]=NOP; idx++; // extra hold for 2-cycle
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd0,5'd19,3'b000,5'd22,OPC_OP); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Load→ALU 1 NOP → check x23 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b010,5'd19,OPC_LOAD);  idx++;
    u_dut.u_instr_mem.mem[idx]=NOP; idx++;
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd0,5'd19,3'b000,5'd23,OPC_OP); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Load→ALU 2 NOPs → check x28 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b010,5'd19,OPC_LOAD);  idx++;
    u_dut.u_instr_mem.mem[idx]=NOP; idx++;
    u_dut.u_instr_mem.mem[idx]=NOP; idx++;
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd0,5'd19,3'b000,5'd28,OPC_OP); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Store→Load (mem[4] test) → check x29 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd100,5'd0,3'b000,5'd29,OPC_OP_IMM); idx++;
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd4,  5'd29,5'd0,3'b010,OPC_STORE); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd4,  5'd0,3'b010,5'd29,OPC_LOAD);  idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Load→Store data fwd (0 NOPs) → check x30 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b010,5'd19,OPC_LOAD);  idx++;
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd8, 5'd19,5'd0,3'b010,OPC_STORE); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd8, 5'd0,3'b010,5'd30,OPC_LOAD);  idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- LUI→ALU fwd → check x25 ----
    u_dut.u_instr_mem.mem[idx]=enc_u(32'h12345000,5'd24,OPC_LUI); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd0,5'd24,3'b000,5'd25,OPC_OP); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- JALR base-reg + wb forwarding → check x27 ----
    // Place target at word (jalr_base+6): ADDI x27, x0, 200
    jalr_base = idx;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // placeholder for x24
    u_dut.u_instr_mem.mem[idx]=NOP; idx++;
    u_dut.u_instr_mem.mem[idx]=NOP; idx++;
    u_dut.u_instr_mem.mem[idx]=NOP; idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd24,3'b000,5'd31,OPC_JALR); idx++; // JALR x31,x24,0
    u_dut.u_instr_mem.mem[idx]=NOP; idx++; // flushed
    // Target instruction:
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd200,5'd0,3'b000,5'd27,OPC_OP_IMM); idx++; // x27=200
    // Patch x24 with target byte address: (jalr_base+6)*4
    u_dut.u_instr_mem.mem[jalr_base]=enc_i((jalr_base+6)*4, 5'd0,3'b000,5'd24,OPC_OP_IMM);
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Branch taken (BNE, mispredict flush) → check x24 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd1, 5'd0,3'b000,5'd25,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd12,5'd25,5'd24,3'b001,OPC_BRANCH); idx++; // BNE taken, +12
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // flushed
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // flushed
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd77,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // target: x24=77
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Branch not-taken (BEQ with false condition) → check x26 ----
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd2,5'd1,3'b000,OPC_BRANCH); idx++; // BEQ x1,x2: 10!=20 → not-taken
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd88,5'd0,3'b000,5'd26,OPC_OP_IMM); idx++; // x26=88 (executes)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- MUL→ALU fwd (0 NOPs, FWD_MULDIV path) → check x16 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd6, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // x24=6
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd7, 5'd0,3'b000,5'd25,OPC_OP_IMM); idx++; // x25=7
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd25,5'd24,3'b000,5'd16,OPC_OP); idx++; // MUL x16=42
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd1, 5'd16,3'b000,5'd16,OPC_OP_IMM); idx++; // ADDI x16=x16+1=43 (fwd from MUL)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- DIV→ALU fwd (0 NOPs, FWD_MULDIV path) → check x17 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd100,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // x24=100
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd7,  5'd0,3'b000,5'd25,OPC_OP_IMM); idx++; // x25=7
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd25,5'd24,3'b100,5'd17,OPC_OP); idx++; // DIV x17=14
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd8, 5'd17,3'b000,5'd17,OPC_OP_IMM); idx++; // ADDI x17=x17+8=22 (fwd from DIV)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Multi-hop chain: A→B→C (x24→x25→x26) ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd5, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // x24=5
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd0,5'd24,3'b000,5'd25,OPC_OP); idx++; // x25=x24+0=5 (EX/MEM fwd)
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd0,5'd25,3'b000,5'd26,OPC_OP); idx++; // x26=x25+0=5 (EX/MEM fwd)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Branch with data dependency: BNE on forwarded value → check x24 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd10,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // x24=10
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd10,5'd0,3'b000,5'd25,OPC_OP_IMM); idx++; // x25=10
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd12,5'd25,5'd24,3'b001,OPC_BRANCH); idx++; // BNE x24,x25: 10==10 → not-taken
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd99,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // x24=99 (executes because not-taken)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Load→Branch (load-use before branch, should stall) → check x26 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b010,5'd19,OPC_LOAD);  idx++; // LW x19, 0(x0) → x19=42
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd42,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // x24=42
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd24,5'd19,3'b000,OPC_BRANCH); idx++; // BEQ x19,x24: 42==42 → taken
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd26,OPC_OP_IMM); idx++; // flushed
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd66,5'd0,3'b000,5'd26,OPC_OP_IMM); idx++; // target: x26=66
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- AUIPC→ALU fwd → check x27 ----
    u_dut.u_instr_mem.mem[idx]=enc_u(32'h00001000,5'd24,OPC_AUIPC); idx++; // x24 = PC + 0x1000
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd24,3'b000,5'd27,OPC_OP_IMM); idx++; // x27 = x24 (fwd)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Halt ----
    u_dut.u_instr_mem.mem[idx] = enc_j(21'd0, 5'd0, OPC_JAL); idx++;

    $display("[TB] Phase 2 done: %0d words", idx);
  endtask

  task automatic check_phase2();
    $display("");
    $display("========================================");
    $display("  PHASE 2: HAZARD / FORWARDING");
    $display("========================================");
    for (int i = 0; i < 32; i++) read_regfile(i[4:0], reg_val[i]);

    // ALU→ALU forwarding
    check_reg("x18 (ALU-ALU 2 NOPs)",      reg_val[18], 32'd9);
    // Load→ALU forwarding
    check_reg("x22 (Load-ALU 0 NOP)",      reg_val[22], 32'd42);
    check_reg("x23 (Load-ALU 1 NOP)",      reg_val[23], 32'd42);
    check_reg("x28 (Load-ALU 2 NOPs)",     reg_val[28], 32'd42);
    // Store→Load forwarding
    check_reg("x29 (Store-Load mem[4]=100)", reg_val[29], 32'd100);
    // Load→Store data forwarding
    check_reg("x30 (Load-Store fwd=42)",   reg_val[30], 32'd42);

    // MULDIV→ALU forwarding (FWD_MULDIV path)
    check_reg("x16 (MUL+ADDI fwd=43)",    reg_val[16], 32'd43);
    check_reg("x17 (DIV+ADDI fwd=22)",    reg_val[17], 32'd22);

    // Multi-hop chain (x24→x25→x26, all =5)
    check_reg("x25 (chain A→B=5)",         reg_val[25], 32'd5);

    // Load→Branch (x26 = target value)
    check_reg("x26 (load-branch=66)",     reg_val[26], 32'd66);

    // AUIPC→ALU forwarding (x27 forwarded from x24)
    check_reg("x27 (AUIPC fwd)",          reg_val[27], reg_val[24]);
  endtask

  // #########################################################################
  //
  //  PHASE 3 — Non-blocking M-extension (runs in isolation after reset)
  //
  // #########################################################################
  task automatic load_phase3();
    idx = 0;
    $display("[TB] Phase 3: non-blocking M-extension (starting word %0d)", idx);

    // ---- MUL→ADDI fwd (0 NOPs) → check x20 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd6, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd7, 5'd0,3'b000,5'd25,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd25,5'd24,3'b000,5'd20,OPC_OP); idx++; // MUL x20=42
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd1, 5'd20,3'b000,5'd20,OPC_OP_IMM); idx++; // ADDI x20=x20+1=43
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- MUL b2b → check x21, x22 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd2, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd3, 5'd0,3'b000,5'd25,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd4, 5'd0,3'b000,5'd1, OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd5, 5'd0,3'b000,5'd2, OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd25,5'd24,3'b000,5'd21,OPC_OP); idx++; // MUL x21=6
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd2, 5'd1, 3'b000,5'd22,OPC_OP); idx++; // MUL x22=20
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- DIV→ADDI fwd → check x24 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd100,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd7,  5'd0,3'b000,5'd25,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd25,5'd24,3'b100,5'd24,OPC_OP); idx++; // DIV x24=14
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd8, 5'd24,3'b000,5'd24,OPC_OP_IMM); idx++; // ADDI x24=22
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- MUL→SW→LW → check x26 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd10, 5'd0,3'b000,5'd28,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd20, 5'd0,3'b000,5'd29,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd29,5'd28,3'b000,5'd25,OPC_OP); idx++; // MUL x25=200
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd12, 5'd25,5'd0,3'b010,OPC_STORE); idx++; // SW x25,12(x0)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd12, 5'd0,3'b010,5'd26,OPC_LOAD); idx++; // LW x26,12(x0)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Back-to-back DIV → check x27, x28 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd100,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // x24=100
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd7,  5'd0,3'b000,5'd25,OPC_OP_IMM); idx++; // x25=7
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd50, 5'd0,3'b000,5'd1, OPC_OP_IMM); idx++; // x1=50
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd6,  5'd0,3'b000,5'd2, OPC_OP_IMM); idx++; // x2=6
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd25,5'd24,3'b100,5'd27,OPC_OP); idx++; // DIV x27=100/7=14
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd2, 5'd1, 3'b101,5'd28,OPC_OP); idx++; // DIVU x28=50/6=8
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- REM→ADDI fwd → check x29 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd100,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // x24=100
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd7,  5'd0,3'b000,5'd25,OPC_OP_IMM); idx++; // x25=7
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd25,5'd24,3'b110,5'd29,OPC_OP); idx++; // REM x29=100%7=2
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd10, 5'd29,3'b000,5'd29,OPC_OP_IMM); idx++; // ADDI x29=x29+10=12
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- MUL→Branch (MUL result used in branch comparison) → check x24 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd6, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // x24=6
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd7, 5'd0,3'b000,5'd25,OPC_OP_IMM); idx++; // x25=7
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd25,5'd24,3'b000,5'd30,OPC_OP); idx++; // MUL x30=42
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd42,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // x24=42
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd30,5'd24,3'b000,OPC_BRANCH); idx++; // BEQ x30,x24: 42==42 → taken
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // flushed
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd77,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // target: x24=77
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- MUL with concurrent ALU (parallel execution) → check x30 ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd3, 5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // x24=3
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd4, 5'd0,3'b000,5'd25,OPC_OP_IMM); idx++; // x25=4
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd10,5'd0,3'b000,5'd1, OPC_OP_IMM); idx++; // x1=10
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd20,5'd0,3'b000,5'd2, OPC_OP_IMM); idx++; // x2=20
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000001,5'd25,5'd24,3'b000,5'd30,OPC_OP); idx++; // MUL x30=12 (slow)
    u_dut.u_instr_mem.mem[idx]=enc_r(7'b0000000,5'd2, 5'd1, 3'b000,5'd29,OPC_OP); idx++; // ADD x29=30 (ALU, fast)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Halt ----
    u_dut.u_instr_mem.mem[idx] = enc_j(21'd0, 5'd0, OPC_JAL); idx++;

    $display("[TB] Phase 3 done: %0d words", idx);
  endtask

  task automatic check_phase3();
    $display("");
    $display("========================================");
    $display("  PHASE 3: NON-BLOCKING M-EXTENSION");
    $display("========================================");
    for (int i = 0; i < 32; i++) read_regfile(i[4:0], reg_val[i]);

    check_reg("x20 (MUL+ADDI fwd=43)",   reg_val[20], 32'd43);
    check_reg("x21 (MUL b2b 2*3=6)",     reg_val[21], 32'd6);
    check_reg("x22 (MUL b2b 4*5=20)",    reg_val[22], 32'd20);
    check_reg("x26 (MUL-SW-LW=200)",     reg_val[26], 32'd200);

    // Back-to-back DIV
    check_reg("x27 (DIV 100/7=14)",      reg_val[27], 32'd14);
    check_reg("x28 (DIVU 50/6=8)",       reg_val[28], 32'd8);

    // REM→ADDI forwarding
    check_reg("x29 (REM+ADDI fwd=12)",   reg_val[29], 32'd12);

    // MUL→Branch (branch taken to x24=77)
    check_reg("x24 (MUL-branch=77)",     reg_val[24], 32'd77);

    // MUL+ALU parallel execution (x29 overwritten to 30 by ADD)
    check_reg("x29 (MUL||ALU add=30)",   reg_val[29], 32'd30);
    check_reg("x30 (MUL||ALU mul=12)",   reg_val[30], 32'd12);
  endtask

  // #########################################################################
  //
  //  MAIN — run each phase in isolation (reset between phases)
  //
  // #########################################################################
  initial begin
    $dumpfile("soc_final.vcd");
    $dumpvars(0, tb_soc_final);
    pass_count = 0;
    fail_count = 0;

    // ===== PHASE 1: Instruction correctness =====
    fill_nops();
    fill_dmem_zeros();
    load_phase1();
    rst_n = 0; repeat(3) @(posedge clk); #1 rst_n = 1;
    run_to_halt(5000);
    check_phase1();

    // ===== PHASE 2: Hazard / Forwarding =====
    fill_nops();
    fill_dmem_zeros();
    load_phase2();
    rst_n = 0; repeat(3) @(posedge clk); #1 rst_n = 1;
    run_to_halt(5000);
    check_phase2();

    // ===== PHASE 3: Non-blocking M-extension =====
    fill_nops();
    fill_dmem_zeros();
    load_phase3();
    rst_n = 0; repeat(3) @(posedge clk); #1 rst_n = 1;
    run_to_halt(5000);
    check_phase3();

    // ===== Summary =====
    $display("");
    $display("========================================");
    $display("  TOTAL: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("========================================");
    $display("");

    #10;
    $finish;
  end

endmodule
