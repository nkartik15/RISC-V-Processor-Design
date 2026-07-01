// ====================================================================
// tb_data_memory.v  ?  datamemory unit testbench
//
// The module under test:
//   - Synchronous write  (posedge clk, memWrite=1)
//   - Combinational read (memRead=1, address < N*4)
//   - Byte-addressed (little-endian); word access uses byte address
//   - Returns 32'd0 for out-of-bounds or memRead=0 address
//
// Test cases  (one per distinct logical path)
// ??????????
//  1. Basic write then read-back (happy path)
//  2. Sync-write / comb-read timing: read returns OLD value on the
//     same cycle as write, NEW value on next cycle
//  3. memWrite=0 guard: data must not change
//  4. memRead=0: readData must be 32'd0 regardless of address content
//  5. Aligned word addressing (4-byte aligned LW/SW)
//  6. Multiple independent addresses (no aliasing between indices)
//  7. Out-of-bounds address (>= N*4 = 1024): readData = 32'd0
//  8. Boundary address: last valid word (address = (N-1)*4 = 1020)
// ====================================================================
`timescale 1ns/1ps

module tb_data_memory;

reg         clk, memRead, memWrite;
reg  [31:0] address, writeData;
wire [31:0] readData;
wire [2:0] funct3;

datamemory DUT (
    .clk      (clk),
    .memRead  (memRead),
    .memWrite (memWrite),
    .address  (address),
    .writeData(writeData),
    .readData (readData),
    .funct3(funct3)
);

integer pass_count, fail_count, i;

initial clk=0; 
always #5 clk = ~clk;

task check;
    input [200:0] name;
    input [31:0]  exp;
    begin
        if (readData === exp) begin
            $display("PASS [%0s]  got=%08h", name, readData);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0s]  got=%08h  exp=%08h", name, readData, exp);
            fail_count = fail_count + 1;
        end
    end
endtask

// Helper: perform one synchronous write
task do_write;
    input [31:0] addr, data;
    begin
        address=addr; writeData=data; memWrite=1'b1; memRead=1'b0;
        @(posedge clk); #1;
        memWrite = 1'b0;
    end
endtask

// Helper: set up combinational read and check immediately
task do_read_check;
    input [31:0]  addr;
    input [200:0] name;
    input [31:0]  exp;
    begin
        address=addr; memRead=1'b1; memWrite=1'b0;
        #1; check(name, exp);
    end
endtask

initial begin
    pass_count=0; fail_count=0;
    memRead=0; memWrite=0; address=0; writeData=0;
    $display("=== DATA MEMORY TESTBENCH ===");

    // Initialise all memory to 0 so tests start from a known state
    for (i=0; i<1024; i=i+1)
        DUT.memory[i] = 8'd0;

    // ----------------------------------------------------------------
    // TEST 1: Basic write then read-back
    // ----------------------------------------------------------------
    $display("-- basic write / read-back");
    do_write(32'd0, 32'hDEAD_BEEF);
    do_read_check(32'd0, "basic_readback", 32'hDEAD_BEEF);

    // ----------------------------------------------------------------
    // TEST 2: Sync-write / comb-read timing
    // On the SAME clock edge that the write occurs the combinational
    // read should still return the OLD value (before the write latches).
    // The NEW value appears in the next evaluation after clk rises.
    // ----------------------------------------------------------------
    $display("-- sync-write / comb-read timing");
    // Set up a fresh address with known old value = 0
    for (i=0; i<1024; i=i+1) DUT.memory[i] = 8'd0;

    address=32'd8; writeData=32'hCAFE_CAFE; memWrite=1'b1; memRead=1'b1;
    // Sample BEFORE posedge ? must see old value (0)
    #1; check("timing_before_clk", 32'd0);

    @(posedge clk); #1;   // write latches here
    memWrite=1'b0;
    // Sample AFTER posedge ? must see new value
    check("timing_after_clk", 32'hCAFE_CAFE);

    // ----------------------------------------------------------------
    // TEST 3: memWrite=0 does not modify memory
    // ----------------------------------------------------------------
    $display("-- memWrite=0 guard");
    do_write(32'd4, 32'hAAAA_AAAA);   // valid write first
    address=32'd4; writeData=32'h1234_5678; memWrite=1'b0; memRead=1'b0;
    @(posedge clk); #1;               // clock with write disabled
    do_read_check(32'd4, "write_guard", 32'hAAAA_AAAA);

    // ----------------------------------------------------------------
    // TEST 4: memRead=0 ? readData = 32'd0
    // (Even if the address is valid and contains data.)
    // ----------------------------------------------------------------
    $display("-- memRead=0 returns 0");
    // Ensure the word at address 0 has non-zero content
    do_write(32'd0, 32'hBEEF_CAFE);
    address=32'd0; memRead=1'b0; memWrite=1'b0;
    #1; check("memread_0_gate", 32'd0);

    // ----------------------------------------------------------------
    // TEST 5: Aligned word addressing (LW uses byte address; unaligned LW not tested)
    // ----------------------------------------------------------------
    $display("-- aligned word addressing");
    do_write(32'd0, 32'h1234_5678);
    do_read_check(32'd0, "word_addr_aligned0", 32'h1234_5678);
    // Address 4 must NOT alias to address 0
    do_write(32'd4, 32'hABCD_EF01);
    do_read_check(32'd4, "word_addr_next",  32'hABCD_EF01);
    do_read_check(32'd0, "word_addr_no_alias", 32'h1234_5678);

    // ----------------------------------------------------------------
    // TEST 6: Multiple independent addresses (no aliasing)
    // Write distinct values to several words, read back all of them.
    // ----------------------------------------------------------------
    $display("-- multiple independent addresses");
    do_write(32'd0,  32'h0000_0001);
    do_write(32'd4,  32'h0000_0002);
    do_write(32'd8,  32'h0000_0003);
    do_write(32'd12, 32'h0000_0004);
    do_read_check(32'd0,  "multi_addr_0",  32'h0000_0001);
    do_read_check(32'd4,  "multi_addr_4",  32'h0000_0002);
    do_read_check(32'd8,  "multi_addr_8",  32'h0000_0003);
    do_read_check(32'd12, "multi_addr_12", 32'h0000_0004);

    // ----------------------------------------------------------------
    // TEST 7: Out-of-bounds address (>= N*4 = 1024) ? readData = 0
    // ----------------------------------------------------------------
    $display("-- out-of-bounds address returns 0");
    address=32'd1024; memRead=1'b1; memWrite=1'b0;
    #1; check("oob_addr_1024", 32'd0);

    address=32'hFFFF_FFFC; memRead=1'b1;
    #1; check("oob_addr_max",  32'd0);

    // ----------------------------------------------------------------
    // TEST 8: Last valid address (N-1)*4 = 255*4 = 1020
    // ----------------------------------------------------------------
    $display("-- boundary: last valid address (1020)");
    do_write(32'd1020, 32'hF00D_FACE);
    do_read_check(32'd1020, "boundary_last_word", 32'hF00D_FACE);

    // One past the last valid address ? 0
    address=32'd1024; memRead=1'b1; memWrite=1'b0;
    #1; check("boundary_one_past", 32'd0);

    // ----------------------------------------------------------------
    // SUMMARY
    // ----------------------------------------------------------------
    $display("\n=== RESULTS: %0d passed, %0d failed ===",
             pass_count, fail_count);
    if (fail_count==0) $display("ALL TESTS PASSED");
    else               $display("*** FAILURES ? review above ***");
    $finish;
end
assign funct3=3'b010;
endmodule
