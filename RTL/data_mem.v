// ====================================================================
// datamemory — byte/halfword/word access (C3 fix)
//
//  funct3:  000=LB/SB  001=LH/SH  010=LW/SW  100=LBU  101=LHU
//  Storage is byte-organised (little-endian), 256 words = 1 KB.
// ====================================================================
module datamemory(
    input         clk,
    input         memRead,
    input         memWrite,
    input  [2:0]  funct3,          // width/sign selector (C3 fix)
    input  [31:0] address,
    input  [31:0] writeData,
    output reg [31:0] readData
);

localparam N = 256;                // words → N*4 = 1024 bytes

reg [7:0] memory [0:N*4-1];       // byte-addressable

wire [9:0] byte_addr = address[9:0];

integer k;
initial begin
    for (k = 0; k < N*4; k = k + 1) memory[k] = 8'd0;
end

// ── WRITE (synchronous) ──────────────────────────────────────────────
always @(posedge clk) begin
    if (memWrite && (address < N*4)) begin
        case (funct3)
            3'b000: memory[byte_addr] <= writeData[7:0];              // SB
            3'b001: begin                                              // SH
                memory[byte_addr  ] <= writeData[7:0];
                memory[byte_addr+1] <= writeData[15:8];
            end
            default: begin                                             // SW
                memory[byte_addr  ] <= writeData[7:0];
                memory[byte_addr+1] <= writeData[15:8];
                memory[byte_addr+2] <= writeData[23:16];
                memory[byte_addr+3] <= writeData[31:24];
            end
        endcase
    end
end

// ── READ (combinational) ─────────────────────────────────────────────
always @(*) begin
    readData = 32'd0;
    if (memRead && (address < N*4)) begin
        case (funct3)
            3'b000: readData = {{24{memory[byte_addr][7]}},   memory[byte_addr]};               // LB
            3'b001: readData = {{16{memory[byte_addr+1][7]}}, memory[byte_addr+1], memory[byte_addr]}; // LH
            3'b010: readData = {memory[byte_addr+3], memory[byte_addr+2],
                                memory[byte_addr+1], memory[byte_addr]};                         // LW
            3'b100: readData = {24'd0, memory[byte_addr]};                                       // LBU
            3'b101: readData = {16'd0, memory[byte_addr+1], memory[byte_addr]};                  // LHU
            default: readData = {memory[byte_addr+3], memory[byte_addr+2],
                                 memory[byte_addr+1], memory[byte_addr]};
        endcase
    end
end

endmodule
