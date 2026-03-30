`timescale 1ns / 1ps

// =============================================================================
// gpu_top_tb.v — Custom GPU ANN Accelerator Testbench
//
// Mirrors gpu_test.sh step by step:
//   [1] Assert reset
//   [2] Load IMEM via prog interface (reads from gpu_program.hex)
//   [3] Load DMEM via prog interface (reads from data_memory.hex)
//   [4] Set host_thread_id
//   [5] Release prog mode and reset — GPU executes
//   [6] Poll gpu_done
//   [7] Read and verify gpu_result
//
// NOTE: $readmemh is used here in the TESTBENCH (not in the memory modules).
// The memory modules have $readmemh commented out because XST ignores it on
// hardware. The testbench loads the same files into local arrays and then
// drives the prog interface to write each word — exactly what gpu_test.sh
// does on the real NetFPGA via PCI register writes.
//
// Expected result: 0x4060406040604060
//   BFloat16 FMA: (2.0 × 1.5) + 0.5 = 3.5 = 0x4060 in each of 4 lanes
// =============================================================================

module gpu_top_design_tb;

    // =========================================================================
    // CLOCK
    // =========================================================================
    reg clk;
    initial clk = 0;
    always #4 clk = ~clk;   // 125 MHz — matches NetFPGA

    // =========================================================================
    // DUT CONNECTIONS
    // =========================================================================
    reg         rst;
    reg  [31:0] host_thread_id;

    // Programming interface (mirrors PCI register writes in gpu_test.sh)
    reg         prog_en;
    reg         dmem_sel;
    reg         prog_we;
    reg  [31:0] prog_addr;
    reg  [31:0] prog_wdata_lo;
    reg  [31:0] prog_wdata_hi;

    // Outputs
    wire [63:0] gpu_result;
    wire [31:0] debug_pc;
    wire        gpu_done;

    gpu_top_design dut (
        .clk           (clk),
        .rst           (rst),
        .host_thread_id(host_thread_id),
        .prog_en       (prog_en),
        .dmem_sel      (dmem_sel),
        .prog_we       (prog_we),
        .prog_addr     (prog_addr),
        .prog_wdata_lo (prog_wdata_lo),
        .prog_wdata_hi (prog_wdata_hi),
        .debug_pc      (debug_pc),
        .gpu_done      (gpu_done),
        .gpu_result    (gpu_result)
    );

    // =========================================================================
    // LOCAL MEMORY ARRAYS — loaded from the same files used on hardware
    // =========================================================================
    // IMEM: 32-bit instruction words (same format as gpu_program.hex)
    reg [31:0] imem_data [0:1023];

    // DMEM: 64-bit data words (same format as data_memory.hex)
    // $readmemh reads 64-bit hex values into 64-bit array entries
    reg [63:0] dmem_data [0:1023];

    // =========================================================================
    // HELPER TASKS — mirrors the PCI register write sequence in gpu_test.sh
    // =========================================================================

    // Write one 32-bit instruction word to IMEM at byte address 'baddr'
    // Mirrors in gpu_test.sh:
    //   gpureg write PROG_ADDR baddr
    //   gpureg write PROG_WDATA_LO word
    //   gpureg write CMD 0xA   (prog_en=1, dmem_sel=0, prog_we=1)
    //   gpureg write CMD 0x2   (prog_en=1, dmem_sel=0, prog_we=0)
    task imem_write;
        input [31:0] baddr;
        input [31:0] word;
        begin
            @(posedge clk); #1;
            prog_addr     = baddr;
            prog_wdata_lo = word;
            prog_en       = 1;
            dmem_sel      = 0;
            prog_we       = 1;   // CMD = 0xA
            @(posedge clk); #1;
            prog_we       = 0;   // CMD = 0x2 (deassert write strobe)
        end
    endtask

    // Write one 64-bit data word to DMEM at byte address 'baddr'
    // PCI is 32-bit, so lo and hi are passed separately — same as gpu_test.sh.
    // Mirrors in gpu_test.sh:
    //   gpureg write PROG_ADDR baddr
    //   gpureg write PROG_WDATA_LO lo
    //   gpureg write PROG_WDATA_HI hi
    //   gpureg write CMD 0xE   (prog_en=1, dmem_sel=1, prog_we=1)
    //   gpureg write CMD 0x6   (prog_en=1, dmem_sel=1, prog_we=0)
    task dmem_write;
        input [31:0] baddr;
        input [31:0] lo;
        input [31:0] hi;
        begin
            @(posedge clk); #1;
            prog_addr     = baddr;
            prog_wdata_lo = lo;
            prog_wdata_hi = hi;
            prog_en       = 1;
            dmem_sel      = 1;
            prog_we       = 1;   // CMD = 0xE
            @(posedge clk); #1;
            prog_we       = 0;   // CMD = 0x6 (deassert write strobe)
        end
    endtask

    // Read one 64-bit word from DMEM (2-clock settle for synchronous BRAM)
    task dmem_read;
        input  [31:0] baddr;
        output [63:0] data_out;
        begin
            @(posedge clk); #1;
            prog_addr = baddr;
            prog_en   = 1;
            dmem_sel  = 1;
            prog_we   = 0;
            @(posedge clk); #1;  // 1st clock: address latches into BRAM
            @(posedge clk); #1;  // 2nd clock: data valid at output
            data_out  = gpu_result;  // gpu_result reflects DMEM read in prog_mode
        end
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    integer i;
    integer imem_word_count;
    integer dmem_word_count;
    reg [63:0] readback;
    integer timeout_count;

    initial begin
        // ── Initialise all signals ────────────────────────────────────────
        rst            = 1;
        prog_en        = 0;
        dmem_sel       = 0;
        prog_we        = 0;
        prog_addr      = 0;
        prog_wdata_lo  = 0;
        prog_wdata_hi  = 0;
        host_thread_id = 32'd0;

        $display("[TB] ============================================");
        $display("[TB]  Custom GPU ANN Accelerator — ModelSim Test");
        $display("[TB] ============================================");

        // ── [1] Assert Reset ─────────────────────────────────────────────
        $display("[TB]");
        $display("[TB] [1] GPU held in reset.");
        repeat(4) @(posedge clk);

        // ── Load files into local arrays ──────────────────────────────────
        // $readmemh lives here in the TESTBENCH (not in the memory modules).
        // On hardware, gpu_test.sh drives these same values over PCI.
        $readmemh("C:/USC CE/EE533/Lab7/CustomGPU_ANN_Accelerator/src/gpu_program.hex",  imem_data);
        $readmemh("C:/USC CE/EE533/Lab7/CustomGPU_ANN_Accelerator/src/data_memory.hex",  dmem_data);
        $display("[TB]     Files loaded: gpu_program.hex, data_memory.hex");

        // Count valid IMEM words (non-zero entries from the file)
        // gpu_program.hex has 6 instructions
        imem_word_count = 6;
        // Count DMEM entries: data_memory.hex has 3 lines
        dmem_word_count = 3;

        // ── [2] Load IMEM over prog interface ────────────────────────────
        $display("[TB]");
        $display("[TB] [2] Loading IMEM (%0d instructions from gpu_program.hex)...",
                 imem_word_count);
        for (i = 0; i < imem_word_count; i = i + 1) begin
            imem_write(i * 4, imem_data[i]);
            $display("[TB]     IMEM[%0d] addr=0x%03h  data=0x%08h", i, i*4, imem_data[i]);
        end
        $display("[TB]     IMEM loaded.");

        // ── [3] Load DMEM over prog interface ────────────────────────────
        $display("[TB]");
        $display("[TB] [3] Loading DMEM (%0d entries from data_memory.hex)...",
                 dmem_word_count);
        for (i = 0; i < dmem_word_count; i = i + 1) begin
            // Split each 64-bit dmem_data entry into lo[31:0] and hi[63:32]
            dmem_write(i * 8, dmem_data[i][31:0], dmem_data[i][63:32]);
            $display("[TB]     DMEM[%0d] addr=0x%03h  data=0x%016h", i, i*8, dmem_data[i]);
        end
        $display("[TB]     DMEM loaded.");

        // ── [4] Verify DMEM (readback) ────────────────────────────────────
        $display("[TB]");
        $display("[TB] [4] Verifying DMEM readback (2-clock BRAM latency)...");
        for (i = 0; i < dmem_word_count; i = i + 1) begin
            dmem_read(i * 8, readback);
            $display("[TB]     DMEM[%0d] = 0x%016h  expected=0x%016h  %s",
                     i, readback, dmem_data[i],
                     (readback === dmem_data[i]) ? "OK" : "MISMATCH");
        end

        // ── [5] Set host_thread_id ────────────────────────────────────────
        $display("[TB]");
        $display("[TB] [5] Setting host_thread_id = 0");
        host_thread_id = 32'd0;

        // ── [6] Release prog mode and reset — GPU starts executing ────────
        $display("[TB]");
        $display("[TB] [6] Releasing prog mode and reset — GPU executing...");
        @(posedge clk); #1;
        prog_en  = 0;
        dmem_sel = 0;
        prog_we  = 0;
        rst      = 0;

        // ── [7] Poll gpu_done ─────────────────────────────────────────────
        $display("[TB]");
        $display("[TB] [7] Polling gpu_done (asserts when PC >= 0x18)...");
        timeout_count = 0;
        while (gpu_done !== 1'b1) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
            if (timeout_count % 20 == 0)
                $display("[TB]     cycle %0d: PC=0x%02h  gpu_done=%b",
                         timeout_count, debug_pc[7:0], gpu_done);
            if (timeout_count >= 5000) begin
                $display("[TB] ERROR: Timeout at cycle %0d — gpu_done never asserted.",
                         timeout_count);
                $display("[TB]   Last PC    = 0x%08h", debug_pc);
                $display("[TB]   gpu_result = 0x%016h", gpu_result);
                $finish;
            end
        end
        $display("[TB]     gpu_done asserted at cycle %0d  PC=0x%02h",
                 timeout_count, debug_pc[7:0]);

        // ── [8] Read GPU result ───────────────────────────────────────────
        // Give one extra clock for the WB stage to propagate the final result
        @(posedge clk); #1;

        $display("[TB]");
        $display("[TB] ============================================");
        $display("[TB]  GPU Result:   0x%016h", gpu_result);
        $display("[TB]  Expected:     0x4060406040604060");
        $display("[TB]  Computation:  (2.0 * 1.5) + 0.5 = 3.5");
        $display("[TB]  BF16 3.5   =  0x4060 per lane");
        if (gpu_result === 64'h4060406040604060) begin
            $display("[TB]  *** SUCCESS — Correct BFloat16 FMA result! ***");
        end else begin
            $display("[TB]  *** MISMATCH — Incorrect result. ***");
            $display("[TB]");
            $display("[TB]  Per-lane breakdown:");
            $display("[TB]    Lane 3 [63:48] = 0x%04h  (expected 0x4060)", gpu_result[63:48]);
            $display("[TB]    Lane 2 [47:32] = 0x%04h  (expected 0x4060)", gpu_result[47:32]);
            $display("[TB]    Lane 1 [31:16] = 0x%04h  (expected 0x4060)", gpu_result[31:16]);
            $display("[TB]    Lane 0 [15: 0] = 0x%04h  (expected 0x4060)", gpu_result[15:0]);
        end
        $display("[TB] ============================================");

        // ── [9] Read back result from DMEM (what ST64 wrote) ─────────────
        $display("[TB]");
        $display("[TB] [8] Reading result from DMEM (ST64 stored to Mem[thread_id+0])...");
        @(posedge clk); #1;
        prog_en  = 1;
        dmem_sel = 1;
        prog_we  = 0;
        // thread_id=0, so result was stored at DMEM address 0x000
        dmem_read(32'h0, readback);
        $display("[TB]     DMEM[0] = 0x%016h", readback);
        if (readback === 64'h4060406040604060)
            $display("[TB]     DMEM readback correct — ST64 wrote the right value.");
        else
            $display("[TB]     DMEM readback MISMATCH — ST64 may not have executed.");

        $display("[TB]");
        $display("[TB] Simulation complete.");
        #100;
        $finish;
    end

    // =========================================================================
    // CYCLE COUNTER
    // =========================================================================
    reg [31:0] sim_cycle;
    initial sim_cycle = 0;
    always @(posedge clk) sim_cycle <= sim_cycle + 1;

    // =========================================================================
    // WAVEFORM DUMP
    // =========================================================================
    initial begin
        $dumpfile("gpu_top_design_tb.vcd");
        $dumpvars(0, gpu_top_design_tb);
    end

endmodule
