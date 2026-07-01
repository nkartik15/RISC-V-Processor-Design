// ====================================================================
// tb_branch_jump.v  ?  Branch & Jump integration testbench
//
// Tests every RV32I control-flow instruction end-to-end through
// cpu_pipeline.v.  Each test is a small self-contained program loaded
// at a fixed offset in instruction memory; a sentinel register write
// distinguishes "branch taken" from "branch not taken".
//
// Strategy
// ????????
// Each mini-program:
//   [setup]    load operands
//   [branch]   the instruction under test
//   [skip_A]   addi xN, x0, 0xBAD   ? reached only if NOT taken
//   [target_B] addi xN, x0, GOOD    ? reached only if taken
//   [nop...]   pipeline drain
//
// After enough cycles, check xN:
//   GOOD value  ? taken path executed correctly
//   BAD  value  ? not-taken executed (wrong)
//   0           ? neither executed (also wrong)
//
// For not-taken tests the layout is reversed:
//   [branch]   should fall through
//   [fall]     addi xN, x0, GOOD    ? must execute
//   [target]   addi xN, x0, BAD     ? must NOT execute
//
// Branch types tested
// ???????????????????
//  BEQ  : taken (equal),      not-taken (unequal)
//  BNE  : taken (unequal),    not-taken (equal)
//  BLT  : taken (signed <),   not-taken (signed >=)
//  BGE  : taken (signed >=),  not-taken (signed <)
//  BLTU : taken (unsigned <), not-taken (unsigned >=)
//  BGEU : taken (unsigned >=),not-taken (unsigned <)
//  JAL  : link register gets pc+4, target executed
//  JALR : link register gets pc+4, target computed from rs1+imm
//
// Each mini-program is placed at a 16-word (64-byte) boundary so
// branches target the correct absolute address regardless of program
// order.
// ====================================================================
`timescale 1ns/1ps
`include "pipeline_pkg.v"

module tb_branch_jump;

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
integer cycle_count;
initial  clk=0;
always #5 clk = ~clk;

always @(posedge clk) begin
    cycle_count = cycle_count + 1;
end

// ?? Sentinel values ??????????????????????????????????????????????????
localparam GOOD = 32'd42;
localparam BAD  = 32'h0BAD;   // 0xBAD = 2989

// ?? check task ???????????????????????????????????????????????????????
task chk;
    input [200:0] name;
    input [4:0]   rnum;
    input [31:0]  exp;
    begin
        if (DUT.RF.register_array[rnum] === exp) begin
            $display("PASS [%0s]  x%0d=%0d", name, rnum, exp);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0s]  x%0d got=%0d exp=%0d",
                     name, rnum, DUT.RF.register_array[rnum], exp);
            fail_count = fail_count + 1;
        end
    end
endtask

// ?? NOP = ADDI x0,x0,0 ???????????????????????????????????????????????
localparam NOP = 32'h0000_0013;

// ?? Helpers to build common instruction encodings ????????????????????
// addi rd, rs1, imm  (I-type)
function [31:0] addi;
    input [4:0]  rd, rs1;
    input [11:0] imm;
    begin addi = {imm, rs1, 3'b000, rd, 7'b0010011}; end
endfunction

// add rd, rs1, rs2  (R-type)
function [31:0] add_r;
    input [4:0] rd, rs1, rs2;
    begin add_r = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011}; end
endfunction

// BEQ rs1, rs2, imm13  (B-type, imm is the full signed 13-bit offset)
function [31:0] beq_enc;
    input [4:0]  rs1, rs2;
    input [12:0] imm;
    begin
        beq_enc = {imm[12], imm[10:5], rs2, rs1,
                   3'b000, imm[4:1], imm[11], 7'b1100011};
    end
endfunction
function [31:0] bne_enc;
    input [4:0]  rs1, rs2;
    input [12:0] imm;
    begin
        bne_enc = {imm[12], imm[10:5], rs2, rs1,
                   3'b001, imm[4:1], imm[11], 7'b1100011};
    end
