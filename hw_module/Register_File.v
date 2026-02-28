module Register_File (
    input wire clk,
    input wire rst,
    input wire we,         			// Write Enable from WB stage
    input wire [3:0] rs1_addr,   	// Port 1 address
    input wire [3:0] rs2_addr,   	// Port 2 address
    input wire [3:0] rd_addr,    	// Write address
    input wire [63:0] write_data, 	// Data from WB stage
	
    output wire [63:0] rs1_data,
    output wire [63:0] rs2_data
);

    reg [63:0] registers [0:15];
    integer i;

    always @(posedge clk or posedge rst) begin
        if(rst)
		begin
            for(i = 0; i < 16; i = i + 1) 
			begin
                registers[i] <= 64'd0;
            end
        end 
		
		else if(we && rd_addr != 4'd0) 
		begin 
            // Optional: Hardwire R0 to 0 if desired, otherwise remove rd_addr != 0 check
            registers[rd_addr] <= write_data;
        end
    end

    // Continuous assignment for read ports
    assign rs1_data = registers[rs1_addr];
    assign rs2_data = registers[rs2_addr];

endmodule
