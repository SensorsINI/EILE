
`timescale 1 ns / 1 ps

`define C_M_AXIS_CMD_DATA_WIDTH (CFG_BW+AXI_DM_CMD_WIDTH*2)
`define CNT_BW                  (16)

module FCTA_CTL_wrapper #(

    // Parameters of AXILite Slave Bus Interface S_AXI
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 32,

    // Parameters of BRAM Master Interface BRAM
    parameter C_BRAM_ADDR_WIDTH = 32,
    parameter C_BRAM_DATA_WIDTH = 256,

    // Parameters of AXIS Master Bus Interface M_AXIS_FCTA_CFG
    parameter CFG_BW            = 96,

    // Parameters of AXIS Master Bus Interface M_AXIS_MM2S_CMD
    // Parameters of AXIS Master Bus Interface M_AXIS_S2MM_CMD
    parameter AXI_DM_CMD_WIDTH  = 72,

    // Parameters of AXIS Slave Bus Interface S_AXIS_MM2S_STS
    // Parameters of AXIS Slave Bus Interface S_AXIS_S2MM_STS
    parameter AXI_DM_STS_WIDTH  = 8

    // Parameters of AXIS Master Bus Interface M_AXIS_CMD
    // localparam C_M_AXIS_CMD_DATA_WIDTH = CFG_BW+AXI_DM_CMD_WIDTH*2,

    // localparam CNT_BW           = 16

) (

    input  wire                                 clk,
    input  wire                                 rstn,

    // Ports of AXILite Slave Bus Interface S_AXI
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0]      s_axi_awaddr,
    input  wire [2 : 0]                         s_axi_awprot,
    input  wire                                 s_axi_awvalid,
    output wire                                 s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1 : 0]      s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0]  s_axi_wstrb,
    input  wire                                 s_axi_wvalid,
    output wire                                 s_axi_wready,
    output wire [1 : 0]                         s_axi_bresp,
    output wire                                 s_axi_bvalid,
    input  wire                                 s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0]      s_axi_araddr,
    input  wire [2 : 0]                         s_axi_arprot,
    input  wire                                 s_axi_arvalid,
    output wire                                 s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0]      s_axi_rdata,
    output wire [1 : 0]                         s_axi_rresp,
    output wire                                 s_axi_rvalid,
    input  wire                                 s_axi_rready,

    // Ports of BRAM Master Interface BRAM
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM CLK" *)
    (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL,MEM_ECC NONE,MEM_WIDTH 256,MEM_SIZE 1024,READ_WRITE_MODE READ_WRITE" *)
    output wire                                 bram_clkb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM RST" *)
    output wire                                 bram_rstb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM ADDR" *)
    output wire [C_BRAM_ADDR_WIDTH-1 : 0]       bram_addrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM DIN" *)
    output wire [C_BRAM_DATA_WIDTH-1 : 0]       bram_dinb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM DOUT" *)
    input  wire [C_BRAM_DATA_WIDTH-1 : 0]       bram_doutb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM EN" *)
    output wire                                 bram_enb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM WE" *)
    output wire [(C_BRAM_DATA_WIDTH/8)-1 : 0]   bram_web,

    // Ports of AXIS Master Bus Interface M_AXIS_CMD
    output wire                                 m_axis_cmd_tvalid,
    output wire [`C_M_AXIS_CMD_DATA_WIDTH-1 : 0] m_axis_cmd_tdata,
    input  wire                                 m_axis_cmd_tready,

    // Ports of AXIS Slave Bus Interface S_AXIS_MM2S_STS
    input  wire                                 s_axis_mm2s_sts_tvalid,
    input  wire                                 s_axis_mm2s_sts_tlast,
    input  wire [AXI_DM_STS_WIDTH-1 : 0]        s_axis_mm2s_sts_tdata,
    output wire                                 s_axis_mm2s_sts_tready,

    // Ports of AXIS Slave Bus Interface S_AXIS_S2MM_STS
    input  wire                                 s_axis_s2mm_sts_tvalid,
    input  wire                                 s_axis_s2mm_sts_tlast,
    input  wire [AXI_DM_STS_WIDTH-1 : 0]        s_axis_s2mm_sts_tdata,
    output wire                                 s_axis_s2mm_sts_tready

);



    FCTA_CTL #(
        .C_S_AXI_DATA_WIDTH     (C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH     (C_S_AXI_ADDR_WIDTH),
        .C_BRAM_ADDR_WIDTH      (C_BRAM_ADDR_WIDTH),
        .C_BRAM_DATA_WIDTH      (C_BRAM_DATA_WIDTH),
        .CFG_BW                 (CFG_BW),
        .AXI_DM_CMD_WIDTH       (AXI_DM_CMD_WIDTH),
        .AXI_DM_STS_WIDTH       (AXI_DM_STS_WIDTH)
    ) FCTA_CTL_inst (
        .clk                    (clk),
        .rstn                   (rstn),

        .s_axi_awaddr           (s_axi_awaddr),
        .s_axi_awprot           (s_axi_awprot),
        .s_axi_awvalid          (s_axi_awvalid),
        .s_axi_awready          (s_axi_awready),
        .s_axi_wdata            (s_axi_wdata),
        .s_axi_wstrb            (s_axi_wstrb),
        .s_axi_wvalid           (s_axi_wvalid),
        .s_axi_wready           (s_axi_wready),
        .s_axi_bresp            (s_axi_bresp),
        .s_axi_bvalid           (s_axi_bvalid),
        .s_axi_bready           (s_axi_bready),
        .s_axi_araddr           (s_axi_araddr),
        .s_axi_arprot           (s_axi_arprot),
        .s_axi_arvalid          (s_axi_arvalid),
        .s_axi_arready          (s_axi_arready),
        .s_axi_rdata            (s_axi_rdata),
        .s_axi_rresp            (s_axi_rresp),
        .s_axi_rvalid           (s_axi_rvalid),
        .s_axi_rready           (s_axi_rready),

        .bram_clkb              (bram_clkb),
        .bram_rstb              (bram_rstb),
        .bram_addrb             (bram_addrb),
        .bram_dinb              (bram_dinb),
        .bram_doutb             (bram_doutb),
        .bram_enb               (bram_enb),
        .bram_web               (bram_web),

        .m_axis_cmd_tvalid      (m_axis_cmd_tvalid),
        .m_axis_cmd_tdata       (m_axis_cmd_tdata),
        .m_axis_cmd_tready      (m_axis_cmd_tready),

        .s_axis_mm2s_sts_tvalid (s_axis_mm2s_sts_tvalid),
        .s_axis_mm2s_sts_tlast  (s_axis_mm2s_sts_tlast),
        .s_axis_mm2s_sts_tdata  (s_axis_mm2s_sts_tdata),
        .s_axis_mm2s_sts_tready (s_axis_mm2s_sts_tready),

        .s_axis_s2mm_sts_tvalid (s_axis_s2mm_sts_tvalid),
        .s_axis_s2mm_sts_tlast  (s_axis_s2mm_sts_tlast),
        .s_axis_s2mm_sts_tdata  (s_axis_s2mm_sts_tdata),
        .s_axis_s2mm_sts_tready (s_axis_s2mm_sts_tready)
    );



endmodule
