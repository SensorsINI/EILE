# EILE - Efficient Incremental Learning on the Edge
This repo mainly contains:
- Source codes (SystemVerilog) for EILE, the MLP training accelerator, published at AICAS'21

# Project Structure
```
.
└── HDL                     # HDL codes for EILE accelerator
    ├── fcta.sv                 # Top module, FCTA is the internal code of EILE meaning "Fully-Connected network Training Accelerator"
    ├── fcta_bram_sdp.sv        # Simple Dual-Port (1R1W) BRAM
    ├── fcta_bram_tdp_nc.sv     # True Dual-Port BRAM
    ├── fcta_ccm.sv             # CCM (Core Computing Module)
    ├── fcta_cfg.sv             # Configure module, sends commands from FCTA_CTL to FCTA
    ├── fcta_ctl.sv             # Control module. Controlled by AXI4-Lite registers, reads commands, sends configurations to FCTA, sends MM2S/S2MM commands to AXI_Datamover
    ├── fcta_ipm.sv             # IPM (Input Processing Module)
    ├── fcta_macc.sv            # PE array (Parallel/Cascade mode)
    ├── fcta_opm.sv             # OPM (Output Processing Module)
    ├── fcta_pkg.sv             # Package for common data types
    ├── fcta_tb.sv              # Testbench for simulation
    ├── fcta.v                  # Verilog stub for FCTA (Needed for instantiating the RTL module in the Xilinx Vivado block design)
    ├── fcta_ctl.v              # Verilog stub for FCTA_CTL
    └── fcta_ctl_reg.v          # AXI4-Lite registers for FCTA_CTL
└── sdk                     # C codes for the ARM CPU on Xilinx Zynq FPGA SoC
    ├── cfg_reg.h               # List of commands for the EILE controller
    ├── lscript.ld              # Linker script
    └── main.c                  # Main
└── block_design.tcl            # TCL script for creating the block design in Vivado
```

# Instructions

The project was tested on a Zynq-7 Mini-Module Plus board with Xilinx Vivado 2018.2.

1. Create a project using the above FPGA board in Xilinx Vivado.
2. Import HDL source codes from the *HDL* folder.
3. Create a block design with the provided script *block_design.tcl*.
4. Create a HDL wrapper for the block design and set as top.
5. Run normal FPGA SoC flow (Synthesis -> Implementation -> Generate Bitstream -> Export hardware including the bitstream -> Launch SDK).
6. In SDK, initialize BSP, create an application project with the codes from the *sdk* folder.
7. Compile and run the codes on FPGA, connect serial port to receive status and measured results for training.

# Reference
If you find this repository helpful, please cite our work.
- [AICAS 2021] EILE: Efficient Incremental Learning on the Edge
```
@INPROCEEDINGS{9458554,
  author={Chen, Xi and Gao, Chang and Delbruck, Tobi and Liu, Shih-Chii},
  booktitle={2021 IEEE 3rd International Conference on Artificial Intelligence Circuits and Systems (AICAS)}, 
  title={EILE: Efficient Incremental Learning on the Edge}, 
  year={2021},
  volume={},
  number={},
  pages={1-4},
  keywords={Training;Backpropagation;Random access memory;Bandwidth;Speech recognition;Throughput;System-on-chip;deep neural network;hardware accelerator;on-chip training;incremental learning;edge computing;FPGA},
  doi={10.1109/AICAS51828.2021.9458554}}
```