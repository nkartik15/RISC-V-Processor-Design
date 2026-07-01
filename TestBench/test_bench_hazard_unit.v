// ====================================================================
// tb_hazard_unit.v  ?  hazard_unit unit testbench
//
// The module under test resolves two classes of hazard:
//   (A) Load-use data hazard   ? stall=1, id_ex_bubble=1
//   (B) ALU data hazard        ? forwarding via fwd_a / fwd_b
//
// Forwarding encoding:
//   FWD_NONE    = 2'b00   use ID/EX register value (no forward)
//   FWD_EX_MEM  = 2'b10   forward from EX/MEM ALU result
//   FWD_MEM_WB  = 2'b01   forward from MEM/WB write-back data
//
// Test cases  (one per distinct logical path)
// ??????????
//  Load-use stall
//  1.  EX is a load, rd matches rs1 in ID  ? stall + bubble
//  2.  EX is a load, rd matches rs2 in ID  ? stall + bubble
//  3.  EX is a load, rd matches both rs1 and rs2 ? stall + bubble
//  4.  EX is a load, rd=x0                 ? no stall (x0 guard)
//  5.  EX is not a load                    ? no stall regardless of match
//  6.  Load rd matches but rs1/rs2 = x0    ? no stall  (x0 consumer guard)
//
//  EX/MEM ? EX forwarding  (fwd_a / fwd_b)
//  7.  ex_mem_rd == id_ex_rs1, regWrite=1  ? fwd_a = EX_MEM
//  8.  ex_mem_rd == id_ex_rs2, regWrite=1  ? fwd_b = EX_MEM
//  9.  ex_mem_rd = x0, regWrite=1          ? fwd_a/b = NONE  (x0 guard)
//  10. ex_mem_regWrite=0                   ? fwd_a/b = NONE
//
//  MEM/WB ? EX forwarding
//  11. mem_wb_rd == id_ex_rs1, regWrite=1  ? fwd_a = MEM_WB
//  12. mem_wb_rd == id_ex_rs2, regWrite=1  ? fwd_b = MEM_WB
//  13. mem_wb_rd = x0, regWrite=1          ? fwd_a/b = NONE  (x0 guard)
//
//  Priority: EX/MEM beats MEM/WB
//  14. Both stages write the same destination as rs1 ? fwd_a = EX_MEM
//  15. Both stages write the same destination as rs2 ? fwd_b = EX_MEM
//
//  ext_stall_req
//  16. ext_stall_req=1, no other hazard     ? stall=1, bubble=0
//  17. ext_stall_req=1 AND load-use hazard  ? stall=1, bubble=1
// ====================================================================
`timescale 1ns/1ps
`include "pipeline_pkg.v"

module tb_hazard_unit;

// ?? DUT ports ????????????????????????????????????????????????????????
reg  [4:0]  if_id_rs1,   if_id_rs2;
reg  [4:0]  id_ex_rd;
reg         id_ex_memRead;
reg  [4:0]  id_ex_rs1,   id_ex_rs2;
reg  [4:0]  ex_mem_rd;
reg         ex_mem_regWrite;
reg  [4:0]  mem_wb_rd;
reg         mem_wb_regWrite;
reg         ext_stall_req;

wire        stall, id_ex_bubble;
wire [1:0]  fwd_a, fwd_b;

hazard_unit DUT (
    .if_id_rs1      (if_id_rs1),
    .if_id_rs2      (if_id_rs2),
    .id_ex_rd       (id_ex_rd),
    .id_ex_memRead  (id_ex_memRead),
    .id_ex_rs1      (id_ex_rs1),
    .id_ex_rs2      (id_ex_rs2),
    .ex_mem_rd      (ex_mem_rd),
    .ex_mem_regWrite(ex_mem_regWrite),
    .mem_wb_rd      (mem_wb_rd),
    .mem_wb_regWrite(mem_wb_regWrite),
    .ext_stall_req  (ext_stall_req),
    .stall          (stall),
    .id_ex_bubble   (id_ex_bubble),
    .fwd_a          (fwd_a),
    .fwd_b          (fwd_b)
);

integer pass_count, fail_count;

