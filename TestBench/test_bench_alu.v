// ====================================================================
// tb_alu.v  ?  ALU unit testbench  (focused, ~25 checks)
// Tests every distinct logical path through alu.v without redundancy.
// ====================================================================
`timescale 1ns/1ps

module tb_alu;

reg  [31:0] operand_a, operand_b;
reg  [ 3:0] alu_control;
wire [31:0] alu_result;
wire        zero_flag, comp_flag, carry_flag, sign_bit, borrow, overflow;

// ALU control encoding ? matches alu.v localparams
localparam ADD=4'b0000, SUB=4'b1000, AND=4'b0111, OR=4'b0110,
           XOR=4'b0100, SLT=4'b0010, SLL=4'b0001, SRL=4'b0101,
           SRA=4'b1101;

localparam MAX_POS  = 32'h7FFF_FFFF;
localparam MIN_NEG  = 32'h8000_0000;
localparam ALL_ONES = 32'hFFFF_FFFF;

integer pass_count, fail_count;

alu DUT (
    .operand_a  (operand_a),   .operand_b  (operand_b),
    .alu_control(alu_control),
    .alu_result (alu_result),  .zero_flag  (zero_flag),
    .comp_flag  (comp_flag),   .carry_flag (carry_flag),
    .sign_bit   (sign_bit),    .borrow     (borrow),
    .overflow   (overflow)
);

// ?? check task: pass 1'bx for flags you don't care about ????????????
task check;
    input [200:0] name;
    input [31:0]  exp_result;
    input         exp_zero, exp_carry, exp_borrow, exp_overflow,
                  exp_sign, exp_comp;
    reg failed;
    begin
        #2; failed = 0;
        if (alu_result   !== exp_result)                           begin $display("FAIL [%0s] result   got=%08h exp=%08h", name, alu_result,  exp_result);  failed=1; end
        if (exp_zero     !== 1'bx && zero_flag  !== exp_zero)     begin $display("FAIL [%0s] zero     got=%b    exp=%b",  name, zero_flag,   exp_zero);    failed=1; end
        if (exp_carry    !== 1'bx && carry_flag !== exp_carry)    begin $display("FAIL [%0s] carry    got=%b    exp=%b",  name, carry_flag,  exp_carry);   failed=1; end
        if (exp_borrow   !== 1'bx && borrow     !== exp_borrow)   begin $display("FAIL [%0s] borrow   got=%b    exp=%b",  name, borrow,      exp_borrow);  failed=1; end
        if (exp_overflow !== 1'bx && overflow   !== exp_overflow) begin $display("FAIL [%0s] overflow got=%b    exp=%b",  name, overflow,    exp_overflow);failed=1; end
        if (exp_sign     !== 1'bx && sign_bit   !== exp_sign)     begin $display("FAIL [%0s] sign     got=%b    exp=%b",  name, sign_bit,    exp_sign);    failed=1; end
        if (exp_comp     !== 1'bx && comp_flag  !== exp_comp)     begin $display("FAIL [%0s] comp     got=%b    exp=%b",  name, comp_flag,   exp_comp);    failed=1; end
        if (!failed) begin $display("PASS [%0s]", name); pass_count=pass_count+1; end
        else         fail_count = fail_count + 1;
    end
endtask

initial begin
    pass_count=0; fail_count=0;
    $display("=== ALU TESTBENCH ===");

    // ?? ADD ?????????????????????????????????????????????????????????
    $display("-- ADD");
    alu_control=ADD; operand_a=32'd15;   operand_b=32'd10;
    check("ADD_typical",    32'd25,      1'b0,1'bx,1'bx,1'b0,1'b0,1'bx);

    alu_control=ADD; operand_a=32'd5;    operand_b=32'hFFFF_FFFB; // 5+(-5)=0
    check("ADD_zero",       32'd0,       1'b1,1'b1,1'bx,1'b0,1'b0,1'bx);

    alu_control=ADD; operand_a=MAX_POS;  operand_b=32'd1;          // +ve overflow
    check("ADD_overflow",   MIN_NEG,     1'b0,1'b0,1'bx,1'b1,1'b1,1'bx);

    // ?? SUB ?????????????????????????????????????????????????????????
    $display("-- SUB");
    alu_control=SUB; operand_a=32'd20;   operand_b=32'd7;
    check("SUB_typical",    32'd13,      1'b0,1'b1,1'b0,1'b0,1'b0,1'bx);

    alu_control=SUB; operand_a=32'd3;    operand_b=32'd5;           // borrow
    check("SUB_borrow",     32'hFFFF_FFFE,1'b0,1'b0,1'b1,1'b0,1'b1,1'bx);

    alu_control=SUB; operand_a=MIN_NEG;  operand_b=32'd1;           // -ve overflow
    check("SUB_overflow",   MAX_POS,     1'b0,1'b1,1'b0,1'b1,1'b0,1'bx);

    // ?? AND ?????????????????????????????????????????????????????????
    $display("-- AND");
    alu_control=AND; operand_a=32'hF0F0_F0F0; operand_b=32'hA5A5_A5A5;
    check("AND_typical",    32'hA0A0_A0A0,1'b0,1'bx,1'bx,1'bx,1'b1,1'bx);

    alu_control=AND; operand_a=32'hAAAA_AAAA; operand_b=32'h5555_5555;
    check("AND_zero",       32'd0,         1'b1,1'bx,1'bx,1'bx,1'b0,1'bx);

    // ?? OR ??????????????????????????????????????????????????????????
    $display("-- OR");
    alu_control=OR;  operand_a=32'hA5A5_A5A5; operand_b=32'h5A5A_5A5A;
    check("OR_typical",     ALL_ONES,      1'b0,1'bx,1'bx,1'bx,1'b1,1'bx);

    alu_control=OR;  operand_a=32'h1234_5678; operand_b=32'd0;
    check("OR_identity",    32'h1234_5678,  1'b0,1'bx,1'bx,1'bx,1'b0,1'bx);

    // ?? XOR ?????????????????????????????????????????????????????????
    $display("-- XOR");
    alu_control=XOR; operand_a=32'hFFFF_0000; operand_b=32'h0000_FFFF;
    check("XOR_typical",    ALL_ONES,      1'b0,1'bx,1'bx,1'bx,1'b1,1'bx);

    alu_control=XOR; operand_a=32'hDEAD_BEEF; operand_b=32'hDEAD_BEEF;
    check("XOR_self_zero",  32'd0,         1'b1,1'bx,1'bx,1'bx,1'b0,1'bx);

    // ?? SLT ?????????????????????????????????????????????????????????
    $display("-- SLT");
    alu_control=SLT; operand_a=32'd3;     operand_b=32'd7;      // pos < pos ? 1
    check("SLT_pos_less",   32'd1,        1'b0,1'bx,1'bx,1'bx,1'b0,1'b1);

    alu_control=SLT; operand_a=ALL_ONES;  operand_b=32'd1;      // neg < pos ? 1
    check("SLT_neg_lt_pos", 32'd1,        1'b0,1'bx,1'bx,1'bx,1'b0,1'b1);

    alu_control=SLT; operand_a=32'd5;     operand_b=32'd5;      // equal ? 0
    check("SLT_equal",      32'd0,        1'b1,1'bx,1'bx,1'bx,1'b0,1'b0);

    // ?? SLL ?????????????????????????????????????????????????????????
    $display("-- SLL");
    alu_control=SLL; operand_a=32'h0000_00FF; operand_b=32'd0;
    check("SLL_by0",        32'h0000_00FF, 1'b0,1'bx,1'bx,1'bx,1'b0,1'bx);

    alu_control=SLL; operand_a=32'h0000_0001; operand_b=32'd1;
    check("SLL_by1",        32'h0000_0002,  1'b0,1'bx,1'bx,1'bx,1'b0,1'bx);

    alu_control=SLL; operand_a=32'h0000_0001; operand_b=32'd31; // only MSB survives
    check("SLL_by31",       MIN_NEG,          1'b0,1'bx,1'bx,1'bx,1'b1,1'bx);

    // ?? SRL ?????????????????????????????????????????????????????????
    $display("-- SRL");
    alu_control=SRL; operand_a=32'h8000_0000; operand_b=32'd1;  // MSB ? 0, not replicated
    check("SRL_by1",        32'h4000_0000,  1'b0,1'bx,1'bx,1'bx,1'b0,1'bx);

    alu_control=SRL; operand_a=32'h8000_0000; operand_b=32'd31;
    check("SRL_by31",       32'd1,           1'b0,1'bx,1'bx,1'bx,1'b0,1'bx);

    // ?? SRA ?????????????????????????????????????????????????????????
    $display("-- SRA");
    alu_control=SRA; operand_a=32'h0800_0000; operand_b=32'd4;  // positive: 0 fills
    check("SRA_positive",   32'h0080_0000,  1'b0,1'bx,1'bx,1'bx,1'b0,1'bx);

    alu_control=SRA; operand_a=MIN_NEG;       operand_b=32'd4;  // negative: 1 fills
    check("SRA_negative",   32'hF800_0000,  1'b0,1'bx,1'bx,1'bx,1'b1,1'bx);

    alu_control=SRA; operand_a=MIN_NEG;       operand_b=32'd31; // all bits become sign
    check("SRA_by31",       ALL_ONES,        1'b0,1'bx,1'bx,1'bx,1'b1,1'bx);

    // ?? CSLA: carry must ripple across all four 8-bit block boundaries
    $display("-- CSLA");
    alu_control=ADD; operand_a=ALL_ONES;  operand_b=32'd1;
    check("CSLA_full_ripple", 32'd0,      1'b1,1'b1,1'bx,1'b0,1'b0,1'bx);

    // ?? SUMMARY ?????????????????????????????????????????????????????
    $display("\n=== RESULTS: %0d passed, %0d failed ===",
             pass_count, fail_count);
    if (fail_count==0) $display("ALL TESTS PASSED");
    else               $display("*** FAILURES ? review above ***");
    $finish;
end

endmodule
