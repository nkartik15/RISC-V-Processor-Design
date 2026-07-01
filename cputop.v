module cpu (
    input clk,
    input reset
);

// WIRE DECLARATIONS

// Program counter & instruction
wire [31:0] pc;
wire [31:0] instruction;

// Instruction fields
wire [6:0] opcode;
wire [4:0] rd, rs1, rs2;
wire [2:0] funct3;
wire [6:0] funct7;

// Main-control outputs
wire        regWrite, memRead, memWrite, memtoReg;
wire        aluSrc;
wire [1:0]  alu_src_a;   // operand-A select: 00=rs1, 01=zero, 10=pc
wire [1:0]  aluOp;
wire [2:0]  immSel;
wire        branch, jump, jalr;

// Register file
wire [31:0] rs1_data, rs2_data;

// Immediate
wire [31:0] imm;

// ALU
wire [3:0]  ALUcontrol;
wire [31:0] alu_in1, alu_in2;
wire [31:0] alu_result;
wire        zero_flag, comp_flag, carry_flag, sign_bit, borrow, overflow;

// Branch
wire        branch_taken;
reg         branch_cond;

// Memory
wire [31:0] read_data;

// Write-back
wire [31:0] write_data;


// INSTRUCTION FETCH

pc PC_inst (
    .clk         (clk),
    .reset       (reset),
    .jump        (jump),
    .jalr        (jalr),
    .branch_taken(branch_taken),
    .rs1         (rs1_data),
    .imm         (imm),
    .pc          (pc)
);

instructionmem IMEM (
    .pc (pc),
    .rd (instruction)
);

// DECODE

assign opcode = instruction[6:0];
assign rd     = instruction[11:7];
assign funct3 = instruction[14:12];
assign rs1    = instruction[19:15];
assign rs2    = instruction[24:20];
assign funct7 = instruction[31:25];


// CONTROL UNIT

maincontrol CTRL (
    .opcode   (opcode),
    .regWrite (regWrite),
    .memRead  (memRead),
    .memWrite (memWrite),
    .memtoReg (memtoReg),
    .aluSrc   (aluSrc),
    .alu_src_a(alu_src_a),
    .aluOp    (aluOp),
    .immSel   (immSel),
    .branch   (branch),
    .jump     (jump),
    .jalr     (jalr)
);


// REGISTER FILE

reg_array RF (
    .sr1         (rs1),
    .sr2         (rs2),
    .wr          (rd),
    .wd          (write_data),
    .write_enable(regWrite),
    .clk         (clk),
    .rst         (reset),
    .rs1         (rs1_data),
    .rs2         (rs2_data)
);


// IMMEDIATE GENERATOR

immediate_generator IMM (
    .instruction(instruction),
    .immSel     (immSel),
    .immOut     (imm)
);


// OPERAND-A MUX  (supports LUI and AUIPC)
//   alu_src_a = 2'b00  ? rs1_data      (all R/I/Load/Store/Branch)
//   alu_src_a = 2'b01  ? 32'h0         (LUI:  0 + imm = imm)
//   alu_src_a = 2'b10  ? pc            (AUIPC: pc + imm)

assign alu_in1 = (alu_src_a == 2'b01) ? 32'd0 :
                 (alu_src_a == 2'b10) ? pc     :
                                        rs1_data;

// OPERAND-B MUX
assign alu_in2 = aluSrc ? imm : rs2_data;



// ALU CONTROL + ALU

alucontrol ALUCTRL (
    .ALUcontrol(ALUcontrol),
    .aluOp     (aluOp),
    .funct3    (funct3),
    .funct7    (funct7)
);

alu ALU (
    .operand_a (alu_in1),
    .operand_b (alu_in2),
    .alu_control(ALUcontrol),
    .alu_result(alu_result),
    .zero_flag (zero_flag),
    .comp_flag (comp_flag),
    .carry_flag(carry_flag),
    .sign_bit  (sign_bit),
    .borrow    (borrow),
    .overflow  (overflow)
);


// BRANCH CONDITION  (full RISC-V branch set)
//   BEQ  (000): A == B         ? zero_flag
//   BNE  (001): A != B         ? ~zero_flag
//   BLT  (100): A <s B         ? sign_bit ^ overflow  (signed)
//   BGE  (101): A >=s B        ? ~(sign_bit ^ overflow)
//   BLTU (110): A <u B         ? borrow  (no carry-out from A-B)
//   BGEU (111): A >=u B        ? ~borrow

always @(*) begin
    case (funct3)
        3'b000: branch_cond = zero_flag;               // BEQ
        3'b001: branch_cond = ~zero_flag;              // BNE
        3'b100: branch_cond =  sign_bit ^ overflow;    // BLT  (signed)
        3'b101: branch_cond = ~(sign_bit ^ overflow);  // BGE  (signed)
        3'b110: branch_cond =  borrow;                 // BLTU (unsigned)
        3'b111: branch_cond = ~borrow;                 // BGEU (unsigned)
        default: branch_cond = 1'b0;
    endcase
end

assign branch_taken = branch & branch_cond;

// DATA MEMORY

datamemory DMEM (
    .clk      (clk),
    .memRead  (memRead),
    .memWrite (memWrite),
    .funct3   (funct3),      // C3 fix: byte/halfword width select
    .address  (alu_result),
    .writeData(rs2_data),
    .readData (read_data)
);


// WRITE-BACK MUX
//   JAL / JALR  ? pc + 4  (link address)
//   Load        ? read_data
//   Otherwise   ? alu_result
//   (LUI / AUIPC already produce the correct alu_result)

assign write_data = (jump || jalr) ? (pc + 32'd4) :
                    memtoReg       ? read_data     :
                                     alu_result;

endmodule
