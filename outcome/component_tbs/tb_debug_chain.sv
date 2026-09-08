`timescale 1ns/1ps
module tb_debug_chain;
  import rv32i_pkg::*;
  logic clk; logic rst_n;
  initial clk=0; always #5 clk=~clk;
  logic [XLEN-1:0] dbg_pc; logic [31:0] dbg_instr; logic dbg_valid;
  logic [REG_ADDR-1:0] dbg_regfile_addr; logic [XLEN-1:0] dbg_regfile_data;
  soc_top #(.IMEM_DEPTH(1024),.DMEM_DEPTH(1024)) u_dut(.clk(clk),.rst_n(rst_n),.dbg_pc(dbg_pc),.dbg_instr(dbg_instr),.dbg_valid(dbg_valid),.dbg_regfile_addr(dbg_regfile_addr),.dbg_regfile_data(dbg_regfile_data));
  function automatic logic [31:0] enc_r(input logic [6:0] f7,input logic [4:0] rs2,input logic [4:0] rs1,input logic [2:0] f3,input logic [4:0] rd,input logic [6:0] op);
    return {f7, rs2, rs1, f3, rd, op};
  endfunction
  function automatic logic [31:0] enc_i(input logic [11:0] imm,input logic [4:0] rs1,input logic [2:0] f3,input logic [4:0] rd,input logic [6:0] op);
    return {imm, rs1, f3, rd, op};
  endfunction
  function automatic logic [31:0] enc_j(input logic [20:0] off,input logic [4:0] rd,input logic [6:0] op);
    logic [31:0] i; i[31]=off[20]; i[30:21]=off[10:1]; i[20]=off[11]; i[19:12]=off[19:12]; i[11:7]=rd; i[6:0]=op; return i;
  endfunction
  localparam NOP=32'h00000013;
  initial begin
    for(int i=0;i<1024;i++) u_dut.u_instr_mem.mem[i]=NOP;
    for(int i=0;i<1024;i++) u_dut.u_data_mem.mem[i]=0;
    // simple chain: x24=5, x25=x24, x26=x25
    u_dut.u_instr_mem.mem[0]=enc_i(12'd5,5'd0,3'b000,5'd24,OPC_OP_IMM);
    u_dut.u_instr_mem.mem[1]=enc_r(7'b0000000,5'd0,5'd24,3'b000,5'd25,OPC_OP);
    u_dut.u_instr_mem.mem[2]=enc_r(7'b0000000,5'd0,5'd25,3'b000,5'd26,OPC_OP);
    u_dut.u_instr_mem.mem[3]=enc_j(21'd0,5'd0,OPC_JAL);
    rst_n=0; repeat(3) @(posedge clk); #1 rst_n=1;
    // debug loop
    for(int c=0;c<30;c++) begin
      @(posedge clk); #1;
      $display("C%0d PC=0x%08h instr=0x%08h dbg_valid=%0b id_rs1=%0d id_rs2=%0d idex_rd=%0d idex_rs1=%0d idex_rs2=%0d exmem_rd=%0d fwdA=%0d fwdB=%0d alu_op_a=0x%08h alu_op_b=0x%08h ex_result=0x%08h",
        c, dbg_pc, dbg_instr, dbg_valid,
        u_dut.u_core.id_rs1, u_dut.u_core.id_rs2,
        u_dut.u_core.idex_rd, u_dut.u_core.idex_rs1, u_dut.u_core.idex_rs2,
        u_dut.u_core.exmem_rd,
        u_dut.u_core.forward_a_sel, u_dut.u_core.forward_b_sel,
        u_dut.u_core.ex_alu_op_a, u_dut.u_core.ex_alu_op_b,
        u_dut.u_core.ex_result);
      if(dbg_instr==32'h0000006F && c>10) begin
        // halt detected
        #10;
        // read regs
        dbg_regfile_addr=24; #1; $display("x24=0x%08h", dbg_regfile_data);
        dbg_regfile_addr=25; #1; $display("x25=0x%08h", dbg_regfile_data);
        dbg_regfile_addr=26; #1; $display("x26=0x%08h", dbg_regfile_data);
        $finish;
      end
    end
    $finish;
  end
endmodule
