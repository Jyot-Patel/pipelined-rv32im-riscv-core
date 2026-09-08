`timescale 1ns / 1ps

module tb_hazards;

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
  // Instruction memory (registered read — matches real BRAM timing)
  // =========================================================================
  localparam int unsigned IMEM_DEPTH = 1024;
  logic [31:0] imem [0:IMEM_DEPTH-1];

  always_ff @(posedge clk) begin
    instr_rdata <= imem[instr_addr[31:2]];
  end

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
  // Debug port signals for regfile read
  // =========================================================================
  logic [4:0]  dbg_regfile_addr;
  logic [31:0] dbg_regfile_data;

  // =========================================================================
  // DUT instantiation
  // =========================================================================
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
  // Debug port: read register file combinationally
  // =========================================================================
  logic [31:0] reg_val [0:31];

  task automatic read_regfile(input [4:0] addr, output logic [31:0] val);
    dbg_regfile_addr = addr;
    #0;
    val = dbg_regfile_data;
  endtask

  // =========================================================================
  // RISC-V (RV32I) Instruction Encoding Helpers
  // =========================================================================

  // R-Type: Register-Register operations (e.g., ADD, SUB, AND, OR, SLT)
  // Format: [31:25] funct7 | [24:20] rs2 | [19:15] rs1 | [14:12] funct3 | [11:7] rd | [6:0] opcode
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

  // I-Type: Immediate & Load operations (e.g., ADDI, LW, JALR, SLLI)
  // Format: [31:20] imm[11:0] | [19:15] rs1 | [14:12] funct3 | [11:7] rd | [6:0] opcode
  function automatic logic [31:0] enc_i(
    input logic [11:0] imm,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3,
    input logic [4:0]  rd,
    input logic [6:0]  opcode
  );
    return {imm, rs1, funct3, rd, opcode};
  endfunction

  // S-Type: Store operations (e.g., SW, SH, SB)
  // Format: [31:25] imm[11:5] | [24:20] rs2 | [19:15] rs1 | [14:12] funct3 | [11:7] imm[4:0] | [6:0] opcode
  function automatic logic [31:0] enc_s(
    input logic [11:0] imm,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3,
    input logic [6:0]  opcode
  );
    return {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
  endfunction

  // U-Type: Upper Immediate operations (e.g., LUI, AUIPC)
  // Format: [31:12] imm[31:12] | [11:7] rd | [6:0] opcode
  function automatic logic [31:0] enc_u(
    input logic [31:0] imm,
    input logic [4:0]   rd,
    input logic [6:0]   opcode
  );
    return {imm[31:12], rd, opcode};
  endfunction

  // B-Type: Conditional Branch operations (e.g., BEQ, BNE, BLT, BGE)
  // Format: [31] imm[12] | [30:25] imm[10:5] | [24:20] rs2 | [19:15] rs1 | [14:12] funct3 | [11:8] imm[4:1] | [7] imm[11] | [6:0] opcode
  function automatic logic [31:0] enc_b(
    input logic [12:0] offset,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3,
    input logic [6:0]  opcode
  );
    logic [31:0] instr;
    instr[31]    = offset[12];
    instr[30:25] = offset[10:5];
    instr[24:20] = rs2;
    instr[19:15] = rs1;
    instr[14:12] = funct3;
    instr[11:8]  = offset[4:1];
    instr[7]     = offset[11];
    instr[6:0]   = opcode;
    return instr;
  endfunction

  // J-Type: Unconditional Jump operations (e.g., JAL)
  // Format: [31] imm[20] | [30:21] imm[10:1] | [20] imm[11] | [19:12] imm[19:12] | [11:7] rd | [6:0] opcode
  function automatic logic [31:0] enc_j(
    input logic [20:0] offset,
    input logic [4:0]  rd,
    input logic [6:0]  opcode
  );
    logic [31:0] instr;
    instr[31]    = offset[20];
    instr[30:21] = offset[10:1];
    instr[20]    = offset[11];
    instr[19:12] = offset[19:12];
    instr[11:7]  = rd;
    instr[6:0]   = opcode;
    return instr;
  endfunction

  localparam logic [31:0] NOP = 32'h0000_0013;

  // =========================================================================
  // Hazard test program
  // =========================================================================
  integer pc_idx;

  task automatic load_program();

    // ======================================================================
    // Test program structure:
    //
    //   Each test sets a destination register, then a dependent instruction
    //   follows with 0/1/2 NOPs.  With forwarding + load-use stall:
    //
    //     ALU→ALU 0 NOPs: EX/MEM forward → correct result
    //     ALU→ALU 1 NOP:  MEM/WB forward → correct result
    //     ALU→ALU 2 NOPs: write-first or MEM/WB → correct result
    //     Load→ALU 0 NOPs: load-use stall + MEM/WB forward → correct result
    //     Load→ALU 1 NOP:  MEM/WB forward → correct result
    //     Load→ALU 2 NOPs: write-first or MEM/WB → correct result
    //
    //   Tests 8-9 verify interaction with branch predictor.
    // ======================================================================

    pc_idx = 0;

    // ======================================================================
    // [TEST 1] ALU→ALU, 0 NOPs  —  expect CORRECT via EX/MEM forward
    // ======================================================================
    // Producer: x30 = 42.  Consumer reads x30 with 0 delay.
    // At consumer EX: producer is in EX/MEM → forward 42.
    imem[pc_idx] = enc_i(12'd42, 5'd0, 3'b000, 5'd30, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_r(7'b0000000, 5'd0, 5'd30, 3'b000, 5'd31, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    // Expected: x31 = 42 (EX/MEM forward)

    // ======================================================================
    // [TEST 2] ALU→ALU, 1 NOP  —  expect CORRECT via MEM/WB forward
    // ======================================================================
    imem[pc_idx] = enc_i(12'd7,  5'd0, 3'b000, 5'd29, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = NOP; pc_idx++;
    imem[pc_idx] = enc_r(7'b0000000, 5'd0, 5'd29, 3'b000, 5'd28, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    // Expected: x28 = 7 (MEM/WB forward)

    // ======================================================================
    // [TEST 3] ALU→ALU, 2 NOPs  —  expect CORRECT (write-first forwarding)
    // ======================================================================
    imem[pc_idx] = enc_i(12'd9,  5'd0, 3'b000, 5'd27, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = NOP; pc_idx++;
    imem[pc_idx] = NOP; pc_idx++;
    imem[pc_idx] = enc_r(7'b0000000, 5'd0, 5'd27, 3'b000, 5'd26, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    // Expected: x26 = 9

    // ======================================================================
    // Setup memory for load tests: mem[0] = 42
    // ======================================================================
    imem[pc_idx] = enc_i(12'd42, 5'd0, 3'b000, 5'd7, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    imem[pc_idx] = enc_s(12'd0, 5'd7, 5'd0, 3'b010, OPC_STORE); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    // mem[0] = 42

    // ======================================================================
    // [TEST 4] Load→ALU, 0 NOPs  —  expect CORRECT (stall + MEM/WB forward)
    // ======================================================================
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b010, 5'd8, OPC_LOAD); pc_idx++;
    // 0 NOPs — load-use stall detection inserts bubble
    imem[pc_idx] = enc_r(7'b0000000, 5'd0, 5'd8, 3'b000, 5'd9, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    // Expected: x9 = 42 (load-use stall → MEM/WB forward)

    // ======================================================================
    // [TEST 5] Load→ALU, 1 NOP  —  expect CORRECT via MEM/WB forward
    // ======================================================================
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b010, 5'd10, OPC_LOAD); pc_idx++;
    imem[pc_idx] = NOP; pc_idx++;
    imem[pc_idx] = enc_r(7'b0000000, 5'd0, 5'd10, 3'b000, 5'd11, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    // Expected: x11 = 42 (MEM/WB forward)

    // ======================================================================
    // [TEST 6] Load→ALU, 2 NOPs  —  expect CORRECT (write-first forwarding)
    // ======================================================================
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b010, 5'd12, OPC_LOAD); pc_idx++;
    imem[pc_idx] = NOP; pc_idx++;
    imem[pc_idx] = NOP; pc_idx++;
    imem[pc_idx] = enc_r(7'b0000000, 5'd0, 5'd12, 3'b000, 5'd13, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    // Expected: x13 = 42

    // ======================================================================
    // [TEST 7] Store→Load (mem hazard, no forwarding needed)
    // ======================================================================
    imem[pc_idx] = enc_i(12'd100, 5'd0, 3'b000, 5'd14, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    imem[pc_idx] = enc_s(12'd4, 5'd14, 5'd0, 3'b010, OPC_STORE); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    imem[pc_idx] = enc_i(12'd4, 5'd0, 3'b010, 5'd15, OPC_LOAD); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    // Expected: x15 = 100

    // ======================================================================
    // [TEST 8a] Load→ALU stall + forward (re-verify after other tests)
    // ======================================================================
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b010, 5'd16, OPC_LOAD); pc_idx++;
    imem[pc_idx] = enc_r(7'b0000000, 5'd0, 5'd16, 3'b000, 5'd17, OPC_OP); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    // Expected: x17 = 42 (load-use stall + forward)

    // ======================================================================
    // [TEST 8b] Taken branch immediately after stall recovery
    // ======================================================================
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b000, 5'd18, OPC_OP_IMM); pc_idx++; // x18=0
    imem[pc_idx] = enc_i(12'd1, 5'd0, 3'b000, 5'd19, OPC_OP_IMM); pc_idx++; // x19=1
    // BNE x18,x19,+16: 0 != 1 → taken, predict not-taken (BTB miss) → mispredict
    imem[pc_idx] = enc_b(13'd16, 5'd19, 5'd18, 3'b001, OPC_BRANCH); pc_idx++;
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b000, 5'd20, OPC_OP_IMM); pc_idx++; // flushed
    imem[pc_idx] = NOP; pc_idx++; // flushed
    imem[pc_idx] = NOP; pc_idx++; // flushed
    // target of BNE:
    imem[pc_idx] = enc_i(12'd77, 5'd0, 3'b000, 5'd20, OPC_OP_IMM); pc_idx++; // x20=77
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    // Expected: x20 = 77 (branch taken correctly despite mispredict flush)

    // ======================================================================
    // [TEST 8c] Not-taken branch after stall recovery
    // ======================================================================
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b000, 5'd21, OPC_OP_IMM); pc_idx++; // x21=0
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); pc_idx++; // x22=0
    // BEQ x21,x22,+16: 0 == 0 → taken, predict not-taken (BTB miss) → mispredict
    imem[pc_idx] = enc_b(13'd16, 5'd22, 5'd21, 3'b000, OPC_BRANCH); pc_idx++;
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b000, 5'd23, OPC_OP_IMM); pc_idx++; // flushed
    imem[pc_idx] = NOP; pc_idx++; // flushed
    imem[pc_idx] = NOP; pc_idx++; // flushed
    // target of BEQ:
    imem[pc_idx] = enc_i(12'd88, 5'd0, 3'b000, 5'd23, OPC_OP_IMM); pc_idx++; // x23=88
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    // Expected: x23 = 88 (branch taken correctly)

    // ======================================================================
    // [TEST 9] Branch predictor — aliased entries, same BTB index
    //   Two branches at addresses differing by 256 bytes (64 instr words)
    //   so they map to the same PC[7:2] BTB index.
    //
    //   First (PC_A):   BTB miss → predict not-taken → actually taken → mispredict
    //                   → BTB allocated, BHT → weakly taken
    //   Second (PC_B):  BTB hit  → predict taken → actually taken → correct
    // ======================================================================

    // ---- First aliased branch (PC_A) ----
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++; // x1=0
    imem[pc_idx] = enc_i(12'd1, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++; // x2=1
    // BNE x1,x2,+16: 0 != 1 → taken, BTB miss → mispredict + BTB alloc
    imem[pc_idx] = enc_b(13'd16, 5'd2, 5'd1, 3'b001, OPC_BRANCH); pc_idx++;
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b000, 5'd3, OPC_OP_IMM); pc_idx++; // flushed
    imem[pc_idx] = NOP; pc_idx++; // flushed
    imem[pc_idx] = NOP; pc_idx++; // flushed
    // target T1:
    imem[pc_idx] = enc_i(12'd99, 5'd0, 3'b000, 5'd3, OPC_OP_IMM); pc_idx++; // x3=99
    // Fill NOPs until 64 words from BNE to reach same BTB index.
    // After the target (index BNE+3), we need NOPs to pad to BNE+64.
    // Then come 2 addi's before BNE, so NOP_count = 64 - 3 - 2 = 57.
    repeat (57) begin imem[pc_idx] = NOP; pc_idx++; end

    // ---- Second aliased branch (PC_B = PC_A + 256) ----
    // Same BTB index, BHT weakly taken → predict taken → correct
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b000, 5'd4, OPC_OP_IMM); pc_idx++; // x4=0
    imem[pc_idx] = enc_i(12'd1, 5'd0, 3'b000, 5'd5, OPC_OP_IMM); pc_idx++; // x5=1
    imem[pc_idx] = enc_b(13'd16, 5'd5, 5'd4, 3'b001, OPC_BRANCH); pc_idx++;
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b000, 5'd6, OPC_OP_IMM); pc_idx++; // skipped
    imem[pc_idx] = NOP; pc_idx++; // skipped
    imem[pc_idx] = NOP; pc_idx++; // skipped
    // target T2:
    imem[pc_idx] = enc_i(12'd88, 5'd0, 3'b000, 5'd6, OPC_OP_IMM); pc_idx++; // x6=88

    // ======================================================================
    // [TEST 10] JALR base-reg + writeback forwarding (0 NOPs)
    //   ADDI→JALR (base reg forward) + JALR→ADDI (writeback forward)
    // ======================================================================
    imem[pc_idx] = enc_i(12'd676, 5'd0, 3'b000, 5'd24, OPC_OP_IMM); pc_idx++; // x24=676 (target)
    imem[pc_idx] = enc_i(12'd0, 5'd24, 3'b000, 5'd25, OPC_JALR); pc_idx++;    // JALR x25,x24,0→676
    imem[pc_idx] = NOP; pc_idx++;                                              // flushed
    imem[pc_idx] = enc_i(12'hFFC, 5'd25, 3'b000, 5'd16, OPC_OP_IMM); pc_idx++; // x16=x25-4=668
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // [TEST 11] Load→Store data forwarding (0 NOPs)
    //   LW data forwarded to SW's rs2 for store data
    // ======================================================================
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b010, 5'd24, OPC_LOAD); pc_idx++;    // LW x24,0(x0)→42
    imem[pc_idx] = enc_s(12'd8, 5'd24, 5'd0, 3'b010, OPC_STORE); pc_idx++;   // SW x24,8(x0)
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    imem[pc_idx] = enc_i(12'd8, 5'd0, 3'b010, 5'd27, OPC_LOAD); pc_idx++;    // LW x27,8(x0)→42
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // [TEST 12] LUI→ALU forwarding (0 NOPs)
    // ======================================================================
    imem[pc_idx] = enc_u(32'h12345000, 5'd24, OPC_LUI); pc_idx++;            // LUI x24,0x12345
    imem[pc_idx] = enc_r(7'b0000000, 5'd0, 5'd24, 3'b000, 5'd25, OPC_OP); pc_idx++; // ADD x25,x24,x0
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // [TEST 13] AUIPC→ALU forwarding (0 NOPs)
    // ======================================================================
    imem[pc_idx] = enc_u(32'd0, 5'd24, OPC_AUIPC); pc_idx++;                 // AUIPC x24,0→PC
    imem[pc_idx] = enc_r(7'b0000000, 5'd0, 5'd24, 3'b000, 5'd29, OPC_OP); pc_idx++; // ADD x29,x24,x0
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // [TEST 14] JAL→ALU writeback forwarding (0 NOPs)
    //   JAL writes return address, ADD reads it immediately
    // ======================================================================
    imem[pc_idx] = enc_j(21'd4, 5'd24, OPC_JAL); pc_idx++;                   // JAL x24,+8→jmp to 199
    imem[pc_idx] = NOP; pc_idx++;                                             // skipped
    imem[pc_idx] = enc_r(7'b0000000, 5'd0, 5'd24, 3'b000, 5'd30, OPC_OP); pc_idx++; // x30=x24
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // M-extension hazard interaction tests
    // ======================================================================

    // [M1] MUL → ADDI dependent (0 NOPs) - forwarding from EX/MEM after muldiv
    imem[pc_idx] = enc_i(12'd7, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++; // x1=7
    imem[pc_idx] = enc_i(12'd6, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++; // x2=6
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    imem[pc_idx] = enc_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd8, OPC_OP); pc_idx++; // MUL x8,x1,x2=42
    imem[pc_idx] = enc_i(12'd1, 5'd8, 3'b000, 5'd8, OPC_OP_IMM); pc_idx++;    // ADDI x8,x8,1=43
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // [M2] Back-to-back MUL → MUL (0 NOPs gap) - serialization test
    imem[pc_idx] = enc_i(12'd2, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++;  // x1=2
    imem[pc_idx] = enc_i(12'd3, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;  // x2=3
    imem[pc_idx] = enc_i(12'd4, 5'd0, 3'b000, 5'd4, OPC_OP_IMM); pc_idx++;  // x4=4
    imem[pc_idx] = enc_i(12'd5, 5'd0, 3'b000, 5'd5, OPC_OP_IMM); pc_idx++;  // x5=5
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    imem[pc_idx] = enc_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd10, OPC_OP); pc_idx++; // MUL x10,x1,x2=6
    imem[pc_idx] = enc_r(7'b0000001, 5'd5, 5'd4, 3'b000, 5'd12, OPC_OP); pc_idx++; // MUL x12,x4,x5=20
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // [M3] Branch → MUL interaction: taken branch immediately before MUL
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++; // x1=0
    imem[pc_idx] = enc_i(12'd1, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++; // x2=1
    // BNE x1,x2,+12: taken, BTB miss → mispredict flush
    imem[pc_idx] = enc_b(13'd12, 5'd2, 5'd1, 3'b001, OPC_BRANCH); pc_idx++;
    imem[pc_idx] = NOP; pc_idx++; // flushed
    imem[pc_idx] = NOP; pc_idx++; // flushed
    // target (pc_idx+3 from branch):
    imem[pc_idx] = enc_i(12'd10, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++; // x1=10
    imem[pc_idx] = enc_i(12'd20, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++; // x2=20
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    imem[pc_idx] = enc_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd7, OPC_OP); pc_idx++; // MUL x7,x1,x2=200
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // Halt: infinite loop on self
    imem[pc_idx] = enc_j(21'd0, 5'd0, OPC_JAL); pc_idx++; // jal x0, 0 (self-loop)

    // -- Fill rest with NOPs
    repeat (64) begin imem[pc_idx] = NOP; pc_idx++; end

    $display("[TB] Hazard program loaded: %0d instructions", pc_idx);
  endtask

  // =========================================================================
  // Results checking
  // =========================================================================
  int pass_count;
  int fail_count;

  task automatic check_reg(input string name, input logic [31:0] actual,
                           input logic [31:0] expected);
    if (actual === expected) begin
      $display("[PASS] %0s = 0x%08h", name, actual);
      pass_count++;
    end else begin
      $display("[FAIL] %0s = 0x%08h (expected 0x%08h)", name, actual, expected);
      fail_count++;
    end
  endtask

  task automatic check_results();
    pass_count = 0;
    fail_count = 0;

    // Snapshot regfile via debug port
    for (int i = 0; i < 32; i++) begin
      read_regfile(i[4:0], reg_val[i]);
    end

    $display("");
    $display("============================================");
    $display("  HAZARD TEST RESULTS");
    $display("============================================");

    // ALU→ALU (forwarding)
    check_reg("x31 (ALU-ALU 0 NOP forward)", reg_val[31], 32'h0000_002A);
    check_reg("x28 (ALU-ALU 1 NOP forward)", reg_val[28], 32'h0000_0007);
    check_reg("x26 (ALU-ALU 2 NOPs)",        reg_val[26], 32'h0000_0009);

    // Load→ALU (forwarding + load-use stall)
    check_reg("x9  (Load-ALU 0 NOP stall)",  reg_val[9],  32'h0000_002A);
    check_reg("x11 (Load-ALU 1 NOP fwd)",    reg_val[11], 32'h0000_002A);
    check_reg("x13 (Load-ALU 2 NOPs)",       reg_val[13], 32'h0000_002A);

    // Store→Load
    check_reg("x15 (SW-LW mem[4])",          reg_val[15], 32'h0000_0064);

    // Load→ALU forward + branch interaction
    check_reg("x17 (Load-ALU fwd test 8a)",  reg_val[17], 32'h0000_002A);
    check_reg("x20 (taken branch test 8b)",  reg_val[20], 32'h0000_004D);
    check_reg("x23 (taken branch test 8c)",  reg_val[23], 32'h0000_0058);

    // Branch predictor aliased entries
    check_reg("x3  (BP aliased first)",      reg_val[3],  32'h0000_0063);
    check_reg("x6  (BP aliased second)",     reg_val[6],  32'h0000_0058);

    // New hazard coverage tests
    check_reg("x16 (JALR base+wb forward)",  reg_val[16], 32'h0000_029C);
    check_reg("x27 (Load-Store data fwd)",   reg_val[27], 32'h0000_002A);
    check_reg("x25 (LUI-ALU forward)",       reg_val[25], 32'h1234_5000);
    check_reg("x29 (AUIPC-ALU forward)",     reg_val[29], 32'h0000_02FC);
    check_reg("x30 (JAL-ALU wb forward)",    reg_val[30], 32'h0000_0318);

    // M-extension hazard tests
    check_reg("x8  (MUL→ADDI fwd/43)",       reg_val[8],  32'h0000_002B);
    check_reg("x10 (MUL 2*3/b2b)",           reg_val[10], 32'h0000_0006);
    check_reg("x12 (MUL 4*5/b2b)",           reg_val[12], 32'h0000_0014);
    check_reg("x7  (BR→MUL 10*20)",          reg_val[7],  32'h0000_00C8);

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

    // Inline program
    load_program();

    // Reset
    rst_n = 0;
    repeat (3) @(posedge clk);
    #1 rst_n = 1;

    // Run — enough cycles for ~200 instructions * ~8 stages each
    repeat (2000) @(posedge clk);

    // Check results via debug port
    check_results();

    $finish;
  end

  // =========================================================================
  // Waveform dump
  // =========================================================================
  initial begin
    $dumpfile("hazards.vcd");
    $dumpvars(0, tb_hazards);
  end

  // =========================================================================
  // Debug: trace MUL/DIV signals
  // =========================================================================
  always @(posedge clk) begin
    if (u_dut.idex_is_muldiv || u_dut.muldiv_busy || u_dut.muldiv_done)
      $display("[MULDIV] t=%0t idex_is_muldiv=%0d muldiv_busy=%0d muldiv_done=%0d muldiv_stall=%0d ifid_stall=%0d ds_stall=%0d id_rs1=%0d id_rs2=%0d id_rd=%0d idex_rd=%0d muldiv_result=0x%08x muldiv_result_rd=%0d wb_we=%0d wb_waddr=%0d wb_wdata=0x%08x",
               $time, u_dut.idex_is_muldiv, u_dut.muldiv_busy, u_dut.muldiv_done,
               u_dut.muldiv_stall, u_dut.ifid_stall, u_dut.downstream_stall,
               u_dut.id_rs1, u_dut.id_rs2, u_dut.id_rd, u_dut.idex_rd,
               u_dut.muldiv_result, u_dut.muldiv_result_rd,
               u_dut.wb_we, u_dut.wb_waddr, u_dut.wb_wdata);
    if (u_dut.muldiv_stall)
      $display("[STL] t=%0t muldiv_stall=%0d ifid_stall=%0d pc_stall=%0d id_rs1=%0d id_rs2=%0d mul_rd=%0d mul_rd_valid=%0d",
               $time, u_dut.muldiv_stall, u_dut.ifid_stall, u_dut.pc_stall,
               u_dut.id_rs1, u_dut.id_rs2,
               u_dut.u_hazard.mul_rd, u_dut.u_hazard.mul_rd_valid);
  end

endmodule