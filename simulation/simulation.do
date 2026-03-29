# Reading C:/modeltech64_10.6e/tcl/vsim/pref.tcl
# //  ModelSim SE-64 10.6e Jun 23 2018
# //
# //  Copyright 1991-2018 Mentor Graphics Corporation
# //  All Rights Reserved.
# //
# //  ModelSim SE-64 and its associated documentation contain trade
# //  secrets and commercial or financial information that are the property of
# //  Mentor Graphics Corporation and are privileged, confidential,
# //  and exempt from disclosure under the Freedom of Information Act,
# //  5 U.S.C. Section 552. Furthermore, this information
# //  is prohibited from disclosure under the Trade Secrets Act,
# //  18 U.S.C. Section 1905.
# //
project open {C:/USC CE/EE533/Lab7/CustomGPU_ANN_Accelerator/simulation/CustomGPU_ANN_Accelerator.mpf}
# Loading project CustomGPU_ANN_Accelerator
vsim -gui work.gpu_top_tb -novopt
# vsim -gui work.gpu_top_tb -novopt 
# Start time: 18:20:54 on Feb 28,2026
# ** Warning: (vsim-8891) All optimizations are turned off because the -novopt switch is in effect. This will cause your simulation to run very slowly. If you are using this switch to preserve visibility for Debug or PLI features please see the User's Manual section on Preserving Object Visibility with vopt.
# Loading work.gpu_top_tb
# Loading work.gpu_top
# Loading work.Program_Counter
# Loading work.Instruction_Memory
# Loading work.Pipeline_Reg
# Loading work.Register_File
# Loading work.Control_Unit
# Loading work.Execution_Unit
# Loading work.Tensor_Unit
# Loading work.Data_Memory
add wave -position end  sim:/gpu_top_tb/clk
add wave -position end  sim:/gpu_top_tb/rst
add wave -position end  sim:/gpu_top_tb/host_thread_id
add wave -position end  sim:/gpu_top_tb/uut/ctrl_inst/stall_fetch
add wave -position end  sim:/gpu_top_tb/uut/ctrl_inst/flush_execute
add wave -position end  sim:/gpu_top_tb/uut/if_pc
add wave -position end  sim:/gpu_top_tb/uut/if_instr
add wave -position end  sim:/gpu_top_tb/uut/id_instr
add wave -position end  sim:/gpu_top_tb/uut/id_rs1_data
add wave -position end  sim:/gpu_top_tb/uut/id_rs2_data
add wave -position end  sim:/gpu_top_tb/uut/ex_opcode
add wave -position end  sim:/gpu_top_tb/uut/ex_rs1_data
add wave -position end  sim:/gpu_top_tb/uut/ex_rs2_data
add wave -position end  sim:/gpu_top_tb/uut/ex_alu_out
add wave -position end  sim:/gpu_top_tb/uut/wb_we_reg
add wave -position end  sim:/gpu_top_tb/uut/wb_rd_addr
add wave -position end  sim:/gpu_top_tb/uut/wb_data
add wave -position end  sim:/gpu_top_tb/uut/rf_inst/registers[1]
add wave -position end  sim:/gpu_top_tb/uut/rf_inst/registers[2]
add wave -position end  sim:/gpu_top_tb/uut/rf_inst/registers[3]
# Causality operation skipped due to absence of debug database file
