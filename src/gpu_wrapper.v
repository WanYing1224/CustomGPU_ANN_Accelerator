`timescale 1ns/1ps

module gpu_wrapper 
   #(
      parameter DATA_WIDTH = 64,
      parameter CTRL_WIDTH = DATA_WIDTH/8,
      parameter UDP_REG_SRC_WIDTH = 2
   )
   (
      // --- Register interface (PCIe Communication)
      input                               reg_req_in,
      input                               reg_ack_in,
      input                               reg_rd_wr_L_in,
      input  [`UDP_REG_ADDR_WIDTH-1:0]    reg_addr_in,
      input  [`CPCI_NF2_DATA_WIDTH-1:0]   reg_data_in,
      input  [UDP_REG_SRC_WIDTH-1:0]      reg_src_in,

      output                              reg_req_out,
      output                              reg_ack_out,
      output                              reg_rd_wr_L_out,
      output [`UDP_REG_ADDR_WIDTH-1:0]    reg_addr_out,
      output [`CPCI_NF2_DATA_WIDTH-1:0]   reg_data_out,
      output [UDP_REG_SRC_WIDTH-1:0]      reg_src_out,

      // misc
      input                               reset,
      input                               clk
   );

   // Software registers (Fedora writes to these, GPU reads them)
   wire [31:0] gpu_cmd;
   wire [31:0] host_thread_id;
   
   // Hardware registers (GPU writes to these, Fedora reads them)
   wire [63:0] gpu_result;

   // Instantiate the Register Ring Bridge
   generic_regs
   #( 
      .UDP_REG_SRC_WIDTH   (UDP_REG_SRC_WIDTH),
      .TAG                 (`GPU_BLOCK_ADDR),         
      .REG_ADDR_WIDTH      (`GPU_REG_ADDR_WIDTH),    
      .NUM_COUNTERS        (0),            
      .NUM_SOFTWARE_REGS   (2),                 
      .NUM_HARDWARE_REGS   (2)                  
   ) module_regs (
      .reg_req_in       (reg_req_in),
      .reg_ack_in       (reg_ack_in),
      .reg_rd_wr_L_in   (reg_rd_wr_L_in),
      .reg_addr_in      (reg_addr_in),
      .reg_data_in      (reg_data_in),
      .reg_src_in       (reg_src_in),

      .reg_req_out      (reg_req_out),
      .reg_ack_out      (reg_ack_out),
      .reg_rd_wr_L_out  (reg_rd_wr_L_out),
      .reg_addr_out     (reg_addr_out),
      .reg_data_out     (reg_data_out),
      .reg_src_out      (reg_src_out),

      // SW regs interface
      .software_regs    ({host_thread_id, gpu_cmd}),

      // HW regs interface (Splitting 64-bit result into two 32-bit PCIe registers)
      .hardware_regs    ({gpu_result[63:32], gpu_result[31:0]}),

      .clk              (clk),
      .reset            (reset)
    );

    // GPU Design
    gpu_top_design custom_gpu_inst (
        .clk(clk),
        .rst(reset || gpu_cmd[0]), // Allow software to reset the GPU
        .host_thread_id(host_thread_id),
		.gpu_result(gpu_result)
    );

endmodule
