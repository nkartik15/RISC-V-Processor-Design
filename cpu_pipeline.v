// ====================================================================
// cpu_pipeline.v
// 5-Stage Pipelined RISC-V CPU  ?  RV32I complete
//
//  Pipeline stages
//  ???????????????
//   IF   Instruction Fetch       (PC + instruction memory)
//   ID   Decode / Register Read  (control unit, reg file, imm gen)
//   EX   Execute                 (ALU, forwarding, branch resolution)
//   MEM  Memory Access           (data memory read/write)
//   WB   Write-Back              (register file write)
//
//  Hazard handling
//  ???????????????
//   Data hazards:    Full forwarding (EX/MEM?EX, MEM/WB?EX, WB?ID bypass)
//   Load-use:        1-cycle stall + MEM/WB?EX forwarding on resume
//   Control hazards: Flush IF/ID and ID/EX on branch/jump (predict-not-taken)
//                    Branch resolved at end of EX  ?  2-instruction flush
//
//  Extension interfaces (ports)
//  ????????????????????????????
//   pwr_*    Power Control Module  (clock gating, stage activity)
//   sec_*    Security Module       (tag propagation, fault signalling)
//   macro_*  Macro Instruction Engine (instruction injection)
//
//  Extension sideband bus
//  ??????????????????????
//   Every pipeline register carries a 32-bit ext bus (pipeline_pkg.vh):
//     [7:0]   macro tag   [23:8]  security tag   [31:24]  power hint
//   Connect by tapping the ex_* / mem_* / wb_* versions in a wrapper.
//
//  Existing submodules used unchanged
//  ????????????????????????????????????
//   instructionmem, datamemory, reg_array, immediate_generator,
//   maincontrol, alucontrol, alu  (+ csla_32_bec, rca_8, bec_8)
// ====================================================================

