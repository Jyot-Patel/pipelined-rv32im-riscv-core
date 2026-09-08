`timescale 1ns / 1ps
// tb_soc_hex — verifies program.hex (generated from test.s) via $readmemh
// Uses standard encodings (funct7=0x01 for M). No hierarchical poke.
module tb_soc_hex;
  import rv32i_pkg::*;
  logic clk; logic rst_n;
  localparam CLK_PERIOD=10;
  initial clk=0;
  always #(CLK_PERIOD/2) clk=~clk;
  logic [4:0] dbg_regfile_addr;
  logic [31:0] dbg_regfile_data;
  logic [XLEN-1:0] dbg_pc; logic [31:0] dbg_instr; logic dbg_valid;

  soc_top #(
    .IMEM_DEPTH(1024),
    .DMEM_DEPTH(1024),
    .IMEM_INIT_FILE("E:/RISCV_Minimal/program.hex"),
    .DMEM_INIT_FILE("E:/RISCV_Minimal/data.hex")
  ) u_dut (
    .clk(clk), .rst_n(rst_n),
    .dbg_pc(dbg_pc), .dbg_instr(dbg_instr), .dbg_valid(dbg_valid),
    .dbg_regfile_addr(dbg_regfile_addr), .dbg_regfile_data(dbg_regfile_data)
  );

  task automatic read_regfile(input [4:0] a, output logic [31:0] v);
    dbg_regfile_addr=a; #1; v=dbg_regfile_data;
  endtask
  int pass_count, fail_count;
  task automatic check_reg(input string n, input logic [31:0] act, input logic [31:0] exp);
    if (act===exp) begin $display("  [PASS] %-30s = 0x%08h",n,act); pass_count++; end
    else begin $display("  [FAIL] %-30s = 0x%08h exp 0x%08h",n,act,exp); fail_count++; end
  endtask
  task automatic run_to_halt(input int max);
    logic [31:0] prev=32'hFFFFFFFF; int stable=0;
    for(int i=0;i<max;i++) begin @(posedge clk); #1;
      if(dbg_instr==32'h0000006f && dbg_pc==prev) begin stable++; if(stable>=5) begin repeat(2)@(posedge clk); return; end end
      else begin prev=dbg_pc; stable=0; end
    end
    $display("[TB] timeout PC=0x%08h",dbg_pc);
  endtask

  initial begin
    $dumpfile("tb_soc_hex.vcd"); $dumpvars(0,tb_soc_hex);
    pass_count=0; fail_count=0;
    rst_n=0; repeat(3)@(posedge clk); #1 rst_n=1;
    // program.hex has 142 words, need ~ 6000 cycles (32*22 M ops + NOPs)
    run_to_halt(8000);
    $display("=== program.hex (test.s) result via $readmemh ===");
    for(int i=0;i<32;i++) begin logic [31:0] v; read_regfile(i[4:0],v); $display("x%0d = 0x%08h",i,v); end
    // check expected (same as test.s comments)
    begin logic [31:0] v;
      read_regfile(10,v); check_reg("x10 MUL 10*20",v,32'd200);
      read_regfile(12,v); check_reg("x12 MULH 10*20",v,32'h0);
      read_regfile(13,v); check_reg("x13 MULH -10*20",v,32'hFFFFFFFF);
      read_regfile(15,v); check_reg("x15 MULHSU 10*FFFF",v,32'd9);
      read_regfile(18,v); check_reg("x18 MULHU FFFF*FFFF",v,32'hFFFFFFFE);
      read_regfile(19,v); check_reg("x19 DIV 20/10",v,32'd2);
      read_regfile(23,v); check_reg("x23 REM -10%7",v,32'hFFFFFFFD);
      read_regfile(29,v); check_reg("x29 DIV INT_MIN/-1",v,32'h80000000);
      read_regfile(31,v); check_reg("x31 MUL->ADDI 121",v,32'd121);
      read_regfile(8,v); check_reg("x8 b2b 2*3",v,32'd6);
      read_regfile(9,v); check_reg("x9 b2b 4*5",v,32'd20);
    end
    $display("TOTAL %0d PASS %0d FAIL",pass_count,fail_count);
    if(fail_count==0) $display("[TB] program.hex PASS");
    $finish;
  end
endmodule
