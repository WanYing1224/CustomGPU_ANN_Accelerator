module Control_Unit(
    input wire [31:0] instr_id,
    input wire tensor_busy,
    input wire branch_eval,

    // Scoreboard tracking
    input wire [3:0] rd_ex, rd_mem, rd_wb,
    input wire we_ex, we_mem, we_wb,

    // Effective rs3 address after any remapping in the top level.
    // For ST64 this is instr[25:22] (the Rd field = store-value register).
    // For all other instructions this is instr[13:10] (the normal rs3 field).
    // Passing it in here ensures hazard_rs3 checks the right register.
    input wire [3:0] rs3_override,

    output reg stall_fetch,
    output reg stall_decode,
    output reg flush_decode,
    output reg flush_execute,
    output reg reg_write_en,
    output reg mem_write_en,
    output reg tensor_start
);

    wire [5:0] opcode = instr_id[31:26];
    wire [3:0] rs1    = instr_id[21:18];
    wire [3:0] rs2    = instr_id[17:14];
    // rs3 is now supplied by rs3_override (already remapped for ST64)

    // Scoreboard / RAW Hazard Detection
    wire hazard_rs1 = (rs1 != 0) && ((rs1 == rd_ex && we_ex) || (rs1 == rd_mem && we_mem) || (rs1 == rd_wb && we_wb));
    wire hazard_rs2 = (rs2 != 0) && ((rs2 == rd_ex && we_ex) || (rs2 == rd_mem && we_mem) || (rs2 == rd_wb && we_wb));
    // hazard_rs3 now uses rs3_override, so for ST64 it correctly checks R5
    wire hazard_rs3 = (rs3_override != 0) && ((rs3_override == rd_ex && we_ex) || (rs3_override == rd_mem && we_mem) || (rs3_override == rd_wb && we_wb));

    wire raw_hazard = hazard_rs1 | hazard_rs2 | hazard_rs3;

    always @(*) begin
        stall_fetch   = 1'b0;
        stall_decode  = 1'b0;
        flush_decode  = 1'b0;
        flush_execute = 1'b0;
        reg_write_en  = 1'b0;
        mem_write_en  = 1'b0;
        tensor_start  = 1'b0;

        if (opcode == 6'b100100 && tensor_busy) begin
            stall_fetch  = 1'b1;
            stall_decode = 1'b1;
        end
        else if (raw_hazard) begin
            stall_fetch   = 1'b1;
            stall_decode  = 1'b1;
            flush_execute = 1'b1;
        end

        if (branch_eval) begin
            flush_decode  = 1'b1;
            flush_execute = 1'b1;
            stall_fetch   = 1'b0;
        end

        if (opcode == 6'b010000 || opcode == 6'b010001 || opcode == 6'b000001 ||
            opcode == 6'b000010 || opcode == 6'b000011 || opcode == 6'b100000 ||
            opcode == 6'b100001 || opcode == 6'b100010)
            reg_write_en = 1'b1;

        if (opcode == 6'b000100) mem_write_en = 1'b1;  // ST64

        if (opcode == 6'b100000 || opcode == 6'b100001 || opcode == 6'b100011)
            tensor_start = 1'b1;
    end

endmodule
