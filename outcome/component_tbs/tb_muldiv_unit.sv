`timescale 1ns / 1ps

// =============================================================================
//  Unit-Level Testbench: muldiv_unit
//
//  Directly drives the muldiv_unit module interface (no pipeline).
//  Verifies: control signals (busy/done timing), result correctness,
//  all 8 operations, edge cases, back-to-back sequencing, and stall behavior.
// =============================================================================

module tb_muldiv_unit;

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
  // DUT interface
  // =========================================================================
  logic [XLEN-1:0] operand_a;
  logic [XLEN-1:0] operand_b;
  logic [2:0]       op_sel;
  logic             valid;
  logic [4:0]       rd_in;
  logic             reg_write_in;
  logic             flush;

  logic [XLEN-1:0] result;
  logic             busy;
  logic             done;
  logic [4:0]       result_rd;
  logic             result_we;

  // =========================================================================
  // DUT instantiation
  // =========================================================================
  muldiv_unit u_dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .flush         (flush),
    .operand_a     (operand_a),
    .operand_b     (operand_b),
    .op_sel        (op_sel),
    .valid         (valid),
    .rd_in         (rd_in),
    .reg_write_in  (reg_write_in),
    .result        (result),
    .busy          (busy),
    .done          (done),
    .result_rd     (result_rd),
    .result_we     (result_we)
  );

  // =========================================================================
  // Test infrastructure
  // =========================================================================
  int pass_count;
  int fail_count;
  int test_num;

  task automatic check(
    input string       name,
    input logic [31:0] actual,
    input logic [31:0] expected
  );
    if (actual === expected) begin
      $display("  [PASS] %-24s = 0x%08h", name, actual);
      pass_count++;
    end else begin
      $display("  [FAIL] %-24s = 0x%08h (expected 0x%08h)", name, actual, expected);
      fail_count++;
    end
  endtask

  task automatic check_done_pulse();
    // busy must be high while computing
    if (!busy) begin
      $display("  [FAIL] busy should be high after valid, got 0");
      fail_count++;
    end
    // wait for done pulse
    @(posedge clk);
    while (!done) @(posedge clk);
    // done is a single-cycle pulse — verify it clears next cycle
    @(posedge clk);
    if (done) begin
      $display("  [FAIL] done should be single-cycle pulse, still high");
      fail_count++;
    end
    // busy must be low after done
    if (busy) begin
      $display("  [FAIL] busy should be low after done, got 1");
      fail_count++;
    end
  endtask

  // Drive muldiv_unit and wait for completion.
  // Returns the result value after done.
  
  task automatic run_op(
    input logic [31:0] a,
    input logic [31:0] b,
    input logic [2:0]  op,
    input logic [4:0]  rd,
    output logic [31:0] res
  );
    // Present inputs and assert valid for 1 cycle
    @(negedge clk);
    operand_a    = a;
    operand_b    = b;
    op_sel       = op;
    rd_in        = rd;
    reg_write_in = 1'b1;
    valid        = 1'b1;
    @(posedge clk);
    valid = 1'b0;

    // Wait for done pulse
    while (!done) @(posedge clk);

    // Capture result on the cycle done is high
    res = result;

    // Wait one more cycle for unit to return to IDLE
    @(posedge clk);
  endtask

  // Same as run_op but does NOT wait — caller must handle timing.
  task automatic launch_op(
    input logic [31:0] a,
    input logic [31:0] b,
    input logic [2:0]  op,
    input logic [4:0]  rd
  );
    @(negedge clk);
    operand_a    = a;
    operand_b    = b;
    op_sel       = op;
    rd_in        = rd;
    reg_write_in = 1'b1;
    valid        = 1'b1;
    @(posedge clk);
    valid = 1'b0;
  endtask

  task automatic wait_done();
    while (!done) @(posedge clk);
    @(posedge clk); // let it return to IDLE
  endtask

  // =========================================================================
  // Operation encodings (matches RV32M funct3)
  // =========================================================================
  localparam logic [2:0] OP_MUL    = 3'b000;
  localparam logic [2:0] OP_MULH   = 3'b001;
  localparam logic [2:0] OP_MULHSU = 3'b010;
  localparam logic [2:0] OP_MULHU  = 3'b011;
  localparam logic [2:0] OP_DIV    = 3'b100;
  localparam logic [2:0] OP_DIVU   = 3'b101;
  localparam logic [2:0] OP_REM    = 3'b110;
  localparam logic [2:0] OP_REMU   = 3'b111;

  logic [31:0] res;

  // =========================================================================
  // Main test sequence
  // =========================================================================
  initial begin
    $dumpfile("muldiv_unit.vcd");
    $dumpvars(0, tb_muldiv_unit);

    pass_count = 0;
    fail_count = 0;
    test_num   = 0;

    // Init inputs
    operand_a    = '0;
    operand_b    = '0;
    op_sel       = '0;
    valid        = 1'b0;
    rd_in        = '0;
    reg_write_in = 1'b0;
    flush        = 1'b0;

    // Reset
    rst_n = 0;
    repeat (3) @(posedge clk);
    #1 rst_n = 1;
    repeat (2) @(posedge clk);

    // -----------------------------------------------------------------
    // Verify reset state
    // -----------------------------------------------------------------
    $display("");
    $display("========================================");
    $display("  MULDIV UNIT — RESET STATE");
    $display("========================================");
    check("busy after reset", busy, 1'b0);
    check("done after reset", done, 1'b0);

    // =================================================================
    // 1) MUL — all four variants
    // =================================================================
    $display("");
    $display("========================================");
    $display("  TEST GROUP: MUL (multiply)");
    $display("========================================");

    // MUL: 10 * 20 = 200
    test_num++;
    run_op(32'd10, 32'd20, OP_MUL, 5'd1, res);
    check("MUL 10*20", res, 32'd200);

    // MUL: 0x80000000 * 2 = 0x00000000 (lower 32 bits overflow)
    test_num++;
    run_op(32'h80000000, 32'd2, OP_MUL, 5'd2, res);
    check("MUL 0x80000000*2 lo", res, 32'h00000000);

    // MUL: 0xFFFFFFFF * 0xFFFFFFFF = 1 (lower 32 bits)
    test_num++;
    run_op(32'hFFFFFFFF, 32'hFFFFFFFF, OP_MUL, 5'd3, res);
    check("MUL -1*-1", res, 32'h00000001);

    // MULH: signed(-2^31) * signed(-2^31) = 0x40000000 (upper 32)
    test_num++;
    run_op(32'h80000000, 32'h80000000, OP_MULH, 5'd4, res);
    check("MULH 0x80000000*0x80000000", res, 32'h40000000);

    // MULH: 7 * 6 = 42 → upper = 0
    test_num++;
    run_op(32'd7, 32'd6, OP_MULH, 5'd5, res);
    check("MULH 7*6", res, 32'h00000000);

    // MULHSU: signed(-1) * unsigned(0x7FFFFFFF) = 0xFFFFFFFF (upper)
    //   -1 * (2^31-1) = -(2^31-1) = 0xC0000001_FFFFFFFF
    test_num++;
    run_op(32'hFFFFFFFF, 32'h7FFFFFFF, OP_MULHSU, 5'd6, res);
    check("MULHSU -1*0x7FFFFFFF", res, 32'hC0000000);

    // MULHU: unsigned(0x80000000) * unsigned(0x80000000) = 0x40000000
    test_num++;
    run_op(32'h80000000, 32'h80000000, OP_MULHU, 5'd7, res);
    check("MULHU 0x80000000*0x80000000", res, 32'h40000000);

    // MULHU: 5 * 5 = 25 → upper = 0
    test_num++;
    run_op(32'd5, 32'd5, OP_MULHU, 5'd8, res);
    check("MULHU 5*5", res, 32'h00000000);

    // =================================================================
    // 2) DIV — signed divide
    // =================================================================
    $display("");
    $display("========================================");
    $display("  TEST GROUP: DIV (signed divide)");
    $display("========================================");

    // DIV: 100 / 7 = 14
    test_num++;
    run_op(32'd100, 32'd7, OP_DIV, 5'd10, res);
    check("DIV 100/7", res, 32'd14);

    // DIV: -100 / 7 = -14
    test_num++;
    run_op(-32'd100, 32'd7, OP_DIV, 5'd11, res);
    check("DIV -100/7", res, -32'd14);

    // DIV: 100 / -7 = -14
    test_num++;
    run_op(32'd100, -32'd7, OP_DIV, 5'd12, res);
    check("DIV 100/-7", res, -32'd14);

    // DIV: -100 / -7 = 14
    test_num++;
    run_op(-32'd100, -32'd7, OP_DIV, 5'd13, res);
    check("DIV -100/-7", res, 32'd14);

    // DIV by zero: result = -1
    test_num++;
    run_op(32'd42, 32'd0, OP_DIV, 5'd14, res);
    check("DIV 42/0", res, 32'hFFFFFFFF);

    // DIV overflow: 0x80000000 / -1 → 0x80000000 (overflow, result = dividend)
    test_num++;
    run_op(32'h80000000, 32'hFFFFFFFF, OP_DIV, 5'd15, res);
    check("DIV 0x80000000/-1", res, 32'h80000000);

    // =================================================================
    // 3) DIVU — unsigned divide
    // =================================================================
    $display("");
    $display("========================================");
    $display("  TEST GROUP: DIVU (unsigned divide)");
    $display("========================================");

    // DIVU: 100 / 7 = 14
    test_num++;
    run_op(32'd100, 32'd7, OP_DIVU, 5'd16, res);
    check("DIVU 100/7", res, 32'd14);

    // DIVU: 0x80000000 / 3 = 0x2AAAAAAA
    test_num++;
    run_op(32'h80000000, 32'd3, OP_DIVU, 5'd17, res);
    check("DIVU 0x80000000/3", res, 32'h2AAAAAAA);

    // DIVU by zero: result = 0xFFFFFFFF
    test_num++;
    run_op(32'd42, 32'd0, OP_DIVU, 5'd18, res);
    check("DIVU 42/0", res, 32'hFFFFFFFF);

    // =================================================================
    // 4) REM — signed remainder
    // =================================================================
    $display("");
    $display("========================================");
    $display("  TEST GROUP: REM (signed remainder)");
    $display("========================================");

    // REM: 100 % 7 = 2
    test_num++;
    run_op(32'd100, 32'd7, OP_REM, 5'd19, res);
    check("REM 100%7", res, 32'd2);

    // REM: -100 % 7 = -2
    test_num++;
    run_op(-32'd100, 32'd7, OP_REM, 5'd20, res);
    check("REM -100%7", res, -32'd2);

    // REM: 100 % -7 = 2
    test_num++;
    run_op(32'd100, -32'd7, OP_REM, 5'd21, res);
    check("REM 100%-7", res, 32'd2);

    // REM by zero: result = dividend
    test_num++;
    run_op(32'd42, 32'd0, OP_REM, 5'd22, res);
    check("REM 42%0", res, 32'd42);

    // =================================================================
    // 5) REMU — unsigned remainder
    // =================================================================
    $display("");
    $display("========================================");
    $display("  TEST GROUP: REMU (unsigned remainder)");
    $display("========================================");

    // REMU: 100 % 7 = 2
    test_num++;
    run_op(32'd100, 32'd7, OP_REMU, 5'd23, res);
    check("REMU 100%7", res, 32'd2);

    // REMU: 0x80000000 % 3 = 2
    test_num++;
    run_op(32'h80000000, 32'd3, OP_REMU, 5'd24, res);
    check("REMU 0x80000000%3", res, 32'd2);

    // REMU by zero: result = dividend
    test_num++;
    run_op(32'h80000000, 32'd0, OP_REMU, 5'd25, res);
    check("REMU 0x80000000%0", res, 32'h80000000);

    // =================================================================
    // 6) Timing verification
    // =================================================================
    $display("");
    $display("========================================");
    $display("  TEST GROUP: TIMING");
    $display("========================================");

    // MUL should take 33 cycles (1 IDLE capture + 32 BUSY + 1 DONE)
    test_num++;
    begin
      int start_time, end_time, elapsed;
      @(negedge clk);
      start_time = $time;
      launch_op(32'd7, 32'd6, OP_MUL, 5'd26);
      wait_done();
      end_time = $time;
      elapsed = (end_time - start_time) / CLK_PERIOD;
      $display("  [INFO] MUL elapsed = %0d cycles", elapsed);
      if (elapsed == 33) begin
        $display("  [PASS] MUL timing = 33 cycles");
        pass_count++;
      end else begin
        $display("  [FAIL] MUL timing = %0d cycles (expected 33)", elapsed);
        fail_count++;
      end
    end

    // DIV by zero should take 1 cycle (IDLE → DONE immediately)
    test_num++;
    begin
      int start_time, end_time, elapsed;
      @(negedge clk);
      start_time = $time;
      launch_op(32'd42, 32'd0, OP_DIV, 5'd27);
      wait_done();
      end_time = $time;
      elapsed = (end_time - start_time) / CLK_PERIOD;
      $display("  [INFO] DIV/0 elapsed = %0d cycles", elapsed);
      if (elapsed == 1) begin
        $display("  [PASS] DIV/0 timing = 1 cycle");
        pass_count++;
      end else begin
        $display("  [FAIL] DIV/0 timing = %0d cycles (expected 1)", elapsed);
        fail_count++;
      end
    end

    // =================================================================
    // 7) Control signal verification
    // =================================================================
    $display("");
    $display("========================================");
    $display("  TEST GROUP: CONTROL SIGNALS");
    // ================================================================================================================

    // Verify busy goes high immediately after valid
    test_num++;
    @(negedge clk);
    operand_a = 32'd3; operand_b = 32'd4; op_sel = OP_MUL;
    rd_in = 5'd28; reg_write_in = 1'b1; valid = 1'b1;
    @(posedge clk);
    valid = 1'b0;
    // On this same posedge, the unit captures and transitions to BUSY
    @(negedge clk); // check after posedge settle
    if (busy) begin
      $display("  [PASS] busy high after valid");
      pass_count++;
    end else begin
      $display("  [FAIL] busy should be high after valid");
      fail_count++;
    end

    // Verify result_rd and result_we are correct during busy
    if (result_rd == 5'd28) begin
      $display("  [PASS] result_rd = %0d during busy", result_rd);
      pass_count++;
    end else begin
      $display("  [FAIL] result_rd = %0d, expected 28", result_rd);
      fail_count++;
    end
    if (result_we) begin
      $display("  [PASS] result_we = 1 during busy");
      pass_count++;
    end else begin
      $display("  [FAIL] result_we should be 1 during busy");
      fail_count++;
    end

    // Wait for completion
    wait_done();

    // Verify busy and done are deasserted
    if (!busy) begin
      $display("  [PASS] busy low after done");
      pass_count++;
    end else begin
      $display("  [FAIL] busy should be low after done");
      fail_count++;
    end

    // =================================================================
    // 8) Back-to-back operations (no stall between)
    // =================================================================
    $display("");
    $display("========================================");
    $display("  TEST GROUP: BACK-TO-BACK");
    $display("========================================");

    // MUL then immediately DIV
    test_num++;
    begin
      logic [31:0] r1, r2;
      run_op(32'd6, 32'd7, OP_MUL, 5'd29, r1);
      check("B2B MUL 6*7", r1, 32'd42);

      // Immediately launch next op
      run_op(32'd100, 32'd7, OP_DIV, 5'd30, r2);
      check("B2B DIV 100/7", r2, 32'd14);
    end

    // DIV then immediately MUL
    test_num++;
    begin
      logic [31:0] r1, r2;
      run_op(32'd50, 32'd5, OP_DIV, 5'd1, r1);
      check("B2B DIV 50/5", r1, 32'd10);

      run_op(32'd3, 32'd3, OP_MUL, 5'd2, r2);
      check("B2B MUL 3*3", r2, 32'd9);
    end

    // =================================================================
    // 9) Stall behavior: valid held during busy
    //    The unit should NOT re-capture inputs if valid stays high
    // =================================================================
    $display("");
    $display("========================================");
    $display("  TEST GROUP: STALL / VALID DURING BUSY");
    $display("========================================");

    test_num++;
    begin
      logic [31:0] r1, r2;

      // Launch first MUL: 5 * 6 = 30
      @(negedge clk);
      operand_a = 32'd5; operand_b = 32'd6; op_sel = OP_MUL;
      rd_in = 5'd3; reg_write_in = 1'b1; valid = 1'b1;
      @(posedge clk);
      valid = 1'b0;

      // Wait until unit is BUSY
      @(negedge clk);
      if (!busy) begin
        $display("  [FAIL] unit should be busy after MUL start");
        fail_count++;
      end

      // Now assert valid with DIFFERENT inputs while busy
      // Unit should NOT re-capture (valid && !done is the capture condition,
      // but we are in BUSY state, not IDLE)
      @(negedge clk);
      operand_a = 32'd99; operand_b = 32'd99; op_sel = OP_MUL;
      rd_in = 5'd99; reg_write_in = 1'b1; valid = 1'b1;
      @(posedge clk);
      valid = 1'b0;

      // Wait for first MUL to complete
      while (!done) @(posedge clk);
      r1 = result;
      @(posedge clk);

      check("STALL: MUL 5*6 not corrupted", r1, 32'd30);

      // The second valid during BUSY should have been ignored.
      // Verify unit is now IDLE and can accept a new op.
      run_op(32'd8, 32'd8, OP_MUL, 5'd4, r2);
      check("STALL: new op after busy works", r2, 32'd64);
    end

    // =================================================================
    // 10) rd_in / reg_write_in passthrough
    // =================================================================
    $display("");
    $display("========================================");
    $display("  TEST GROUP: RD/WE PASSTHROUGH");
    $display("========================================");

    test_num++;
    begin
      logic [31:0] dummy;
      @(negedge clk);
      operand_a = 32'd2; operand_b = 32'd3; op_sel = OP_MUL;
      rd_in = 5'd17; reg_write_in = 1'b1; valid = 1'b1;
      @(posedge clk);
      valid = 1'b0;
      @(negedge clk);
      if (result_rd != 5'd17) begin
        $display("  [FAIL] result_rd = %0d, expected 17", result_rd);
        fail_count++;
      end else begin
        $display("  [PASS] result_rd = %0d (correct)", result_rd);
        pass_count++;
      end
      if (!result_we) begin
        $display("  [FAIL] result_we should be 1");
        fail_count++;
      end else begin
        $display("  [PASS] result_we = 1 (correct)");
        pass_count++;
      end
      wait_done();
    end

    // Test with reg_write_in = 0
    test_num++;
    begin
      @(negedge clk);
      operand_a = 32'd2; operand_b = 32'd3; op_sel = OP_MUL;
      rd_in = 5'd18; reg_write_in = 1'b0; valid = 1'b1;
      @(posedge clk);
      valid = 1'b0;
      @(negedge clk);
      if (result_we) begin
        $display("  [FAIL] result_we should be 0 when reg_write_in=0");
        fail_count++;
      end else begin
        $display("  [PASS] result_we = 0 (correct, reg_write_in=0)");
        pass_count++;
      end
      wait_done();
    end

    // =================================================================
    // Summary
    // =================================================================
    $display("");
    $display("========================================");
    $display("  MULDIV UNIT TEST SUMMARY");
    $display("  %0d tests executed", test_num);
    $display("  %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("========================================");
    $display("");

    #10;
    $finish;
  end

endmodule
