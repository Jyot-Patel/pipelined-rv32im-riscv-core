`timescale 1ns / 1ps

// ============================================================================
// tb_branch_predictor_minimal — copy of tb_branch_predictor for projectMinimal
// Single-file SoC: projectMinimal/soc_top_single.sv
// Fetches program from program.hex / data.hex (INIT_FILE) but also supports
// direct hierarchical load_program() for branch accuracy tests.
// Purpose: same as original — measures predicted==taken via EX sampling.
// See documents/branch_predictor_control.md Ch.5
// ============================================================================
module tb_branch_predictor_minimal;
  import rv32i_pkg::*;

  // --------------------------------------------------------------------------
  // Clock / Reset
  // --------------------------------------------------------------------------
  logic clk;
  logic rst_n;
  localparam CLK_PERIOD = 10;
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // --------------------------------------------------------------------------
  // SoC DUT (same instantiation as tb_soc_final)
  // --------------------------------------------------------------------------
  logic [XLEN-1:0]     dbg_pc;
  logic [31:0]         dbg_instr;
  logic                dbg_valid;
  logic [REG_ADDR-1:0] dbg_regfile_addr;
  logic [XLEN-1:0]     dbg_regfile_data;

  // In minimal project, SoC fetches from hex files (single-file init)
  // Hex files are pre-generated (program.hex/data.hex) and also match load_program()
  soc_top #(
    .IMEM_DEPTH    (1024),
    .DMEM_DEPTH    (1024),
    .IMEM_INIT_FILE ("E:/RISCV_Minimal/program.hex"),
    .DMEM_INIT_FILE ("E:/RISCV_Minimal/data.hex")
  ) u_dut (
    .clk             (clk),
    .rst_n           (rst_n),
    .dbg_pc          (dbg_pc),
    .dbg_instr       (dbg_instr),
    .dbg_valid       (dbg_valid),
    .dbg_regfile_addr(dbg_regfile_addr),
    .dbg_regfile_data(dbg_regfile_data)
  );

  // --------------------------------------------------------------------------
  // Helpers: regfile read + encoding (mirrors tb_soc_final)
  // --------------------------------------------------------------------------
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
  function automatic logic [31:0] enc_b(input logic [12:0] off, input logic [4:0] rs2, input logic [4:0] rs1, input logic [2:0] f3, input logic [6:0] op);
    logic [31:0] i; i[31]=off[12]; i[30:25]=off[10:5]; i[24:20]=rs2; i[19:15]=rs1; i[14:12]=f3; i[11:8]=off[4:1]; i[7]=off[11]; i[6:0]=op; return i;
  endfunction
  function automatic logic [31:0] enc_u(input logic [31:0] imm, input logic [4:0] rd, input logic [6:0] op);
    return {imm[31:12], rd, op};
  endfunction
  function automatic logic [31:0] enc_j(input logic [20:0] off, input logic [4:0] rd, input logic [6:0] op);
    logic [31:0] i; i[31]=off[20]; i[30:21]=off[10:1]; i[20]=off[11]; i[19:12]=off[19:12]; i[11:7]=rd; i[6:0]=op; return i;
  endfunction
  localparam logic [31:0] NOP = 32'h0000_0013;

  // --------------------------------------------------------------------------
  // Accuracy bookkeeping — sampled at EX
  // --------------------------------------------------------------------------
  int total_branches;
  int correct_cnt;
  int mispredict_cnt;
  int taken_cnt;
  int not_taken_cnt;
  int tb_mismatch; // TB logic vs DUT ex_bp_mispredict divergence
  // per-type
  int beq_total, beq_correct;
  int bne_total, bne_correct;
  int blt_total, blt_correct;
  int bge_total, bge_correct;
  int bltu_total, bltu_correct;
  int bgeu_total, bgeu_correct;
  int jal_total, jal_correct;
  int jalr_total, jalr_correct;

  // log buffer
  int log_idx;

  task automatic reset_counters();
    total_branches=0; correct_cnt=0; mispredict_cnt=0; taken_cnt=0;
    not_taken_cnt=0; tb_mismatch=0;
    beq_total=0; beq_correct=0; bne_total=0; bne_correct=0;
    blt_total=0; blt_correct=0; bge_total=0; bge_correct=0;
    bltu_total=0; bltu_correct=0; bgeu_total=0; bgeu_correct=0;
    jal_total=0; jal_correct=0; jalr_total=0; jalr_correct=0;
    log_idx=0;
  endtask

  // sampled each cycle — see monitor always @(posedge clk) below
  // helper to classify
  function automatic string branch_name(input logic [2:0] f3, input logic br, input logic j, input logic jr);
    if (j) return "JAL";
    if (jr) return "JALR";
    if (!br) return "UNKNOWN";
    case (f3)
      3'b000: return "BEQ";
      3'b001: return "BNE";
      3'b100: return "BLT";
      3'b101: return "BGE";
      3'b110: return "BLTU";
      3'b111: return "BGEU";
      default: return "BR?";
    endcase
  endfunction

  // --------------------------------------------------------------------------
  // Monitor: every EX branch/jump compare predicted vs actual
  // Implements documents/branch_predictor_control.md Ch.5.2
  // --------------------------------------------------------------------------
  // Use hierarchical refs into single-file core (soc_top_single.sv:u_core)
  always @(posedge clk) begin
    if (rst_n) begin
      // sample one delta after combinational settles
      #1;
      if (u_dut.u_core.ex_is_branch_jump) begin
        logic        pred_taken;
        logic [31:0] pred_target;
        logic        actual_taken;
        logic [31:0] actual_target;
        logic        dut_mispredict;
        logic        tb_correct;
        logic [31:0] branch_pc;
        logic        is_br, is_j, is_jr;
        logic [2:0]  f3;

        pred_taken     = u_dut.u_core.idex_pred_taken;
        pred_target    = u_dut.u_core.idex_pred_target;
        actual_taken   = u_dut.u_core.ex_branch_taken;
        actual_target  = u_dut.u_core.ex_jump_target;
        dut_mispredict = u_dut.u_core.ex_bp_mispredict;
        branch_pc      = u_dut.u_core.idex_pc4 - 32'd4;
        is_br          = u_dut.u_core.idex_branch;
        is_j           = u_dut.u_core.idex_jump;
        is_jr          = u_dut.u_core.idex_jump_reg;
        f3             = u_dut.u_core.idex_mem_funct3;

        // TB independent correctness: direction equal && (not taken or target equal)
        if (is_j || is_jr) begin
          tb_correct = pred_taken && (pred_target == actual_target);
        end else begin
          if (pred_taken != actual_taken) tb_correct = 1'b0;
          else if (pred_taken && actual_taken && pred_target != actual_target) tb_correct = 1'b0;
          else tb_correct = 1'b1;
        end

        if (tb_correct != !dut_mispredict) begin
          tb_mismatch++;
          $display("[BP_MON][MISMATCH] PC=0x%08h pred_t=%0b pred_ta=0x%08h act_t=%0b act_ta=0x%08h dut_misp=%0b tb_correct=%0b",
                   branch_pc, pred_taken, pred_target, actual_taken, actual_target, dut_mispredict, tb_correct);
        end

        total_branches++;
        if (actual_taken) taken_cnt++; else not_taken_cnt++;
        if (tb_correct) correct_cnt++; else mispredict_cnt++;

        // per-type
        if (is_j) begin jal_total++; if (tb_correct) jal_correct++; end
        else if (is_jr) begin jalr_total++; if (tb_correct) jalr_correct++; end
        else if (is_br) case (f3)
          3'b000: begin beq_total++;  if (tb_correct) beq_correct++;  end
          3'b001: begin bne_total++;  if (tb_correct) bne_correct++;  end
          3'b100: begin blt_total++;  if (tb_correct) blt_correct++;  end
          3'b101: begin bge_total++;  if (tb_correct) bge_correct++;  end
          3'b110: begin bltu_total++; if (tb_correct) bltu_correct++; end
          3'b111: begin bgeu_total++; if (tb_correct) bgeu_correct++; end
        endcase

        $display("[BP_ACC] #%0d PC=0x%08h %-4s pred={%0b,0x%08h} actual={%0b,0x%08h} -> %s (DUT %s)",
                 total_branches, branch_pc, branch_name(f3,is_br,is_j,is_jr),
                 pred_taken, pred_target, actual_taken, actual_target,
                 tb_correct ? "CORRECT" : "MISPREDICT",
                 dut_mispredict ? "MISP" : "COR");
        log_idx++;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Memory helpers
  // --------------------------------------------------------------------------
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
      @(posedge clk); #1;
      if (dbg_instr == 32'h0000006F && dbg_pc == prev_pc) begin
        stable_cnt++;
        if (stable_cnt >= 5) begin repeat(2) @(posedge clk); return; end
      end else begin prev_pc = dbg_pc; stable_cnt = 0; end
    end
    $display("[TB] WARNING timeout PC=0x%08h after %0d cycles", dbg_pc, max_cycles);
  endtask

  // --------------------------------------------------------------------------
  // Program loader — exclusively branch predictor coverage
  // --------------------------------------------------------------------------
  int idx;
  // keep PC for patching
  int loop_start_idx;
  int loop_branch_idx;
  int jal_patch_idx;

  task automatic load_program();
    idx = 0;
    $display("[TB] Loading branch predictor accuracy program");

    // ---- init regs used as branch operands ----
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd10, 5'd0,3'b000,5'd1, OPC_OP_IMM); idx++; // x1=10
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd20, 5'd0,3'b000,5'd2, OPC_OP_IMM); idx++; // x2=20
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd5,  5'd0,3'b000,5'd3, OPC_OP_IMM); idx++; // x3=5
    u_dut.u_instr_mem.mem[idx]=enc_i(12'hFFF,5'd0,3'b000,5'd4, OPC_OP_IMM); idx++; // x4=-1 (0xFFF sign)
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ======================================================================
    // PHASE A: isolated direction coverage (cold)
    // Each taken branch cold -> mispredict (BHT 01, BTB invalid -> pred NT)
    // Each not-taken cold -> correct (pred NT matches)
    // ======================================================================
    // BEQ not-taken: 10 !=20 -> NT, expect CORRECT (pred NT)
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd2,5'd1,3'b000,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd42,5'd0,3'b000,5'd10,OPC_OP_IMM); idx++; // x10=42 fallthrough correct
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    // BEQ taken: x1==x1 -> T, expect MISPREDICT cold, target x10=55
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd1,5'd1,3'b000,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd10,OPC_OP_IMM); idx++; // flushed
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd55,5'd0,3'b000,5'd10,OPC_OP_IMM); idx++; // target
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // BNE taken: 10!=20 -> T MISPREDICT
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd2,5'd1,3'b001,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd11,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd66,5'd0,3'b000,5'd11,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    // BNE not-taken: x1==x1 -> NT CORRECT
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd1,5'd1,3'b001,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd77,5'd0,3'b000,5'd11,OPC_OP_IMM); idx++; // fallthrough overwrites to 77 but NT means executed
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // BLT taken: 10 <20 -> T
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd2,5'd1,3'b100,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd12,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd88,5'd0,3'b000,5'd12,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    // BLT not-taken: 20 <10 false -> NT
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd1,5'd2,3'b100,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd99,5'd0,3'b000,5'd12,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // BGE taken: 20 >=10 -> T (rs1=x2=20, rs2=x1=10)
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd1,5'd2,3'b101,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd13,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd110,5'd0,3'b000,5'd13,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    // BGE not-taken: 10 >=20 false (rs1=x1=10, rs2=x2=20)
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd2,5'd1,3'b101,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd99,5'd0,3'b000,5'd13,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    // BLTU taken: 10 <20 unsigned -> T
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd2,5'd1,3'b110,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd14,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd120,5'd0,3'b000,5'd14,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    // BLTU not-taken: 20 <10 false
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd1,5'd2,3'b110,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd130,5'd0,3'b000,5'd14,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    // BGEU taken: 20 >=10 -> T
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd1,5'd2,3'b111,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0, 5'd0,3'b000,5'd15,OPC_OP_IMM); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd140,5'd0,3'b000,5'd15,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    // BGEU not-taken: 10>=20 false
    u_dut.u_instr_mem.mem[idx]=enc_b(13'd8,5'd2,5'd1,3'b111,OPC_BRANCH); idx++;
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd150,5'd0,3'b000,5'd15,OPC_OP_IMM); idx++;
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end

    // ======================================================================
    // PHASE B: JAL / JALR — always taken, cold miss then BTB training
    // ======================================================================
    // JAL cold taken -> mispredict, second execution later will be correct
    u_dut.u_instr_mem.mem[idx]=enc_j(21'd8,5'd16,OPC_JAL); idx++; // JAL x16,+8
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd0,5'd0,3'b000,5'd16,OPC_OP_IMM); idx++; // flushed
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd77,5'd0,3'b000,5'd17,OPC_OP_IMM); idx++; // target: x17=77
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    // JALR cold taken
    begin
      int jalr_tgt = (idx+5)*4;
      u_dut.u_instr_mem.mem[idx]=enc_i(jalr_tgt[11:0],5'd0,3'b000,5'd18,OPC_OP_IMM); idx++; // x18=target
      repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd0,5'd18,3'b000,5'd19,OPC_JALR); idx++; // JALR x19,x18,0
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd88,5'd0,3'b000,5'd19,OPC_OP_IMM); idx++; // flushed
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd88,5'd0,3'b000,5'd20,OPC_OP_IMM); idx++; // target x20=88
      repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    end

    // ======================================================================
    // PHASE C: Loop — BHT hysteresis demo (5 iterations, same PC repeats)
    // Decrement loop: x5=5 down to 0, BEQ exit when zero
    // Expect: BEQ not-taken 4x (pred NT correct), taken 1x (mispredict then correct after training)
    //         JAL back-edge taken 4x (first mispredict, rest correct)
    // ======================================================================
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd5,5'd0,3'b000,5'd5, OPC_OP_IMM); idx++; // x5=5 counter
    repeat(2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    loop_start_idx = idx;
    loop_branch_idx = idx;
    u_dut.u_instr_mem.mem[idx]=NOP; idx++; // BEQ placeholder (patched below)
    u_dut.u_instr_mem.mem[idx]=enc_i(-12'd1,5'd5,3'b000,5'd5, OPC_OP_IMM); idx++; // x5--
    // JAL back to loop_start (unconditional)
    begin
      int off = loop_start_idx*4 - idx*4;
      u_dut.u_instr_mem.mem[idx]=enc_j(off[20:0],5'd0,OPC_JAL); idx++;
    end
    // exit:
    u_dut.u_instr_mem.mem[idx]=enc_i(12'd99,5'd0,3'b000,5'd21,OPC_OP_IMM); idx++; // x21=99 indicates exit
    repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    // patch BEQ x5,x0, exit (target = exit idx-? compute)
    begin
      int exit_idx = idx -5; // exit ADDI x21 is at idx-5 (see above)
      int off = exit_idx*4 - loop_branch_idx*4;
      u_dut.u_instr_mem.mem[loop_branch_idx]=enc_b(off[12:0],5'd0,5'd5,3'b000,OPC_BRANCH); // BEQ x5,x0, exit
    end

    // ======================================================================
    // PHASE D: BTB aliasing — same PC[7:2] index, different tag
    // First branch at PC_A taken cold -> BTB alloc tag 0
    // Second branch at PC_B = PC_A+256 (same idx, tag 1) -> cold miss again (different tag), proves tag checks
    // Replicates hazards tb alias but for accuracy counting
    // ======================================================================
    // ensure alignment: pad to next 64-word boundary? simpler: record PC_A_idx
    begin
      int pcA_idx;
      int pcB_idx;
      pcA_idx = idx;
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd0,5'd0,3'b000,5'd22,OPC_OP_IMM); idx++; // x22=0
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd1,5'd0,3'b000,5'd23,OPC_OP_IMM); idx++; // x23=1
      u_dut.u_instr_mem.mem[idx]=enc_b(13'd16,5'd23,5'd22,3'b001,OPC_BRANCH); idx++; // BNE taken -> target after 2 flushed
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd0,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++;
      u_dut.u_instr_mem.mem[idx]=NOP; idx++;
      u_dut.u_instr_mem.mem[idx]=NOP; idx++;
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd111,5'd0,3'b000,5'd24,OPC_OP_IMM); idx++; // target x24=111
      // pad to same idx: need PC_B = PC_A+256 = +64 words
      // PC_A branch is at pcA_idx+2 (BNE), so pcA branch addr = (pcA_idx+2)*4
      // Want pcB branch addr = pcA branch addr +256 => pcB branch idx = pcA_idx+2 +64
      // Currently idx after target = pcA_idx+7, need to pad to pcB_idx
      pcB_idx = pcA_idx + 2 + 64;
      while (idx < pcB_idx -2) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
      // place second aliased branch
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd0,5'd0,3'b000,5'd25,OPC_OP_IMM); idx++; // x25=0
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd1,5'd0,3'b000,5'd26,OPC_OP_IMM); idx++; // x26=1
      u_dut.u_instr_mem.mem[idx]=enc_b(13'd16,5'd26,5'd25,3'b001,OPC_BRANCH); idx++; // same idx, different tag, taken -> also cold miss if tag works
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd0,5'd0,3'b000,5'd27,OPC_OP_IMM); idx++;
      u_dut.u_instr_mem.mem[idx]=NOP; idx++;
      u_dut.u_instr_mem.mem[idx]=NOP; idx++;
      u_dut.u_instr_mem.mem[idx]=enc_i(12'd222,5'd0,3'b000,5'd27,OPC_OP_IMM); idx++; // target x27=222
      repeat(4) begin u_dut.u_instr_mem.mem[idx]=NOP; idx++; end
    end

    // ======================================================================
    // PHASE E: Repeat JAL at same PC as earlier to demonstrate BTB hit
    // Need same PC value again -> create loop with jump back to earlier JAL PC
    // Simpler: place a second JAL at same PC offset via unconditional jump back
    // We'll just place a second JAL instruction at a new PC but same PC[7:2] as first JAL to show BTB reuse
    // Actually to show hit, we need same PC address executed twice. Create small jump-back loop:
    // JAL at PC_JAL1 was taken once; now we J back to it and execute again -> second time should be CORRECT
    // ======================================================================
    // At this point idx is after alias test. Insert jump back to first JAL's PC? That PC is earlier ~ 40 words ago, far. Instead we reuse loop construct:
    // simpler: place two consecutive JALs at same index alias (like alias test) to show second predicts correctly because BTB still valid with same tag? That would be destructive not correct.
    // So we implement explicit re-execution via JALR loop: after alias, JAL to first JAL's address
    // Find first JAL idx was ~  after PHASE A; we can hardcode approximate: but easier is to create a dedicated tight loop at the end with its own training:
    // Phase E removed for finite halt — retraining demo already covered by alias and loop phases
    // Direct halt after alias phase to keep total branches finite and accuracy meaningful
    u_dut.u_instr_mem.mem[idx]=enc_j(21'd0,5'd0,OPC_JAL); idx++; // halt self-loop

    // final halt (in case earlier halt not reached, this is absolute)
    // Place explicit self-loop at end (will be reached if loop not perpetual) — our loop above is infinite, so run_to_halt will timeout.
    // Add timeout-friendly halt: we will run with max_cycles 3000 and check counters regardless
    $display("[TB] Program loaded %0d words, loop_start=%0d branch=%0d", idx, loop_start_idx, loop_branch_idx);
  endtask

  task automatic check_results();
    $display("");
    $display("==================================================");
    $display("  BRANCH PREDICTOR ACCURACY RESULTS");
    $display("==================================================");
    $display("  Total branches   : %0d", total_branches);
    $display("  Taken            : %0d", taken_cnt);
    $display("  Not-taken        : %0d", not_taken_cnt);
    $display("  Correct          : %0d", correct_cnt);
    $display("  Mispredict       : %0d", mispredict_cnt);
    if (total_branches != 0)
      $display("  Accuracy         : %0.2f %%", 100.0*correct_cnt/total_branches);
    $display("  TB/DUT mismatch  : %0d (should be 0)", tb_mismatch);
    $display("--------------------------------------------------");
    $display("  BEQ  : %0d/%0d correct", beq_correct, beq_total);
    $display("  BNE  : %0d/%0d correct", bne_correct, bne_total);
    $display("  BLT  : %0d/%0d correct", blt_correct, blt_total);
    $display("  BGE  : %0d/%0d correct", bge_correct, bge_total);
    $display("  BLTU : %0d/%0d correct", bltu_correct, bltu_total);
    $display("  BGEU : %0d/%0d correct", bgeu_correct, bgeu_total);
    $display("  JAL  : %0d/%0d correct", jal_correct, jal_total);
    $display("  JALR : %0d/%0d correct", jalr_correct, jalr_total);
    $display("==================================================");
    for (int i = 0; i < 32; i++) read_regfile(i[4:0], reg_val[i]);
    $display("  Reg snapshot: x5(counter)=%0d x6(limit)=%0d x21=%0d x24(alias1)=%0d x27(alias2)=%0d x29(loop_marker)=%0d",
             reg_val[5], reg_val[6], reg_val[21], reg_val[24], reg_val[27], reg_val[29]);
    $display("");
    if (tb_mismatch != 0) $display("[FAIL] TB/DUT mismatch %0d", tb_mismatch);
    else $display("[PASS] TB prediction logic matches DUT ex_bp_mispredict");
    if (total_branches < 15) $display("[WARN] low branch count, check program");
    if (correct_cnt==total_branches) $display("[NOTE] 100%% accuracy unexpected — check cold misses");
    $display("");
  endtask

  // --------------------------------------------------------------------------
  // Main
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("E:/RISCV_Minimal/branch_predictor_minimal.vcd");
    $dumpvars(0, tb_branch_predictor_minimal);
    reset_counters();
    // Minimal project: SoC already preloaded from program.hex/data.hex.
    // Overwrite with same program via hierarchical poke to keep accuracy test
    // deterministic (hex and poke contain identical program). Comment out
    // these three lines to test pure hex-fetch mode (also passes).
    fill_nops();
    fill_dmem_zeros();
    load_program();
    $display("[TB_MINIMAL_BP] soc_top_single fetch from hex + poke - 4000 cycles");
    rst_n = 0; repeat(3) @(posedge clk); #1 rst_n = 1;
    run_to_halt(4000);
    check_results();
    $display("[TB_MINIMAL_BP] done - to test pure hex mode, comment fill/load and re-run");
    #10;
    $finish;
  end

endmodule
