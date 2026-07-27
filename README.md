# RV32IM RISC-V Processor

![Language](https://img.shields.io/badge/Language-Verilog-blue.svg)
![Tools](https://img.shields.io/badge/Tool-Xilinx_Vivado-red.svg)


A highly optimized, synthesizable 5-stage pipelined RISC-V soft-core processor implementing the standard **RV32IM** instruction set architecture, designed from scratch in Verilog. This project explores advanced computer architecture and pipelined dataflow. It is built to serve as a lightweight, efficient compute core for applications.


## Table of Contents
1. [Project Structure](#1-project-structure)
2. [Architecture Overview](#2-architecture-overview)
3. [Pipeline Stages](#3-pipeline-stages)
4. [Supported Instructions](#4-supported-instructions)

## 1. Project Structure

```
rv32im-riscv-processor/
├── README.md
├── rtl/
│   ├── cla.v
│   ├── dataPathPipelined.v
│   ├── dividerUnsignedPipelined.v
│   ├── header.vh
│   ├── memory.v
│   ├── regfile.v
│   └── riscv_top.v
├── scripts/
│   ├── gds/
│   │   └── gds.py
│   ├── pd/
│   │   ├── constraints.sdc
│   │   ├── constraints.xdc
│   │   ├── pd_poststa.tcl
│   │   └── riscv_top.def
│   ├── sim/
│   │   └── run.do
│   ├── sta/
│   └── synth/
│       ├── riscv_top_netlist.v
│       └── synth.tcl
└── tb/
    ├── Makefile
    ├── tb_riscv_top.v
    └── testbench.py
```

## 2. Architecture Overview

The processor implements the classic RISC 5-stage pipeline with robust hazard mitigation. 

* **Forwarding/Bypassing:** Includes a comprehensive internal forwarding network. It features EX-to-EX (MX bypass), MEM-to-EX (WX bypass), and WB-to-ID (WD bypass) paths to resolve data dependencies without stalling.
* **Hardware Interlocks:** A dedicated Hazard Detection Unit automatically stalls the pipeline (inserting NOP bubbles) upon detecting Load-Use hazards.
* **Branch Prediction & Recovery:** Branches and jumps are resolved in the Execute stage. Upon a misprediction or taken branch, the Fetch and Decode stages are flushed seamlessly to maintain architectural state integrity.
* **Custom Execution Units:** Features a custom Carry Lookahead Adder (CLA) for rapid arithmetic and a dedicated 8-cycle pipelined unsigned divider for the 'M' extension.


## 3. Pipeline Stages

### 1. Fetch (IF)
Computes the next Program Counter (PC). Under normal execution, `PC = PC + 4`. If a branch or jump is taken, the Fetch unit cleanly recovers by fetching from the calculated target address, flushing the subsequent decode stage.

### 2. Decode (ID)
Extracts opcodes, registers, and immediate values. Immediate generation is fully multiplexed for I, S, B, U, and J type instructions. The Register File supports asynchronous reads and synchronous writes, heavily utilizing the WD bypass to allow reading a register in the same cycle it is being written.

### 3. Execute (EX)
The computational heart of the core. 
* Resolves Branch/Jump targets.
* Determines ALU inputs via the Forwarding Unit to prevent stale data usage.
* Computes `ADD`/`SUB` utilizing an external CLA module.
* Executes multiplication and 8-cycle division/remainder operations.

### 4. Memory (MEM)
Interfaces with the single-cycle memory module. Features precise byte-alignment logic to handle byte (`lb`, `sb`), half-word (`lh`, `sh`), and word (`lw`, `sw`) memory accesses, alongside zero-extension for unsigned loads (`lbu`, `lhu`).

### 5. Writeback (WB)
Selects between Memory Read Data and ALU Results to retire the instruction and write the final value back to the Register File.


## 4. Supported Instructions

This core fully implements the Unprivileged RV32I base integer instruction set and the M-Extension.

| Category                           | Instructions                                                           |
| ---------------------------------- | ---------------------------------------------------------------------- |
| Integer Computational (I-Type)     | `addi`, `slti`, `sltiu`, `xori`, `ori`, `andi`, `slli`, `srli`, `srai` |
| Integer Computational (R-Type)     | `add`, `sub`, `sll`, `slt`, `sltu`, `xor`, `srl`, `sra`, `or`, `and`   |
| Control Flow (Branches & Jumps)    | `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu`, `jal`, `jalr`              |
| Load/Store                         | `lb`, `lh`, `lw`, `lbu`, `lhu`, `sb`, `sh`, `sw`                       |
| Upper Immediate                    | `lui`, `auipc`                                                         |
| Environment                        | `ecall`                                                                |
| M-Extension (Multiply/Divide)      | `mul`, `mulh`, `mulhsu`, `mulhu`, `div`, `divu`, `rem`, `remu`         |

# 5. Simulation
To run all tests:
```
cd tb
make all
```





