`timescale 1ns / 1ps
// Exhaustive byte/halfword offset test for SB/SH + LB/LBU/LH/LHU/LW
// Tests every supported offset to verify MEM-stage alignment fixes.

module tb_load_store_offsets;
  import rv32i_pkg::*;

  logic clk;
  logic rst_n;
  localparam CLK_PERIOD = 10;
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  logic [XLEN-1:0]     dbg_pc;
  logic [31:0]         dbg_instr;
  logic                dbg_valid;
  logic [REG_ADDR-1:0] dbg_regfile_addr;
  logic [XLEN-1:0]     dbg_regfile_data;

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

  logic [31:0] reg_val [0:31];
  task automatic read_regfile(input [4:0] addr, output logic [31:0] val);
    dbg_regfile_addr = addr; #0; val = dbg_regfile_data;
  endtask

  function automatic logic [31:0] enc_r(input logic [6:0] f7, input logic [4:0] rs2, input logic [4:0] rs1, input logic [2:0] f3, input logic [4:0] rd, input logic [6:0] op);
    return {f7, rs2, rs1, f3, rd, op};
  endfunction
  function automatic logic [31:0] enc_i(input logic [11:0] imm, input logic [4:0] rs1, input logic [2:0] f3, input logic [4:0] rd, input logic [6:0] op);
    return {imm, rs1, f3, rd, op};
  endfunction
  function automatic logic [31:0] enc_s(input logic [11:0] imm, input logic [4:0] rs2, input logic [4:0] rs1, input logic [2:0] f3, input logic [6:0] op);
    return {imm[11:5], rs2, rs1, f3, imm[4:0], op};
  endfunction
  function automatic logic [31:0] enc_u(input logic [31:0] imm, input logic [4:0] rd, input logic [6:0] op);
    return {imm[31:12], rd, op};
  endfunction
  function automatic logic [31:0] enc_j(input logic [20:0] off, input logic [4:0] rd, input logic [6:0] op);
    logic [31:0] i;
    i[31]=off[20]; i[30:21]=off[10:1]; i[20]=off[11];
    i[19:12]=off[19:12]; i[11:7]=rd; i[6:0]=op;
    return i;
  endfunction

  localparam logic [31:0] NOP = 32'h0000_0013;

  int pass_count, fail_count;
  integer idx;

  task automatic check_reg(input string name, input logic [31:0] actual, input logic [31:0] expected);
    if (actual === expected) begin
      $display("  [PASS] %-40s = 0x%08h", name, actual); pass_count++;
    end else begin
      $display("  [FAIL] %-40s = 0x%08h (expected 0x%08h)", name, actual, expected); fail_count++;
    end
  endtask

  function automatic logic [31:0] read_dmem_word(input int byte_addr);
    return u_dut.u_data_mem.mem[byte_addr >> 2];
  endfunction

  task automatic fill_nops();
    for (int i = 0; i < 1024; i++) u_dut.u_instr_mem.mem[i] = NOP;
  endtask
  task automatic fill_dmem_zeros();
    for (int i = 0; i < 1024; i++) u_dut.u_data_mem.mem[i] = 32'h0;
  endtask

  task automatic run_to_halt(input int max_cycles);
    logic [31:0] prev_pc;
    int stable_cnt;
    prev_pc = 32'hFFFF_FFFF;
    stable_cnt = 0;
    for (int i = 0; i < max_cycles; i++) begin
      @(posedge clk);
      #1;
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

  // Program: exhaustive SB/SH/LB/LBU/LH/LHU at all offsets
  task automatic load_prog();
    idx = 0;
    $display("[TB] Loading exhaustive byte/halfword offset test");

    // x1 = 0x100 (aligned base)
    u_dut.u_instr_mem.mem[idx]=enc_i(12'h100, 5'd0,3'b000,5'd1, OPC_OP_IMM); idx++; // ADDI x1, x0, 0x100
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // Clear word at 0x100
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd2, OPC_OP_IMM); idx++; // x2=0
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd0, 5'd2,5'd1,3'b010,OPC_STORE); idx++; // SW x2,0(x1)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- SB at offsets 0..3 ----
    // SB 0xAA @ 0x100 (off0)
    u_dut.u_instr_mem.mem[idx]=enc_i(12'h0AA, 5'd0,3'b000,5'd2, OPC_OP_IMM); idx++;
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd0, 5'd2,5'd1,3'b000,OPC_STORE); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // SB 0xBB @ 0x101 (off1)
    u_dut.u_instr_mem.mem[idx]=enc_i(12'h0BB, 5'd0,3'b000,5'd2, OPC_OP_IMM); idx++;
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd1, 5'd2,5'd1,3'b000,OPC_STORE); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // SB 0xCC @ 0x102 (off2)
    u_dut.u_instr_mem.mem[idx]=enc_i(12'h0CC, 5'd0,3'b000,5'd2, OPC_OP_IMM); idx++;
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd2, 5'd2,5'd1,3'b000,OPC_STORE); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // SB 0xDD @ 0x103 (off3)
    u_dut.u_instr_mem.mem[idx]=enc_i(12'h0DD, 5'd0,3'b000,5'd2, OPC_OP_IMM); idx++;
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd3, 5'd2,5'd1,3'b000,OPC_STORE); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // Verify via LW x3 = mem[0x100]
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd1,3'b010,5'd3, OPC_LOAD); idx++; // LW x3,0(x1)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- LBU at each offset ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd1,3'b100,5'd4, OPC_LOAD); idx++; // LBU x4,0(x1) -> 0xAA
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd1, 5'd1,3'b100,5'd5, OPC_LOAD); idx++; // LBU x5,1(x1) -> 0xBB
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd2, 5'd1,3'b100,5'd6, OPC_LOAD); idx++; // LBU x6,2(x1) -> 0xCC
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd3, 5'd1,3'b100,5'd7, OPC_LOAD); idx++; // LBU x7,3(x1) -> 0xDD
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- LB (signed) at each offset ----
    // 0xAA = 10101010 -> negative, sign-extend 0xFFFFFFAA
    // 0x7F would be positive; use 0x80 for negative test later but here reuse same bytes
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd1,3'b000,5'd8, OPC_LOAD); idx++; // LB x8,0(x1) -> 0xFFFFFFAA
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd1, 5'd1,3'b000,5'd9, OPC_LOAD); idx++; // LB x9,1(x1) -> 0xFFFFFFBB
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd2, 5'd1,3'b000,5'd10, OPC_LOAD); idx++; // LB x10,2(x1) -> 0xFFFFFFCC
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd3, 5'd1,3'b000,5'd11, OPC_LOAD); idx++; // LB x11,3(x1) -> 0xFFFFFFDD
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- Prepare second word at 0x104 for halfword tests ----
    // Clear
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd2, OPC_OP_IMM); idx++;
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd4, 5'd2,5'd1,3'b010,OPC_STORE); idx++; // SW 0,4(x1) -> mem[0x104]=0
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // SH 0x1122 @ 0x104 (off0)
    u_dut.u_instr_mem.mem[idx]=enc_i(12'h122, 5'd0,3'b000,5'd2, OPC_OP_IMM); idx++; // need 0x1122 -> use LUI+ADDI? Simplify: ADDI 0x122 then LUI trick
    // Instead use: LUI x2, 0x1 -> 0x1000, then ADDI 0x122? That's 0x1122? 0x1000+0x122=0x1122 correct
    // So do LUI then ADDI
    // For brevity use immediate 0x122 + LUI hack: we already have ADDI 0x122 alone gives 0x122 not 0x1122. Let's do LUI+ADDI properly
    // Replace previous line: we will insert 2 insns
    // Undo last idx increment
    idx--; // overwrite
    u_dut.u_instr_mem.mem[idx]=enc_u(32'h00001000,5'd2,OPC_LUI); idx++; // LUI x2,0x1 -> 0x1000
    u_dut.u_instr_mem.mem[idx]=enc_i(12'h122, 5'd2,3'b000,5'd2, OPC_OP_IMM); idx++; // ADDI x2, x2, 0x122 -> 0x1122
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd4, 5'd2,5'd1,3'b001,OPC_STORE); idx++; // SH x2,4(x1) off0
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // SH 0x3344 @ 0x106 (off2)
    u_dut.u_instr_mem.mem[idx]=enc_u(32'h00003000,5'd2,OPC_LUI); idx++; // LUI x2,0x3 -> 0x3000
    u_dut.u_instr_mem.mem[idx]=enc_i(12'h344, 5'd2,3'b000,5'd2, OPC_OP_IMM); idx++; // ADDI -> 0x3344
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd6, 5'd2,5'd1,3'b001,OPC_STORE); idx++; // SH x2,6(x1) off2 (0x106 = 0x104+2)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // Verify word at 0x104 via LW x12
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd4, 5'd1,3'b010,5'd12, OPC_LOAD); idx++; // LW x12,4(x1) -> 0x33441122
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // LHU tests
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd4, 5'd1,3'b101,5'd13, OPC_LOAD); idx++; // LHU x13,4(x1) -> 0x1122
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd6, 5'd1,3'b101,5'd14, OPC_LOAD); idx++; // LHU x14,6(x1) -> 0x3344
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // LH (signed) tests
    // 0x1122 positive (0x1122 = 4386) -> 0x00001122
    // 0x3344 positive -> 0x00003344
    // Need negative halfword: use 0xFF80 -> sign extend 0xFFFFFF80
    // Let's store 0xFF80 at 0x108 for negative LH test
    u_dut.u_instr_mem.mem[idx]=enc_u(32'hFFFFF000,5'd2,OPC_LUI); idx++; // LUI x2,0xFFFFF -> 0xFFFFF000
    u_dut.u_instr_mem.mem[idx]=enc_i(12'hF80, 5'd2,3'b000,5'd2, OPC_OP_IMM); idx++; // ADDI -> 0xFFFFF80? Actually need 0xFFFFFF80: LUI 0xFFFFFF ->? Simplify: use 0x8000 negative?
    // Alternative: just use -1 halfword 0xFFFF already tested earlier. Let's reuse SH -1 at 0x108
    // Instead overwrite: SB/SH -1 test simpler
    // Clear word 0x108
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd15, OPC_OP_IMM); idx++; // x15=0
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd8, 5'd15,5'd1,3'b010,OPC_STORE); idx++; // SW 0,8(x1)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'hFFF, 5'd0,3'b000,5'd2, OPC_OP_IMM); idx++; // x2=-1 (0xFFF = -1 sign-extended? ADDI x2,x0,-1 -> 0xFFFF_FFFF)
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd8, 5'd2,5'd1,3'b001,OPC_STORE); idx++; // SH -1,8(x1) -> mem[0x108] low half 0xFFFF
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd8, 5'd1,3'b001,5'd15, OPC_LOAD); idx++; // LH x15,8(x1) -> 0xFFFFFFFF (sign)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd8, 5'd1,3'b101,5'd16, OPC_LOAD); idx++; // LHU x16,8(x1) -> 0x0000FFFF
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // LH signed at 0x104/0x106 should still be positive
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd4, 5'd1,3'b001,5'd17, OPC_LOAD); idx++; // LH x17,4(x1) -> 0x00001122
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd6, 5'd1,3'b001,5'd18, OPC_LOAD); idx++; // LH x18,6(x1) -> 0x00003344
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- SW/LW sanity (word) ----
    u_dut.u_instr_mem.mem[idx]=enc_u(32'h12345000,5'd2,OPC_LUI); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'h678, 5'd2,3'b000,5'd2, OPC_OP_IMM); idx++; // x2=0x12345678
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd12,5'd2,5'd1,3'b010,OPC_STORE); idx++; // SW x2,12(x1) -> mem[0x10C]
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd12,5'd1,3'b010,5'd19, OPC_LOAD); idx++; // LW x19,12(x1) -> 0x12345678
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ---- SB overwriting partial word test (ensure BE isolation) ----
    // Word at 0x10C is 0x12345678, SB 0xFF at 0x10D (off1) should become 0x1234FF78?
    // Actually little endian: addr 0x10C is byte0, 0x10D is byte1, etc.
    // 0x12345678 LE bytes: [78,56,34,12] at offsets 0..3
    // SB 0xFF @ offset1 should make bytes [78,FF,34,12] = 0x1234FF78
    u_dut.u_instr_mem.mem[idx]=enc_i(12'h0FF, 5'd0,3'b000,5'd2, OPC_OP_IMM); idx++;
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_s(12'd13,5'd2,5'd1,3'b000,OPC_STORE); idx++; // SB 0xFF,13(x1) = 0x10C+1
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd12,5'd1,3'b010,5'd20, OPC_LOAD); idx++; // LW x20,12(x1) -> 0x1234FF78
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // Halt
    u_dut.u_instr_mem.mem[idx] = enc_j(21'd0, 5'd0, OPC_JAL); idx++;
    $display("[TB] Offset test prog done: %0d words", idx);
  endtask

  task automatic check_prog();
    $display("");
    $display("========================================");
    $display("  OFFSET TEST: ALL LOAD/STORE TYPES");
    $display("========================================");
    for (int i = 0; i < 32; i++) read_regfile(i[4:0], reg_val[i]);

    // SB->LW word combine
    check_reg("x3  LW after 4xSB = 0xDDCCBBAA", reg_val[3], 32'hDDCCBBAA);
    check_reg("mem[0x100]=0xDDCCBBAA", read_dmem_word(32'h100), 32'hDDCCBBAA);

    // LBU
    check_reg("x4  LBU off0 = 0xAA", reg_val[4], 32'h000000AA);
    check_reg("x5  LBU off1 = 0xBB", reg_val[5], 32'h000000BB);
    check_reg("x6  LBU off2 = 0xCC", reg_val[6], 32'h000000CC);
    check_reg("x7  LBU off3 = 0xDD", reg_val[7], 32'h000000DD);

    // LB signed (0xAA etc are negative when bit7=1)
    check_reg("x8  LB off0 = 0xFFFFFFAA", reg_val[8], 32'hFFFFFFAA);
    check_reg("x9  LB off1 = 0xFFFFFFBB", reg_val[9], 32'hFFFFFFBB);
    check_reg("x10 LB off2 = 0xFFFFFFCC", reg_val[10], 32'hFFFFFFCC);
    check_reg("x11 LB off3 = 0xFFFFFFDD", reg_val[11], 32'hFFFFFFDD);

    // SH combine
    check_reg("x12 LW 0x104 = 0x33441122", reg_val[12], 32'h33441122);
    check_reg("mem[0x104]=0x33441122", read_dmem_word(32'h104), 32'h33441122);

    // LHU
    check_reg("x13 LHU off0 = 0x1122", reg_val[13], 32'h00001122);
    check_reg("x14 LHU off2 = 0x3344", reg_val[14], 32'h00003344);

    // LH signed negative -1
    check_reg("x15 LH -1 = 0xFFFFFFFF", reg_val[15], 32'hFFFFFFFF);
    check_reg("x16 LHU -1 = 0xFFFF", reg_val[16], 32'h0000FFFF);

    // LH positive
    check_reg("x17 LH 0x1122 pos", reg_val[17], 32'h00001122);
    check_reg("x18 LH 0x3344 pos", reg_val[18], 32'h00003344);

    // SW/LW
    check_reg("x19 LW SW 0x12345678", reg_val[19], 32'h12345678);
    check_reg("mem[0x10C]=0x1234FF78 after SB", read_dmem_word(32'h10C), 32'h1234FF78);
    check_reg("x20 LW after SB @off1 = 0x1234FF78", reg_val[20], 32'h1234FF78);
  endtask

  initial begin
    pass_count = 0; fail_count = 0;
    fill_nops();
    fill_dmem_zeros();
    load_prog();
    rst_n = 0; repeat(3) @(posedge clk); #1 rst_n = 1;
    run_to_halt(5000);
    check_prog();
    $display("");
    $display("========================================");
    $display("  OFFSET TOTAL: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("========================================");
    if (fail_count==0) $display("[SUCCESS] All byte/halfword offsets work!");
    else $display("[FAILURE] %0d checks failed", fail_count);
    #10; $finish;
  end

endmodule
