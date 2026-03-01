`timescale 1ns / 1ps

module gpu_top_tb();

    // Inputs
    reg clk;
    reg rst;
    reg [31:0] host_thread_id;

    // Instantiate the Unit Under Test (UUT)
    gpu_top uut (
        .clk(clk),
        .rst(rst),
        .host_thread_id(host_thread_id)
    );

    // Clock Generation (100MHz)
    always #5 clk = ~clk;

    initial begin
        // Setup Waveform Dumping for Vivado / GTKWave
        $dumpfile("gpu_pipeline.vcd");
        $dumpvars(0, gpu_top_tb);

        // Initialize Inputs
        clk = 0;
        rst = 1;
        host_thread_id = 32'd0;

        // Wait 20 ns for global reset
        #20;
        
        // Release reset and inject a simulated CUDA threadIdx.x
        rst = 0;
        host_thread_id = 32'd10; 
        
        $display("--- SIMULATION STARTED ---");
        $display("Time | PC   | WB_Opcode | WB_Reg | WB_Data (64-bit)");

        // Monitor Writeback stage to verify data successfully traversed the pipeline
        $monitor("%4t | %h |   %b  |   R%0d  | %h", 
                 $time, 
                 uut.pc_inst.pc, 
                 uut.wb_opcode, 
                 uut.wb_rd_addr, 
                 uut.wb_data);

        // Allow the pipeline to run long enough for the compiled CUDA kernel
        // Increased from 100ns to 500ns
        #120;

        $display("--- SIMULATION COMPLETE ---");
        $display("Check ModelSim waveforms to verify Data Memory loads and Tensor Unit outputs.");
        $finish;
    end

	initial begin
        wait(uut.wb_data == 64'h4060406040604060); // 3.5 in BFloat16
        $display("==================================================");
        $display("SUCCESS: bf16_fma executed perfectly at time %0t!", $time);
        $display("Tensor Unit computed: %h", uut.wb_data);
        $display("==================================================");
    end
    
endmodule
