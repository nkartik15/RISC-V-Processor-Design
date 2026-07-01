module maincontrol (
    input  [6:0] opcode,
    // Register / memory control
    output reg        regWrite,
    output reg        memRead,
    output reg        memWrite,
    output reg        memtoReg,
    // ALU / immediate control
    output reg        aluSrc,      // 0 = rs2,  1 = imm
    output reg [1:0]  alu_src_a,   // 00=rs1, 01=zero(LUI), 10=pc(AUIPC)
    output reg [1:0]  aluOp,
    output reg [2:0]  immSel,
    // Branch / jump
    output reg        branch,
    output reg        jump,
    output reg        jalr
);

localparam Rtype = 7'b0110011,
           Itype = 7'b0010011,
           Load  = 7'b0000011,
           Store = 7'b0100011,
           Branch= 7'b1100011,
           JAL   = 7'b1101111,
           JALR  = 7'b1100111,
           LUI   = 7'b0110111,
           AUIPC = 7'b0010111;

// immSel encoding (matches immediate_generator.v)
localparam I_IMM = 3'b000,
           S_IMM = 3'b001,
           B_IMM = 3'b010,
           U_IMM = 3'b011,
           J_IMM = 3'b100;

always @(*) begin
    // ---------- Safe defaults (avoid inferred latches) ----------
    regWrite  = 1'b0;
    memRead   = 1'b0;
    memWrite  = 1'b0;
    memtoReg  = 1'b0;
    aluSrc    = 1'b0;
    alu_src_a = 2'b00;
    branch    = 1'b0;
    jump      = 1'b0;
    jalr      = 1'b0;
    aluOp     = 2'b00;
    immSel    = I_IMM;

    case (opcode)

        Rtype: begin
            regWrite  = 1'b1;
            aluOp     = 2'b10;
        end

        Itype: begin          // ADDI, SLTI, ORI, ANDI, XORI, SLLI, SRLI, SRAI
            regWrite  = 1'b1;
            aluSrc    = 1'b1;
            aluOp     = 2'b11; // I-type: ignore funct7 except for shifts
            immSel    = I_IMM;
        end

        Load: begin           // LW, LH, LB, LHU, LBU
            regWrite  = 1'b1;
            aluSrc    = 1'b1;
            memRead   = 1'b1;
            memtoReg  = 1'b1;
            aluOp     = 2'b00; // ADD for address calculation
            immSel    = I_IMM;
        end

        Store: begin          // SW, SH, SB
            aluSrc    = 1'b1;
            memWrite  = 1'b1;
            aluOp     = 2'b00; // ADD for address calculation
            immSel    = S_IMM;
        end

        Branch: begin         // BEQ, BNE, BLT, BGE, BLTU, BGEU
            branch    = 1'b1;
            aluOp     = 2'b01; // SUB for comparison
            immSel    = B_IMM;
        end

        JAL: begin
            regWrite  = 1'b1;
            jump      = 1'b1;
            immSel    = J_IMM;
        end

        JALR: begin
            regWrite  = 1'b1;
            aluSrc    = 1'b1;
            jalr      = 1'b1;
            aluOp     = 2'b00; // ADD: rs1 + imm for target address
            immSel    = I_IMM;
        end

        LUI: begin
            regWrite  = 1'b1;
            aluSrc    = 1'b1;
            alu_src_a = 2'b01; // operand_a = 0  ?  result = 0 + imm = imm
            aluOp     = 2'b00;
            immSel    = U_IMM;
        end

        AUIPC: begin
            regWrite  = 1'b1;
            aluSrc    = 1'b1;
            alu_src_a = 2'b10; // operand_a = pc  ?  result = pc + imm
            aluOp     = 2'b00;
            immSel    = U_IMM;
        end

        default: ; // all outputs remain at safe defaults above
    endcase
end

endmodule

module alucontrol (
    input  [1:0] aluOp,
    input  [2:0] funct3,
    input  [6:0] funct7,
    output reg [3:0] ALUcontrol
);

// Encoding identical to alu.v localparams
localparam ADD  = 4'b0000,
           SUB  = 4'b1000,
           AND  = 4'b0111,
           OR   = 4'b0110,
           XOR  = 4'b0100,
           SLT  = 4'b0010,
           SLTU = 4'b0011,   // unsigned less-than (C2 fix)
           SLL  = 4'b0001,
           SRL  = 4'b0101,
           SRA  = 4'b1101;

wire [3:0] signal = {funct7[5], funct3};   // direct RISC-V encoding

always @(*) begin
    case (aluOp)
        2'b00: ALUcontrol = ADD;   // load, store, JALR, LUI, AUIPC

        2'b01: ALUcontrol = SUB;   // branch: compare via subtraction

        2'b10: begin               // R-type: use {funct7[5], funct3}
            case (signal)
                ADD:  ALUcontrol = ADD;
                SUB:  ALUcontrol = SUB;
                AND:  ALUcontrol = AND;
                OR :  ALUcontrol = OR;
                XOR:  ALUcontrol = XOR;
                SLT:  ALUcontrol = SLT;
                SLTU: ALUcontrol = SLTU;  // funct7[5]=0, funct3=011
                SLL:  ALUcontrol = SLL;
                SRL:  ALUcontrol = SRL;
                SRA:  ALUcontrol = SRA;
                default: ALUcontrol = ADD;
            endcase
        end

        2'b11: begin               // I-type: ignore funct7 except for shifts
            case (funct3)
                3'b000: ALUcontrol = ADD;  // ADDI
                3'b010: ALUcontrol = SLT;  // SLTI
                3'b011: ALUcontrol = SLTU; // SLTIU
                3'b100: ALUcontrol = XOR;  // XORI
                3'b110: ALUcontrol = OR;   // ORI
                3'b111: ALUcontrol = AND;  // ANDI
                3'b001: ALUcontrol = SLL;  // SLLI
                3'b101: ALUcontrol = funct7[5] ? SRA : SRL; // SRAI/SRLI
                default: ALUcontrol = ADD;
            endcase
        end

        default: ALUcontrol = ADD;
    endcase
end

endmodule
