`timescale 1ns / 1ps

// =============================================================================
// gpu_top_tb.v — Custom GPU ANN Accelerator Testbench
// =============================================================================

module gpu_top_design_tb;

    // =========================================================================
    // CLOCK
    // =========================================================================
    reg clk;
    initial clk = 0;
    always #4 clk = ~clk;   // 125 MHz

    // =========================================================================
    // DUT CONNECTIONS
    // =========================================================================
    reg         rst;
    reg  [31:0] host_thread_id;
    reg         prog_en;
    reg         dmem_sel;
    reg         prog_we;
    reg  [31:0] prog_addr;
    reg  [31:0] prog_wdata_lo;
    reg  [31:0] prog_wdata_hi;
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
    // LOCAL ARRAYS — $readmemh loads files into testbench-only arrays.
    // The prog interface tasks then write each word into the hardware BRAMs,
    // exactly replicating what gpu_test.sh does over PCI on the NetFPGA.
    // =========================================================================
    reg [31:0] imem_data [0:1023];
    reg [63:0] dmem_data [0:1023];

    // =========================================================================
    // HELPER TASKS
    // =========================================================================

    task imem_write;
        input [31:0] baddr;
        input [31:0] word;
        begin
            @(posedge clk); #1;
            prog_addr     = baddr;
            prog_wdata_lo = word;
            prog_en       = 1;
            dmem_sel      = 0;
            prog_we       = 1;
            @(posedge clk); #1;
            prog_we       = 0;
        end
    endtask

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
            prog_we       = 1;
            @(posedge clk); #1;
            prog_we       = 0;
        end
    endtask

    // Synchronous DMEM read via prog interface (1-cycle BRAM latency)
    task dmem_read;
        input  [31:0] baddr;
        output [63:0] data_out;
        begin
            @(posedge clk); #1;
            prog_addr = baddr;
            prog_en   = 1;
            dmem_sel  = 1;
            prog_we   = 0;
            @(posedge clk); #1;   // 1st clock: address latches
            @(posedge clk); #1;   // 2nd clock: data valid
            data_out  = gpu_result;
        end
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    integer i;
    reg [63:0] readback;
    integer timeout_count;

    initial begin
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
        $display("[TB] [1] GPU held in reset.");
        repeat(4) @(posedge clk);

        // ── Load hex files into LOCAL arrays ─────────────────────────────
        $readmemh("C:/USC CE/EE533/Lab7/CustomGPU_ANN_Accelerator/src/gpu_program.hex", imem_data);
        $readmemh("C:/USC CE/EE533/Lab7/CustomGPU_ANN_Accelerator/src/data_memory.hex", dmem_data);
        $display("[TB]     Files read: gpu_program.hex, data_memory.hex");

        // ── [2] Load IMEM via prog interface ─────────────────────────────
        $display("[TB]");
        $display("[TB] [2] Loading IMEM (6 instructions)...");
        for (i = 0; i < 6; i = i + 1) begin
            imem_write(i * 4, imem_data[i]);
            $display("[TB]     IMEM[%0d] addr=0x%03h  data=0x%08h", i, i*4, imem_data[i]);
        end
        $display("[TB]     IMEM loaded.");

        // ── [3] Load DMEM via prog interface ─────────────────────────────
        $display("[TB]");
        $display("[TB] [3] Loading DMEM (3 entries)...");
        for (i = 0; i < 3; i = i + 1) begin
            dmem_write(i * 8, dmem_data[i][31:0], dmem_data[i][63:32]);
            $display("[TB]     DMEM[%0d] addr=0x%03h  data=0x%016h", i, i*8, dmem_data[i]);
        end
        $display("[TB]     DMEM loaded.");

        // ── [4] Verify DMEM readback ──────────────────────────────────────
        $display("[TB]");
        $display("[TB] [4] Verifying DMEM readback...");
        for (i = 0; i < 3; i = i + 1) begin
            dmem_read(i * 8, readback);
            $display("[TB]     DMEM[%0d] = 0x%016h  expected=0x%016h  %s",
                     i, readback, dmem_data[i],
                     (readback === dmem_data[i]) ? "OK" : "MISMATCH");
        end

        // ── [5] Set host_thread_id ────────────────────────────────────────
        $display("[TB]");
        $display("[TB] [5] host_thread_id = 0");
        host_thread_id = 32'd0;

        // ── [6] Release prog mode and reset ──────────────────────────────
        $display("[TB]");
        $display("[TB] [6] Releasing prog mode and reset — GPU executing...");
        @(posedge clk); #1;
        prog_en  = 0;
        dmem_sel = 0;
        prog_we  = 0;
        rst      = 0;

        // ── [7] Poll gpu_done ─────────────────────────────────────────────
        $display("[TB]");
        $display("[TB] [7] Polling gpu_done (PC >= 0x18)...");
        timeout_count = 0;
        while (gpu_done !== 1'b1) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
            if (timeout_count % 20 == 0)
                $display("[TB]     cycle %0d: PC=0x%02h  gpu_done=%b",
                         timeout_count, debug_pc[7:0], gpu_done);
            if (timeout_count >= 5000) begin
                $display("[TB] ERROR: Timeout — gpu_done never asserted.");
                $finish;
            end
        end
        $display("[TB]     gpu_done at cycle %0d  PC=0x%02h",
                 timeout_count, debug_pc[7:0]);

        // ── [8] Read GPU result ───────────────────────────────────────────
        // Wait a few cycles for the pipeline to finish draining cleanly.
        // gpu_result_reg is already latched when BF_MAC hit WB, so this
        // is just for waveform clarity — the value is stable immediately.
        repeat(3) @(posedge clk); #1;

        $display("[TB]");
        $display("[TB] ============================================");
        $display("[TB]  GPU Result:   0x%016h", gpu_result);
        $display("[TB]  Expected:     0x4060406040604060");
        $display("[TB]  (2.0 * 1.5) + 0.5 = 3.5 = 0x4060 per lane");
        if (gpu_result === 64'h4060406040604060) begin
            $display("[TB]  *** SUCCESS — Correct BFloat16 FMA result! ***");
        end else begin
            $display("[TB]  *** MISMATCH ***");
            $display("[TB]  Lane 3 [63:48] = 0x%04h  (exp 0x4060)", gpu_result[63:48]);
            $display("[TB]  Lane 2 [47:32] = 0x%04h  (exp 0x4060)", gpu_result[47:32]);
            $display("[TB]  Lane 1 [31:16] = 0x%04h  (exp 0x4060)", gpu_result[31:16]);
            $display("[TB]  Lane 0 [15: 0] = 0x%04h  (exp 0x4060)", gpu_result[15:0]);
        end
        $display("[TB] ============================================");

        // ── [9] Verify ST64 wrote result to DMEM ─────────────────────────
        // ST64 stores the BF_MAC result to DMEM[thread_id=0] = address 0x000.
        // We must wait for ST64 to fully drain through MEM stage before
        // entering prog_mode — otherwise prog_mode blocks the CPU write path.
        //
        // Worst case: ST64 is still in ID when gpu_done fires (~cycle 11).
        // It needs 3 more clocks to reach MEM stage.
        // We already waited 3 clocks above after gpu_done.
        // Add 10 more to be safe before asserting prog_mode.
        $display("[TB]");
        $display("[TB] [9] Waiting for ST64 to drain through MEM stage...");
        repeat(10) @(posedge clk);

        $display("[TB]     Reading DMEM[0] (ST64 stored result to Mem[thread_id+0])...");
        prog_en  = 1;
        dmem_sel = 1;
        prog_we  = 0;
        dmem_read(32'h0, readback);
        $display("[TB]     DMEM[0] = 0x%016h  %s",
                 readback,
                 (readback === 64'h4060406040604060) ? "OK — ST64 wrote correctly" :
                                                       "MISMATCH — check ST64 path");

        $display("[TB]");
        $display("[TB] Simulation complete.");
        #100;
        $finish;
    end

    // =========================================================================
    // CYCLE COUNTER & WAVEFORM DUMP
    // =========================================================================
    reg [31:0] sim_cycle;
    initial sim_cycle = 0;
    always @(posedge clk) sim_cycle <= sim_cycle + 1;

    initial begin
        $dumpfile("gpu_top_design_tb.vcd");
        $dumpvars(0, gpu_top_design_tb);
    end

endmodule