// ?? helper: set all inputs to a "safe" neutral state ?????????????????
task reset_inputs;
    begin
        if_id_rs1=5'd1;  if_id_rs2=5'd2;
        id_ex_rd=5'd0;   id_ex_memRead=1'b0;
        id_ex_rs1=5'd1;  id_ex_rs2=5'd2;
        ex_mem_rd=5'd0;  ex_mem_regWrite=1'b0;
        mem_wb_rd=5'd0;  mem_wb_regWrite=1'b0;
        ext_stall_req=1'b0;
    end
endtask

// ?? check task ???????????????????????????????????????????????????????
// Pass 1'bx / 2'bxx for outputs you don't care about.
task chk;
    input [200:0] name;
    input         e_stall, e_bubble;
    input [1:0]   e_fwd_a, e_fwd_b;
    reg failed;
    begin
        #2; failed=0;
        if (e_stall  !==1'bx && stall       !==e_stall)  begin $display("FAIL [%0s] stall     got=%b exp=%b",   name,stall,      e_stall);  failed=1; end
        if (e_bubble !==1'bx && id_ex_bubble!==e_bubble) begin $display("FAIL [%0s] bubble    got=%b exp=%b",   name,id_ex_bubble,e_bubble);  failed=1; end
        if (e_fwd_a  !==2'bxx&& fwd_a       !==e_fwd_a)  begin $display("FAIL [%0s] fwd_a     got=%02b exp=%02b",name,fwd_a,     e_fwd_a);  failed=1; end
        if (e_fwd_b  !==2'bxx&& fwd_b       !==e_fwd_b)  begin $display("FAIL [%0s] fwd_b     got=%02b exp=%02b",name,fwd_b,     e_fwd_b);  failed=1; end
        if (!failed) begin $display("PASS [%0s]", name); pass_count=pass_count+1; end
        else         fail_count=fail_count+1;
    end
endtask

initial begin
    pass_count=0; fail_count=0;
    $display("=== HAZARD UNIT TESTBENCH ===");

    // ================================================================
    // LOAD-USE STALL TESTS
    // ================================================================
    $display("\n-- Load-use stall: load rd matches rs1 in ID");
    reset_inputs;
    id_ex_memRead=1'b1; id_ex_rd=5'd3;
    if_id_rs1=5'd3; if_id_rs2=5'd7;   // rs1 matches
    //              stall bubble fwd_a    fwd_b
    chk("load_use_rs1",  1, 1,  2'bxx,   2'bxx);

    $display("-- Load-use stall: load rd matches rs2 in ID");
    reset_inputs;
    id_ex_memRead=1'b1; id_ex_rd=5'd5;
    if_id_rs1=5'd2; if_id_rs2=5'd5;   // rs2 matches
    chk("load_use_rs2",  1, 1,  2'bxx,   2'bxx);

    $display("-- Load-use stall: load rd matches both rs1 and rs2");
    reset_inputs;
    id_ex_memRead=1'b1; id_ex_rd=5'd4;
    if_id_rs1=5'd4; if_id_rs2=5'd4;
    chk("load_use_both", 1, 1,  2'bxx,   2'bxx);

    $display("-- Load-use: load rd=x0 ? no stall (x0 guard)");
    reset_inputs;
    id_ex_memRead=1'b1; id_ex_rd=5'd0;  // x0 is the destination
    if_id_rs1=5'd0; if_id_rs2=5'd0;
    chk("load_use_x0_rd",0, 0,  2'bxx,   2'bxx);

    $display("-- Load-use: EX is NOT a load ? no stall");
    reset_inputs;
    id_ex_memRead=1'b0; id_ex_rd=5'd3;  // ALU instruction, not load
    if_id_rs1=5'd3; if_id_rs2=5'd3;
    chk("no_load_no_stall",0,0, 2'bxx,   2'bxx);

    $display("-- Load-use: consumer rs1/rs2=x0 ? no stall");
    reset_inputs;
    id_ex_memRead=1'b1; id_ex_rd=5'd3;
    if_id_rs1=5'd0; if_id_rs2=5'd0;    // x0 consumers ? never stall
    chk("load_use_x0_consumers",0,0, 2'bxx, 2'bxx);

    // ================================================================
    // EX/MEM ? EX FORWARDING
    // ================================================================
    $display("\n-- EX/MEM fwd: rd matches rs1 ? fwd_a=EX_MEM");
    reset_inputs;
    ex_mem_rd=5'd5; ex_mem_regWrite=1'b1;
    id_ex_rs1=5'd5; id_ex_rs2=5'd2;
    chk("exmem_fwd_a",  0, 0, `FWD_EX_MEM, `FWD_NONE);

    $display("-- EX/MEM fwd: rd matches rs2 ? fwd_b=EX_MEM");
    reset_inputs;
    ex_mem_rd=5'd6; ex_mem_regWrite=1'b1;
    id_ex_rs1=5'd1; id_ex_rs2=5'd6;
    chk("exmem_fwd_b",  0, 0, `FWD_NONE,   `FWD_EX_MEM);

    $display("-- EX/MEM fwd: rd=x0 ? no forwarding");
    reset_inputs;
    ex_mem_rd=5'd0; ex_mem_regWrite=1'b1;
    id_ex_rs1=5'd0; id_ex_rs2=5'd0;
    chk("exmem_x0_guard",0,0, `FWD_NONE, `FWD_NONE);

    $display("-- EX/MEM fwd: regWrite=0 ? no forwarding");
    reset_inputs;
    ex_mem_rd=5'd5; ex_mem_regWrite=1'b0;  // e.g. store instruction
    id_ex_rs1=5'd5; id_ex_rs2=5'd5;
    chk("exmem_no_regwrite",0,0, `FWD_NONE, `FWD_NONE);

    // ================================================================
    // MEM/WB ? EX FORWARDING
    // ================================================================
    $display("\n-- MEM/WB fwd: rd matches rs1 ? fwd_a=MEM_WB");
    reset_inputs;
    mem_wb_rd=5'd7; mem_wb_regWrite=1'b1;
    id_ex_rs1=5'd7; id_ex_rs2=5'd1;
    chk("memwb_fwd_a",  0, 0, `FWD_MEM_WB, `FWD_NONE);

    $display("-- MEM/WB fwd: rd matches rs2 ? fwd_b=MEM_WB");
    reset_inputs;
    mem_wb_rd=5'd8; mem_wb_regWrite=1'b1;
    id_ex_rs1=5'd1; id_ex_rs2=5'd8;
    chk("memwb_fwd_b",  0, 0, `FWD_NONE,   `FWD_MEM_WB);

    $display("-- MEM/WB fwd: rd=x0 ? no forwarding");
    reset_inputs;
    mem_wb_rd=5'd0; mem_wb_regWrite=1'b1;
    id_ex_rs1=5'd0; id_ex_rs2=5'd0;
    chk("memwb_x0_guard",0,0, `FWD_NONE, `FWD_NONE);

    // ================================================================
    // FORWARDING PRIORITY: EX/MEM beats MEM/WB
    // ================================================================
    $display("\n-- Priority: EX/MEM over MEM/WB for rs1");
    reset_inputs;
    // Both stages write to x5, both match rs1
    ex_mem_rd=5'd5; ex_mem_regWrite=1'b1;
    mem_wb_rd=5'd5; mem_wb_regWrite=1'b1;
    id_ex_rs1=5'd5; id_ex_rs2=5'd1;
    chk("priority_fwd_a", 0, 0, `FWD_EX_MEM, `FWD_NONE);

    $display("-- Priority: EX/MEM over MEM/WB for rs2");
    reset_inputs;
    ex_mem_rd=5'd9; ex_mem_regWrite=1'b1;
    mem_wb_rd=5'd9; mem_wb_regWrite=1'b1;
    id_ex_rs1=5'd1; id_ex_rs2=5'd9;
    chk("priority_fwd_b", 0, 0, `FWD_NONE, `FWD_EX_MEM);

    // ================================================================
    // ext_stall_req
    // ================================================================
    $display("\n-- ext_stall_req=1, no other hazard ? stall only, no bubble");
    reset_inputs;
    ext_stall_req=1'b1;
    chk("ext_stall_only",     1, 0, `FWD_NONE, `FWD_NONE);

    $display("-- ext_stall_req=1 AND load-use ? stall + bubble");
    reset_inputs;
    ext_stall_req=1'b1;
    id_ex_memRead=1'b1; id_ex_rd=5'd3;
    if_id_rs1=5'd3;
    chk("ext_stall_plus_load_use", 1, 1, 2'bxx, 2'bxx);

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
