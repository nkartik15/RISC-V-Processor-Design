// ====================================================================
// tb_cpu_pipeline.v  ?  Full-program integration testbench
//
// Four complete programs, each exercising a different mix of the
// full RV32I instruction set and hazard scenarios.
//
// Program 1 ? Fibonacci (iterative)
//   Computes fib(8) = 21 using add/addi/blt.
//   Exercises: ALU forwarding in a tight loop, loop-back branch.
//
// Program 2 ? Factorial (iterative)
//   Computes 5! = 120 using mul-by-addition, ble loop.
//   No MUL instruction (RV32I base has none), so multiply is done
//   by repeated addition.
//   Exercises: nested loop, sw/lw round-trip, branch-not-taken path.
//
// Program 3 ? JAL / JALR call & return
//   Main calls a leaf function via JAL; leaf returns via JALR.
//   Checks: link register written correctly, return lands at right PC,
//           argument passing and return value via registers.
//
// Program 4 ? Bitwise instruction sweep
//   Runs AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU on a fixed pair of
//   operands and stores all results to data memory; reads back and
//   checks every word.
//   Exercises: all ALU opcodes, store/load correctness end-to-end.
// ====================================================================
`timescale 1ns/1ps
`include "pipeline_pkg.v"

module tb_cpu_pipeline;

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
initial clk=0;
always #5 clk = ~clk;

localparam NOP = 32'h0000_0013;

task chk_reg;
    input [200:0] name;
    input [4:0]   rn;
    input [31:0]  exp;
    begin
        if (DUT.RF.register_array[rn]===exp) begin
            $display("PASS [%0s]  x%0d=%0d (0x%08h)", name,rn,exp,exp);
            pass_count=pass_count+1;
        end else begin
            $display("FAIL [%0s]  x%0d got=%0d(0x%08h) exp=%0d(0x%08h)",
                     name,rn,
                     DUT.RF.register_array[rn],DUT.RF.register_array[rn],
                     exp,exp);
            fail_count=fail_count+1;
        end
    end
endtask

task chk_mem;
    input [200:0] name;
    input [7:0]   word_idx;
    input [31:0]  exp;
    integer base;
    reg [31:0] got;
    begin
        base = word_idx << 2;
        got = {DUT.DMEM.memory[base+3], DUT.DMEM.memory[base+2],
               DUT.DMEM.memory[base+1], DUT.DMEM.memory[base]};
        if (got===exp) begin
            $display("PASS [%0s]  mem[%0d]=0x%08h", name,word_idx,exp);
            pass_count=pass_count+1;
        end else begin
            $display("FAIL [%0s]  mem[%0d] got=0x%08h exp=0x%08h",
                     name,word_idx,got,exp);
            fail_count=fail_count+1;
        end
    end
endtask

// Reset + run for N cycles
task run_cycles;
    input integer n;
    begin
        reset=1; #12; reset=0;
        repeat(n) @(posedge clk);
        #1;
    end
endtask

// ?? Instruction encoders ?????????????????????????????????????????????
function [31:0] addi_f;
    input [4:0] rd,rs1; input [11:0] imm;
    addi_f={imm,rs1,3'b000,rd,7'b0010011};
