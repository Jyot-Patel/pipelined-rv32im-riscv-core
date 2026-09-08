`timescale 1ns / 1ps

module tb_soc_top;

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
  // DUT
  // =========================================================================
  logic [4:0]  dbg_regfile_addr;
  logic [31:0] dbg_regfile_data;

  soc_top #(
    .IMEM_DEPTH     (1024),
    .DMEM_DEPTH     (1024),
    .IMEM_INIT_FILE ("../../tb/hex/test_prog.hex"),
    .DMEM_INIT_FILE ("../../tb/hex/test_data.hex")
  ) u_dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .dbg_pc           (),
    .dbg_instr        (),
    .dbg_valid        (),
    .dbg_regfile_addr (dbg_regfile_addr),
    .dbg_regfile_data (dbg_regfile_data)
  );

  // =========================================================================
  // Debug port read helper
  // =========================================================================
  logic [31:0] reg_val [0:31];

  task automatic read_regfile(input [4:0] addr, output logic [31:0] val);
    dbg_regfile_addr = addr;
    #0;
    val = dbg_regfile_data;
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

    for (int i = 0; i < 32; i++) begin
      read_regfile(i[4:0], reg_val[i]);
    end

    $display("");
    $display("========================================");
    $display("  CHECKING REGISTER FILE STATE");
    $display("========================================");

    check_reg("x1  (ADDI 5)",          reg_val[1],  32'h0000_0005);
    check_reg("x2  (ADDI -3)",         reg_val[2],  32'hFFFF_FFFD);
    check_reg("x3  (ADD x1+x2)",       reg_val[3],  32'h0000_0002);
    check_reg("x4  (SUB x1-x2)",       reg_val[4],  32'h0000_0008);
    check_reg("x5  (AND x1&x2)",       reg_val[5],  32'h0000_0005);
    check_reg("x6  (OR x1|x2)",        reg_val[6],  32'hFFFF_FFFD);
    check_reg("x7  (XOR x1^x2)",       reg_val[7],  32'hFFFF_FFF8);
    check_reg("x8  (SLT -3<5)",        reg_val[8],  32'h0000_0001);
    check_reg("x9  (SLTU u(-3)>u(5))", reg_val[9],  32'h0000_0000);
    check_reg("x10 (SLL 5<<29)",       reg_val[10], 32'hA000_0000);
    check_reg("x11 (SRL 5>>29)",       reg_val[11], 32'h0000_0000);
    check_reg("x12 (ADDI -1)",         reg_val[12], 32'hFFFF_FFFF);
    check_reg("x13 (SRA -1>>>29)",     reg_val[13], 32'hFFFF_FFFF);
    check_reg("x14 (LUI 0xABCDE)",     reg_val[14], 32'hABCD_E000);
    $display("[INFO] x15 (AUIPC) = 0x%08h", reg_val[15]);
    check_reg("x16 (ADDI 42)",         reg_val[16], 32'h0000_002A);
    check_reg("x17 (LW from mem[0])",  reg_val[17], 32'h0000_002A);
    check_reg("x18 (ADDI 0xAB)",       reg_val[18], 32'h0000_00AB);
    check_reg("x19 (LB sign-ext)",     reg_val[19], 32'hFFFF_FFAB);
    check_reg("x20 (LBU zero-ext)",    reg_val[20], 32'h0000_00AB);
    check_reg("x21 (ADDI -1)",         reg_val[21], 32'hFFFF_FFFF);
    check_reg("x22 (LH sign-ext)",     reg_val[22], 32'hFFFF_FFFF);
    check_reg("x23 (LHU zero-ext)",    reg_val[23], 32'h0000_FFFF);
    check_reg("x24 (BEQ taken -> 42)", reg_val[24], 32'h0000_002A);
    check_reg("x25 (BEQ not-taken 77)",reg_val[25], 32'h0000_004D);
    check_reg("x26 (BNE taken -> 55)", reg_val[26], 32'h0000_0037);
    check_reg("x27 (BLT taken -> 33)", reg_val[27], 32'h0000_0021);
    check_reg("x28 (BGE taken -> 22)", reg_val[28], 32'h0000_0016);
    check_reg("x29 (BLTU not-taken 11)",reg_val[29],32'h0000_000B);
    check_reg("x30 (BGEU taken -> 88)",reg_val[30], 32'h0000_0058);
    $display("[INFO] x31 (JAL link) = 0x%08h", reg_val[31]);

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
    $dumpfile("soc_top.vcd");
    $dumpvars(0, tb_soc_top);
  end

endmodule