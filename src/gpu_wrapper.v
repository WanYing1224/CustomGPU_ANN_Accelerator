`timescale 1ns/1ps

module gpu_wrapper
   #(
      parameter DATA_WIDTH = 64,
      parameter CTRL_WIDTH = DATA_WIDTH/8,
      parameter UDP_REG_SRC_WIDTH = 2
   )
   (
      // Register interface (PCI communication)
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

      input                               reset,
      input                               clk
   );

   // ──────────────────────────────────────────────────────────────────────
   // Software Registers (host writes, GPU reads)
   // ──────────────────────────────────────────────────────────────────────
   // SW[0] 0x2000300  gpu_cmd
   //   bit[0] = reset    : assert GPU reset
   //   bit[1] = prog_en  : software owns memory address buses
   //   bit[2] = dmem_sel : 1=target DMEM, 0=target IMEM
   //   bit[3] = prog_we  : write strobe (pulse 1→0 commits one word)
   //
   // CMD quick reference:
   //   0x0  GPU running
   //   0x2  IMEM prog idle    (prog_en=1, dmem_sel=0, prog_we=0)
   //   0xA  IMEM write pulse  (prog_en=1, dmem_sel=0, prog_we=1)  [bit3=1,bit1=1]
   //   0x6  DMEM prog idle    (prog_en=1, dmem_sel=1, prog_we=0)
   //   0xE  DMEM write pulse  (prog_en=1, dmem_sel=1, prog_we=1)  [bit3=1,bit2=1,bit1=1]
   //
   // SW[1] 0x2000304  host_thread_id
   // SW[2] 0x2000308  prog_addr
   // SW[3] 0x200030c  prog_wdata_lo  (bits [31:0]  of 64-bit DMEM word / 32-bit IMEM word)
   // SW[4] 0x2000310  prog_wdata_hi  (bits [63:32] of 64-bit DMEM word, ignored for IMEM)
   // ──────────────────────────────────────────────────────────────────────
   wire [31:0] gpu_cmd;
   wire [31:0] host_thread_id;
   wire [31:0] prog_addr;
   wire [31:0] prog_wdata_lo;
   wire [31:0] prog_wdata_hi;

   // ──────────────────────────────────────────────────────────────────────
   // Hardware Registers (GPU writes, host reads)
   // ──────────────────────────────────────────────────────────────────────
   // HW[0] 0x2000314  gpu_result_low   [31:0]
   // HW[1] 0x2000318  gpu_result_high  [63:32]
   // HW[2] 0x200031c  gpu_pc           bit[31]=gpu_done, bit[7:0]=PC
   // ──────────────────────────────────────────────────────────────────────
   wire [63:0] gpu_result;
   wire [31:0] debug_pc;
   wire        gpu_done;

   wire [31:0] gpu_pc_reg = {gpu_done, 23'd0, debug_pc[7:0]};

   // ── Register Ring Bridge ──────────────────────────────────────────────
   generic_regs
   #(
      .UDP_REG_SRC_WIDTH  (UDP_REG_SRC_WIDTH),
      .TAG                (`GPU_BLOCK_ADDR),
      .REG_ADDR_WIDTH     (`GPU_REG_ADDR_WIDTH),
      .NUM_COUNTERS       (0),
      .NUM_SOFTWARE_REGS  (5),
      .NUM_HARDWARE_REGS  (3)
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

      // SW order (ids.xml): cmd(0), thread_id(1), prog_addr(2), wdata_lo(3), wdata_hi(4)
      .software_regs ({prog_wdata_hi, prog_wdata_lo, prog_addr, host_thread_id, gpu_cmd}),

      // HW order (ids.xml): result_low(0), result_high(1), gpu_pc(2)
      .hardware_regs ({gpu_pc_reg, gpu_result[63:32], gpu_result[31:0]}),

      .clk   (clk),
      .reset (reset)
   );

   // ── CMD Bit Extraction ────────────────────────────────────────────────
   wire gpu_rst  = reset || gpu_cmd[0];  // hardware reset OR software reset bit
   wire prog_en  = gpu_cmd[1];           // software owns memory buses
   wire dmem_sel = gpu_cmd[2];           // 0=IMEM target, 1=DMEM target
   wire prog_we  = gpu_cmd[3];           // write strobe

   // ── GPU Core ──────────────────────────────────────────────────────────
   gpu_top_design custom_gpu_inst (
      .clk          (clk),
      .rst          (gpu_rst),
      .host_thread_id(host_thread_id),

      // Programming interface
      .prog_en      (prog_en),
      .dmem_sel     (dmem_sel),
      .prog_we      (prog_we),
      .prog_addr    (prog_addr),
      .prog_wdata_lo(prog_wdata_lo),
      .prog_wdata_hi(prog_wdata_hi),

      // Done / debug
      .debug_pc     (debug_pc),
      .gpu_done     (gpu_done),

      // Result
      .gpu_result   (gpu_result)
   );

endmodule
