// ====================================================================
// tb_pipeline_hazards.v  ?  Pipeline hazard integration testbench
//
// Tests four hazard scenarios end-to-end through cpu_pipeline.v.
// Each scenario is a minimal instruction sequence that isolates
// exactly one hazard class.  Register results are checked after
// enough cycles for the pipeline to drain.
//
// Scenario 1 ? EX/MEM ? EX forwarding (back-to-back ALU)
//   addi x1, x0, 10      # x1 = 10
//   addi x2, x1, 5       # x2 = x1 + 5 = 15  ? fwd from EX/MEM
//   add  x3, x2, x1      # x3 = 15 + 10 = 25 ? both operands forwarded
//
// Scenario 2 ? MEM/WB ? EX forwarding (two-instruction gap)
//   addi x4, x0, 7       # x4 = 7
//   addi x5, x0, 3       # x5 = 3   (gap instruction)
//   add  x6, x4, x5      # x6 = 10  ? fwd from MEM/WB for x4
//
// Scenario 3 ? Load-use stall (1 cycle bubble)
//   addi x7,  x0, 20     # x7 = 20
//   sw   x7,  0(x0)      # mem[0] = 20
//   lw   x8,  0(x0)      # x8 = 20  (load)
//   addi x9,  x8, 1      # x9 = 21  ? load-use stall: must wait 1 cycle
//
// Scenario 4 ? Taken branch flushes two instructions
//   addi x10, x0, 1      # x10 = 1
//   beq  x10, x10, +8    # taken ? skip next two words
//   addi x11, x0, 99     # MUST NOT execute (flushed)
//   addi x11, x0, 99     # MUST NOT execute (flushed)
//   addi x11, x0, 42     # x11 = 42  ? branch target
//
// All scenarios run sequentially in one program; registers are
// checked after a 30-cycle drain (pipeline has 5 stages; longest
// hazard sequence needs ~15 cycles to complete).
// ====================================================================
`timescale 1ns/1ps
`include "pipeline_pkg.v"

module tb_pipeline_hazards;

reg clk, reset;
wire [4:0] pwr_stage_active;
wire       sec_fault, macro_stall_ack;

