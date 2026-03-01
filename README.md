# Custom GPU ANN Accelerator

This repository contains the RTL implementation and custom software compiler for a 5-stage pipelined Custom GPU / Artificial Neural Network (ANN) Accelerator. Designed to execute compiled CUDA PTX kernels, the core features a dedicated Tensor Unit capable of performing SIMD (Single Instruction, Multiple Data) BFloat16 Fused Multiply-Accumulate (FMA) operations.

## 👥 Authors
**USC EE533 Group 2 Members: [Kevelyn Lin](https://github.com/WanYing1224), [Yuxiang Luo](https://github.com/lllyxxxx), [Ian Chen](https://github.com/ichen522)**

## 🏗️ Architecture Overview

The accelerator is built around a classic 5-stage RISC pipeline (Fetch, Decode, Execute, Memory, Writeback), enhanced with specialized data paths for machine learning workloads.

* **Datapath Width:** 64-bit memory and register buses.
* **Instruction Width:** 32-bit custom ISA.
* **Register File:** 16x64-bit hardware registers. Upgraded with **3 independent read ports** (`rs1`, `rs2`, `rs3`) and 1 write port (`rd`) to natively support 3-operand math.
* **Memory Architecture:** Separate Instruction ROM and Data RAM (BRAM). Data memory utilizes asynchronous combinational reads to eliminate 1-cycle latency bottlenecks during the MEM stage.

## 🧠 The Tensor Unit (AI Acceleration)

At the heart of the execution stage is the Tensor Unit, designed to accelerate the mathematical backbone of neural networks: the Fused Multiply-Accumulate operation ($D = (A \times B) + C$).

* **SIMD Execution:** The 64-bit datapath is sliced into four independent 16-bit lanes.
* **Data Type:** Hardware-level support for IEEE-754 **BFloat16** (1 sign bit, 8 exponent bits, 7 mantissa bits).
* **Parallel Processing:** Instantiates four parallel `bf16_mac` combinational cores to perform 4 simultaneous floating-point calculations in a single clock cycle.
* **Multiplexed Execution:** The Control Unit dynamically routes data between the standard Integer ALU (for memory offset calculation and integer math) and the Tensor Unit based on decoded opcodes.

## 🛡️ Control Unit & Hazard Mitigation

To maintain pipeline integrity during deep neural network workloads, the Control Unit implements rigorous, hardware-level hazard detection:

* **Scoreboard RAW Detection:** The hazard unit monitors all three read operands (`rs1`, `rs2`, `rs3`) against the destination registers (`rd`) currently in the EX, MEM, and WB stages.
* **Dynamic Stalling:** If a Read-After-Write (RAW) data hazard is detected (e.g., a `LD64` instruction fetching Vector C right before a `BF_MAC` instruction needs it), the unit asserts `stall_fetch` and injects `NOP` bubbles (`flush_execute`) until the data is safely written back to the Register File.
* **Control Hazards:** Automatically flushes the Fetch and Decode pipeline registers upon detecting a branch misprediction.

## ⚙️ Software Toolchain: PTX to Hex Compiler

This architecture does not run assembly natively; it executes real CUDA kernels. The repository includes a custom Python compiler (`ptx_parser.py`) that acts as a bridge between NVIDIA's `nvcc` and the Verilog hardware.

1.  **Kernel Target Lock:** The parser scans the `.ptx` file, ignores C++ standard library injections, and strictly locks onto target functions (e.g., `.visible .entry bf16_fma`).
2.  **Smart Register Allocation:** Dynamically maps PTX virtual registers (`%rd1`, `%rs2`) to available physical hardware registers (`R2`, `R3`, etc.).
3.  **Memory Mapping:** Automatically converts `.global` pointer logic into sequential hardware memory offsets.
4.  **Machine Code Generation:** Emits 32-bit binary strings conforming to the custom ISA and packages them into `gpu_program.hex` for ModelSim initialization.

## 🚀 Simulation and Testing

The design is rigorously verified using a ModelSim automated testbench (`gpu_top_tb.v`).

### Running the Verification Suite
1.  **Compile the Software:** bash: `
    python ptx_parser.py kernel.ptx
    `
    *This generates the `gpu_program.hex` instruction memory file.*
2.  **Initialize Test Vectors:** Ensure `data_memory.hex` contains the appropriately formatted 64-bit hexadecimal BFloat16 vectors.
3.  **Run ModelSim:** Compile the `hw_module` directory and execute the testbench.
4.  **Automated Success Monitoring:** The testbench runs a parallel verification block independent of the system clock. It actively monitors the `wb_data` bus and will automatically print a success trace to the transcript the exact picosecond the expected BFloat16 mathematical matrix sum successfully traverses the Writeback stage.