endfunction
function [31:0] blt_enc;
    input [4:0]  rs1, rs2;
    input [12:0] imm;
    begin
        blt_enc = {imm[12], imm[10:5], rs2, rs1,
                   3'b100, imm[4:1], imm[11], 7'b1100011};
    end
endfunction
function [31:0] bge_enc;
    input [4:0]  rs1, rs2;
    input [12:0] imm;
    begin
        bge_enc = {imm[12], imm[10:5], rs2, rs1,
                   3'b101, imm[4:1], imm[11], 7'b1100011};
    end
endfunction
function [31:0] bltu_enc;
    input [4:0]  rs1, rs2;
    input [12:0] imm;
    begin
        bltu_enc = {imm[12], imm[10:5], rs2, rs1,
                    3'b110, imm[4:1], imm[11], 7'b1100011};
    end
endfunction
function [31:0] bgeu_enc;
    input [4:0]  rs1, rs2;
    input [12:0] imm;
    begin
        bgeu_enc = {imm[12], imm[10:5], rs2, rs1,
                    3'b111, imm[4:1], imm[11], 7'b1100011};
    end
endfunction

// JAL rd, imm21
function [31:0] jal_enc;
    input [4:0]  rd;
    input [20:0] imm;
    begin
        jal_enc = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
    end
endfunction

// JALR rd, rs1, imm12
function [31:0] jalr_enc;
    input [4:0]  rd, rs1;
    input [11:0] imm;
    begin
        jalr_enc = {imm, rs1, 3'b000, rd, 7'b1100111};
    end
endfunction

// ?? Place a mini-program at a 16-word-aligned base ???????????????????
// base is in words (multiply by 4 for byte address)
task load_at;
    input integer base;
    input [31:0] i0,i1,i2,i3,i4,i5,i6,i7;
    begin
        DUT.IMEM.memory[base+0]=i0; DUT.IMEM.memory[base+1]=i1;
        DUT.IMEM.memory[base+2]=i2; DUT.IMEM.memory[base+3]=i3;
        DUT.IMEM.memory[base+4]=i4; DUT.IMEM.memory[base+5]=i5;
        DUT.IMEM.memory[base+6]=i6; DUT.IMEM.memory[base+7]=i7;
    end
endtask

// ?? Reset and run a single mini-program starting at word 'base' ??????
// Runs for 'cycles' clock cycles after reset de-asserts.
task run_program;
    input integer base_word, cycles;
    integer b;
    begin
        // Point PC to base_word by pre-loading instruction memory
        // already done by the caller; we just need to reset + run.
        // We abuse the fact that reset sends PC to 0, so we copy
        // the mini-program to word 0 through 15 before reset.
        for (b=0; b<16; b=b+1)
            DUT.IMEM.memory[b] = DUT.IMEM.memory[base_word+b];

        reset=1; #12; reset=0;
        repeat (cycles) @(posedge clk);
        #1;
    end
endtask