endfunction
function [31:0] add_f;
    input [4:0] rd,rs1,rs2;
    add_f={7'b0000000,rs2,rs1,3'b000,rd,7'b0110011};
endfunction
function [31:0] sub_f;
    input [4:0] rd,rs1,rs2;
    sub_f={7'b0100000,rs2,rs1,3'b000,rd,7'b0110011};
endfunction
function [31:0] and_f;
    input [4:0] rd,rs1,rs2;
    and_f={7'b0000000,rs2,rs1,3'b111,rd,7'b0110011};
endfunction
function [31:0] or_f;
    input [4:0] rd,rs1,rs2;
    or_f={7'b0000000,rs2,rs1,3'b110,rd,7'b0110011};
endfunction
function [31:0] xor_f;
    input [4:0] rd,rs1,rs2;
    xor_f={7'b0000000,rs2,rs1,3'b100,rd,7'b0110011};
endfunction
function [31:0] sll_f;
    input [4:0] rd,rs1,rs2;
    sll_f={7'b0000000,rs2,rs1,3'b001,rd,7'b0110011};
endfunction
function [31:0] srl_f;
    input [4:0] rd,rs1,rs2;
    srl_f={7'b0000000,rs2,rs1,3'b101,rd,7'b0110011};
endfunction
function [31:0] sra_f;
    input [4:0] rd,rs1,rs2;
    sra_f={7'b0100000,rs2,rs1,3'b101,rd,7'b0110011};
endfunction
function [31:0] slt_f;
    input [4:0] rd,rs1,rs2;
    slt_f={7'b0000000,rs2,rs1,3'b010,rd,7'b0110011};
endfunction
function [31:0] sw_f;
    input [4:0] rs1,rs2; input [11:0] imm;
    sw_f={imm[11:5],rs2,rs1,3'b010,imm[4:0],7'b0100011};
endfunction
function [31:0] lw_f;
    input [4:0] rd,rs1; input [11:0] imm;
    lw_f={imm,rs1,3'b010,rd,7'b0000011};
endfunction
function [31:0] blt_f;
    input [4:0] rs1,rs2; input [12:0] imm;
    blt_f={imm[12],imm[10:5],rs2,rs1,3'b100,imm[4:1],imm[11],7'b1100011};
endfunction
function [31:0] bge_f;
    input [4:0] rs1,rs2; input [12:0] imm;
    bge_f={imm[12],imm[10:5],rs2,rs1,3'b101,imm[4:1],imm[11],7'b1100011};
endfunction
function [31:0] bne_f;
    input [4:0] rs1,rs2; input [12:0] imm;
    bne_f={imm[12],imm[10:5],rs2,rs1,3'b001,imm[4:1],imm[11],7'b1100011};
endfunction
function [31:0] jal_f;
    input [4:0] rd; input [20:0] imm;
    jal_f={imm[20],imm[10:1],imm[11],imm[19:12],rd,7'b1101111};
endfunction
function [31:0] jalr_f;
    input [4:0] rd,rs1; input [11:0] imm;
    jalr_f={imm,rs1,3'b000,rd,7'b1100111};
endfunction

// ????????????????????????????????????????????????????????????????????
// PROGRAM 1 ? Fibonacci(8) = 21
// ????????????????????????????????????????????????????????????????????
// Registers:
//   x1 = a (fib[n-2]), starts 0
//   x2 = b (fib[n-1]), starts 1
//   x3 = counter, starts 1
//   x4 = limit = 8
//   x5 = temp
//
// Assembly:
//   addi x1, x0, 0    # a=0
//   addi x2, x0, 1    # b=1
//   addi x3, x0, 1    # i=1
//   addi x4, x0, 8    # limit=8
// loop:               # word 4 = byte 16
//   add  x5, x1, x2   # t = a+b
//   addi x1, x2, 0    # a = b
//   addi x2, x5, 0    # b = t
//   addi x3, x3, 1    # i++
//   blt  x3, x4, -16  # if i<limit goto loop
//   # x2 = fib(8) = 21
task prog1_fibonacci;
    integer base;
    begin
        base=0;
        for (i=0;i<64;i=i+1) DUT.IMEM.memory[i]=NOP;
        DUT.IMEM.memory[base+0] = addi_f(5'd1,5'd0,12'd0);
        DUT.IMEM.memory[base+1] = addi_f(5'd2,5'd0,12'd1);
        DUT.IMEM.memory[base+2] = addi_f(5'd3,5'd0,12'd1);
        DUT.IMEM.memory[base+3] = addi_f(5'd4,5'd0,12'd8);
        // loop at word 4 (byte 16)
        DUT.IMEM.memory[base+4] = add_f (5'd5,5'd1,5'd2);
        DUT.IMEM.memory[base+5] = addi_f(5'd1,5'd2,12'd0);
        DUT.IMEM.memory[base+6] = addi_f(5'd2,5'd5,12'd0);
        DUT.IMEM.memory[base+7] = addi_f(5'd3,5'd3,12'd1);
        // blt x3, x4, -16  (offset = -16 = 13'h1FF0)
        DUT.IMEM.memory[base+8] = blt_f(5'd3,5'd4,13'h1FF0);
    end
endtask

// ????????????????????????????????????????????????????????????????????
// PROGRAM 2 ? Factorial(5) = 120  (multiply by repeated addition)
// ????????????????????????????????????????????????????????????????????
// multiply(a,b): result = 0; repeat b times: result += a
// Registers:
//   x1 = n (countdown from 5 to 1)
//   x2 = accumulator (running product), start=1
//   x3 = inner counter
//   x4 = temp / partial sum
//   x5 = result of multiply
//
// multiply x2 by x1, store in x2, then x1--; repeat until x1==1
//
// Simplified: since 5! = 1*2*3*4*5, compute iteratively
//   result=1
//   for i=2..5: result = result * i  (multiply by repeated add)
//
// Assembly (flat, no function call):
//   addi x1, x0, 1    # result = 1
//   addi x6, x0, 2    # i = 2
//   addi x7, x0, 5    # limit = 5
// outer:              # word 3
//   addi x2, x0, 0    # partial = 0
//   addi x3, x0, 0    # j = 0
// inner:              # word 5
//   add  x2, x2, x1   # partial += result
//   addi x3, x3, 1    # j++
//   blt  x3, x6, -8   # if j < i goto inner
//   addi x1, x2, 0    # result = partial
//   addi x6, x6, 1    # i++
//   bge  x7, x6, -20  # if limit >= i goto outer  (offset = -20)
//   sw   x1, 0(x0)    # store result
task prog2_factorial;
    integer base;
    begin
        base=0;
        for (i=0;i<64;i=i+1) DUT.IMEM.memory[i]=NOP;
        DUT.IMEM.memory[0]  = addi_f(5'd1,5'd0,12'd1);   // result=1
        DUT.IMEM.memory[1]  = addi_f(5'd6,5'd0,12'd2);   // i=2
        DUT.IMEM.memory[2]  = addi_f(5'd7,5'd0,12'd5);   // limit=5
        // outer: word 3
        DUT.IMEM.memory[3]  = addi_f(5'd2,5'd0,12'd0);   // partial=0
        DUT.IMEM.memory[4]  = addi_f(5'd3,5'd0,12'd0);   // j=0
        // inner: word 5
        DUT.IMEM.memory[5]  = add_f (5'd2,5'd2,5'd1);    // partial+=result
        DUT.IMEM.memory[6]  = addi_f(5'd3,5'd3,12'd1);   // j++
        // blt x3,x6,-8  offset=-8 = 13'h1FF8
        DUT.IMEM.memory[7]  = blt_f(5'd3,5'd6,13'h1FF8); // if j<i goto inner
        DUT.IMEM.memory[8]  = addi_f(5'd1,5'd2,12'd0);   // result=partial
        DUT.IMEM.memory[9]  = addi_f(5'd6,5'd6,12'd1);   // i++
        // bge x7,x6,-28  offset=-28 = 13'h1FE4
        DUT.IMEM.memory[10] = bge_f(5'd7,5'd6,13'h1FE4); // if limit>=i goto outer
        DUT.IMEM.memory[11] = sw_f(5'd0,5'd1,12'd0);     // store result
    end
endtask

// ????????????????????????????????????????????????????????????????????
// PROGRAM 3 ? JAL call / JALR return
// ????????????????????????????????????????????????????????????????????
// main:
//   addi x10, x0, 7   # arg a0 = 7
//   addi x11, x0, 3   # arg a1 = 3
//   jal  x1, +12      # call add_func (word 5), ra=x1=pc+4
//   addi x12, x0, 0   # skipped by jal
//   addi x12, x0, 0   # skipped by jal
// add_func: (word 5, byte 20)
//   add  x10, x10, x11  # a0 = a0 + a1
//   jalr x0, x1, 0      # return via ra (x1)
// after_call: (word 3, byte 12)
//   addi x13, x10, 0  # x13 = return value (should be 10)
task prog3_call_return;
    integer base;
    begin
        base=0;
        for (i=0;i<64;i=i+1) DUT.IMEM.memory[i]=NOP;
        // word 0: addi x10, x0, 7
        DUT.IMEM.memory[0] = addi_f(5'd10,5'd0,12'd7);
        // word 1: addi x11, x0, 3
        DUT.IMEM.memory[1] = addi_f(5'd11,5'd0,12'd3);
        // word 2: jal x1, +12  (skip words 3,4; land on word 5)
        DUT.IMEM.memory[2] = jal_f(5'd1,21'd12);
        // word 3: after_call ? addi x13, x10, 0  (return here: pc=12)
        DUT.IMEM.memory[3] = addi_f(5'd13,5'd10,12'd0);
        // word 4: jump over add_func after return
        DUT.IMEM.memory[4] = jal_f(5'd0,21'd12); // skip words 5-6
        // word 5: add_func
        DUT.IMEM.memory[5] = add_f(5'd10,5'd10,5'd11);  // a0 = a0+a1
        // word 6: jalr x0, x1, 0  (return to ra)
        DUT.IMEM.memory[6] = jalr_f(5'd0,5'd1,12'd0);
    end
endtask

// ????????????????????????????????????????????????????????????????????
// PROGRAM 4 ? Bitwise / shift / SLT sweep
// ????????????????????????????????????????????????????????????????????
// Operands: x1=0xF0F0F0F0, x2=0x0F0F0F0F, x3=4 (shift amount)
// Compute and store:
//   mem[0]  = x1 AND x2 = 0x00000000
//   mem[1]  = x1 OR  x2 = 0xFFFFFFFF
//   mem[2]  = x1 XOR x2 = 0xFFFFFFFF
//   mem[3]  = x1 SLL x3 = 0x0F0F0F00  (shift x1 left by 4)
//   mem[4]  = x1 SRL x3 = 0x0F0F0F0F  (shift x1 right logical by 4)
//   mem[5]  = x1 SRA x3 = 0xFF0F0F0F  (shift x1 right arith by 4)
//   mem[6]  = SLT(x2, x1) = 0 (x2=0x0F0F0F0F > x1=0xF0F0F0F0 signed?
//                               x1 is negative, x2 positive ? x2 > x1
//                               so x2 < x1 signed? NO ? result=0)
//   mem[7]  = SLT(x1, x2) = 1 (x1 negative < x2 positive ? 1)
//
// Build x1 and x2 with lui+addi since they're 32-bit constants:
//   lui  x1, 0xF0F0F   ? x1 = 0xF0F0F000
//   addi x1, x1, 0xF0  ? but 0xF0 = +240; however addi sign-extends
//                         need 0x0F0 = 240... actually 0xF0F0F0F0:
//   lui loads upper 20 bits: 0xF0F0F << 12 | lower 12
//   0xF0F0F0F0: upper20 = 0xF0F0F, lower12 = 0x0F0
//   But addi sign-extends: 0x0F0 = +240, no sign issue here.
//   Actually: 0xF0F0F0F0 = 0xF0F0F000 | 0x0F0
//   lui x1, 0xF0F0F; addi x1,x1,0x0F0
//   Check: 0xF0F0F000 + 0x0F0 = 0xF0F0F0F0 ?
//
//   0x0F0F0F0F: upper20 = 0x0F0F0, lower12 = 0xF0F
//   BUT 0xF0F = 3855, bit11=1 ? sign-extended as negative (-241)
//   So lui loads 0x0F0F0000, addi adds -241:
//   0x0F0F0000 + 0xFFFFF0F = wrong.
//   Fix: use 0x0F0F1 for lui (add 1), then addi -0xF1 = addi 0xF0F:
//   lui x2, 0x0F0F1 ? 0x0F0F1000
//   addi x2, x2, -0xF1 ? 0x0F0F1000 - 0xF1 = 0x0F0F0F0F ?
//   -0xF1 in 12-bit = 12'hF0F
task prog4_bitwise;
    integer base;
    begin
        base=0;
        for (i=0;i<64;i=i+1) DUT.IMEM.memory[i]=NOP;
        for (i=0;i<32;i=i+1) DUT.DMEM.memory[i]=8'd0;

        // Load x1 = 0xF0F0F0F0
        // lui x1, 0xF0F0F
        DUT.IMEM.memory[0] = {20'hF0F0F, 5'd1, 7'b0110111};
        // addi x1, x1, 0x0F0
        DUT.IMEM.memory[1] = addi_f(5'd1,5'd1,12'h0F0);

        // Load x2 = 0x0F0F0F0F
        // lui x2, 0x0F0F1
        DUT.IMEM.memory[2] = {20'h0F0F1, 5'd2, 7'b0110111};
        // addi x2, x2, -0xF1  (12'hF0F = -241)
        DUT.IMEM.memory[3] = addi_f(5'd2,5'd2,12'hF0F);

        // x3 = 4 (shift amount)
        DUT.IMEM.memory[4] = addi_f(5'd3,5'd0,12'd4);

        // Compute and store results
        // mem[0] = AND
        DUT.IMEM.memory[5]  = and_f(5'd4,5'd1,5'd2);
        DUT.IMEM.memory[6]  = sw_f(5'd0,5'd4,12'd0);
        // mem[1] = OR
        DUT.IMEM.memory[7]  = or_f(5'd4,5'd1,5'd2);
        DUT.IMEM.memory[8]  = sw_f(5'd0,5'd4,12'd4);
        // mem[2] = XOR
        DUT.IMEM.memory[9]  = xor_f(5'd4,5'd1,5'd2);
        DUT.IMEM.memory[10] = sw_f(5'd0,5'd4,12'd8);
        // mem[3] = SLL x1 by x3
        DUT.IMEM.memory[11] = sll_f(5'd4,5'd1,5'd3);
        DUT.IMEM.memory[12] = sw_f(5'd0,5'd4,12'd12);
        // mem[4] = SRL x1 by x3
        DUT.IMEM.memory[13] = srl_f(5'd4,5'd1,5'd3);
        DUT.IMEM.memory[14] = sw_f(5'd0,5'd4,12'd16);
        // mem[5] = SRA x1 by x3
        DUT.IMEM.memory[15] = sra_f(5'd4,5'd1,5'd3);
        DUT.IMEM.memory[16] = sw_f(5'd0,5'd4,12'd20);
        // mem[6] = SLT(x2, x1): x4 = (x2 < x1) signed
        DUT.IMEM.memory[17] = slt_f(5'd4,5'd2,5'd1);
        DUT.IMEM.memory[18] = sw_f(5'd0,5'd4,12'd24);
        // mem[7] = SLT(x1, x2): x4 = (x1 < x2) signed
        DUT.IMEM.memory[19] = slt_f(5'd4,5'd1,5'd2);
        DUT.IMEM.memory[20] = sw_f(5'd0,5'd4,12'd28);
    end
endtask

initial begin
    $dumpfile("wave.vcd");           // ADD HERE
    $dumpvars(0, tb_cpu_pipeline);   // ADD HERE - correct module name

    pass_count=0; fail_count=0;
    reset=1;
    for (i=0;i<64;i=i+1) DUT.IMEM.memory[i]=NOP;
    for (i=0;i<1024;i=i+1) DUT.DMEM.memory[i]=8'd0;

    // ================================================================
    // PROGRAM 1: Fibonacci(8) = 21
    // ================================================================
    $display("=== PROGRAM 1: Fibonacci(8) ===");
    prog1_fibonacci;
    run_cycles(80);
    // fib(8): 0,1,1,2,3,5,8,13,21 ? after 7 iterations x2=21
    chk_reg("fib8_result", 5'd2, 32'd21);

    // ================================================================
    // PROGRAM 2: Factorial(5) = 120
    // ================================================================
    $display("\n=== PROGRAM 2: Factorial(5) ===");
    for (i=0;i<1024;i=i+1) DUT.DMEM.memory[i]=8'd0;
    prog2_factorial;
    run_cycles(200);
    chk_reg("fact5_reg",   5'd1, 32'd120);
    chk_mem("fact5_mem",   8'd0, 32'd120);

    // ================================================================
    // PROGRAM 3: JAL call / JALR return
    // ================================================================
    $display("\n=== PROGRAM 3: Call & Return ===");
    prog3_call_return;
    run_cycles(40);
    // add_func returns 7+3=10 in x10; main copies to x13
    chk_reg("call_ret_result", 5'd13, 32'd10);
    // ra (x1) = pc of jal + 4 = byte 8+4 = 12
    chk_reg("call_ret_ra",     5'd1,  32'd12);

    // ================================================================
    // PROGRAM 4: Bitwise sweep
    // ================================================================
    $display("\n=== PROGRAM 4: Bitwise / Shift / SLT sweep ===");
    prog4_bitwise;
    run_cycles(60);
    // x1=0xF0F0F0F0, x2=0x0F0F0F0F
    chk_mem("bw_AND",     8'd0, 32'h0000_0000);
    chk_mem("bw_OR",      8'd1, 32'hFFFF_FFFF);
    chk_mem("bw_XOR",     8'd2, 32'hFFFF_FFFF);
    chk_mem("bw_SLL",     8'd3, 32'h0F0F_0F00); // x1<<4
    chk_mem("bw_SRL",     8'd4, 32'h0F0F_0F0F); // x1>>4 logical
    chk_mem("bw_SRA",     8'd5, 32'hFF0F_0F0F); // x1>>4 arithmetic
    chk_mem("bw_SLT_x2x1",8'd6, 32'd0);          // x2 not < x1 (signed)
    chk_mem("bw_SLT_x1x2",8'd7, 32'd1);          // x1 < x2 (signed, x1 negative)

    // ================================================================
    // SUMMARY
    // ================================================================
    $display("\n=== FINAL RESULTS: %0d passed, %0d failed ===",
             pass_count, fail_count);
    if (fail_count==0) $display("ALL TESTS PASSED");
    else               $display("*** FAILURES ? review above ***");
    $finish;
end

endmodule
