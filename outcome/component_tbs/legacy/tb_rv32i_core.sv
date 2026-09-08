`timescale 1ns / 1ps

module tb_rv32i_core;

  import rv32i_pkg::*;

  // =========================================================================
  // Clock / Reset
  // =========================================================================
  logic clk;
  logic rst_n;

  localparam CLK_PERIOD = 10;
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // =========================================================================
  // DUT interface signals
  // =========================================================================
  logic [XLEN-1:0] instr_addr;
  logic [XLEN-1:0] instr_rdata;
  logic [XLEN-1:0] data_addr;
  logic [XLEN-1:0] data_wdata;
  logic [XLEN-1:0] data_rdata;
  logic            data_we;
  logic [3:0]      data_be;
  logic            data_re;

  // =========================================================================
  // Instruction memory (combinational read)
  // =========================================================================
  localparam int unsigned IMEM_DEPTH = 1024;
  logic [31:0] imem [0:IMEM_DEPTH-1];

  assign instr_rdata = imem[instr_addr[31:2]];

  // =========================================================================
  // Data memory (registered read, synchronous write with byte-enable)
  // =========================================================================
  localparam int unsigned DMEM_DEPTH = 1024;
  logic [7:0] dmem [0:DMEM_DEPTH*4-1];
  logic [31:0] dm_raw;

  always_ff @(posedge clk) begin
    if (data_we) begin
      if (data_be[0]) dmem[data_addr + 0] <= data_wdata[7:0];
      if (data_be[1]) dmem[data_addr + 1] <= data_wdata[15:8];
      if (data_be[2]) dmem[data_addr + 2] <= data_wdata[23:16];
      if (data_be[3]) dmem[data_addr + 3] <= data_wdata[31:24];
    end
    dm_raw <= {dmem[data_addr[31:2]*4+3], dmem[data_addr[31:2]*4+2],
               dmem[data_addr[31:2]*4+1], dmem[data_addr[31:2]*4]};
  end

  assign data_rdata = dm_raw;

  // =========================================================================
  // DUT instantiation
  // =========================================================================
  logic [4:0]  dbg_regfile_addr;
  logic [31:0] dbg_regfile_data;

  rv32i_core u_dut (
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
    .dbg_pc      (),
    .dbg_instr   (),
    .dbg_valid   (),
    .dbg_regfile_addr(dbg_regfile_addr),
    .dbg_regfile_data(dbg_regfile_data)
  );

  // =========================================================================
  // Register file access for checking (hierarchical reference)
  // =========================================================================
  logic [31:0] regfile [0:31];
  always_comb begin
    for (int i = 0; i < 32; i++) begin
      if (i == 0)
        regfile[i] = 32'h0;
      else
        regfile[i] = u_dut.u_regfile.regs[i];
    end
  end

  // =========================================================================
  // Instruction encoding helpers
  // =========================================================================
  function automatic logic [31:0] enc_r(
    input logic [6:0]  funct7,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3,
    input logic [4:0]  rd,
    input logic [6:0]  opcode
  );
    return {funct7, rs2, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] enc_i(
    input logic [11:0] imm,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3,
    input logic [4:0]  rd,
    input logic [6:0]  opcode
  );
    return {imm, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] enc_s(
    input logic [11:0] imm,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3,
    input logic [6:0]  opcode
  );
    return {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
  endfunction

  function automatic logic [31:0] enc_b(
    input logic [12:0] imm,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3,
    input logic [6:0]  opcode
  );
    return {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
  endfunction

  function automatic logic [31:0] enc_u(
    input logic [31:0] imm,
    input logic [4:0]   rd,
    input logic [6:0]   opcode
  );
    return {imm[31:12], rd, opcode};
  endfunction

  function automatic logic [31:0] enc_j(
    input logic [20:1] imm,
    input logic [4:0]  rd,
    input logic [6:0]  opcode
  );
    return {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
  endfunction

  // =========================================================================
  // NOP shorthand
  // =========================================================================
  localparam logic [31:0] NOP = 32'h0000_0013;

  // =========================================================================
  // Test program
  // =========================================================================
  integer pc_idx;

  task automatic load_program();
    pc_idx = 0;

    imem[pc_idx] = enc_i(12'd5,     5'd0, 3'b000, 5'd1,  OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(-12'd3,    5'd0, 3'b000, 5'd2,  OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd0,     5'd0, 3'b000, 5'd3,  OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd0,     5'd0, 3'b000, 5'd4,  OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd0,     5'd0, 3'b000, 5'd5,  OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_r(7'b0100000, 5'd2, 5'd1, 3'b000, 5'd4, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_r(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd5, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_r(7'b0000000, 5'd2, 5'd1, 3'b110, 5'd6, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_r(7'b0000000, 5'd2, 5'd1, 3'b100, 5'd7, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_r(7'b0000000, 5'd1, 5'd2, 3'b010, 5'd8, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_r(7'b0000000, 5'd1, 5'd2, 3'b011, 5'd9, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_r(7'b0000000, 5'd2, 5'd1, 3'b001, 5'd10, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_r(7'b0000000, 5'd2, 5'd1, 3'b101, 5'd11, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_i(-12'd1,    5'd0, 3'b000, 5'd12, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_r(7'b0100000, 5'd2, 5'd12, 3'b101, 5'd13, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_u(32'hABCDE000, 5'd14, OPC_LUI); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_u(32'h00001000, 5'd15, OPC_AUIPC); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_i(12'd42,    5'd0, 3'b000, 5'd16, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_s(12'd0, 5'd16, 5'd0, 3'b010, OPC_STORE); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_i(12'd0,     5'd0, 3'b010, 5'd17, OPC_LOAD); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_i(12'h0AB,   5'd0, 3'b000, 5'd18, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_s(12'd4, 5'd18, 5'd0, 3'b000, OPC_STORE); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_i(12'd4,     5'd0, 3'b000, 5'd19, OPC_LOAD); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_i(12'd4,     5'd0, 3'b100, 5'd20, OPC_LOAD); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_i(-12'd1,    5'd0, 3'b000, 5'd21, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_s(12'd8, 5'd21, 5'd0, 3'b001, OPC_STORE); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_i(12'd8,     5'd0, 3'b001, 5'd22, OPC_LOAD); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_i(12'd8,     5'd0, 3'b101, 5'd23, OPC_LOAD); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // Branches
    imem[pc_idx] = enc_b(13'd8, 5'd1, 5'd1, 3'b000, OPC_BRANCH); pc_idx++;
    imem[pc_idx] = enc_i(12'd99, 5'd0, 3'b000, 5'd24, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd0,  5'd0, 3'b000, 5'd24, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd42, 5'd0, 3'b000, 5'd24, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_b(13'd8, 5'd1, 5'd2, 3'b000, OPC_BRANCH); pc_idx++;
    imem[pc_idx] = enc_i(12'd77, 5'd0, 3'b000, 5'd25, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_b(13'd4, 5'd1, 5'd2, 3'b001, OPC_BRANCH); pc_idx++;
    imem[pc_idx] = enc_i(12'd99, 5'd0, 3'b000, 5'd26, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd55, 5'd0, 3'b000, 5'd26, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_b(13'd4, 5'd1, 5'd2, 3'b100, OPC_BRANCH); pc_idx++;
    imem[pc_idx] = enc_i(12'd99, 5'd0, 3'b000, 5'd27, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd33, 5'd0, 3'b000, 5'd27, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_b(13'd4, 5'd2, 5'd1, 3'b101, OPC_BRANCH); pc_idx++;
    imem[pc_idx] = enc_i(12'd99, 5'd0, 3'b000, 5'd28, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd22, 5'd0, 3'b000, 5'd28, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_b(13'd4, 5'd1, 5'd2, 3'b110, OPC_BRANCH); pc_idx++;
    imem[pc_idx] = enc_i(12'd11, 5'd0, 3'b000, 5'd29, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    imem[pc_idx] = enc_b(13'd4, 5'd1, 5'd2, 3'b111, OPC_BRANCH); pc_idx++;
    imem[pc_idx] = enc_i(12'd99, 5'd0, 3'b000, 5'd30, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd88, 5'd0, 3'b000, 5'd30, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // JAL x31, 8
    imem[pc_idx] = enc_j(20'd8, 5'd31, OPC_JAL); pc_idx++;
    imem[pc_idx] = enc_i(12'd99, 5'd0, 3'b000, 5'd24, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd0,  5'd0, 3'b000, 5'd0, OPC_OP_IMM); pc_idx++;
    repeat (16) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // OP-IMM instruction coverage — all 8 I-type ALU variants
    //   Each result stored to dmem, verified in check_results via read_dword
    // ======================================================================

    // SLLI  x15, x1, 1  (5 << 1 = 10)
    imem[pc_idx] = enc_i(12'd1, 5'd1, 3'b001, 5'd15, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_s(12'd256, 5'd15, 5'd0, 3'b010, OPC_STORE); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // SLTI  x15, x2, 0  (-3 < 0 = 1)
    imem[pc_idx] = enc_i(12'd0, 5'd2, 3'b010, 5'd15, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_s(12'd260, 5'd15, 5'd0, 3'b010, OPC_STORE); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // SLTIU x15, x2, 0  (0xFFFFFFFD < 0 unsigned = 0)
    imem[pc_idx] = enc_i(12'd0, 5'd2, 3'b011, 5'd15, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_s(12'd264, 5'd15, 5'd0, 3'b010, OPC_STORE); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // XORI  x15, x2, -1  (-3 ^ -1 = 2)
    imem[pc_idx] = enc_i(12'hFFF, 5'd2, 3'b100, 5'd15, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_s(12'd268, 5'd15, 5'd0, 3'b010, OPC_STORE); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // SRLI  x15, x1, 1  (5 >> 1 = 2)
    imem[pc_idx] = enc_i(12'd1, 5'd1, 3'b101, 5'd15, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_s(12'd272, 5'd15, 5'd0, 3'b010, OPC_STORE); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // SRAI  x15, x12, 1  (-1 >>> 1 = -1)
    imem[pc_idx] = enc_i(12'h401, 5'd12, 3'b101, 5'd15, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_s(12'd276, 5'd15, 5'd0, 3'b010, OPC_STORE); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ORI   x15, x1, 0xF0  (5 | 0xF0 = 0xF5)
    imem[pc_idx] = enc_i(12'h0F0, 5'd1, 3'b110, 5'd15, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_s(12'd280, 5'd15, 5'd0, 3'b010, OPC_STORE); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ANDI  x15, x1, 0x0F0  (5 & 0x0F0 = 0)
    imem[pc_idx] = enc_i(12'h0F0, 5'd1, 3'b111, 5'd15, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_s(12'd284, 5'd15, 5'd0, 3'b010, OPC_STORE); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // FENCE / FENCE.I as safe no-ops
    // ======================================================================
    imem[pc_idx] = enc_i(12'd100, 5'd0, 3'b000, 5'd31, OPC_OP_IMM); pc_idx++; // x31=100
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    imem[pc_idx] = 32'h0000000F; pc_idx++; // FENCE
    imem[pc_idx] = enc_i(12'd200, 5'd0, 3'b000, 5'd31, OPC_OP_IMM); pc_idx++; // x31=200
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    imem[pc_idx] = 32'h0000200F; pc_idx++; // FENCE.I
    imem[pc_idx] = enc_i(12'd300, 5'd0, 3'b000, 5'd31, OPC_OP_IMM); pc_idx++; // x31=300
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // Halt
    imem[pc_idx] = enc_j(21'd0, 5'd0, OPC_JAL); pc_idx++;

    $display("[TB] Program loaded: %0d instructions", pc_idx);
  endtask

  // =========================================================================
  // Expected results
  // =========================================================================
  int pass_count;
  int fail_count;

  task automatic check_reg(input string name, input logic [31:0] actual, input logic [31:0] expected);
    if (actual === expected) begin
      $display("[PASS] %0s = 0x%08h", name, actual);
      pass_count++;
    end else begin
      $display("[FAIL] %0s = 0x%08h (expected 0x%08h)", name, actual, expected);
      fail_count++;
    end
  endtask

  // --------------------------------------------------------------------------
  // Helper: read a 32-bit word from dmem at byte address
  // --------------------------------------------------------------------------
  function automatic logic [31:0] read_dword(input int addr);
    return {dmem[addr+3], dmem[addr+2], dmem[addr+1], dmem[addr]};
  endfunction

  task automatic check_results();
    pass_count = 0;
    fail_count = 0;

    $display("");
    $display("========================================");
    $display("  CHECKING REGISTER FILE STATE");
    $display("========================================");

    check_reg("x1  (ADDI 5)",          regfile[1],  32'h0000_0005);
    check_reg("x2  (ADDI -3)",         regfile[2],  32'hFFFF_FFFD);
    check_reg("x3  (ADD x1+x2)",       regfile[3],  32'h0000_0002);
    check_reg("x4  (SUB x1-x2)",       regfile[4],  32'h0000_0008);
    check_reg("x5  (AND x1&x2)",       regfile[5],  32'h0000_0005);
    check_reg("x6  (OR x1|x2)",        regfile[6],  32'hFFFF_FFFD);
    check_reg("x7  (XOR x1^x2)",       regfile[7],  32'hFFFF_FFF8);
    check_reg("x8  (SLT -3<5)",        regfile[8],  32'h0000_0001);
    check_reg("x9  (SLTU u(-3)>u(5))", regfile[9],  32'h0000_0000);
    check_reg("x10 (SLL 5<<29)",       regfile[10], 32'hA000_0000);
    check_reg("x11 (SRL 5>>29)",       regfile[11], 32'h0000_0000);
    check_reg("x12 (ADDI -1)",         regfile[12], 32'hFFFF_FFFF);
    check_reg("x13 (SRA -1>>>29)",     regfile[13], 32'hFFFF_FFFF);
    check_reg("x14 (LUI 0xABCDE)",     regfile[14], 32'hABCD_E000);
    $display("[INFO] x15 (AUIPC) = 0x%08h", regfile[15]);
    check_reg("x16 (ADDI 42)",         regfile[16], 32'h0000_002A);
    check_reg("x17 (LW from mem[0])",  regfile[17], 32'h0000_002A);
    check_reg("x18 (ADDI 0xAB)",       regfile[18], 32'h0000_00AB);
    check_reg("x19 (LB sign-ext)",     regfile[19], 32'hFFFF_FFAB);
    check_reg("x20 (LBU zero-ext)",    regfile[20], 32'h0000_00AB);
    check_reg("x21 (ADDI -1)",         regfile[21], 32'hFFFF_FFFF);
    check_reg("x22 (LH sign-ext)",     regfile[22], 32'hFFFF_FFFF);
    check_reg("x23 (LHU zero-ext)",    regfile[23], 32'h0000_FFFF);
    check_reg("x24 (BEQ taken -> 42)", regfile[24], 32'h0000_002A);
    check_reg("x25 (BEQ not-taken 77)",regfile[25], 32'h0000_004D);
    check_reg("x26 (BNE taken -> 55)", regfile[26], 32'h0000_0037);
    check_reg("x27 (BLT taken -> 33)", regfile[27], 32'h0000_0021);
    check_reg("x28 (BGE taken -> 22)", regfile[28], 32'h0000_0016);
    check_reg("x29 (BLTU not-taken 11)",regfile[29],32'h0000_000B);
    check_reg("x30 (BGEU taken -> 88)",regfile[30], 32'h0000_0058);
    $display("[INFO] x31 (JAL link) = 0x%08h", regfile[31]);

    $display("---- OP-IMM coverage tests ----");
    check_reg("SLLI 5<<1=10",         read_dword(256), 32'd10);
    check_reg("SLTI -3<0=1",          read_dword(260), 32'd1);
    check_reg("SLTIU u(-3)<0=0",      read_dword(264), 32'd0);
    check_reg("XORI -3^-1=2",         read_dword(268), 32'd2);
    check_reg("SRLI 5>>1=2",          read_dword(272), 32'd2);
    check_reg("SRAI -1>>>1=-1",       read_dword(276), 32'hFFFFFFFF);
    check_reg("ORI 5|0xF0=0xF5",      read_dword(280), 32'h000000F5);
    check_reg("ANDI 5&0x0F0=0",       read_dword(284), 32'd0);

    $display("---- FENCE / FENCE.I coverage test ----");
    check_reg("x31(FENCE no-op=300)", regfile[31], 32'd300);

    $display("");
    $display("========================================");
    $display("  RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("========================================");
    $display("");
  endtask

  // =========================================================================
  // Test sequence
  // =========================================================================
  initial begin
    for (int i = 0; i < IMEM_DEPTH; i++) imem[i] = NOP;
    for (int i = 0; i < DMEM_DEPTH*4; i++) dmem[i] = 8'h00;

    load_program();

    rst_n = 0;
    repeat (3) @(posedge clk);
    #1 rst_n = 1;

    repeat (600) @(posedge clk);

    check_results();

    $finish;
  end

  // =========================================================================
  // Waveform dump
  // =========================================================================
  initial begin
    $dumpfile("rv32i_core.vcd");
    $dumpvars(0, tb_rv32i_core);
  end

endmodule
