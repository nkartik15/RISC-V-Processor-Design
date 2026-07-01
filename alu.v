module alu (
    input  [31:0] operand_a,
    input  [31:0] operand_b,
    input  [ 3:0] alu_control,

    output reg [31:0] alu_result,
    output reg        zero_flag,
    output reg        comp_flag,
    output reg        carry_flag,
    output reg        sign_bit,
    output reg        borrow,
    output reg        overflow
);

localparam ADD = 4'b0000,   // funct7[5]=0, funct3=000
           SUB = 4'b1000,   // funct7[5]=1, funct3=000
           AND = 4'b0111,   // funct7[5]=0, funct3=111
           OR  = 4'b0110,   // funct7[5]=0, funct3=110
           XOR = 4'b0100,   // funct7[5]=0, funct3=100
           SLT = 4'b0010,   // funct7[5]=0, funct3=010
           SLTU= 4'b0011,   // funct7[5]=0, funct3=011  (C2 fix)
           SLL = 4'b0001,   // funct7[5]=0, funct3=001
           SRL = 4'b0101,   // funct7[5]=0, funct3=101
           SRA = 4'b1101;   // funct7[5]=1, funct3=101

//  Shared subtract / add control
wire        is_sub = (alu_control == SUB) || (alu_control == SLT);
wire [31:0] b_mux  = is_sub ? ~operand_b : operand_b;
wire        cin    = is_sub ? 1'b1       : 1'b0;


//  CSLA (Carry-Select Adder with BEC)

wire [31:0] sum;
wire        carry_out;

csla_32_bec csla (
    .A   (operand_a),
    .B   (b_mux),
    .Cin (cin),
    .Sum (sum),
    .Cout(carry_out)
);


//  ALU datapath

always @(*) begin
    // Defaults (prevent latches)
    alu_result = 32'd0;
    carry_flag = 1'b0;
    borrow     = 1'b0;
    overflow   = 1'b0;
    comp_flag  = 1'b0;

    case (alu_control)

        ADD: begin
            alu_result = sum;
            carry_flag = carry_out;
            overflow   = (~operand_a[31] & ~operand_b[31] &  sum[31]) |
                         ( operand_a[31] &  operand_b[31] & ~sum[31]);
        end

        SUB: begin
            alu_result = sum;
            carry_flag = carry_out;
            borrow     = ~carry_out;          // borrow when no carry-out
            overflow   = (~operand_a[31] &  operand_b[31] &  sum[31]) |
                         ( operand_a[31] & ~operand_b[31] & ~sum[31]);
        end

        AND: alu_result = operand_a & operand_b;
        OR : alu_result = operand_a | operand_b;
        XOR: alu_result = operand_a ^ operand_b;

        SLT: begin
            // Signed less-than: result is 1 when A < B
            comp_flag  = (operand_a[31] != operand_b[31])
                             ? operand_a[31]   // different signs: negative < positive
                             : sum[31];        // same sign: check subtraction MSB
            alu_result = {31'd0, comp_flag};
        end

        SLTU: begin
            // Unsigned less-than: result is 1 when A <u B  (C2 fix)
            // borrow = ~carry_out from A - B; borrow=1 means A < B unsigned
            comp_flag  = ~carry_out;           // borrow signal from subtractor
            alu_result = {31'd0, comp_flag};
        end

        SLL: alu_result = operand_a << operand_b[4:0];
        SRL: alu_result = operand_a >> operand_b[4:0];
        SRA: alu_result = $signed(operand_a) >>> operand_b[4:0];

        default: alu_result = 32'd0;
    endcase

    zero_flag = (alu_result == 32'd0);
    sign_bit  = alu_result[31];
end

endmodule

//  32-bit Carry-Select Adder using Binary-to-Excess-1 Code

module csla_32_bec (
    input  [31:0] A,
    input  [31:0] B,
    input         Cin,
    output [31:0] Sum,
    output        Cout
);

wire [3:0] carry;   // carry propagated between 8-bit blocks

// ----- Block 0 (no mux needed ? directly driven by external Cin) -----
rca_8 rca0 (.A(A[7:0]), .B(B[7:0]), .Cin(Cin),  .Sum(Sum[7:0]),  .Cout(carry[0]));

// ----- Block 1 -----
wire [7:0] sum1_c0, sum1_c1;
wire       c1_c0, c1_c1;

rca_8 rca1_c0 (.A(A[15:8]), .B(B[15:8]), .Cin(1'b0), .Sum(sum1_c0), .Cout(c1_c0));
bec_8 bec1    (.in(sum1_c0), .out(sum1_c1));
// FIX: drive c1_c1 ? carry with Cin=1 equals c1_c0 OR all-ones sum
assign c1_c1    = c1_c0 | (&sum1_c0);
assign Sum[15:8] = carry[0] ? sum1_c1 : sum1_c0;
assign carry[1]  = carry[0] ? c1_c1   : c1_c0;

// ----- Block 2 -----
wire [7:0] sum2_c0, sum2_c1;
wire       c2_c0, c2_c1;

rca_8 rca2_c0 (.A(A[23:16]), .B(B[23:16]), .Cin(1'b0), .Sum(sum2_c0), .Cout(c2_c0));
bec_8 bec2    (.in(sum2_c0), .out(sum2_c1));
// FIX: drive c2_c1
assign c2_c1     = c2_c0 | (&sum2_c0);
assign Sum[23:16] = carry[1] ? sum2_c1 : sum2_c0;
assign carry[2]   = carry[1] ? c2_c1   : c2_c0;

// ----- Block 3 -----
wire [7:0] sum3_c0, sum3_c1;
wire       c3_c0, c3_c1;

rca_8 rca3_c0 (.A(A[31:24]), .B(B[31:24]), .Cin(1'b0), .Sum(sum3_c0), .Cout(c3_c0));
bec_8 bec3    (.in(sum3_c0), .out(sum3_c1));
// FIX: drive c3_c1
assign c3_c1     = c3_c0 | (&sum3_c0);
assign Sum[31:24] = carry[2] ? sum3_c1 : sum3_c0;
assign Cout       = carry[2] ? c3_c1   : c3_c0;

endmodule


// 8-bit Ripple-Carry Adder
module rca_8 (
    input  [7:0] A, B,
    input        Cin,
    output [7:0] Sum,
    output       Cout
);
    assign {Cout, Sum} = A + B + Cin;
endmodule

// 8-bit Binary-to-Excess-1 Code converter (sum + 1)
module bec_8 (
    input  [7:0] in,
    output [7:0] out
);
    assign out = in + 1'b1;
endmodule
