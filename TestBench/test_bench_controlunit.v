// ====================================================================
// tb_control_unit.v  ?  maincontrol + alucontrol unit testbench
//
// Coverage
// ????????
// maincontrol : all 9 opcodes � every output signal
// alucontrol  : aluOp=00 (forced ADD), aluOp=01 (forced SUB),
//               aluOp=10 � every {funct7[5],funct3} R/I combination
//
// Design philosophy
// ?????????????????
// One test per distinct logical path; the check task prints got/expected
// and tracks totals.  Control signals are verified as a bundle so a
// single misplaced bit in any case is caught with a clear label.
// ====================================================================
`timescale 1ns/1ps

module tb_control_unit;

// ?? maincontrol DUT ports ????????????????????????????????????????????
reg  [6:0] opcode;
wire       regWrite, memRead, memWrite, memtoReg;
wire       aluSrc;
wire [1:0] alu_src_a, aluOp;
wire [2:0] immSel;
wire       branch, jump, jalr;

maincontrol MAIN (
    .opcode   (opcode),
    .regWrite (regWrite),  .memRead  (memRead),
    .memWrite (memWrite),  .memtoReg (memtoReg),
    .aluSrc   (aluSrc),    .alu_src_a(alu_src_a),
    .aluOp    (aluOp),     .immSel   (immSel),
    .branch   (branch),    .jump     (jump),
    .jalr     (jalr)
);

// ?? alucontrol DUT ports ?????????????????????????????????????????????
reg  [1:0] ac_aluOp;
reg  [2:0] ac_funct3;
reg  [6:0] ac_funct7;
wire [3:0] ALUcontrol;

alucontrol ALUCTRL (
    .aluOp     (ac_aluOp),
    .funct3    (ac_funct3),
    .funct7    (ac_funct7),
    .ALUcontrol(ALUcontrol)
);

// ?? ALU control encoding (matches alu.v / controlunit.v) ????????????
localparam AC_ADD=4'b0000, AC_SUB=4'b1000, AC_AND=4'b0111,
           AC_OR =4'b0110, AC_XOR=4'b0100, AC_SLT=4'b0010,
           AC_SLL=4'b0001, AC_SRL=4'b0101, AC_SRA=4'b1101;

// ?? immSel encoding ??????????????????????????????????????????????????
localparam I_IMM=3'b000, S_IMM=3'b001, B_IMM=3'b010,
           U_IMM=3'b011, J_IMM=3'b100;

// ?? opcode constants ?????????????????????????????????????????????????
localparam OP_R     = 7'b0110011,
           OP_I     = 7'b0010011,
           OP_LOAD  = 7'b0000011,
           OP_STORE = 7'b0100011,
           OP_BR    = 7'b1100011,
           OP_JAL   = 7'b1101111,
           OP_JALR  = 7'b1100111,
           OP_LUI   = 7'b0110111,
           OP_AUIPC = 7'b0010111;

integer pass_count, fail_count;

// ?? maincontrol check task ???????????????????????????????????????????
// Pass 1'bx / 2'bxx / 3'bxxx for fields you don't want to check.
task chk_main;
    input [200:0] name;
    // expected values (1'bx / 2'bxx = don't-care)
    input        e_regW, e_memR, e_memW, e_m2R;
    input        e_aluSrc;
    input [1:0]  e_srcA, e_aluOp;
    input [2:0]  e_immSel;
    input        e_branch, e_jump, e_jalr;
    reg failed;
    begin
        #2; failed = 0;
        if (e_regW   !== 1'bx && regWrite  !== e_regW)   begin $display("FAIL [%0s] regWrite  got=%b exp=%b",  name,regWrite, e_regW);  failed=1; end
        if (e_memR   !== 1'bx && memRead   !== e_memR)   begin $display("FAIL [%0s] memRead   got=%b exp=%b",  name,memRead,  e_memR);  failed=1; end
        if (e_memW   !== 1'bx && memWrite  !== e_memW)   begin $display("FAIL [%0s] memWrite  got=%b exp=%b",  name,memWrite, e_memW);  failed=1; end
        if (e_m2R    !== 1'bx && memtoReg  !== e_m2R)    begin $display("FAIL [%0s] memtoReg  got=%b exp=%b",  name,memtoReg, e_m2R);   failed=1; end
        if (e_aluSrc !== 1'bx && aluSrc    !== e_aluSrc) begin $display("FAIL [%0s] aluSrc    got=%b exp=%b",  name,aluSrc,   e_aluSrc);failed=1; end
        if (e_srcA   !== 2'bxx&& alu_src_a !== e_srcA)   begin $display("FAIL [%0s] alu_src_a got=%b exp=%b",  name,alu_src_a,e_srcA);  failed=1; end
        if (e_aluOp  !== 2'bxx&& aluOp     !== e_aluOp)  begin $display("FAIL [%0s] aluOp     got=%b exp=%b",  name,aluOp,    e_aluOp); failed=1; end
        if (e_immSel !== 3'bxxx&&immSel    !== e_immSel) begin $display("FAIL [%0s] immSel    got=%b exp=%b",  name,immSel,   e_immSel);failed=1; end
        if (e_branch !== 1'bx && branch    !== e_branch) begin $display("FAIL [%0s] branch    got=%b exp=%b",  name,branch,   e_branch);failed=1; end
        if (e_jump   !== 1'bx && jump      !== e_jump)   begin $display("FAIL [%0s] jump      got=%b exp=%b",  name,jump,     e_jump);  failed=1; end
        if (e_jalr   !== 1'bx && jalr      !== e_jalr)   begin $display("FAIL [%0s] jalr      got=%b exp=%b",  name,jalr,     e_jalr);  failed=1; end
        if (!failed) begin $display("PASS [%0s]", name); pass_count=pass_count+1; end
        else         fail_count=fail_count+1;
    end
endtask

// ?? alucontrol check task ????????????????????????????????????????????
task chk_alu;
    input [200:0] name;
    input [3:0]   exp_ctrl;
    reg failed;
    begin
        #2; failed = 0;
        if (ALUcontrol !== exp_ctrl) begin
            $display("FAIL [%0s] ALUcontrol got=%04b exp=%04b", name, ALUcontrol, exp_ctrl);
            failed=1; fail_count=fail_count+1;
        end else begin
            $display("PASS [%0s]", name); pass_count=pass_count+1;
        end
    end
endtask

initial begin
    pass_count=0; fail_count=0;
    $display("=== CONTROL UNIT TESTBENCH ===");

    // ================================================================
    // PART A : maincontrol ? one test per opcode
    // ================================================================
    $display("\n-- maincontrol: R-type");
    // R-type: regWrite=1, aluOp=10, no mem, no imm, no branch/jump
    opcode = OP_R;
    //        name      rW mR mW m2R aluSrc srcA  aluOp immSel br  jmp  jr
    chk_main("R_type",  1, 0, 0, 0,  0,    2'b00,2'b10,3'bxxx,0,  0,   0);

    $display("-- maincontrol: I-type (ALU immediate)");
    // I-type: regWrite=1, aluSrc=1 (use imm), aluOp=11, I_IMM
    opcode = OP_I;
    chk_main("I_type",  1, 0, 0, 0,  1,    2'b00,2'b11,I_IMM, 0,  0,   0);

    $display("-- maincontrol: Load");
    // Load: regWrite=1, memRead=1, memtoReg=1, aluSrc=1, aluOp=00, I_IMM
    opcode = OP_LOAD;
    chk_main("Load",    1, 1, 0, 1,  1,    2'b00,2'b00,I_IMM, 0,  0,   0);

    $display("-- maincontrol: Store");
    // Store: memWrite=1, aluSrc=1, aluOp=00, S_IMM; no regWrite
    opcode = OP_STORE;
    chk_main("Store",   0, 0, 1, 0,  1,    2'b00,2'b00,S_IMM, 0,  0,   0);

    $display("-- maincontrol: Branch");
    // Branch: branch=1, aluOp=01 (SUB for compare), B_IMM; no regWrite
    opcode = OP_BR;
    chk_main("Branch",  0, 0, 0, 0,  0,    2'b00,2'b01,B_IMM, 1,  0,   0);

    $display("-- maincontrol: JAL");
    // JAL: regWrite=1, jump=1, J_IMM; no mem, no aluSrc
    opcode = OP_JAL;
    chk_main("JAL",     1, 0, 0, 0,  0,    2'bxx,3'bxxx,J_IMM,0,  1,   0);

    $display("-- maincontrol: JALR");
    // JALR: regWrite=1, jalr=1, aluSrc=1, aluOp=00, I_IMM
    opcode = OP_JALR;
    chk_main("JALR",    1, 0, 0, 0,  1,    2'b00,2'b00,I_IMM, 0,  0,   1);

    $display("-- maincontrol: LUI");
    // LUI: regWrite=1, aluSrc=1, alu_src_a=01 (zero), aluOp=00, U_IMM
    opcode = OP_LUI;
    chk_main("LUI",     1, 0, 0, 0,  1,    2'b01,2'b00,U_IMM, 0,  0,   0);

    $display("-- maincontrol: AUIPC");
    // AUIPC: regWrite=1, aluSrc=1, alu_src_a=10 (PC), aluOp=00, U_IMM
    opcode = OP_AUIPC;
    chk_main("AUIPC",   1, 0, 0, 0,  1,    2'b10,2'b00,U_IMM, 0,  0,   0);

    $display("-- maincontrol: default (unknown opcode)");
    // Unknown opcode: all safe defaults = 0
    opcode = 7'b1111111;
    chk_main("default", 0, 0, 0, 0,  0,    2'b00,2'b00,3'bxxx,0,  0,   0);

    // ================================================================
    // PART B : alucontrol
    // ================================================================

    $display("\n-- alucontrol: aluOp=00 (always ADD)");
    // Load, Store, JALR, LUI, AUIPC all force ADD regardless of funct
    ac_aluOp=2'b00; ac_funct3=3'b000; ac_funct7=7'h00;
    chk_alu("op00_ADD_funct0",   AC_ADD);
    ac_funct7=7'h20;
    chk_alu("op00_ADD_funct7_20",AC_ADD);  // funct7 ignored for aluOp=00
    ac_funct3=3'b111;
    chk_alu("op00_ADD_funct3_7", AC_ADD);

    $display("-- alucontrol: aluOp=01 (always SUB)");
    // Branch: always SUB for comparison
    ac_aluOp=2'b01; ac_funct3=3'b000; ac_funct7=7'h00;
    chk_alu("op01_SUB_funct0",   AC_SUB);
    ac_funct3=3'b110;
    chk_alu("op01_SUB_funct3_6", AC_SUB);  // funct3 ignored

    $display("-- alucontrol: aluOp=10 R/I-type decode");
    // signal = {funct7[5], funct3}
    ac_aluOp=2'b10;

    // ADD  : funct7[5]=0, funct3=000
    ac_funct7=7'h00; ac_funct3=3'b000; chk_alu("op10_ADD",  AC_ADD);
    // SUB  : funct7[5]=1, funct3=000
    ac_funct7=7'h20; ac_funct3=3'b000; chk_alu("op10_SUB",  AC_SUB);
    // SLL  : funct7[5]=0, funct3=001
    ac_funct7=7'h00; ac_funct3=3'b001; chk_alu("op10_SLL",  AC_SLL);
    // SLT  : funct7[5]=0, funct3=010
    ac_funct7=7'h00; ac_funct3=3'b010; chk_alu("op10_SLT",  AC_SLT);
    // XOR  : funct7[5]=0, funct3=100
    ac_funct7=7'h00; ac_funct3=3'b100; chk_alu("op10_XOR",  AC_XOR);
    // SRL  : funct7[5]=0, funct3=101
    ac_funct7=7'h00; ac_funct3=3'b101; chk_alu("op10_SRL",  AC_SRL);
    // SRA  : funct7[5]=1, funct3=101
    ac_funct7=7'h20; ac_funct3=3'b101; chk_alu("op10_SRA",  AC_SRA);
    // OR   : funct7[5]=0, funct3=110
    ac_funct7=7'h00; ac_funct3=3'b110; chk_alu("op10_OR",   AC_OR);
    // AND  : funct7[5]=0, funct3=111
    ac_funct7=7'h00; ac_funct3=3'b111; chk_alu("op10_AND",  AC_AND);

    // default inside aluOp=10 (undefined signal) ? ADD
    ac_funct7=7'h20; ac_funct3=3'b010; chk_alu("op10_default_ADD", AC_ADD);

    // ================================================================
    // SUMMARY
    // ================================================================
    $display("\n=== RESULTS: %0d passed, %0d failed ===",
             pass_count, fail_count);
    if (fail_count==0) $display("ALL TESTS PASSED");
    else               $display("*** FAILURES ? review above ***");
    $finish;
end

endmodule