`include "pipeline_pkg.v"

module cpu_pipeline (
    input  clk,
    input  reset,

    // ?? Power Control Module interface ???????????????????????????
    // Drive pwr_stall_req to freeze the entire pipeline (all stages
    // hold; no state is lost).  pwr_stage_active is one-hot per stage
    // to indicate which stages contain a valid, non-bubble instruction
    // (useful for fine-grained clock gating).
    input         pwr_stall_req,      // external stall request
    output [4:0]  pwr_stage_active,   // [4]=WB [3]=MEM [2]=EX [1]=ID [0]=IF

    // ?? Security Module interface ????????????????????????????????
    // sec_tag_in is sampled at the IF stage and propagated through all
    // pipeline registers alongside the instruction.  The Security Module
    // inspects (and optionally modifies) the tag at any stage.
    // sec_fault is asserted by this CPU when an internal check fails
    // (currently tied to 0; connect the Security Module to drive it).
    input  [15:0] sec_tag_in,         // initial tag from security controller
    output        sec_fault,          // security violation (placeholder)

    // ?? Macro Instruction Engine interface ???????????????????????
    // When macro_valid=1, the CPU replaces the fetched instruction with
    // macro_instr and stalls the PC / IF stage so the engine can inject
    // a sequence of micro-ops one per cycle.
    // macro_stall_ack goes high whenever the CPU has consumed macro_instr
    // (i.e. stall=0 and macro_valid=1 on the same cycle).
    input         macro_valid,        // engine presents an expanded instr
    input  [31:0] macro_instr,        // the expanded instruction word
    output        macro_stall_ack     // CPU has accepted macro_instr
);

// ====================================================================
// SECTION 0  ?  WIRE / REGISTER DECLARATIONS
// ====================================================================

// ?? IF stage ????????????????????????????????????????????????????????
reg  [31:0] pc_reg;
wire [31:0] if_instr_raw;       // direct from instruction memory
wire [31:0] if_instr;           // after macro engine bypass

// ?? IF/ID pipeline register ?????????????????????????????????????????
reg [31:0] if_id_pc;
reg [31:0] if_id_instr;
reg [31:0] if_id_ext;           // extension sideband [31:0]

// ?? ID stage ????????????????????????????????????????????????????????
// Instruction field decode
wire [6:0] id_opcode  = if_id_instr[6:0];
wire [4:0] id_rd      = if_id_instr[11:7];
wire [2:0] id_funct3  = if_id_instr[14:12];
wire [4:0] id_rs1     = if_id_instr[19:15];
wire [4:0] id_rs2     = if_id_instr[24:20];
wire [6:0] id_funct7  = if_id_instr[31:25];

// Control unit outputs
wire        id_regWrite, id_memRead, id_memWrite, id_memtoReg;
wire        id_aluSrc, id_branch, id_jump, id_jalr;
wire [1:0]  id_alu_src_a, id_aluOp;
wire [2:0]  id_immSel;

// Register file raw outputs (before WB?ID bypass)
wire [31:0] id_rs1_raw, id_rs2_raw;

// Immediate
wire [31:0] id_imm;

// ?? ID/EX pipeline register ?????????????????????????????????????????
reg [31:0] id_ex_pc;
reg        id_ex_regWrite, id_ex_memRead, id_ex_memWrite, id_ex_memtoReg;
reg        id_ex_aluSrc, id_ex_branch, id_ex_jump, id_ex_jalr;
reg [1:0]  id_ex_alu_src_a, id_ex_aluOp;
reg [2:0]  id_ex_funct3;
reg [6:0]  id_ex_funct7;
reg [31:0] id_ex_rs1_data, id_ex_rs2_data;
reg [31:0] id_ex_imm;
reg [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
reg [31:0] id_ex_ext;

// ?? EX stage ????????????????????????????????????????????????????????
wire [1:0]  fwd_a, fwd_b;           // from hazard unit
wire [31:0] ex_fwd_rs1, ex_fwd_rs2; // post-forwarding operands
wire [31:0] ex_alu_in1, ex_alu_in2; // final ALU inputs
wire [3:0]  ex_alu_control;
wire [31:0] ex_alu_result;
wire        ex_zero_flag, ex_comp_flag, ex_carry_flag;
wire        ex_sign_bit, ex_borrow, ex_overflow;
reg         ex_branch_cond;
wire        ex_branch_taken;
wire [31:0] ex_pc_imm;              // pc + imm  (branch/JAL target)
wire [31:0] ex_redirect_target;
wire        ex_redirect;            // any control-flow change in EX

// ?? EX/MEM pipeline register ????????????????????????????????????????
reg [31:0] ex_mem_pc;
reg        ex_mem_regWrite, ex_mem_memRead, ex_mem_memWrite, ex_mem_memtoReg;
reg        ex_mem_jump, ex_mem_jalr;
reg [31:0] ex_mem_alu_result;
reg [31:0] ex_mem_rs2_fwd;         // forwarded rs2 (used by stores)
reg [4:0]  ex_mem_rd;
reg [31:0] ex_mem_ext;

// ?? MEM stage ???????????????????????????????????????????????????????
wire [31:0] mem_read_data;

// ?? MEM/WB pipeline register ????????????????????????????????????????
reg [31:0] mem_wb_pc;
reg        mem_wb_regWrite, mem_wb_memtoReg, mem_wb_jump, mem_wb_jalr;
reg [31:0] mem_wb_alu_result;
reg [31:0] mem_wb_read_data;
reg [4:0]  mem_wb_rd;
reg [31:0] mem_wb_ext;

// ?? WB stage ????????????????????????????????????????????????????????
wire [31:0] wb_write_data;

// ?? Hazard unit outputs ?????????????????????????????????????????????
wire stall, id_ex_bubble;


// ====================================================================
// SECTION 1  ?  INSTRUCTION FETCH  (IF)
// ====================================================================

// ??? Macro engine instruction mux ???????????????????????????????????
// When macro_valid=1 the engine supplies a synthetic instruction word.
// The PC is frozen so the engine can stream a sequence of micro-ops.
assign if_instr      = macro_valid ? macro_instr : if_instr_raw;
assign macro_stall_ack = macro_valid & ~stall & ~pwr_stall_req;

// ??? PC register ????????????????????????????????????????????????????
// Priority: reset > redirect (branch/jump) > stall (hold) > +4
always @(posedge clk or posedge reset) begin
    if (reset)
        pc_reg <= 32'd0;
    else if (ex_redirect)
        pc_reg <= ex_redirect_target;
    else if (!stall && !pwr_stall_req && !macro_valid)
        pc_reg <= pc_reg + 32'd4;
    // else: hold (load-use stall, power stall, or macro injection)
end

// Instruction memory (combinational read)
instructionmem IMEM (
    .pc (pc_reg),
    .rd (if_instr_raw)
);

// ??? IF/ID pipeline register ????????????????????????????????????????
always @(posedge clk or posedge reset) begin
    if (reset) begin
        if_id_pc    <= 32'd0;
        if_id_instr <= `NOP_INSTR;
        if_id_ext   <= 32'd0;
    end
    else if (ex_redirect) begin
        // Control-flow redirect: flush this stage (insert NOP bubble)
        if_id_pc    <= 32'd0;
        if_id_instr <= `NOP_INSTR;
        if_id_ext   <= 32'd0;
    end
    else if (!stall && !pwr_stall_req && !macro_valid) begin
        // Normal advance
        if_id_pc    <= pc_reg;
        if_id_instr <= if_instr;
        // Build extension sideband: [31:24]=pwr_hint, [23:8]=sec_tag, [7:0]=macro_tag
        if_id_ext   <= { 8'd0 /*pwr hint*/, sec_tag_in, 8'd0 /*macro*/ };
    end
    // else: hold (stall or macro injection ? PC and IF/ID freeze together)
end


// ====================================================================
// SECTION 2  ?  DECODE / REGISTER READ  (ID)
// ====================================================================

// ??? Main Control Unit ??????????????????????????????????????????????
maincontrol CTRL (
    .opcode   (id_opcode),
    .regWrite (id_regWrite),
    .memRead  (id_memRead),
    .memWrite (id_memWrite),
    .memtoReg (id_memtoReg),
    .aluSrc   (id_aluSrc),
    .alu_src_a(id_alu_src_a),
    .aluOp    (id_aluOp),
    .immSel   (id_immSel),
    .branch   (id_branch),
    .jump     (id_jump),
    .jalr     (id_jalr)
);

// ??? Register File ??????????????????????????????????????????????????
// Write port driven by WB stage (wb_write_data computed in Section 5).
reg_array RF (
    .sr1         (id_rs1),
    .sr2         (id_rs2),
    .wr          (mem_wb_rd),
    .wd          (wb_write_data),
    .write_enable(mem_wb_regWrite),
    .clk         (clk),
    .rst         (reset),
    .rs1         (id_rs1_raw),
    .rs2         (id_rs2_raw)
);

// ??? WB?ID bypass (write-before-read forwarding) ???????????????????
// The register file has a synchronous write: on the same clock edge
// that WB writes a register, ID reads the old (pre-write) value.
// We fix this by bypassing wb_write_data directly into the ID/EX
// register when addresses match.  This covers the case where only
// 3 instructions separate a producer from a consumer (no gap).
wire [31:0] id_rs1_data = (mem_wb_regWrite &&
                            mem_wb_rd != 5'd0 &&
                            mem_wb_rd == id_rs1)
                           ? wb_write_data : id_rs1_raw;

wire [31:0] id_rs2_data = (mem_wb_regWrite &&
                            mem_wb_rd != 5'd0 &&
                            mem_wb_rd == id_rs2)
                           ? wb_write_data : id_rs2_raw;

// ??? Immediate Generator ?????????????????????????????????????????????
immediate_generator IMM (
    .instruction(if_id_instr),
    .immSel     (id_immSel),
    .immOut     (id_imm)
);

// ??? ID/EX pipeline register ?????????????????????????????????????????
// Flushed (bubble) on: reset | ex_redirect | load-use stall (id_ex_bubble)
// Held on: stall from hazard unit (stall=1 but NOT id_ex_bubble)
// Note: id_ex_bubble is always asserted together with stall by hazard_unit,
//       so we don't need a separate "hold" case ? bubble takes priority.
always @(posedge clk or posedge reset) begin
    if (reset || ex_redirect || id_ex_bubble) begin
        // Insert NOP bubble: zero all control signals
        id_ex_pc        <= 32'd0;
        id_ex_regWrite  <= 1'b0;
        id_ex_memRead   <= 1'b0;
        id_ex_memWrite  <= 1'b0;
        id_ex_memtoReg  <= 1'b0;
        id_ex_aluSrc    <= 1'b0;
        id_ex_alu_src_a <= 2'b00;
        id_ex_aluOp     <= 2'b00;
        id_ex_branch    <= 1'b0;
        id_ex_jump      <= 1'b0;
        id_ex_jalr      <= 1'b0;
        id_ex_funct3    <= 3'd0;
        id_ex_funct7    <= 7'd0;
        id_ex_rs1_data  <= 32'd0;
        id_ex_rs2_data  <= 32'd0;
        id_ex_imm       <= 32'd0;
        id_ex_rs1       <= 5'd0;
        id_ex_rs2       <= 5'd0;
        id_ex_rd        <= 5'd0;
        id_ex_ext       <= 32'd0;
    end
    else if (!stall && !pwr_stall_req) begin
        id_ex_pc        <= if_id_pc;
        id_ex_regWrite  <= id_regWrite;
        id_ex_memRead   <= id_memRead;
        id_ex_memWrite  <= id_memWrite;
        id_ex_memtoReg  <= id_memtoReg;
        id_ex_aluSrc    <= id_aluSrc;
        id_ex_alu_src_a <= id_alu_src_a;
        id_ex_aluOp     <= id_aluOp;
        id_ex_branch    <= id_branch;
        id_ex_jump      <= id_jump;
        id_ex_jalr      <= id_jalr;
        id_ex_funct3    <= id_funct3;
        id_ex_funct7    <= id_funct7;
        id_ex_rs1_data  <= id_rs1_data;  // with WB bypass
        id_ex_rs2_data  <= id_rs2_data;
        id_ex_imm       <= id_imm;
        id_ex_rs1       <= id_rs1;
        id_ex_rs2       <= id_rs2;
        id_ex_rd        <= id_rd;
        id_ex_ext       <= if_id_ext;    // propagate sideband
    end
    // else: hold (pwr_stall_req with no load-use bubble)
end


// ====================================================================
// SECTION 3  ?  EXECUTE  (EX)
// ====================================================================

// ??? Forwarding muxes ???????????????????????????????????????????????
// EX/MEM ? EX forwarding uses ex_mem_alu_result (result is computed,
// memory not yet read).
// MEM/WB ? EX forwarding uses wb_write_data (final value after memtoReg
// mux, covers loads and regular ALU ops uniformly).
assign ex_fwd_rs1 =
    (fwd_a == `FWD_EX_MEM) ? ex_mem_alu_result :
    (fwd_a == `FWD_MEM_WB) ? wb_write_data     :
                              id_ex_rs1_data;

assign ex_fwd_rs2 =
    (fwd_b == `FWD_EX_MEM) ? ex_mem_alu_result :
    (fwd_b == `FWD_MEM_WB) ? wb_write_data     :
                              id_ex_rs2_data;

// ??? Operand-A mux (LUI / AUIPC / normal) ???????????????????????????
assign ex_alu_in1 =
    (id_ex_alu_src_a == `ASRC_ZERO) ? 32'd0      :   // LUI
    (id_ex_alu_src_a == `ASRC_PC  ) ? id_ex_pc   :   // AUIPC
                                       ex_fwd_rs1;    // normal

// ??? Operand-B mux (immediate / rs2) ????????????????????????????????
assign ex_alu_in2 = id_ex_aluSrc ? id_ex_imm : ex_fwd_rs2;

// ??? ALU Control ????????????????????????????????????????????????????
alucontrol ALUCTRL (
    .aluOp     (id_ex_aluOp),
    .funct3    (id_ex_funct3),
    .funct7    (id_ex_funct7),
    .ALUcontrol(ex_alu_control)
);

// ??? ALU (CSLA-based, from alu.v) ???????????????????????????????????
alu ALU (
    .operand_a  (ex_alu_in1),
    .operand_b  (ex_alu_in2),
    .alu_control(ex_alu_control),
    .alu_result (ex_alu_result),
    .zero_flag  (ex_zero_flag),
    .comp_flag  (ex_comp_flag),
    .carry_flag (ex_carry_flag),
    .sign_bit   (ex_sign_bit),
    .borrow     (ex_borrow),
    .overflow   (ex_overflow)
);

// ??? Branch condition decoder (full RV32I branch set) ???????????????
always @(*) begin
    case (id_ex_funct3)
        3'b000: ex_branch_cond =  ex_zero_flag;              // BEQ
        3'b001: ex_branch_cond = ~ex_zero_flag;              // BNE
        3'b100: ex_branch_cond =  ex_sign_bit ^ ex_overflow; // BLT  (signed)
        3'b101: ex_branch_cond = ~(ex_sign_bit ^ ex_overflow);// BGE  (signed)
        3'b110: ex_branch_cond =  ex_borrow;                 // BLTU (unsigned)
        3'b111: ex_branch_cond = ~ex_borrow;                 // BGEU (unsigned)
        default: ex_branch_cond = 1'b0;
    endcase
end

assign ex_branch_taken = id_ex_branch & ex_branch_cond;

// ??? Redirect target computation ????????????????????????????????????
// Branch / JAL target: pc + sign-extended imm   (one adder, shared)
// JALR target        : (rs1 + imm) & ~1         (ALU already computed this)
assign ex_pc_imm        = id_ex_pc + id_ex_imm;
assign ex_redirect_target = id_ex_jalr ? (ex_alu_result & ~32'b1) : ex_pc_imm;

// Any control-flow change resolved in EX
assign ex_redirect = ex_branch_taken | id_ex_jump | id_ex_jalr;

// ??? EX/MEM pipeline register ???????????????????????????????????????
// F1 fix: also gate on pwr_stall_req so all five stage registers freeze
// together — prevents state corruption when an external stall is injected.
always @(posedge clk or posedge reset) begin
    if (reset) begin
        ex_mem_pc         <= 32'd0;
        ex_mem_regWrite   <= 1'b0;
        ex_mem_memRead    <= 1'b0;
        ex_mem_memWrite   <= 1'b0;
        ex_mem_memtoReg   <= 1'b0;
        ex_mem_jump       <= 1'b0;
        ex_mem_jalr       <= 1'b0;
        ex_mem_alu_result <= 32'd0;
        ex_mem_rs2_fwd    <= 32'd0;
        ex_mem_rd         <= 5'd0;
        ex_mem_ext        <= 32'd0;
        ex_mem_funct3     <= 3'd2;   // default SW/LW (safe)
    end
    else if (!pwr_stall_req) begin   // F1 fix: hold on power stall
        ex_mem_pc         <= id_ex_pc;
        ex_mem_regWrite   <= id_ex_regWrite;
        ex_mem_memRead    <= id_ex_memRead;
        ex_mem_memWrite   <= id_ex_memWrite;
        ex_mem_memtoReg   <= id_ex_memtoReg;
        ex_mem_jump       <= id_ex_jump;
        ex_mem_jalr       <= id_ex_jalr;
        ex_mem_alu_result <= ex_alu_result;
        ex_mem_rs2_fwd    <= ex_fwd_rs2;   // forwarded rs2 for stores
        ex_mem_rd         <= id_ex_rd;
        ex_mem_ext        <= id_ex_ext;
        ex_mem_funct3     <= id_ex_funct3; // C3 fix: propagate width/sign select
    end
    // else: hold (pwr_stall_req — entire pipeline frozen)
end


// ====================================================================
// SECTION 4  ?  MEMORY ACCESS  (MEM)
// ====================================================================

// C3 fix: pass funct3 through EX/MEM register to select byte/hw/word access.
// The EX/MEM register needs to carry funct3 — we reuse id_ex_funct3 latched
// into ex_mem_funct3 declared below.
reg [2:0] ex_mem_funct3;

datamemory DMEM (
    .clk      (clk),
    .memRead  (ex_mem_memRead),
    .memWrite (ex_mem_memWrite),
    .funct3   (ex_mem_funct3),       // C3 fix: byte/halfword select
    .address  (ex_mem_alu_result),
    .writeData(ex_mem_rs2_fwd),
    .readData (mem_read_data)
);

// ??? MEM/WB pipeline register ???????????????????????????????????????
always @(posedge clk or posedge reset) begin
    if (reset) begin
        mem_wb_pc           <= 32'd0;
        mem_wb_regWrite     <= 1'b0;
        mem_wb_memtoReg     <= 1'b0;
        mem_wb_jump         <= 1'b0;
        mem_wb_jalr         <= 1'b0;
        mem_wb_alu_result   <= 32'd0;
        mem_wb_read_data    <= 32'd0;
        mem_wb_rd           <= 5'd0;
        mem_wb_ext          <= 32'd0;
    end
    else if (!pwr_stall_req) begin   // F1 fix: hold on power stall
        mem_wb_pc           <= ex_mem_pc;
        mem_wb_regWrite     <= ex_mem_regWrite;
        mem_wb_memtoReg     <= ex_mem_memtoReg;
        mem_wb_jump         <= ex_mem_jump;
        mem_wb_jalr         <= ex_mem_jalr;
        mem_wb_alu_result   <= ex_mem_alu_result;
        mem_wb_read_data    <= mem_read_data;
        mem_wb_rd           <= ex_mem_rd;
        mem_wb_ext          <= ex_mem_ext;
    end
    // else: hold (pwr_stall_req — entire pipeline frozen)
end


// ====================================================================
// SECTION 5  ?  WRITE-BACK  (WB)
// ====================================================================
//   JAL / JALR : write pc+4 (link address) into rd
//   Load       : write memory read data into rd
//   Otherwise  : write ALU result into rd
//   (LUI / AUIPC produce correct ALU result; no special case needed)

assign wb_write_data =
    (mem_wb_jump | mem_wb_jalr) ? (mem_wb_pc + 32'd4) :
     mem_wb_memtoReg            ?  mem_wb_read_data    :
                                   mem_wb_alu_result;

// wb_write_data feeds back to:
//   1.  reg_array.wd  (declared in Section 2 instantiation)
//   2.  Forwarding muxes in EX stage (Section 3)
//   3.  WB?ID bypass wires (Section 2)


// ====================================================================
// SECTION 6  ?  HAZARD UNIT
// ====================================================================

hazard_unit HAZARD (
    // IF/ID source registers (load-use detection)
    .if_id_rs1       (id_rs1),            // decoded from if_id_instr
    .if_id_rs2       (id_rs2),

    // ID/EX destination + memRead (load-use detection)
    .id_ex_rd        (id_ex_rd),
    .id_ex_memRead   (id_ex_memRead),

    // ID/EX source registers (forwarding)
    .id_ex_rs1       (id_ex_rs1),
    .id_ex_rs2       (id_ex_rs2),

    // EX/MEM forwarding info
    .ex_mem_rd       (ex_mem_rd),
    .ex_mem_regWrite (ex_mem_regWrite),

    // MEM/WB forwarding info
    .mem_wb_rd       (mem_wb_rd),
    .mem_wb_regWrite (mem_wb_regWrite),

    // Extension: external stall (power gating, security hold, macro inject)
    .ext_stall_req   (pwr_stall_req),

    // Hazard outputs
    .stall           (stall),
    .id_ex_bubble    (id_ex_bubble),

    // Forwarding selects
    .fwd_a           (fwd_a),
    .fwd_b           (fwd_b)
);


// ====================================================================
// SECTION 7  ?  EXTENSION INTERFACES
// ====================================================================

// ??? Power stage activity monitor ???????????????????????????????????
// Each bit indicates a valid (non-bubble) instruction in that stage.
// An external Power Control Module can use this to gate clocks or
// voltage domains for idle stages.
assign pwr_stage_active = {
    mem_wb_regWrite | mem_wb_memtoReg | mem_wb_jump | mem_wb_jalr,  // [4] WB
    ex_mem_regWrite | ex_mem_memRead  | ex_mem_memWrite,             // [3] MEM
    id_ex_regWrite  | id_ex_memRead   | id_ex_memWrite | id_ex_branch
                                      | id_ex_jump     | id_ex_jalr, // [2] EX
    |if_id_instr,                                                    // [1] ID
    1'b1                                                             // [0] IF always
};

// ??? Security fault (placeholder) ???????????????????????????????????
// The Security Module will drive this from an external wrapper.
// Internal fault examples to implement later:
//   - mem_wb_ext[`EXT_SEC] mismatch with expected tag
//   - PC alignment fault
//   - Privilege-level violation on data memory address
assign sec_fault = 1'b0;

