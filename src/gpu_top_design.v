`include "isa_defines.vh"

module gpu_top_design(
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] host_thread_id,

    // ── PCI Programming Interface ─────────────────────────────────────────
    input  wire        prog_en,
    input  wire        dmem_sel,
    input  wire        prog_we,
    input  wire [31:0] prog_addr,
    input  wire [31:0] prog_wdata_lo,
    input  wire [31:0] prog_wdata_hi,

    // ── Debug / Done Outputs ─────────────────────────────────────────────
    output wire [31:0] debug_pc,
    output wire        gpu_done,

    // ── GPU Result ───────────────────────────────────────────────────────
    output wire [63:0] gpu_result
);

    wire imem_prog = prog_en && !dmem_sel;
    wire dmem_prog = prog_en &&  dmem_sel;

    // =========================================================================
    // IF Stage
    // =========================================================================
    wire [31:0] if_pc, if_instr;
    wire [31:0] branch_target;
    wire        branch_taken;
    wire        stall_fetch;

    Program_Counter pc_inst(
        .clk          (clk),
        .rst          (rst),
        .stall_en     (stall_fetch),
        .branch_taken (branch_taken),
        .branch_target(branch_target),
        .pc           (if_pc)
    );

    assign debug_pc = if_pc;

    Instruction_Memory imem_inst(
        .clk       (clk),
        .prog_mode (imem_prog),
        .prog_we   (prog_we),
        .prog_addr (prog_addr),
        .prog_din  (prog_wdata_lo),
        .pc        (if_pc),
        .instr     (if_instr)
    );

    // =========================================================================
    // IF/ID Pipeline Register
    // =========================================================================
    wire        flush_decode;
    wire [31:0] id_pc, id_instr;

    Pipeline_Reg #(64) if_id_reg(
        .clk  (clk),
        .rst  (rst),
        .stall(stall_fetch),
        .flush(flush_decode),
        .d    ({if_pc, if_instr}),
        .q    ({id_pc, id_instr})
    );

    // =========================================================================
    // ID & RR Stage
    // =========================================================================
    wire [63:0] id_rs1_data, id_rs2_data, id_rs3_data;
    wire        stall_decode;
    wire        id_we_reg, id_we_mem, id_tensor_start;
    wire [3:0]  id_rd_addr = id_instr[25:22];
    wire [17:0] id_imm     = id_instr[17:0];

    wire        flush_execute;
    wire        tensor_busy;

    wire [3:0]  ex_rd_addr, mem_rd_addr, wb_rd_addr;
    wire        ex_we_reg,  mem_we_reg,  wb_we_reg;
    wire [63:0] wb_data;

    // ── ST64 store-data and hazard fix ────────────────────────────────────
    // ISA: ST64  Mem[Rs1 + Imm] <- Rd
    wire [3:0] rs3_read_addr = (id_instr[31:26] == `OP_ST64)
                                ? id_instr[25:22]   // ST64: Rd is the store source
                                : id_instr[13:10];  // all others: normal rs3

    Register_File rf_inst (
        .clk       (clk),
        .we        (wb_we_reg),
        .rs1_addr  (id_instr[21:18]),
        .rs2_addr  (id_instr[17:14]),
        .rs3_addr  (rs3_read_addr),      // remapped for ST64
        .rd_addr   (wb_rd_addr),
        .write_data(wb_data),
        .rs1_data  (id_rs1_data),
        .rs2_data  (id_rs2_data),
        .rs3_data  (id_rs3_data)
    );

    // Pass the EFFECTIVE rs3 address (after ST64 remapping) to the Control
    // Unit so that hazard_rs3 checks the right register (R5 for ST64, not R0).
    Control_Unit ctrl_inst(
        .instr_id    (id_instr),
        .tensor_busy (tensor_busy),
        .branch_eval (branch_taken),
        .rd_ex       (ex_rd_addr),  .we_ex  (ex_we_reg),
        .rd_mem      (mem_rd_addr), .we_mem (mem_we_reg),
        .rd_wb       (wb_rd_addr),  .we_wb  (wb_we_reg),
        .stall_fetch (stall_fetch),
        .stall_decode(stall_decode),
        .flush_decode(flush_decode),
        .flush_execute(flush_execute),
        .reg_write_en(id_we_reg),
        .mem_write_en(id_we_mem),
        .tensor_start(id_tensor_start),
        // Pass the remapped rs3 addr so hazard_rs3 checks R5 for ST64
        .rs3_override(rs3_read_addr)
    );

    wire [63:0] id_fwd_rs1 = (id_instr[31:26] == `OP_READ_TID) ?
                              {32'd0, host_thread_id} : id_rs1_data;

    // =========================================================================
    // ID/EX Pipeline Register
    // =========================================================================
    wire [31:0] ex_pc, ex_instr;
    wire [63:0] ex_rs1_data, ex_rs2_data, ex_rs3_data;
    wire [17:0] ex_imm;
    wire        ex_we_mem, ex_tensor_start;

    Pipeline_Reg #(217) id_ex_reg(
        .clk  (clk),
        .rst  (rst),
        .stall(1'b0),
        .flush(flush_execute),
        .d    ({id_pc, id_instr, id_fwd_rs1, id_rs2_data, id_imm,
                id_rd_addr, id_we_reg, id_we_mem, id_tensor_start}),
        .q    ({ex_pc, ex_instr, ex_rs1_data, ex_rs2_data, ex_imm,
                ex_rd_addr, ex_we_reg, ex_we_mem, ex_tensor_start})
    );

    Pipeline_Reg #(64) id_ex_rs3_reg(
        .clk  (clk),
        .rst  (rst),
        .stall(1'b0),
        .flush(flush_execute),
        .d    (id_rs3_data),
        .q    (ex_rs3_data)
    );

    // =========================================================================
    // EX Stage
    // =========================================================================
    wire [63:0] ex_alu_out, ex_tensor_out;
    wire        cmp_flag, tensor_done;
    wire [5:0]  ex_opcode = ex_instr[31:26];

    Execution_Unit alu_inst(
        .opcode   (ex_opcode),
        .rs1_data (ex_rs1_data),
        .rs2_data (ex_rs2_data),
        .alu_out  (ex_alu_out),
        .cmp_flag (cmp_flag)
    );

    Tensor_Unit tensor_inst(
        .clk     (clk),
        .rst     (rst),
        .start   (ex_tensor_start),
        .rs1_data(ex_rs1_data),
        .rs2_data(ex_rs2_data),
        .rs3_data(ex_rs3_data),
        .busy    (tensor_busy),
        .done    (tensor_done),
        .acc_out (ex_tensor_out)
    );

    assign branch_taken  = (ex_opcode == `OP_BRANCH) & cmp_flag;
    assign branch_target = ex_pc + {{14{ex_imm[17]}}, ex_imm};

    wire [63:0] ex_result =
        (ex_opcode == `OP_BF_MAC)                          ? ex_tensor_out :
        (ex_opcode == `OP_LD64 || ex_opcode == `OP_ST64)  ? (ex_rs1_data + {{46{ex_imm[17]}}, ex_imm}) :
        (ex_opcode == `OP_LDI)                             ? {{46{ex_imm[17]}}, ex_imm} :
        (ex_opcode == `OP_READ_TID)                        ? ex_rs1_data :
                                                              ex_alu_out;

    // =========================================================================
    // EX/MEM Pipeline Register
    // ST64 store data = ex_rs3_data (carries R5 via the remapped rs3 port)
    // =========================================================================
    wire [63:0] mem_alu_result, mem_store_data;
    wire        mem_we_mem;
    wire [5:0]  mem_opcode;

    wire [63:0] ex_store_data = (ex_opcode == `OP_ST64) ? ex_rs3_data : ex_rs2_data;

    Pipeline_Reg #(140) ex_mem_reg(
        .clk  (clk),
        .rst  (rst),
        .stall(1'b0),
        .flush(1'b0),
        .d    ({ex_result, ex_store_data, ex_rd_addr, ex_we_reg, ex_we_mem, ex_opcode}),
        .q    ({mem_alu_result, mem_store_data, mem_rd_addr, mem_we_reg, mem_we_mem, mem_opcode})
    );

    // =========================================================================
    // MEM Stage — async CPU read preserved (matches working hw_module design)
    // =========================================================================
    wire [63:0] mem_read_data;
    wire [63:0] dmem_prog_read_data;

    Data_Memory dmem_inst(
        .clk           (clk),
        .prog_mode     (dmem_prog),
        .prog_we       (prog_we),
        .prog_addr     (prog_addr),
        .prog_wdata_lo (prog_wdata_lo),
        .prog_wdata_hi (prog_wdata_hi),
        .we            (mem_we_mem),
        .addr          (mem_alu_result[31:0]),
        .write_data    (mem_store_data),
        .read_data     (mem_read_data),
        .prog_read_data(dmem_prog_read_data)
    );

    // =========================================================================
    // MEM/WB Pipeline Register
    // =========================================================================
    wire [63:0] wb_alu_result, wb_mem_read_data;
    wire [5:0]  wb_opcode;

    Pipeline_Reg #(139) mem_wb_reg(
        .clk  (clk),
        .rst  (rst),
        .stall(1'b0),
        .flush(1'b0),
        .d    ({mem_read_data, mem_alu_result, mem_rd_addr, mem_we_reg, mem_opcode}),
        .q    ({wb_mem_read_data, wb_alu_result, wb_rd_addr, wb_we_reg, wb_opcode})
    );

    // =========================================================================
    // WB Stage
    // =========================================================================
    assign wb_data = (wb_opcode == `OP_LD64) ? wb_mem_read_data : wb_alu_result;

    // =========================================================================
    // GPU RESULT REGISTER
    // =========================================================================
    reg [63:0] gpu_result_reg;

    always @(posedge clk) begin
        if (rst)
            gpu_result_reg <= 64'd0;
        else if (wb_opcode == `OP_BF_MAC && wb_we_reg)
            gpu_result_reg <= wb_data;
    end

    assign gpu_result = dmem_prog ? dmem_prog_read_data : gpu_result_reg;

    // =========================================================================
    // GPU DONE
    // =========================================================================
    localparam [31:0] PROG_END = 32'h00000018;

    reg gpu_done_reg;
    always @(posedge clk) begin
        if (rst || prog_en)
            gpu_done_reg <= 1'b0;
        else
            gpu_done_reg <= (if_pc >= PROG_END);
    end

    assign gpu_done = gpu_done_reg;

endmodule
