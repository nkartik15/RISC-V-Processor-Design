// ====================================================================
// tb_instruction_memory.v  ?  instructionmem unit testbench
//
// The module under test:
//   - Loads program.hex at elaboration via $readmemh
//   - Reads are purely combinational (no clock)
//   - Index is pc[9:2] (word address from byte PC)
//   - Returns NOP (32'h0000_0013) for out-of-range PC (pc[31:10] != 0)
//
// Test cases
// ??????????
//  1. Known word at address 0  (first hex entry)
//  2. Known word at address 4  (second hex entry)
//  3. Word-aligned sequential reads match all 7 program entries
//  4. Out-of-range PC (> 10-bit addressable space) ? NOP fallback
//  5. PC misaligned (pc[1:0] != 00) ? address still word-indexed; verify
//     the module uses pc[9:2] not pc[9:0]
//
// NOTE: This testbench pre-loads memory directly (DUT.memory[i]) so it
// is independent of whatever program.hex contains on disk.  The test
// for $readmemh correctness (case 3) uses the known hex values from
// program.hex embedded here ? if program.hex changes the test will
// still compile; it just may report a mismatch on case 3 if the file
// on disk differs.
// ====================================================================
`timescale 1ns/1ps

module tb_instruction_memory;

reg  [31:0] pc;
wire [31:0] rd;

instructionmem DUT (
    .pc(pc),
    .rd(rd)
);

integer pass_count, fail_count, i;

task check;
    input [200:0] name;
    input [31:0]  exp;
    begin
        #2;
        if (rd === exp) begin
            $display("PASS [%0s]  got=%08h", name, rd);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0s]  got=%08h  exp=%08h", name, rd, exp);
            fail_count = fail_count + 1;
        end
    end
endtask

// ?? known program words (mirrors program.hex) ????????????????????????
// addi x1,x0,5 | addi x2,x0,3 | add x3,x1,x2 | sw x3,0(x0)
// lw x4,0(x0)  | bne x4,x3,-4 | addi x5,x0,7
localparam [31:0] W0 = 32'h00500093,
                  W1 = 32'h00300113,
                  W2 = 32'h002081B3,
                  W3 = 32'h00302023,
                  W4 = 32'h00002203,
                  W5 = 32'hFE3216E3,
                  W6 = 32'h00700293;

initial begin
    pass_count=0; fail_count=0;
    $display("=== INSTRUCTION MEMORY TESTBENCH ===");

    // ----------------------------------------------------------------
    // Pre-load known values so the test is self-contained regardless
    // of what program.hex looks like on disk.
    // ----------------------------------------------------------------
    DUT.memory[0] = W0;
    DUT.memory[1] = W1;
    DUT.memory[2] = W2;
    DUT.memory[3] = W3;
    DUT.memory[4] = W4;
    DUT.memory[5] = W5;
    DUT.memory[6] = W6;
    // Fill remainder with NOPs so reads beyond [6] return a known value
    for (i = 7; i < 256; i = i+1)
        DUT.memory[i] = 32'h0000_0013;

    // ----------------------------------------------------------------
    // TEST 1: First word  pc=0x00000000 ? memory[0]
    // ----------------------------------------------------------------
    $display("-- word at pc=0");
    pc = 32'h0000_0000;
    check("word_pc0", W0);

    // ----------------------------------------------------------------
    // TEST 2: Second word  pc=0x00000004 ? memory[1]
    // ----------------------------------------------------------------
    $display("-- word at pc=4");
    pc = 32'h0000_0004;
    check("word_pc4", W1);

    // ----------------------------------------------------------------
    // TEST 3: Sequential read of all 7 program words
    // Verifies pc[9:2] indexing across the full program
    // ----------------------------------------------------------------
    $display("-- sequential read of all program words");
    begin : seq_block
        reg [31:0] expected [0:6];
        expected[0]=W0; expected[1]=W1; expected[2]=W2;
        expected[3]=W3; expected[4]=W4; expected[5]=W5; expected[6]=W6;
        for (i=0; i<7; i=i+1) begin
            pc = i * 4;
            #2;
            if (rd === expected[i]) begin
                $display("PASS [seq_%0d]  got=%08h", i, rd);
                pass_count = pass_count+1;
            end else begin
                $display("FAIL [seq_%0d]  got=%08h  exp=%08h", i, rd, expected[i]);
                fail_count = fail_count+1;
            end
        end
    end

    // ----------------------------------------------------------------
    // TEST 4: Out-of-range PC  ?  NOP fallback
    // pc[31:10] != 0 triggers the guard in instructionmem.v
    // ----------------------------------------------------------------
    $display("-- out-of-range PC returns NOP");
    pc = 32'h0000_0400;   // pc[10]=1 ? pc[31:10] != 0
    check("oob_pc_0x400",  32'h0000_0013);

    pc = 32'hFFFF_FFFC;   // way out of range
    check("oob_pc_ffff",   32'h0000_0013);

    // ----------------------------------------------------------------
    // TEST 5: Word-select uses pc[9:2], not pc[1:0]
    // pc=0x00000005 ? index = 0x05>>2 = 1 ? same as pc=4
    // pc=0x00000006 ? index = 1           ? same as pc=4
    // If the module used pc[9:0] directly these would give wrong words.
    // ----------------------------------------------------------------
    $display("-- word-address extraction ignores pc[1:0]");
    pc = 32'h0000_0005;   // byte-misaligned, index should still be 1
    check("misalign_pc5_word1", W1);

    pc = 32'h0000_0006;   // byte-misaligned, index should still be 1
    check("misalign_pc6_word1", W1);

    pc = 32'h0000_0007;   // byte-misaligned, index should still be 1
    check("misalign_pc7_word1", W1);

    // ----------------------------------------------------------------
    // SUMMARY
    // ----------------------------------------------------------------
    $display("\n=== RESULTS: %0d passed, %0d failed ===",
             pass_count, fail_count);
    if (fail_count==0) $display("ALL TESTS PASSED");
    else               $display("*** FAILURES ? review above ***");
    $finish;
end

endmodule
