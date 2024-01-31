# EILE - Efficient Incremental Learning on the Edge
This repo mainly contains:
- Source codes (SystemVerilog) for EILE, the MLP training accelerator, published at AICAS'21

# Project Structure
```
.
└── fcta.sv                 # Top module, FCTA is the internal code of EILE meaning "Fully-Connected network Training Accelerator"
└── fcta_bram_sdp.sv        # Simple Dual-Port (1R1W) BRAM
└── fcta_bram_tdp_nc.sv     # True Dual-Port BRAM
└── fcta_ccm.sv             # CCM (Core Computing Module)
└── fcta_cfg.sv             # Configure module, sends commands from FCTA_CTL to FCTA
└── fcta_ctl.sv             # Control module. Controlled by AXI4-Lite registers, reads commands, sends configurations to FCTA, sends MM2S/S2MM commands to AXI_Datamover
└── fcta_ipm.sv             # IPM (Input Processing Module)
└── fcta_macc.sv            # PE array (Parallel/Cascade mode)
└── fcta_opm.sv             # OPM (Output Processing Module)
└── fcta_pkg.sv             # Package for common data types
└── fcta_tb.sv              # Testbench for simulation
└── fcta.v                  # Verilog stub for FCTA (Needed for instantiating the RTL module in the Xilinx Vivado block design)
└── fcta_ctl.v              # Verilog stub for FCTA_CTL
└── fcta_ctl_reg.v          # AXI4-Lite registers for FCTA_CTL
```

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