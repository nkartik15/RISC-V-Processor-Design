`timescale 1ns/1ps
`include "pipeline_pkg.v"

module tb_pipeline;
reg clk, reset;
// Extension ports
wire [4:0] pwr_stage_active;
wire       sec_fault;
wire       macro_stall_ack;

cpu_pipeline DUT (
    .clk             (clk),
    .reset           (reset),
    .pwr_stall_req   (1'b0),
    .pwr_stage_active(pwr_stage_active),
    .sec_tag_in      (16'hABCD),
    .sec_fault       (sec_fault),
    .macro_valid     (1'b0),
    .macro_instr     (32'd0),
    .macro_stall_ack (macro_stall_ack)
);

// Load a tiny test program into instruction memory
// Instruction set:
//  0: addi x1, x0, 5       0x00500093
//  1: addi x2, x0, 3       0x00300113
//  2: add  x3, x1, x2      0x002081B3
//  3: sw   x3, 0(x0)       0x00302023
//  4: lw   x4, 0(x0)       0x00002203
//  5: bne  x4, x3, -4      0xFE321EE3  (should NOT branch -> x4==x3)
//  6: addi x5, x0, 7       0x00700293
//  7+ : nop loop
integer i;
initial begin
    // Initialize instruction memory
    for (i = 0; i < 256; i = i+1)
        DUT.IMEM.memory[i] = 32'h0000_0013;  // NOP

    DUT.IMEM.memory[0] = 32'h00500093;  // addi x1, x0, 5
    DUT.IMEM.memory[1] = 32'h00300113;  // addi x2, x0, 3
    DUT.IMEM.memory[2] = 32'h002081B3;  // add  x3, x1, x2
    DUT.IMEM.memory[3] = 32'h00302023;  // sw   x3, 0(x0)
    DUT.IMEM.memory[4] = 32'h00002203;  // lw   x4, 0(x0)
    DUT.IMEM.memory[5] = 32'hFE321EE3;  // bne  x4, x3, -4  (corrected encoding)
    DUT.IMEM.memory[6] = 32'h00700293;  // addi x5, x0, 7

    clk = 0; reset = 1;
    #15 reset = 0;
    #200;

    $display("x1 = %0d (expect 5)", DUT.RF.register_array[1]);
    $display("x2 = %0d (expect 3)", DUT.RF.register_array[2]);
    $display("x3 = %0d (expect 8)", DUT.RF.register_array[3]);
    $display("x4 = %0d (expect 8)", DUT.RF.register_array[4]);
    $display("x5 = %0d (expect 7)", DUT.RF.register_array[5]);
    $display("pwr_stage_active = %05b", pwr_stage_active);
    $display("DONE");
    $finish;
end

always #5 clk = ~clk;
endmodule
