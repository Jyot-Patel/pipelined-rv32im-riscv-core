`timescale 1ns / 1ps

module tb_muldiv;

  import rv32i_pkg::*;

  logic clk;
  logic rst_n;

  localparam CLK_PERIOD = 10;
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  logic [XLEN-1:0] instr_addr;
  logic [XLEN-1:0] instr_rdata;
  logic [XLEN-1:0] data_addr;
  logic [XLEN-1:0] data_wdata;
  logic [XLEN-1:0] data_rdata;
  logic            data_we;
  logic [3:0]      data_be;
  logic            data_re;

  localparam int unsigned IMEM_DEPTH = 1024;
  logic [31:0] imem [0:IMEM_DEPTH-1];

  assign instr_rdata = imem[instr_addr[31:2]];

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

  logic [31:0] regfile [0:31];
  always_comb begin
    for (int i = 0; i < 32; i++) begin
      if (i == 0)
        regfile[i] = 32'h0;
      else
        regfile[i] = u_dut.u_regfile.regs[i];
    end
  end

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

  function automatic logic [31:0] enc_mul(
    input logic [4:0] rs2, input logic [4:0] rs1, input logic [2:0] funct3, input logic [4:0] rd
  );
    return enc_r(7'b0000001, rs2, rs1, funct3, rd, OPC_OP);
  endfunction

  localparam logic [31:0] NOP = 32'h0000_0013;
  integer pc_idx;

  task automatic load_program();
    pc_idx = 0;

    // ======================================================================
    // Test 1: MUL basic - 10 * 20 = 200
    // ======================================================================
    imem[pc_idx] = enc_i(12'd10, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd20, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b000, 5'd10); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // MUL lower 32: 0x80000000 * 2 = 0x00000000
    imem[pc_idx] = enc_u(32'h80000000, 5'd1, OPC_LUI); pc_idx++;
    imem[pc_idx] = enc_i(12'd2, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b000, 5'd11); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Test 2: MULH - signed(0x80000000) * signed(0x80000000) = 0x40000000
    // ======================================================================
    imem[pc_idx] = enc_u(32'h80000000, 5'd1, OPC_LUI); pc_idx++;
    imem[pc_idx] = enc_u(32'h80000000, 5'd2, OPC_LUI); pc_idx++;
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b001, 5'd12); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // MULH small positive: 7 * 6 = 42 → MULH = 0
    imem[pc_idx] = enc_i(12'd7, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd6, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b001, 5'd13); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Test 3: MULHSU - signed(0x80000000) * unsigned(0x7FFFFFFF)
    //   = signed(-2^31) * unsigned(2^31-1)
    //   = -2^62 + 2^31 (upper 32 = 0xC0000000)
    // ======================================================================
    imem[pc_idx] = enc_u(32'h80000000, 5'd1, OPC_LUI); pc_idx++;
    imem[pc_idx] = enc_i(12'hFFF, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd0, 5'd2, 3'b001, 5'd2, OPC_OP_IMM); pc_idx++; // SLLI x2,x2,0 → x2 = 0xFFFFFFFF
    imem[pc_idx] = enc_i(12'd1, 5'd2, 3'b101, 5'd2, OPC_OP_IMM); pc_idx++; // SRLI x2,x2,1 → x2 = 0x7FFFFFFF
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b010, 5'd14); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Test 4: MULHU - unsigned(0x80000000) * unsigned(0x80000000)
    //   0x40000000_00000000 → upper = 0x40000000
    // ======================================================================
    imem[pc_idx] = enc_u(32'h80000000, 5'd1, OPC_LUI); pc_idx++;
    imem[pc_idx] = enc_u(32'h80000000, 5'd2, OPC_LUI); pc_idx++;
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b011, 5'd15); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // MULHU small: 5 * 5 = 25 → upper = 0
    imem[pc_idx] = enc_i(12'd5, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd5, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b011, 5'd16); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Test 5: DIV - 100 / 7 = 14
    // ======================================================================
    imem[pc_idx] = enc_i(12'd100, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd7, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b100, 5'd17); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Test 6: DIVU - 0x80000000 / 3 = 0x2AAAAAAA
    // ======================================================================
    imem[pc_idx] = enc_u(32'h80000000, 5'd1, OPC_LUI); pc_idx++;
    imem[pc_idx] = enc_i(12'd3, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b101, 5'd18); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Test 7: REM - 100 % 7 = 2
    // ======================================================================
    imem[pc_idx] = enc_i(12'd100, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd7, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b110, 5'd19); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Test 8: REMU - 0x80000000 % 3 = 2
    // ======================================================================
    imem[pc_idx] = enc_u(32'h80000000, 5'd1, OPC_LUI); pc_idx++;
    imem[pc_idx] = enc_i(12'd3, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b111, 5'd20); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Edge: DIV by zero - result = -1 = 0xFFFFFFFF
    // ======================================================================
    imem[pc_idx] = enc_i(12'd42, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b100, 5'd21); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Edge: DIVU by zero - result = 0xFFFFFFFF
    // ======================================================================
    imem[pc_idx] = enc_i(12'd42, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_mul(5'd0, 5'd1, 3'b101, 5'd22); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Edge: REM by zero - result = dividend unchanged
    // ======================================================================
    imem[pc_idx] = enc_i(12'd42, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_mul(5'd0, 5'd1, 3'b110, 5'd23); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Edge: REMU by zero - result = dividend unchanged
    // ======================================================================
    imem[pc_idx] = enc_u(32'h80000000, 5'd1, OPC_LUI); pc_idx++;
    imem[pc_idx] = enc_mul(5'd0, 5'd1, 3'b111, 5'd24); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Edge: DIV overflow - 0x80000000 / 0xFFFFFFFF = 0x80000000
    // ======================================================================
    imem[pc_idx] = enc_u(32'h80000000, 5'd1, OPC_LUI); pc_idx++;
    imem[pc_idx] = enc_i(12'hFFF, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b100, 5'd25); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Forwarding: MUL → ADDI (0 NOPs) - result forwarded from EX/MEM
    //   MUL x1=7, x2=6 → x3=42; ADDI x4,x3,1 → x4=43
    // ======================================================================
    imem[pc_idx] = enc_i(12'd7, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd6, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b000, 5'd3); pc_idx++;
    imem[pc_idx] = enc_i(12'd1, 5'd3, 3'b000, 5'd4, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Back-to-back: MUL → MUL (0 NOPs gap)
    //   MUL x1=2, x2=3 → x5=6
    //   MUL x1=4, x2=5 → x6=20
    // ======================================================================
    imem[pc_idx] = enc_i(12'd2, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd3, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd4, 5'd0, 3'b000, 5'd6, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd5, 5'd0, 3'b000, 5'd7, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b000, 5'd5); pc_idx++;
    imem[pc_idx] = enc_mul(5'd7, 5'd6, 3'b000, 5'd26); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Back-to-back: DIV → DIV (0 NOPs gap)
    // ======================================================================
    imem[pc_idx] = enc_i(12'd100, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd200, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd4,  5'd0, 3'b000, 5'd6, OPC_OP_IMM); pc_idx++;
    imem[pc_idx] = enc_i(12'd5,  5'd0, 3'b000, 5'd7, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end
    imem[pc_idx] = enc_mul(5'd2, 5'd1, 3'b100, 5'd27); pc_idx++;
    imem[pc_idx] = enc_mul(5'd7, 5'd6, 3'b100, 5'd28); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // ======================================================================
    // Branch → muldiv interaction: branch redirect + muldiv stall
    // ======================================================================
    imem[pc_idx] = enc_i(12'd0, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); pc_idx++; // x1=0
    imem[pc_idx] = enc_i(12'd1, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); pc_idx++; // x2=1
    // BNE x1,x2, +12: 0!=1 → taken
    imem[pc_idx] = {12'b0, 5'd2, 5'd1, 3'b001, 4'b0, 1'b1, 1'b0, 7'b1100011}; pc_idx++;
    imem[pc_idx] = NOP; pc_idx++; // flushed
    imem[pc_idx] = NOP; pc_idx++; // flushed
    // target:
    imem[pc_idx] = enc_i(12'd99, 5'd0, 3'b000, 5'd29, OPC_OP_IMM); pc_idx++;
    repeat (4) begin imem[pc_idx] = NOP; pc_idx++; end

    // Halt
    imem[pc_idx] = enc_j(21'd0, 5'd0, OPC_JAL); pc_idx++;

    $display("[TB] Muldiv program loaded: %0d instructions", pc_idx);
  endtask

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

  task automatic check_results();
    pass_count = 0;
    fail_count = 0;

    for (int i = 0; i < 32; i++) begin
      if (i == 0)
        regfile[i] = 32'h0;
      else
        regfile[i] = u_dut.u_regfile.regs[i];
    end

    $display("");
    $display("========================================");
    $display("  M-EXTENSION TEST RESULTS");
    $display("========================================");

    check_reg("x10 MUL 10*20",       regfile[10], 32'd200);
    check_reg("x11 MUL 0x8000*2 lo", regfile[11], 32'd0);
    check_reg("x12 MULH 0x8000*0x8000", regfile[12], 32'h40000000);
    check_reg("x13 MULH 7*6",        regfile[13], 32'd0);
    check_reg("x14 MULHSU 0x8000*0x7FFF", regfile[14], 32'hC0000000);
    check_reg("x15 MULHU 0x8000*0x8000", regfile[15], 32'h40000000);
    check_reg("x16 MULHU 5*5",       regfile[16], 32'd0);
    check_reg("x17 DIV 100/7",       regfile[17], 32'd14);
    check_reg("x18 DIVU 0x8000/3",   regfile[18], 32'h2AAAAAAA);
    check_reg("x19 REM 100%7",       regfile[19], 32'd2);
    check_reg("x20 REMU 0x8000%3",   regfile[20], 32'd2);
    check_reg("x21 DIV /0",          regfile[21], 32'hFFFFFFFF);
    check_reg("x22 DIVU /0",         regfile[22], 32'hFFFFFFFF);
    check_reg("x23 REM /0",          regfile[23], 32'd42);
    check_reg("x24 REMU /0",         regfile[24], 32'h80000000);
    check_reg("x25 DIV ovfl",        regfile[25], 32'h80000000);

    // Forwarding: MUL→ADDI
    check_reg("x4  MUL→ADDI fwd",    regfile[4],  32'd43);

    // Back-to-back MUL→MUL
    check_reg("x5  MUL 2*3",         regfile[5],  32'd6);
    check_reg("x26 MUL 4*5 (b2b)",   regfile[26], 32'd20);

    // Back-to-back DIV→DIV
    check_reg("x27 DIV 100/200",     regfile[27], 32'd0);
    check_reg("x28 DIV 4/5 (b2b)",   regfile[28], 32'd0);

    $display("");
    $display("========================================");
    $display("  RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("========================================");
    $display("");
  endtask

  initial begin
    for (int i = 0; i < IMEM_DEPTH; i++) imem[i] = NOP;
    for (int i = 0; i < DMEM_DEPTH*4; i++) dmem[i] = 8'h00;

    load_program();

    rst_n = 0;
    repeat (3) @(posedge clk);
    #1 rst_n = 1;

    repeat (3000) @(posedge clk);

    check_results();

    $finish;
  end

  initial begin
    $dumpfile("muldiv.vcd");
    $dumpvars(0, tb_muldiv);
  end

endmodule
