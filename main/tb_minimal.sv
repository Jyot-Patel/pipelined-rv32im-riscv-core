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
  logic [31:0] dbg_pc;
  logic [31:0] dbg_instr;
  logic        dbg_valid;

  soc_top #(
    .IMEM_DEPTH     (1024),
    .DMEM_DEPTH     (1024),
    .IMEM_INIT_FILE ("E:/RISCV_Minimal/program.hex"),
    .DMEM_INIT_FILE ("E:/RISCV_Minimal/data.hex")
  ) u_dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .dbg_pc           (dbg_pc),
    .dbg_instr        (dbg_instr),
    .dbg_valid        (dbg_valid),
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

  task showRegContent;
    automatic int i;
    automatic logic[31:0] temp;
    $display("//////////////Contents of Reg file /////////");
    for(i=0;i <32;i++)begin
      read_regfile(i,temp);
      $display("r%0d : %h",i,temp);
    end
    
  endtask
  // =========================================================================
  // Results checking
  // =========================================================================
  int pass_count;
  int fail_count;

//   task automatic check_reg(input string name, input logic [31:0] actual,
//                            input logic [31:0] expected);
//     if (actual === expected) begin
//       $display("[PASS] %0s = 0x%08h", name, actual);
//       pass_count++;
//     end else begin
//       $display("[FAIL] %0s = 0x%08h (expected 0x%08h)", name, actual, expected);
//       fail_count++;
//     end
//   endtask

  // =========================================================================
  // Test sequence
  // =========================================================================
  // Halt detection: wait for j halt (0x0000006f) with PC stable
  task automatic run_to_halt(input int max_cycles);
    logic [31:0] prev_pc = 32'hFFFFFFFF;
    int stable=0;
    for(int i=0;i<max_cycles;i++) begin
      @(posedge clk); #1;
      if(dbg_instr==32'h0000006f && dbg_pc==prev_pc) begin
        stable++; if(stable>=5) begin repeat(2)@(posedge clk); return; end
      end else begin prev_pc=dbg_pc; stable=0; end
    end
    $display("[TB] WARNING timeout PC=0x%08h instr=0x%08h after %0d cycles", dbg_pc, dbg_instr, max_cycles);
  endtask

  initial begin
    rst_n = 0;
    repeat (3) @(posedge clk);
    #1 rst_n = 1;

    // Was repeat(50) — insufficient for 32-cycle M-unit (needs ~8000 cycles for 22 M ops)
    run_to_halt(8000);
    
    showRegContent();

//     check_results();

    $finish;
  end

  // =========================================================================
  // Waveform dump
  // =========================================================================
//   initial begin
//     $dumpfile("soc_top.vcd");
//     $dumpvars(0, tb_soc_top);
//   end

endmodule