initial begin
    pass_count=0; fail_count=0; cycle_count=0;
    reset=1;
    for (i=0;i<256;i=i+1) DUT.IMEM.memory[i]=NOP;

    $display("=== BRANCH & JUMP TESTBENCH ===");

    // ================================================================
    // BEQ ? TAKEN  (rs1 == rs2)
    // ================================================================
    // Layout (at word 32):
    //  0: addi x1, x0, 5
    //  1: addi x2, x0, 5
    //  2: beq  x1, x2, +8   ? skip word 3, land on word 4
    //  3: addi x3, x0, BAD  (should be skipped)
    //  4: addi x3, x0, 42   (GOOD)
    $display("\n-- BEQ taken");
    DUT.IMEM.memory[32] = addi(5'd1,5'd0,12'd5);
    DUT.IMEM.memory[33] = addi(5'd2,5'd0,12'd5);
    DUT.IMEM.memory[34] = beq_enc(5'd1,5'd2,13'd8);
    DUT.IMEM.memory[35] = addi(5'd3,5'd0,12'hBAD);
    DUT.IMEM.memory[36] = addi(5'd3,5'd0,12'd42);
    for (i=37;i<48;i=i+1) DUT.IMEM.memory[i]=NOP;
    run_program(32, 20);
    chk("beq_taken", 5'd3, GOOD);

    // ================================================================
    // BEQ ? NOT TAKEN  (rs1 != rs2)
    // ================================================================
    $display("-- BEQ not taken");
    DUT.IMEM.memory[32] = addi(5'd1,5'd0,12'd5);
    DUT.IMEM.memory[33] = addi(5'd2,5'd0,12'd6);
    DUT.IMEM.memory[34] = beq_enc(5'd1,5'd2,13'd8);
    DUT.IMEM.memory[35] = addi(5'd3,5'd0,12'd42);          // fall-through = GOOD
    DUT.IMEM.memory[36] = jal_enc(5'd0, 21'd8);            // skip BAD
    DUT.IMEM.memory[37] = addi(5'd3,5'd0,12'hBAD);         // target = BAD
    for (i=38;i<48;i=i+1) DUT.IMEM.memory[i]=NOP;
    run_program(32, 20);
    chk("beq_not_taken", 5'd3, GOOD);

    // ================================================================
    // BNE ? TAKEN  (rs1 != rs2)
    // ================================================================
    $display("-- BNE taken");
    DUT.IMEM.memory[32] = addi(5'd1,5'd0,12'd3);
    DUT.IMEM.memory[33] = addi(5'd2,5'd0,12'd7);
    DUT.IMEM.memory[34] = bne_enc(5'd1,5'd2,13'd8);
    DUT.IMEM.memory[35] = addi(5'd3,5'd0,12'hBAD);
    DUT.IMEM.memory[36] = addi(5'd3,5'd0,12'd42);
    for (i=37;i<48;i=i+1) DUT.IMEM.memory[i]=NOP;
    run_program(32, 20);
    chk("bne_taken", 5'd3, GOOD);

    // ================================================================
    // BNE ? NOT TAKEN  (rs1 == rs2)
    // ================================================================
    $display("-- BNE not taken");
    DUT.IMEM.memory[32] = addi(5'd1,5'd0,12'd4);
    DUT.IMEM.memory[33] = addi(5'd2,5'd0,12'd4);
    DUT.IMEM.memory[34] = bne_enc(5'd1,5'd2,13'd8);
    DUT.IMEM.memory[35] = addi(5'd3,5'd0,12'd42);
    DUT.IMEM.memory[36] = jal_enc(5'd0, 21'd8);
    DUT.IMEM.memory[37] = addi(5'd3,5'd0,12'hBAD);
    for (i=38;i<48;i=i+1) DUT.IMEM.memory[i]=NOP;
    run_program(32, 20);
    chk("bne_not_taken", 5'd3, GOOD);

    // ================================================================
    // BLT ? TAKEN  (signed: -1 < 1)
    // ================================================================
    $display("-- BLT taken (signed)");
    DUT.IMEM.memory[32] = addi(5'd1,5'd0,12'hFFF); // -1
    DUT.IMEM.memory[33] = addi(5'd2,5'd0,12'd1);
    DUT.IMEM.memory[34] = blt_enc(5'd1,5'd2,13'd8);
    DUT.IMEM.memory[35] = addi(5'd3,5'd0,12'hBAD);
    DUT.IMEM.memory[36] = addi(5'd3,5'd0,12'd42);
    for (i=37;i<48;i=i+1) DUT.IMEM.memory[i]=NOP;
    run_program(32, 20);
    chk("blt_taken", 5'd3, GOOD);

    // ================================================================
    // BLT ? NOT TAKEN  (signed: 5 >= 3)
    // ================================================================
    $display("-- BLT not taken");
    DUT.IMEM.memory[32] = addi(5'd1,5'd0,12'd5);
    DUT.IMEM.memory[33] = addi(5'd2,5'd0,12'd3);
    DUT.IMEM.memory[34] = blt_enc(5'd1,5'd2,13'd8);
    DUT.IMEM.memory[35] = addi(5'd3,5'd0,12'd42);
    DUT.IMEM.memory[36] = jal_enc(5'd0, 21'd8);
    DUT.IMEM.memory[37] = addi(5'd3,5'd0,12'hBAD);
    for (i=38;i<48;i=i+1) DUT.IMEM.memory[i]=NOP;
    run_program(32, 20);
    chk("blt_not_taken", 5'd3, GOOD);

    // ================================================================
    // BGE ? TAKEN  (signed: 5 >= 3)
    // ================================================================
    $display("-- BGE taken (signed)");
    DUT.IMEM.memory[32] = addi(5'd1,5'd0,12'd5);
    DUT.IMEM.memory[33] = addi(5'd2,5'd0,12'd3);
    DUT.IMEM.memory[34] = bge_enc(5'd1,5'd2,13'd8);
    DUT.IMEM.memory[35] = addi(5'd3,5'd0,12'hBAD);
    DUT.IMEM.memory[36] = addi(5'd3,5'd0,12'd42);
    for (i=37;i<48;i=i+1) DUT.IMEM.memory[i]=NOP;
    run_program(32, 20);
    chk("bge_taken", 5'd3, GOOD);

    // ================================================================
    // BGE ? NOT TAKEN  (signed: -1 < 1, so NOT >=)
    // ================================================================
    $display("-- BGE not taken");
    DUT.IMEM.memory[32] = addi(5'd1,5'd0,12'hFFF); // -1
    DUT.IMEM.memory[33] = addi(5'd2,5'd0,12'd1);
    DUT.IMEM.memory[34] = bge_enc(5'd1,5'd2,13'd8);
    DUT.IMEM.memory[35] = addi(5'd3,5'd0,12'd42);
    DUT.IMEM.memory[36] = jal_enc(5'd0, 21'd8);
    DUT.IMEM.memory[37] = addi(5'd3,5'd0,12'hBAD);
    for (i=38;i<48;i=i+1) DUT.IMEM.memory[i]=NOP;
    run_program(32, 20);
    chk("bge_not_taken", 5'd3, GOOD);

    // ================================================================
    // BLTU ? TAKEN  (unsigned: 1 < 0xFFF ? 1 < 4095)
    // ================================================================
    $display("-- BLTU taken (unsigned)");
    DUT.IMEM.memory[32] = addi(5'd1,5'd0,12'd1);
    DUT.IMEM.memory[33] = addi(5'd2,5'd0,12'hFFF); // 4095 unsigned
    DUT.IMEM.memory[34] = bltu_enc(5'd1,5'd2,13'd8);
    DUT.IMEM.memory[35] = addi(5'd3,5'd0,12'hBAD);
    DUT.IMEM.memory[36] = addi(5'd3,5'd0,12'd42);
    for (i=37;i<48;i=i+1) DUT.IMEM.memory[i]=NOP;
    run_program(32, 20);
    chk("bltu_taken", 5'd3, GOOD);

    // ================================================================
    // BLTU ? NOT TAKEN  (unsigned: 0xFFF >= 1)
    // ================================================================
    $display("-- BLTU not taken");
    DUT.IMEM.memory[32] = addi(5'd1,5'd0,12'hFFF);
    DUT.IMEM.memory[33] = addi(5'd2,5'd0,12'd1);
    DUT.IMEM.memory[34] = bltu_enc(5'd1,5'd2,13'd8);
    DUT.IMEM.memory[35] = addi(5'd3,5'd0,12'd42);
    DUT.IMEM.memory[36] = jal_enc(5'd0, 21'd8);
    DUT.IMEM.memory[37] = addi(5'd3,5'd0,12'hBAD);
    for (i=38;i<48;i=i+1) DUT.IMEM.memory[i]=NOP;
    run_program(32, 20);
    chk("bltu_not_taken", 5'd3, GOOD);

    // ================================================================
    // BGEU ? TAKEN  (unsigned: 0xFFF >= 1)
    // ================================================================
    $display("-- BGEU taken (unsigned)");
    DUT.IMEM.memory[32] = addi(5'd1,5'd0,12'hFFF);
    DUT.IMEM.memory[33] = addi(5'd2,5'd0,12'd1);
    DUT.IMEM.memory[34] = bgeu_enc(5'd1,5'd2,13'd8);
    DUT.IMEM.memory[35] = addi(5'd3,5'd0,12'hBAD);
    DUT.IMEM.memory[36] = addi(5'd3,5'd0,12'd42);
    for (i=37;i<48;i=i+1) DUT.IMEM.memory[i]=NOP;
    run_program(32, 20);
    chk("bgeu_taken", 5'd3, GOOD);

    // ================================================================
    // BGEU ? NOT TAKEN  (unsigned: 1 < 0xFFF, not >=)
    // ================================================================
    $display("-- BGEU not taken");
    DUT.IMEM.memory[32] = addi(5'd1,5'd0,12'd1);
    DUT.IMEM.memory[33] = addi(5'd2,5'd0,12'hFFF);
    DUT.IMEM.memory[34] = bgeu_enc(5'd1,5'd2,13'd8);
    DUT.IMEM.memory[35] = addi(5'd3,5'd0,12'd42);
    DUT.IMEM.memory[36] = jal_enc(5'd0, 21'd8);
    DUT.IMEM.memory[37] = addi(5'd3,5'd0,12'hBAD);
    for (i=38;i<48;i=i+1) DUT.IMEM.memory[i]=NOP;
    run_program(32, 20);
    chk("bgeu_not_taken", 5'd3, GOOD);

    // ================================================================
    // JAL ? link address + correct jump target
    // ================================================================
    // Layout:
    //  0: jal  x4, +8     ? rd=x4 gets pc+4 = 4; jump to word 2
    //  1: addi x3, x0, BAD  (should be flushed/skipped)
    //  2: addi x3, x0, 42   (jump target = GOOD)
    $display("\n-- JAL");
    DUT.IMEM.memory[32] = jal_enc(5'd4, 21'd8);    // jal x4, +8
    DUT.IMEM.memory[33] = addi(5'd3,5'd0,12'hBAD);
    DUT.IMEM.memory[34] = addi(5'd3,5'd0,12'd42);
    for (i=35;i<48;i=i+1) DUT.IMEM.memory[i]=NOP;
    run_program(32, 20);
    chk("jal_target",    5'd3, GOOD);
    // Link: PC of JAL instruction = 0 (word 0 after copy), so pc+4 = 4
    chk("jal_link_x4",  5'd4, 32'd4);

    // ================================================================
    // JALR ? dynamic target from rs1+imm, link address
    // ================================================================
    // Layout:
    //  0: addi x5, x0, 12   # x5 = 12 (byte address of word 3)
    //  1: jalr x6, x5, 0    ? rd=x6 gets pc+4=8; jump to address 12
    //  2: addi x3, x0, BAD  (should be skipped)
    //  3: addi x3, x0, 42   (JALR target = GOOD)
    $display("-- JALR");
    DUT.IMEM.memory[32] = addi(5'd5,5'd0,12'd12);
    DUT.IMEM.memory[33] = jalr_enc(5'd6,5'd5,12'd0); // jalr x6, x5, 0
    DUT.IMEM.memory[34] = addi(5'd3,5'd0,12'hBAD);
    DUT.IMEM.memory[35] = addi(5'd3,5'd0,12'd42);
    for (i=36;i<48;i=i+1) DUT.IMEM.memory[i]=NOP;
    run_program(32, 20);
    chk("jalr_target",   5'd3, GOOD);
    // Link: PC of JALR = 4 (word 1 after copy), so pc+4 = 8
    chk("jalr_link_x6", 5'd6, 32'd8);

    // ================================================================
    // SUMMARY
    // ================================================================
    $display("\n=== RESULTS: %0d passed, %0d failed ===",
             pass_count, fail_count);
    if (fail_count==0) $display("ALL TESTS PASSED");
    else               $display("*** FAILURES ? review above ***");
    $finish;
end

// Safety watchdog: end simulation if it stalls unexpectedly.
initial begin
    #100000;
    $display("*** TIMEOUT: no finish after %0d cycles ***", cycle_count);
    $finish;
end

endmodule
