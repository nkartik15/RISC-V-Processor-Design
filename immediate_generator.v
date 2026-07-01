module immediate_generator(instruction,immSel,immOut);
input [31:0]instruction;
input [2:0] immSel;
output reg [31:0]immOut;
localparam I_type=3'b000, S_type=3'b001, B_type=3'b010, U_type=3'b011, J_type=3'b100;
always @(*)
begin
	immOut=32'd0;
	case(immSel)
		I_type:	immOut={ {20{instruction[31]}}, instruction[31:20] };
		S_type:	immOut={ {20{instruction[31]}}, instruction[31:25], instruction[11:7] };
		B_type:	immOut={ {19{instruction[31]}}, instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0 };
		U_type:	immOut={ instruction[31:12], 12'b0 };
		J_type:	immOut={ {11{instruction[31]}}, instruction[31], instruction[19:12], instruction[20], instruction[30:21], 1'b0 };
		default: immOut=32'd0;
	endcase
end
endmodule
