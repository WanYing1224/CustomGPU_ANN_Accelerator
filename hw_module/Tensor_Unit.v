module Tensor_Unit(
    input wire clk,
    input wire rst,
    input wire start,      // Triggered by OP_TF_START
    input wire [63:0] rs1_data,
    input wire [63:0] rs2_data,
	
    output reg busy,
    output reg done,
    output reg [63:0] acc_out
);

    reg [1:0] state;
	
    localparam IDLE = 2'b00, MULTIPLY = 2'b01, ACCUMULATE = 2'b10;

    // Parallel BFloat16 outputs (from same sub-modules as EX unit, ideally shared)
    wire [63:0] parallel_bf_mul_res; 

    always @(posedge clk or posedge rst) begin
        if(rst) 
		begin
            state   <= IDLE;
            acc_out <= 64'd0;
            busy    <= 1'b0;
            done    <= 1'b0;
        end 
		
		else 
		begin
            case(state)
                IDLE: 
				begin
                    done <= 1'b0;
                    if(start) 
					begin
                        busy  <= 1'b1;
                        state <= MULTIPLY;
                    end
                end
				
                MULTIPLY: 
				begin
                    // Cycle 1: Let the combinational BF16 multipliers stabilize
                    state <= ACCUMULATE;
                end
				
                ACCUMULATE: 
				begin
                    // Cycle 2: Add to internal accumulator (requires BF16 Adders)
                    // acc_out <= BF16_ADD(acc_out, parallel_bf_mul_res);
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                end
				
            endcase
        end
    end
	
endmodule
