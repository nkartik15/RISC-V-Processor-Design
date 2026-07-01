// ====================================================================
// tb_immediate_generator.v  ?  immediate_generator unit testbench
//
// Focus: correct bit-field extraction and placement for all 5 types.
// B-type and J-type are the highest risk ? 5 non-contiguous fragments
// each ? so they get an extra walking-1 test to isolate every bit.
//
// Test cases
// ??????????
//  1. I-type : typical positive, typical negative (sign-extend check)
//  2. S-type : typical positive, typical negative
//  3. B-type : typical offset, negative offset, LSB always 0,
//              walking-1 across all source bits
//  4. U-type : typical, lower 12 bits must be zero
//  5. J-type : typical offset, negative offset, LSB always 0,
//              walking-1 across all source bits
//  6. Default: unknown immSel ? 32'd0
// ====================================================================
`timescale 1ns/1ps

module tb_immediate_generator;

// ?? DUT ports ????????????????????????????????????????????????????????
reg  [31:0] instruction;
reg  [ 2:0] immSel;
wire [31:0] immOut;

// immSel encoding ? mirrors immediate_generator.v
localparam I_TYPE = 3'b000,
           S_TYPE = 3'b001,
           B_TYPE = 3'b010,
           U_TYPE = 3'b011,
           J_TYPE = 3'b100;

integer pass_count, fail_count;

// ?? DUT ??????????????????????????????????????????????????????????????
immediate_generator DUT (
    .instruction(instruction),
    .immSel     (immSel),
    .immOut     (immOut)
);

// ?? check task ???????????????????????????????????????????????????????
task check;
    input [200:0] name;
    input [31:0]  exp;
    begin
        #2;
        if (immOut === exp) begin
            $display("PASS [%0s]  got=%08h", name, immOut);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0s]  got=%08h  exp=%08h", name, immOut, exp);
            fail_count = fail_count + 1;
        end
    end
endtask

initial begin
    pass_count = 0; fail_count = 0;
    instruction = 32'd0; immSel = I_TYPE;
    $display("=== IMMEDIATE GENERATOR TESTBENCH ===");

    // ----------------------------------------------------------------
    // TEST GROUP 1 : I-type
    // Format: inst[31:20] = imm[11:0], sign-extended to 32 bits
    // ----------------------------------------------------------------
    $display("-- I-type");

    // Positive immediate: imm = +5  ? inst[31:20] = 12'b000000000101
    // Build a representative I-type instruction word:
    //   inst[31:20]=12'h005, rest can be anything (we only check immOut)
    instruction = 32'b000000000101_00000_000_00000_0010011; // ADDI encoding
    immSel = I_TYPE;
    check("I_positive", 32'h0000_0005);

    // Negative immediate: imm = -4  ? inst[31:20] = 12'hFFC
    // -4 in 12-bit two's complement = 0xFFC, sign-extends to 0xFFFFFFFC
    instruction = 32'b111111111100_00000_000_00000_0010011;
    immSel = I_TYPE;
    check("I_negative", 32'hFFFF_FFFC);

    // ----------------------------------------------------------------
    // TEST GROUP 2 : S-type
    // Format: {inst[31:25], inst[11:7]} = imm[11:0], sign-extended
    // ----------------------------------------------------------------
    $display("-- S-type");

    // Positive: imm = +8  ? imm[11:5]=7'b0000000, imm[4:0]=5'b01000
    // inst[31:25]=7'b0000000, inst[11:7]=5'b01000
    instruction = 32'b0000000_00001_00000_010_01000_0100011; // SW encoding
    immSel = S_TYPE;
    check("S_positive", 32'h0000_0008);

    // Negative: imm = -8  ? 12'hFF8
    // imm[11:5]=7'b1111111, imm[4:0]=5'b11000
    // inst[31:25]=7'b1111111, inst[11:7]=5'b11000
    instruction = 32'b1111111_00001_00000_010_11000_0100011;
    immSel = S_TYPE;
    check("S_negative", 32'hFFFF_FFF8);

    // ----------------------------------------------------------------
    // TEST GROUP 3 : B-type
    // Format (bit scatter):
    //   immOut[31:12] = {19{inst[31]}}
    //   immOut[11]    = inst[7]
    //   immOut[10:5]  = inst[30:25]
    //   immOut[4:1]   = inst[11:8]
    //   immOut[0]     = 1'b0          ? always 0 (half-word aligned)
    // ----------------------------------------------------------------
    $display("-- B-type");

    // Positive branch offset: +8
    // immOut = 32'h00000008
    // immOut[3]=1 ? inst[11:8]=4'b1000 (bit 3 of offset lands in inst[11])
    // all other imm bits = 0
    // inst[31]=0 (positive), inst[7]=imm[11]=0,
    // inst[30:25]=imm[10:5]=6'b000000, inst[11:8]=imm[4:1]=4'b0100
    instruction = 32'b0_000000_00001_00010_000_0100_0_1100011; // BEQ
    immSel = B_TYPE;
    check("B_positive_8", 32'h0000_0008);

    // Negative branch offset: -4
    // -4 in 13-bit = 13'h1FFC ? imm[12]=1,imm[11:1]=11'b11111111110
    // inst[31]=1, inst[7]=imm[11]=1, inst[30:25]=imm[10:5]=6'b111111
    // inst[11:8]=imm[4:1]=4'b1110
    instruction = 32'b1_111111_00001_00010_000_1110_1_1100011;
    immSel = B_TYPE;
    check("B_negative_4", 32'hFFFF_FFFC);

    // LSB must always be 0 ? use all-ones instruction
    instruction = 32'hFFFF_FFFF;
    immSel = B_TYPE;
    // immOut[0] must be 0 regardless; sign-extended all-ones otherwise
    // Expected: 32'hFFFF_FFFE  (all 1s except forced bit0=0)
    check("B_lsb_always_0", 32'hFFFF_FFFE);

    // Walking-1 test: set exactly one source bit at a time and verify
    // it lands in the correct output bit position.
    // inst[7]  ? immOut[11]
    instruction = 32'b0_000000_00000_00000_000_0000_1_1100011;
    immSel = B_TYPE;
    check("B_walk_inst7_to_imm11", 32'h0000_0800);

    // inst[30] ? immOut[10]
    instruction = 32'b0_100000_00000_00000_000_0000_0_1100011;
    immSel = B_TYPE;
    check("B_walk_inst30_to_imm10", 32'h0000_0400);

    // inst[8] ? immOut[1]  (lowest non-zero output bit via inst[11:8])
    instruction = 32'b0_000000_00000_00000_000_0001_0_1100011;
    immSel = B_TYPE;
    check("B_walk_inst8_to_imm1", 32'h0000_0002);

    // ----------------------------------------------------------------
    // TEST GROUP 4 : U-type
    // Format: immOut = {inst[31:12], 12'b0}
    // Lower 12 bits of output must always be zero.
    // ----------------------------------------------------------------
    $display("-- U-type");

    // LUI x1, 0x12345  ? immOut = 0x12345000
    instruction = 32'h1234_50B7; // LUI x1, 0x12345
    immSel = U_TYPE;
    check("U_typical", 32'h1234_5000);

    // All-ones upper: inst[31:12]=20'hFFFFF ? immOut = 0xFFFFF000
    instruction = 32'hFFFF_F0B7;
    immSel = U_TYPE;
    check("U_lower12_zero", 32'hFFFF_F000);

    // ----------------------------------------------------------------
    // TEST GROUP 5 : J-type
    // Format (bit scatter):
    //   immOut[31:21] = {11{inst[31]}}
    //   immOut[20]    = inst[31]
    //   immOut[19:12] = inst[19:12]
    //   immOut[11]    = inst[20]
    //   immOut[10:1]  = inst[30:21]
    //   immOut[0]     = 1'b0          ? always 0
    // ----------------------------------------------------------------
    $display("-- J-type");

    // JAL with offset +12:
    // immOut = 32'h0000_000C
    // imm[20]=0,imm[19:12]=8'b0,imm[11]=0,imm[10:1]=10'b0000000110
    // inst[31]=0, inst[19:12]=8'b0, inst[20]=0, inst[30:21]=10'b0000000110
    instruction = 32'b0_0000000110_0_00000000_00001_1101111;
    immSel = J_TYPE;
    check("J_positive_12", 32'h0000_000C);

    // Negative offset: -4
    // -4 in 21-bit = 21'h1FFFFC
    // imm[20]=1,imm[19:12]=8'hFF,imm[11]=1,imm[10:1]=10'h3FE
    // inst[31]=1,inst[19:12]=8'hFF,inst[20]=1,inst[30:21]=10'h3FE
    instruction = 32'b1_1111111110_1_11111111_00001_1101111;
    immSel = J_TYPE;
    check("J_negative_4", 32'hFFFF_FFFC);

    // LSB must always be 0
    instruction = 32'hFFFF_FFFF;
    immSel = J_TYPE;
    check("J_lsb_always_0", 32'hFFFF_FFFE);

    // Walking-1: inst[19] ? immOut[12]  (lowest bit of inst[19:12] field)
    instruction = 32'b0_0000000000_0_00000001_00000_1101111;
    immSel = J_TYPE;
    check("J_walk_inst19_to_imm12", 32'h0000_1000);

    // Walking-1: inst[21] ? immOut[1]  (lowest bit of inst[30:21] field)
    instruction = 32'b0_0000000001_0_00000000_00000_1101111;
    immSel = J_TYPE;
    check("J_walk_inst21_to_imm1", 32'h0000_0002);

    // ----------------------------------------------------------------
    // TEST GROUP 6 : Default (unknown immSel ? 0)
    // ----------------------------------------------------------------
    $display("-- default");
    instruction = 32'hFFFF_FFFF; immSel = 3'b111;
    check("default_unknown_sel", 32'd0);

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
