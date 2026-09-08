`timescale 1ns / 1ps
// =============================================================================
// Testbench: tb_soc_m_ext
// Target: soc_top (RV32IM) — M-extension focused verification
// Simulator: ModelSim Altera (vsim/vlog)
// Issue: "only 2 mul and mulh passes. for all other instructions register values is always 0000000"
// Root cause: tb_minimal used back-to-back M ops with only 50 cycles wait.
//   MUL/DIV iterative (32 cycles) needs ~200 cycles for 6 consecutive ops.
// Fix: isolated tests + enough cycles + halt detection
// Usage (ModelSim Altera):
//   vlib work; vmap work work
//   vlog -sv -work work soc_top.sv
//   vlog -sv -work work tb_soc_m_ext.sv
//   vsim -t 1ps -L work -voptargs="+acc" tb_soc_m_ext
//   add wave -position insertpoint sim:/tb_soc_m_ext/*
//   add wave -position insertpoint sim:/tb_soc_m_ext/u_dut/u_core/*
//   run -all
// =============================================================================

module tb_soc_m_ext;

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
    .IMEM_DEPTH     (1024),
    .DMEM_DEPTH     (1024),
    .IMEM_INIT_FILE (""),
    .DMEM_INIT_FILE ("")
  ) u_dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .dbg_pc           (dbg_pc),
    .dbg_instr        (dbg_instr),
    .dbg_valid        (dbg_valid),
    .dbg_regfile_addr (dbg_regfile_addr),
    .dbg_regfile_data (dbg_regfile_data)
  );

  logic [31:0] reg_val [0:31];
  task automatic read_regfile(input [4:0] addr, output logic [31:0] val);
    dbg_regfile_addr = addr; #1; val = dbg_regfile_data;
  endtask

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
  localparam logic [6:0] F7_M = 7'b0000001;

  int pass_count, fail_count;
  int idx;

  task automatic check_reg(input string name, input logic [31:0] actual, input logic [31:0] expected);
    if (actual === expected) begin
      $display("  [PASS] %-38s = 0x%08h", name, actual); pass_count++;
    end else begin
      $display("  [FAIL] %-38s = 0x%08h (expected 0x%08h)", name, actual, expected); fail_count++;
    end
  endtask

  task automatic fill_nops();
    for (int i=0;i<1024;i++) u_dut.u_instr_mem.mem[i]=NOP;
  endtask
  task automatic fill_dmem_zeros();
    for (int i=0;i<1024;i++) u_dut.u_data_mem.mem[i]='0;
  endtask

  task automatic run_to_halt(input int max_cycles);
    logic [31:0] prev_pc;
    int stable_cnt;
    prev_pc = 32'hFFFFFFFF;
    stable_cnt=0;
    for (int i=0;i<max_cycles;i++) begin
      @(posedge clk); #1;
      if (dbg_instr==32'h0000006F && dbg_pc==prev_pc) begin
        stable_cnt++;
        if (stable_cnt>=5) begin repeat(2) @(posedge clk); return; end
      end else begin prev_pc=dbg_pc; stable_cnt=0; end
    end
    $display("[TB] WARNING timeout PC=0x%08h instr=0x%08h after %0d cycles", dbg_pc, dbg_instr, max_cycles);
  endtask

  task automatic dump_regs();
    $display("------ Regfile dump ------");
    for (int i=0;i<32;i++) begin
      logic [31:0] v; read_regfile(i[4:0], v);
      $display("  x%0d = 0x%08h (%0d)", i, v, $signed(v));
    end
  endtask

  // =========================================================================
  // Program
  //   x1=10 x2=20 x3=-10 x4=-5 x5=7 x6=0 x9=-1 x10=0x80000000
  //   Phase A: isolated M ops (4 NOPs) -> preserves x20-x31
  //   Phase B: MUL->ADDI forwarding (0 NOP) -> x7=43
  //   Phase C: b2b MULs (0 NOP) -> x1=6 x2=20 (uses non-sacred regs)
  // =========================================================================
  task automatic load_program();
    idx=0;
    $display("[TB] Loading M-extension test program");

    // Setup constants
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd10,  5'd0,3'b000,5'd1, OPC_OP_IMM); idx++; // x1=10
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd20,  5'd0,3'b000,5'd2, OPC_OP_IMM); idx++; // x2=20
    u_dut.u_instr_mem.mem[idx]=enc_i(-12'd10, 5'd0,3'b000,5'd3, OPC_OP_IMM); idx++; // x3=-10
    u_dut.u_instr_mem.mem[idx]=enc_i(-12'd5,  5'd0,3'b000,5'd4, OPC_OP_IMM); idx++; // x4=-5
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd7,   5'd0,3'b000,5'd5, OPC_OP_IMM); idx++; // x5=7
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0,   5'd0,3'b000,5'd6, OPC_OP_IMM); idx++; // x6=0
    u_dut.u_instr_mem.mem[idx]=enc_i(-12'd1,  5'd0,3'b000,5'd9, OPC_OP_IMM); idx++; // x9=-1
    u_dut.u_instr_mem.mem[idx]=enc_u(32'h80000000,5'd10,OPC_LUI); idx++;            // x10=INT_MIN
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // Phase A isolated (4 NOPs)
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd2,5'd1,3'b000,5'd20,OPC_OP); idx++; // MUL x20 10*20=200
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd2,5'd3,3'b000,5'd21,OPC_OP); idx++; // MUL x21 -10*20=-200
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd2,5'd1,3'b001,5'd22,OPC_OP); idx++; // MULH x22 10*20=0
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd2,5'd3,3'b001,5'd23,OPC_OP); idx++; // MULH x23 -10*20=-1
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd10,5'd10,3'b001,5'd24,OPC_OP); idx++; // MULH x24 INT_MIN*INT_MIN=0x40000000
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd9,5'd1,3'b010,5'd25,OPC_OP); idx++; // MULHSU x25 10*0xFFFFFFFF=9
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd2,5'd3,3'b010,5'd26,OPC_OP); idx++; // MULHSU x26 -10*20=-1
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd2,5'd1,3'b011,5'd27,OPC_OP); idx++; // MULHU x27 10*20=0
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd9,5'd9,3'b011,5'd28,OPC_OP); idx++; // MULHU x28 FFFF*FFFF=FFFFFFFE
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd1,5'd2,3'b100,5'd29,OPC_OP); idx++; // DIV x29 20/10=2
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd4,5'd3,3'b100,5'd30,OPC_OP); idx++; // DIV x30 -10/-5=2
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd5,5'd3,3'b100,5'd31,OPC_OP); idx++; // DIV x31 -10/7=-1
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd5,5'd2,3'b101,5'd11,OPC_OP); idx++; // DIVU x11 20/7=2
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd1,5'd2,3'b110,5'd12,OPC_OP); idx++; // REM x12 20%10=0
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd5,5'd3,3'b110,5'd13,OPC_OP); idx++; // REM x13 -10%7=-3
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd5,5'd2,3'b111,5'd14,OPC_OP); idx++; // REMU x14 20%7=6
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd6,5'd1,3'b100,5'd15,OPC_OP); idx++; // DIV x15 10/0=-1
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd6,5'd2,3'b101,5'd16,OPC_OP); idx++; // DIVU x16 20/0=-1
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd6,5'd1,3'b110,5'd17,OPC_OP); idx++; // REM x17 10%0=10
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd6,5'd2,3'b111,5'd18,OPC_OP); idx++; // REMU x18 20%0=20
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd9,5'd10,3'b100,5'd19,OPC_OP); idx++; // DIV x19 INT_MIN/-1=INT_MIN
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd9,5'd10,3'b110,5'd8,OPC_OP); idx++; // REM x8 INT_MIN%-1=0
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // Phase B: MUL->ADDI forwarding (needs FWD_MULDIV)
    // Use x5=7 and x6=6 (x6 was 0, reprogram to 6)
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd6,5'd0,3'b000,5'd6,OPC_OP_IMM); idx++; // x6=6
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd5,5'd6,3'b000,5'd7,OPC_OP); idx++; // MUL x7=42
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd1,5'd7,3'b000,5'd7,OPC_OP_IMM); idx++; // ADDI x7=43 forward
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // Phase C: back-to-back MULs (0 NOP between) -> tests hazard stall
    // Repurpose non-sacred regs x1-x6 as sources, write to x1,x2 preserving Phase A x20-x31
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd2,5'd0,3'b000,5'd3,OPC_OP_IMM); idx++; // x3=2
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd3,5'd0,3'b000,5'd4,OPC_OP_IMM); idx++; // x4=3
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd4,5'd0,3'b000,5'd5,OPC_OP_IMM); idx++; // x5=4
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd5,5'd0,3'b000,5'd6,OPC_OP_IMM); idx++; // x6=5
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd4,5'd3,3'b000,5'd1,OPC_OP); idx++; // MUL x1=6 (2*3) b2b start
    u_dut.u_instr_mem.mem[idx]=enc_r(F7_M,5'd6,5'd5,3'b000,5'd2,OPC_OP); idx++; // MUL x2=20 (4*5) should stall until first done
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // Halt
    u_dut.u_instr_mem.mem[idx]=enc_j(21'd0,5'd0,OPC_JAL); idx++;
    $display("[TB] Program loaded %0d words", idx);
  endtask

  task automatic check_final();
    $display("");
    $display("========================================");
    $display("  M-EXTENSION FINAL CHECK");
    $display("========================================");
    for (int i=0;i<32;i++) read_regfile(i[4:0], reg_val[i]);

    // Phase A isolated
    check_reg("x20 MUL 10*20=200",        reg_val[20], 32'd200);
    check_reg("x21 MUL -10*20=-200",     reg_val[21], 32'hFFFFFF38);
    check_reg("x22 MULH 10*20=0",        reg_val[22], 32'h0);
    check_reg("x23 MULH -10*20=-1",      reg_val[23], 32'hFFFFFFFF);
    check_reg("x24 MULH INT_MIN*INT_MIN=0x40000000", reg_val[24], 32'h40000000);
    check_reg("x25 MULHSU 10*FFFF=9",    reg_val[25], 32'd9);
    check_reg("x26 MULHSU -10*20=-1",    reg_val[26], 32'hFFFFFFFF);
    check_reg("x27 MULHU 10*20=0",       reg_val[27], 32'h0);
    check_reg("x28 MULHU FFFF*FFFF=FFFFFFFE", reg_val[28], 32'hFFFFFFFE);
    check_reg("x29 DIV 20/10=2",         reg_val[29], 32'd2);
    check_reg("x30 DIV -10/-5=2",        reg_val[30], 32'd2);
    check_reg("x31 DIV -10/7=-1",        reg_val[31], 32'hFFFFFFFF);
    check_reg("x11 DIVU 20/7=2",         reg_val[11], 32'd2);
    check_reg("x12 REM 20%10=0",         reg_val[12], 32'd0);
    check_reg("x13 REM -10%7=-3",        reg_val[13], 32'hFFFFFFFD);
    check_reg("x14 REMU 20%7=6",         reg_val[14], 32'd6);
    check_reg("x15 DIV 10/0=-1",         reg_val[15], 32'hFFFFFFFF);
    check_reg("x16 DIVU 20/0=-1",        reg_val[16], 32'hFFFFFFFF);
    check_reg("x17 REM 10%0=10",         reg_val[17], 32'd10);
    check_reg("x18 REMU 20%0=20",        reg_val[18], 32'd20);
    check_reg("x19 DIV INT_MIN/-1=80000000", reg_val[19], 32'h80000000);
    check_reg("x8  REM INT_MIN%-1=0",    reg_val[8], 32'd0);
    check_reg("x9  -1",                  reg_val[9], 32'hFFFFFFFF);
    check_reg("x10 INT_MIN",             reg_val[10], 32'h80000000);
    // Phase B forwarding
    check_reg("x7  MUL->ADDI fwd 43",    reg_val[7], 32'd43);
    // Phase C b2b
    check_reg("x1  b2b MUL 2*3=6",       reg_val[1], 32'd6);
    check_reg("x2  b2b MUL 4*5=20",      reg_val[2], 32'd20);
  endtask

  initial begin
    $dumpfile("tb_soc_m_ext.vcd");
    $dumpvars(0, tb_soc_m_ext);
    pass_count=0; fail_count=0;
    fill_nops(); fill_dmem_zeros();
    load_program();
    rst_n=0; repeat(3) @(posedge clk); #1 rst_n=1;
    run_to_halt(8000);
    dump_regs();
    check_final();
    $display("");
    $display("========================================");
    $display("  TOTAL: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("========================================");
    if (fail_count==0) $display("[TB] ALL M-EXT TESTS PASSED");
    else $display("[TB] SOME TESTS FAILED - see waveform tb_soc_m_ext.vcd");
    $finish;
  end

endmodule