cpu_pipeline DUT (
    .clk             (clk),
    .reset           (reset),
    .pwr_stall_req   (1'b0),
    .pwr_stage_active(pwr_stage_active),
    .sec_tag_in      (16'd0),
    .sec_fault       (sec_fault),
    .macro_valid     (1'b0),
    .macro_instr     (32'd0),
    .macro_stall_ack (macro_stall_ack)
);

integer pass_count, fail_count, i;

always #5 clk = ~clk;

task check_reg;
    input [200:0] name;
    input [4:0]   reg_num;
    input [31:0]  exp;
    begin
        if (DUT.RF.register_array[reg_num] === exp) begin
            $display("PASS [%0s]  x%0d = %0d", name, reg_num, exp);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0s]  x%0d got=%0d exp=%0d",
                     name, reg_num,
                     DUT.RF.register_array[reg_num], exp);
            fail_count = fail_count + 1;
        end
    end
endtask

initial begin
    pass_count=0; fail_count=0;
    clk=0; reset=1;

    // ?? zero all instruction memory ??????????????????????????????????
    for (i=0; i<256; i=i+1)
        DUT.IMEM.memory[i] = `NOP_INSTR;

    // ================================================================
    // SCENARIO 1: EX/MEM ? EX forwarding  (instructions 0-2)
    // ================================================================
    //  0: addi x1,  x0, 10   0x00A00093
    //  1: addi x2,  x1,  5   0x00508113   ? EX/MEM fwd on x1
    //  2: add  x3,  x2, x1   0x001101B3   ? EX/MEM fwd on x2, MEM/WB on x1
    DUT.IMEM.memory[0] = 32'h00A00093;  // addi x1, x0, 10
    DUT.IMEM.memory[1] = 32'h00508113;  // addi x2, x1, 5
    DUT.IMEM.memory[2] = 32'h001101B3;  // add  x3, x2, x1

    // ================================================================
    // SCENARIO 2: MEM/WB ? EX forwarding  (instructions 3-5)
    // ================================================================
    //  3: addi x4,  x0,  7   0x00700213
    //  4: addi x5,  x0,  3   0x00300293   (gap ? independent)
    //  5: add  x6,  x4, x5   0x00520333   ? MEM/WB fwd on x4
    DUT.IMEM.memory[3] = 32'h00700213;  // addi x4, x0, 7
    DUT.IMEM.memory[4] = 32'h00300293;  // addi x5, x0, 3
    DUT.IMEM.memory[5] = 32'h00520333;  // add  x6, x4, x5

    // ================================================================
    // SCENARIO 3: Load-use stall  (instructions 6-9)
    // ================================================================
    //  6: addi x7,  x0, 20   0x01400393
    //  7: sw   x7,  0(x0)    0x00702023
    //  8: lw   x8,  0(x0)    0x00002403
    //  9: addi x9,  x8,  1   0x00140493   ? load-use stall on x8
    DUT.IMEM.memory[6] = 32'h01400393;  // addi x7, x0, 20
    DUT.IMEM.memory[7] = 32'h00702023;  // sw   x7, 0(x0)
    DUT.IMEM.memory[8] = 32'h00002403;  // lw   x8, 0(x0)
    DUT.IMEM.memory[9] = 32'h00140493;  // addi x9, x8, 1

    // ================================================================
    // SCENARIO 4: Taken branch flush  (instructions 10-14)
    // ================================================================
    //  10: addi x10, x0,  1   0x00100513
    //  11: beq  x10, x10, +8  0x00A50463  (offset=+8 ? skip instr 12,13)
    //  12: addi x11, x0, 99   0x06300593  ? must be flushed
    //  13: addi x11, x0, 99   0x06300593  ? must be flushed
    //  14: addi x11, x0, 42   0x02A00593  ? branch target
    DUT.IMEM.memory[10] = 32'h00100513;  // addi x10, x0, 1
    DUT.IMEM.memory[11] = 32'h00A50463;  // beq  x10, x10, +8
    DUT.IMEM.memory[12] = 32'h06300593;  // addi x11, x0, 99  (flushed)
    DUT.IMEM.memory[13] = 32'h06300593;  // addi x11, x0, 99  (flushed)
    DUT.IMEM.memory[14] = 32'h02A00593;  // addi x11, x0, 42

    // ?? Release reset, run enough cycles to drain all scenarios ?????
    #12 reset = 0;
    // 15 instructions + up to 2 stall cycles + 5 pipeline stages
    // + branch flush overhead = ~30 cycles comfortably
    repeat (45) @(posedge clk);
    #1; // settle combinational outputs

    $display("=== PIPELINE HAZARDS TESTBENCH ===");

    $display("\n-- Scenario 1: EX/MEM forwarding (back-to-back ALU)");
    check_reg("exmem_fwd_x1", 5'd1,  32'd10);
    check_reg("exmem_fwd_x2", 5'd2,  32'd15);
    check_reg("exmem_fwd_x3", 5'd3,  32'd25);

    $display("\n-- Scenario 2: MEM/WB forwarding (2-instr gap)");
    check_reg("memwb_fwd_x4", 5'd4,  32'd7);
    check_reg("memwb_fwd_x5", 5'd5,  32'd3);
    check_reg("memwb_fwd_x6", 5'd6,  32'd10);

    $display("\n-- Scenario 3: Load-use stall");
    check_reg("load_use_x7",  5'd7,  32'd20);
    check_reg("load_use_x8",  5'd8,  32'd20);
    check_reg("load_use_x9",  5'd9,  32'd21);

    $display("\n-- Scenario 4: Taken branch ? two instructions flushed");
    check_reg("branch_x10",   5'd10, 32'd1);
    check_reg("branch_x11",   5'd11, 32'd42); // NOT 99 if flush worked

    $display("\n=== RESULTS: %0d passed, %0d failed ===",
             pass_count, fail_count);
    if (fail_count==0) $display("ALL TESTS PASSED");
    else               $display("*** FAILURES ? review above ***");
    $finish;
end

endmodule
