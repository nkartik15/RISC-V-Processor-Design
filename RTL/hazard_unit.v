// ====================================================================
// hazard_unit.v
// Hazard Detection + Forwarding Unit for 5-Stage RISC-V Pipeline
//
// Responsibilities
// ????????????????
//  1. Load-use data hazard detection ? stall (1 cycle)
//  2. EX/MEM  ? EX  forwarding  (fwd_a / fwd_b = FWD_EX_MEM)
//  3. MEM/WB  ? EX  forwarding  (fwd_a / fwd_b = FWD_MEM_WB)
//
// Control-flow hazards (branch / jump flushes) are handled directly
// in cpu_pipeline.v because the redirect signal is already computed
// there.  This module only deals with data hazards.
//
// Forwarding priority (highest ? lowest):
//   EX/MEM result > MEM/WB result > ID/EX register value
//
// Extension hook
// ??????????????
//  ext_stall_req : any future module (power, security, macro engine)
//  can assert this to inject an additional stall without modifying
//  this file.
// ====================================================================

`include "pipeline_pkg.v"

module hazard_unit (
    // ?? IF/ID stage ? instruction being decoded ??????????????????
    input  [4:0]  if_id_rs1,        // rs1 of instruction in IF/ID
    input  [4:0]  if_id_rs2,        // rs2 of instruction in IF/ID

    // ?? ID/EX stage ??????????????????????????????????????????????
    input  [4:0]  id_ex_rd,         // destination of instruction in EX
    input         id_ex_memRead,    // EX instruction is a load
    input  [4:0]  id_ex_rs1,        // rs1 of instruction in EX  (for fwd)
    input  [4:0]  id_ex_rs2,        // rs2 of instruction in EX  (for fwd)

    // ?? EX/MEM stage ?????????????????????????????????????????????
    input  [4:0]  ex_mem_rd,        // destination of instruction in MEM
    input         ex_mem_regWrite,  // MEM instruction writes a register

    // ?? MEM/WB stage ?????????????????????????????????????????????
    input  [4:0]  mem_wb_rd,        // destination of instruction in WB
    input         mem_wb_regWrite,  // WB instruction writes a register

    // ?? Extension hook ???????????????????????????????????????????
    input         ext_stall_req,    // external stall (power/security/macro)

    // ?? Hazard outputs ???????????????????????????????????????????
    output reg    stall,            // freeze PC + IF/ID; bubble ID/EX
    output reg    id_ex_bubble,     // insert NOP into ID/EX this cycle

    // ?? Forwarding selects (to EX-stage muxes in cpu_pipeline) ??
    // Encoding: FWD_NONE=2'b00, FWD_EX_MEM=2'b10, FWD_MEM_WB=2'b01
    output reg [1:0] fwd_a,         // for operand A (rs1) in EX
    output reg [1:0] fwd_b          // for operand B (rs2) in EX
);

// ====================================================================
// 1.  LOAD-USE HAZARD DETECTION
//     If the instruction in EX is a load AND its destination matches
//     either source of the instruction currently in ID, we must stall
//     one cycle.  The forwarding path (MEM/WB ? EX) resolves the
//     dependency on the following cycle automatically.
// ====================================================================
always @(*) begin
    stall       = ext_stall_req;    // ext_stall_req can also force stall
    id_ex_bubble = 1'b0;

    if (id_ex_memRead) begin
        // load-use: stall if rd overlaps rs1 or rs2 in IF/ID
        if ( (id_ex_rd != 5'd0) &&
             ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2)) ) begin
            stall        = 1'b1;
            id_ex_bubble = 1'b1;   // inject bubble into ID/EX
        end
    end
end

// ====================================================================
// 2.  FORWARDING LOGIC  (for EX-stage operand muxes)
//
//     Priority: EX/MEM is more recent than MEM/WB, so check it first.
//     x0 is hardwired to 0 ? never forward to x0 reads.
// ====================================================================
always @(*) begin
    // ?? Operand A (rs1) ??????????????????????????????????????????
    fwd_a = `FWD_NONE;

    if (ex_mem_regWrite &&
        (ex_mem_rd != 5'd0) &&
        (ex_mem_rd == id_ex_rs1)) begin
        fwd_a = `FWD_EX_MEM;               // EX/MEM ? EX  (highest priority)

    end else if (mem_wb_regWrite &&
                 (mem_wb_rd != 5'd0) &&
                 (mem_wb_rd == id_ex_rs1)) begin
        fwd_a = `FWD_MEM_WB;               // MEM/WB ? EX
    end

    // ?? Operand B (rs2) ??????????????????????????????????????????
    fwd_b = `FWD_NONE;

    if (ex_mem_regWrite &&
        (ex_mem_rd != 5'd0) &&
        (ex_mem_rd == id_ex_rs2)) begin
        fwd_b = `FWD_EX_MEM;

    end else if (mem_wb_regWrite &&
                 (mem_wb_rd != 5'd0) &&
                 (mem_wb_rd == id_ex_rs2)) begin
        fwd_b = `FWD_MEM_WB;
    end
end

endmodule
