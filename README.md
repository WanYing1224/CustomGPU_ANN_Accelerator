# Custom GPU ANN Accelerator

Design and implementation of a custom, standalone GPU processor targeting the NetFPGA. This project features a custom Instruction Set Architecture (ISA) and datapath designed to accelerate Artificial Neural Network (ANN) functions using 64-bit wide vector and tensor operations, including Google's BFloat16 support. The repository also contains the custom Python compiler toolchain built to parse and translate NVIDIA PTX assembly (compiled from CUDA kernels) into the custom GPU opcodes.

## 👥 Authors
**USC EE533 Group 2 Members: [Kevelyn Lin](https://github.com/WanYing1224), [Yuxiang Luo](https://github.com/lllyxxxx), [Ian Chen](https://github.com/ichen522)**

## Overview
This repository contains the design and implementation of a custom, standalone GPU processor targeting the NetFPGA platform. The primary objective of this architecture is to accelerate Artificial Neural Network (ANN) functions using 64-bit wide vector and tensor operations. 

Additionally, this repository hosts the custom compilation toolchain required to translate standard CUDA kernels (via NVIDIA's PTX assembly) into our custom GPU machine code.

## Architecture Highlights
* **Instruction Set Architecture (ISA):** Custom 32-bit instructions tailored for vector math and tensor operations.
* **Datapath:** Single Program Counter (PC) and single instruction stream executing on a custom Execution Unit and Tensor Unit.
* **Registers:** 64-bit wide registers treated as packed vectors of smaller data elements (e.g., four 16-bit elements processed simultaneously).
* **Data Types:** Native support for standard 16-bit integers and Google's BFloat16 floating-point SIMD operations.

## Directory Structure
* `/hw` - Verilog source files for the GPU hardware components (Datapath, ALU, Tensor Unit, Control Unit, and Memory Interface).
* `/sw/compiler` - Python parsing scripts to translate `.ptx` files into `.hex` custom GPU opcodes.
* `/sw/kernels` - CUDA source code (`kernel.cu`) containing vector operations (Addition, Subtraction, BFloat16 Multiply, BFloat16 Fused Multiply-Accumulate, and ReLU).

## Compilation Pipeline
Our software toolchain bridges standard CUDA C to our custom hardware using the following pipeline:
1. Write kernel in `kernel.cu`.
2. Compile to PTX: `nvcc -ptx -arch=sm_80 kernel.cu`
3. Translate to Machine Code: `python ptx_parser.py kernel.ptx > gpu_program.hex`
4. Load `.hex` into the GPU Instruction Memory for execution.

## Daily Commit Log
> **Note to team:** We must commit/push all modifications with detailed descriptions at least once daily. These records will be submitted along with the final GitHub link to Coursistant.
