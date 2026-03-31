module Data_Memory #(
    parameter MEM_DEPTH = 1024
)(
    input  wire        clk,

    // ── PCI Programming Interface ─────────────────────────────────────────
    input  wire        prog_mode,
    input  wire        prog_we,
    input  wire [31:0] prog_addr,
    input  wire [31:0] prog_wdata_lo,
    input  wire [31:0] prog_wdata_hi,

    // ── CPU Data Interface ────────────────────────────────────────────────
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [63:0] write_data,

    // ── Read Outputs ─────────────────────────────────────────────────────
    output wire [63:0] read_data,       // Async — zero latency for CPU pipeline (LD64)
    output reg  [63:0] prog_read_data   // Sync  — 1-cycle latency for prog readback only
);

    reg [63:0] ram [0:MEM_DEPTH-1];

    // ── Address Decoding ─────────────────────────────────────────────────
    wire [9:0] cpu_word_addr  = addr[12:3];
    wire [9:0] prog_word_addr = prog_addr[12:3];

    // ── Synchronous Write ────────────────────────────────────────────────
    always @(posedge clk) begin
        if (prog_mode && prog_we)
            ram[prog_word_addr] <= {prog_wdata_hi, prog_wdata_lo};
        else if (!prog_mode && we)
            ram[cpu_word_addr]  <= write_data;
    end

    // ── Asynchronous Read for CPU pipeline ───────────────────────────────
    assign read_data = ram[cpu_word_addr];

    // ── Synchronous Read for prog readback only ───────────────────────────
    always @(posedge clk) begin
        prog_read_data <= ram[prog_word_addr];
    end

endmodule
