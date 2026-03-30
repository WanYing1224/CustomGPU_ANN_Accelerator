module Data_Memory #(
    parameter MEM_DEPTH = 1024
)(
    input  wire        clk,

    // ── PCI Programming Interface ─────────────────────────────────────────
    // prog_mode = 1: software drives addr/data, write enabled by prog_we
    // The PCI bus is 32-bit. Two registers (wdata_lo + wdata_hi) are assembled
    // into one 64-bit word and written together on the prog_we pulse.
    input  wire        prog_mode,      // HIGH during software loading
    input  wire        prog_we,        // Write strobe (synchronous, 1-cycle pulse)
    input  wire [31:0] prog_addr,      // Byte address from software
    input  wire [31:0] prog_wdata_lo,  // Lower 32 bits of 64-bit DMEM word
    input  wire [31:0] prog_wdata_hi,  // Upper 32 bits of 64-bit DMEM word

    // ── CPU Data Interface ────────────────────────────────────────────────
    input  wire        we,             // Write enable from pipeline (ST64)
    input  wire [31:0] addr,           // Computed address (Base + Offset) from EX stage
    input  wire [63:0] write_data,     // Store data from pipeline (ST64)

    output reg  [63:0] read_data       // Load data to pipeline (LD64), 1-cycle latency
);

    // 64-bit wide RAM — each entry is one 64-bit vector lane
    reg [63:0] ram [0:MEM_DEPTH-1];

/*
    initial begin
        $readmemh("data_memory.hex", ram);
    end
*/

    integer k;
    initial begin
        for (k = 0; k < MEM_DEPTH; k = k + 1)
            ram[k] = 64'h0000000000000000;
    end

    // ── Address Decoding ─────────────────────────────────────────────────
    // DMEM is 64-bit (8-byte) aligned:  word index = byte_addr >> 3
    wire [9:0] cpu_word_addr  = addr[12:3];
    wire [9:0] prog_word_addr = prog_addr[12:3];

    // ── Synchronous Write ────────────────────────────────────────────────
    // Two write sources:
    //   1. PCI programming (prog_mode=1): assembles 64-bit word from lo+hi regs
    //   2. CPU pipeline (prog_mode=0, we=1): normal ST64 store
    always @(posedge clk) begin
        if (prog_mode && prog_we)
            ram[prog_word_addr] <= {prog_wdata_hi, prog_wdata_lo};
        else if (!prog_mode && we)
            ram[cpu_word_addr]  <= write_data;
    end

    // ── Synchronous Read (1-cycle latency) ───────────────────────────────
    always @(posedge clk) begin
        if (prog_mode)
            read_data <= ram[prog_word_addr];
        else
            read_data <= ram[cpu_word_addr];
    end

endmodule
