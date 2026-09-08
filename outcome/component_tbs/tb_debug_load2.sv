`timescale 1ns/1ps
module tb_debug_load2;
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
  function automatic logic [31:0] enc_s(input logic [11:0] imm,input logic [4:0] rs2,input logic [4:0] rs1,input logic [2:0] f3,input logic [6:0] op);
    return {imm[11:5], rs2, rs1, f3, imm[4:0], op};
  endfunction
  function automatic logic [31:0] enc_j(input logic [20:0] off,input logic [4:0] rd,input logic [6:0] op);
    logic [31:0] i; i[31]=off[20]; i[30:21]=off[10:1]; i[20]=off[11]; i[19:12]=off[19:12]; i[11:7]=rd; i[6:0]=op; return i;
  endfunction
  localparam NOP=32'h00000013;
  initial begin
    for(int i=0;i<1024;i++) u_dut.u_instr_mem.mem[i]=NOP;
    for(int i=0;i<1024;i++) u_dut.u_data_mem.mem[i]=0;
    u_dut.u_instr_mem.mem[0]=enc_i(12'd42,5'd0,3'b000,5'd26,OPC_OP_IMM);
    u_dut.u_instr_mem.mem[1]=NOP;
    u_dut.u_instr_mem.mem[2]=NOP;
    u_dut.u_instr_mem.mem[3]=enc_s(12'd0,5'd26,5'd0,3'b010,OPC_STORE);
    u_dut.u_instr_mem.mem[4]=NOP; u_dut.u_instr_mem.mem[5]=NOP; u_dut.u_instr_mem.mem[6]=NOP; u_dut.u_instr_mem.mem[7]=NOP;
    u_dut.u_instr_mem.mem[8]=enc_i(12'd0,5'd0,3'b010,5'd19,OPC_LOAD);
    u_dut.u_instr_mem.mem[9]=enc_r(7'b0000000,5'd0,5'd19,3'b000,5'd22,OPC_OP);
    u_dut.u_instr_mem.mem[10]=NOP;u_dut.u_instr_mem.mem[11]=NOP;u_dut.u_instr_mem.mem[12]=NOP;u_dut.u_instr_mem.mem[13]=NOP;
    u_dut.u_instr_mem.mem[14]=enc_j(21'd0,5'd0,OPC_JAL);
    rst_n=0; repeat(3) @(posedge clk); #1 rst_n=1;
    for(int c=0;c<20;c++) begin
      @(posedge clk); #1;
      $display("C%0d pc_reg=0x%08h dbg_pc=0x%08h instr_addr=0x%08h rdata=0x%08h dbg_instr=0x%08h id_rs1=%0d id_rs2=%0d idex_rd=%0d", c, u_dut.u_core.pc_reg, dbg_pc, u_dut.u_core.instr_addr, u_dut.u_core.instr_rdata, dbg_instr, u_dut.u_core.id_rs1, u_dut.u_core.id_rs2, u_dut.u_core.idex_rd);
    end
    $finish;
  end
endmodule