// ??? Extension sideband access points ???????????????????????????????
// These wires are exposed for use in a top-level wrapper that connects
// the Power, Security and Macro modules.  Synthesis will keep them if
// the wrapper drives/reads them; otherwise they are optimised away.
//
//   if_id_ext   [31:0]  ? sideband after IF stage
//   id_ex_ext   [31:0]  ? sideband after ID stage
//   ex_mem_ext  [31:0]  ? sideband after EX stage
//   mem_wb_ext  [31:0]  ? sideband after MEM stage
//   (all declared as regs above; accessible from wrapper via port if
//    promoted to output ports in a future revision)

endmodule


// ====================================================================
// EXTENSION INTERFACE NOTES  (for future module authors)
// ====================================================================
//
// ?? Power Control Module ????????????????????????????????????????????
//  Instantiate alongside cpu_pipeline.  Connect:
//    .pwr_stall_req  ? assert to freeze all stages cleanly
//    .pwr_stage_active ? read to decide which stage clocks to gate
//  Add per-stage clock enables by gating `clk` with a generated enable
//  derived from pwr_stage_active.  Wrap each pipeline register clock
//  with an ICG (integrated clock gate) cell in a tech-specific wrapper.
//
// ?? Security Module ?????????????????????????????????????????????????
//  Tap mem_wb_ext[`EXT_SEC] at the WB stage to verify authentication
//  tags that were set by the Security Module at instruction dispatch.
//  On violation: assert pwr_stall_req to freeze pipeline, then handle
//  the fault (trap, zeroise, reset, etc.).  Drive sec_fault high.
//
// ?? Macro Instruction Engine ????????????????????????????????????????
//  When a macro opcode is detected in IF (by monitoring if_instr_raw),
//  the engine asserts macro_valid and presents the first micro-op on
//  macro_instr.  The engine monitors macro_stall_ack: each rising edge
//  (while macro_valid=1) means the CPU has consumed one micro-op.
//  The engine de-asserts macro_valid after the last micro-op, allowing
//  normal fetch to resume from pc_reg+4.
// ====================================================================
