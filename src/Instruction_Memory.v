module Instruction_Memory #(
    parameter MEM_DEPTH = 1024
)(
    input  wire        clk,

    // ── PCI Programming Interface ─────────────────────────────────────────
    // prog_mode = 1: software drives addr/data, write enabled by prog_we
    // prog_mode = 0: PC drives addr, read-only
    input  wire        prog_mode,   // HIGH during software loading
    input  wire        prog_we,     // Write strobe (synchronous, 1-cycle pulse)
    input  wire [31:0] prog_addr,   // Byte address from software
    input  wire [31:0] prog_din,    // 32-bit instruction word from software

    // ── CPU Fetch Interface ───────────────────────────────────────────────
    input  wire [31:0] pc,          // Current program counter
    output wire [31:0] instr        // Instruction word to pipeline (async read)
);

    reg [31:0] rom [0:MEM_DEPTH-1];
/*
    initial begin
        $readmemh("gpu_program.hex", rom);
    end
*/
    // ── Synchronous Write (PCI loading) ──────────────────────────────────
    always @(posedge clk) begin
        if (prog_mode && prog_we)
            rom[prog_addr[11:2]] <= prog_din;
    end

    // ── Asynchronous Read (CPU fetch, zero latency) ───────────────────────
    assign instr = rom[pc[11:2]];

endmodule
