
// ====================================================================
// tb_register_file.v  ?  reg_array unit testbench (focused)
//
// Test cases (one per distinct logical path)
//  1. x0 always reads 0 regardless of write attempts
//  2. Reset zeroes all registers
//  3. write_enable=0 does not modify any register
//  4. Normal write then read-back (typical path)
//  5. Sync-write / comb-read timing: read gets OLD value same cycle
//     as write, NEW value on the next cycle
//  6. Simultaneous read of two different registers while a third
//     is being written
// ====================================================================
`timescale 1ns/1ps

module tb_register_file;

// ?? DUT ports ????????????????????????????????????????????????????????
reg        clk, rst, write_enable;
reg  [4:0] sr1, sr2, wr;
reg [31:0] wd;
wire[31:0] rs1, rs2;

// ?? Pass/fail tracking ???????????????????????????????????????????????
integer pass_count, fail_count;

// ?? DUT ??????????????????????????????????????????????????????????????
reg_array DUT (
    .clk(clk), .rst(rst), .write_enable(write_enable),
    .sr1(sr1), .sr2(sr2), .wr(wr), .wd(wd),
    .rs1(rs1), .rs2(rs2)
);

// 10 ns clock
always #5 clk = ~clk;

// ?? check task ???????????????????????????????????????????????????????
task check;
    input [200:0] name;
    input [31:0]  got, exp;
    begin
        if (got === exp) begin
            $display("PASS [%0s]  got=%08h", name, got);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0s]  got=%08h  exp=%08h", name, got, exp);
            fail_count = fail_count + 1;
        end
    end
endtask

// ?? helper: one write cycle ??????????????????????????????????????????
task write_reg;
    input [4:0]  reg_addr;
    input [31:0] data;
    begin
        wr = reg_addr; wd = data; write_enable = 1'b1;
        @(posedge clk); #1;       // let write latch, then settle 1ns
        write_enable = 1'b0;
    end
endtask

initial begin
    pass_count = 0; fail_count = 0;
    clk = 0; rst = 1; write_enable = 0;
    sr1 = 0; sr2 = 0; wr = 0; wd = 0;

    $display("=== REGISTER FILE TESTBENCH ===");

    // ----------------------------------------------------------------
    // TEST 1 : x0 hardwired to 0
    // Attempt to write a non-zero value to x0, then verify rs1 = 0.
    // write_enable=1 but the DUT guards wr==0 internally.
    // ----------------------------------------------------------------
    $display("-- x0 hardwired to 0");
    @(posedge clk); #1; rst = 0;   // come out of reset

    wr = 5'd0; wd = 32'hDEAD_BEEF; write_enable = 1'b1;
    @(posedge clk); #1;
    write_enable = 1'b0;

    sr1 = 5'd0;
    #1; check("x0_always_zero", rs1, 32'd0);

    // ----------------------------------------------------------------
    // TEST 2 : Reset zeroes all registers
    // Write a known value into x1, assert reset, verify x1 = 0.
    // ----------------------------------------------------------------
    $display("-- reset zeroes registers");
    write_reg(5'd1, 32'hCAFE_BABE);
    sr1 = 5'd1; #1;
    check("before_reset_x1", rs1, 32'hCAFE_BABE);  // confirm write worked

    rst = 1'b1;
    @(posedge clk); #1;
    rst = 1'b0;

    sr1 = 5'd1; #1;
    check("after_reset_x1",  rs1, 32'd0);

    // ----------------------------------------------------------------
    // TEST 3 : write_enable = 0 does not modify register
    // ----------------------------------------------------------------
    $display("-- write_enable guard");
    // First write a known value properly
    write_reg(5'd2, 32'hAAAA_AAAA);

    // Now try to overwrite with write_enable=0
    wr = 5'd2; wd = 32'h1234_5678; write_enable = 1'b0;
    @(posedge clk); #1;

    sr1 = 5'd2; #1;
    check("write_enable_guard", rs1, 32'hAAAA_AAAA);  // must be unchanged

    // ----------------------------------------------------------------
    // TEST 4 : Normal write then read-back
    // ----------------------------------------------------------------
    $display("-- normal write/read");
    write_reg(5'd3, 32'h1357_9BDF);
    sr1 = 5'd3; #1;
    check("write_readback", rs1, 32'h1357_9BDF);

    // ----------------------------------------------------------------
    // TEST 5 : Sync-write / comb-read timing
    // On the same clock edge that WB writes x4, a combinational read
    // of x4 must still return the OLD value (32'd0 after reset).
    // The NEW value appears one cycle later.
    // This is the exact scenario the WB?ID bypass in cpu_pipeline fixes.
    // ----------------------------------------------------------------
    $display("-- sync-write / comb-read timing");
    sr1 = 5'd4;          // point read port at x4
    wr  = 5'd4;
    wd  = 32'hBEEF_CAFE;
    write_enable = 1'b1;

    // Sample rs1 BEFORE the clock edge ? must be old value (0)
    #1; check("timing_before_clk", rs1, 32'd0);

    @(posedge clk); #1;  // write latches here
    write_enable = 1'b0;

    // Sample rs1 AFTER the clock edge ? must be new value
    check("timing_after_clk",  rs1, 32'hBEEF_CAFE);

    // ----------------------------------------------------------------
    // TEST 6 : Two simultaneous reads while a third register is written
    // ----------------------------------------------------------------
    $display("-- simultaneous dual read + write");
    write_reg(5'd5, 32'hAAAA_0000);
    write_reg(5'd6, 32'h0000_BBBB);

    // Read x5 and x6 while writing x7 ? reads must be unaffected
    sr1 = 5'd5; sr2 = 5'd6;
    wr  = 5'd7; wd  = 32'hFFFF_FFFF; write_enable = 1'b1;
    @(posedge clk); #1;
    write_enable = 1'b0;

    check("dual_read_rs1", rs1, 32'hAAAA_0000);
    check("dual_read_rs2", rs2, 32'h0000_BBBB);

    // Confirm x7 also got written correctly
    sr1 = 5'd7; #1;
    check("concurrent_write_x7", rs1, 32'hFFFF_FFFF);

    // ----------------------------------------------------------------
    // SUMMARY
    // ----------------------------------------------------------------
    $display("\n=== RESULTS: %0d passed, %0d failed ===",
             pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else                 $display("*** FAILURES ? review above ***");
    $finish;
end

endmodule
