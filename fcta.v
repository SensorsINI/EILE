// Target: MMP



`define STAGE_BW                3                   // definesPkg
`define MAX_CNT_RR              (MAX_M*MAX_N)       // (MAX_M>MAX_NoP)? (MAX_M*MAX_N):(MAX_NoP*MAX_N)
`define MAX_CNT_DDO             (MAX_M*MAX_N)       // (MAX_M>MAX_NoP)? (MAX_M*MAX_N):(MAX_NoP*MAX_N)

`define IPM_BRAM_DDB_DEPTH      (NUM_PE+1)          // (MAX_M>NUM_PE)? (MAX_M+1):(NUM_PE+1)
`define OPM_BRAM_DDB_DEPTH      (NUM_PE)            // (MAX_M>NUM_PE)? (MAX_M):(NUM_PE)

`define CFG_REG_BW              32                  // AXI_GPIO



module FCTA_wrapper #(

    // Global
    parameter NUM_PE            = 64,           //16
    parameter NUM_ACT_FUNC      = 2,

    parameter WEIGHT_QM         = 2,
    parameter WEIGHT_QN         = 14,
    parameter ACT_QM            = 8,
    parameter ACT_QN            = 8,
    parameter ACC_QM            = 10,
    parameter ACC_QN            = 22,

    parameter MAX_N             = 1024,         //1024
    parameter MAX_M             = 32,           //32
    parameter MAX_NoP           = MAX_N/NUM_PE, //64

    // IPM
    parameter IPM_BRAM_DDB_BW   = 16,
    // parameter IPM_BRAM_DDB_DEPTH = (MAX_M>NUM_PE)? (MAX_M+1):(NUM_PE+1),    //32

    // CCM
    parameter BRAM_MAC_DEPTH    = MAX_M*MAX_NoP,   //2048
    parameter BRAM_ACC_DEPTH    = MAX_M,           //32

    // OPM
    parameter OPM_BRAM_DDB_BW   = 16,
    // parameter OPM_BRAM_DDB_DEPTH = (MAX_M>NUM_PE)? (MAX_M):(NUM_PE),    //32    //DDB depth irrelevant?

    // Shared
    parameter AXIS_BW           = 1024,         //256
    parameter BRAM_IDB_BW       = 16,
    parameter BRAM_IDB_DEPTH    = MAX_M*MAX_NoP*2,

    // CFG
    parameter CFG_BW            = 96

    // Local
    // localparam WEIGHT_BW        = WEIGHT_QM + WEIGHT_QN,
    // localparam ACT_BW           = ACT_QM + ACT_QN,
    // localparam ACC_BW           = ACC_QM + ACC_QN,

    // localparam ADDR_IDB_A       = 0,
    // localparam ADDR_IDB_dZ      = 0,
    // localparam ADDR_IDB_dA      = MAX_M*MAX_NoP

    // localparam MAX_CNT_RR = MAX_NoP*MAX_N,      //(MAX_M>MAX_NoP)? (MAX_M*MAX_N):(MAX_NoP*MAX_N),
    // localparam MAX_CNT_DDO = MAX_NoP*MAX_N,     //(MAX_M>MAX_NoP)? (MAX_M*MAX_N):(MAX_NoP*MAX_N)
    // localparam STAGE_BW = 3                     // definesPkg

) (

    input                       clk,
    input                       rstn,
    
    input                       s_axis_cfg_tvalid,
    input                       s_axis_cfg_tlast,
    input  [CFG_BW-1:0]         s_axis_cfg_tdata,

    input                       s_axis_mm2s_tvalid,
    input                       s_axis_mm2s_tlast,
    input  [AXIS_BW-1:0]        s_axis_mm2s_tdata,

    input                       m_axis_s2mm_tready,

    output                      s_axis_cfg_tready,

    output                      s_axis_mm2s_tready,

    output                      m_axis_s2mm_tvalid,
    output                      m_axis_s2mm_tlast,
    output [AXIS_BW-1:0]        m_axis_s2mm_tdata

);



    FCTA #(

        .NUM_PE                 (NUM_PE),
        .NUM_ACT_FUNC           (NUM_ACT_FUNC),

        .WEIGHT_QM              (WEIGHT_QM),
        .WEIGHT_QN              (WEIGHT_QN),
        .ACT_QM                 (ACT_QM),
        .ACT_QN                 (ACT_QN),
        .ACC_QM                 (ACC_QM),
        .ACC_QN                 (ACC_QN),

        .MAX_N                  (MAX_N),
        .MAX_M                  (MAX_M),
        .MAX_NoP                (MAX_NoP),
        
        .IPM_BRAM_DDB_BW        (IPM_BRAM_DDB_BW),
        .IPM_BRAM_DDB_DEPTH     (`IPM_BRAM_DDB_DEPTH),

        .BRAM_MAC_DEPTH         (BRAM_MAC_DEPTH),
        .BRAM_ACC_DEPTH         (BRAM_ACC_DEPTH),

        .OPM_BRAM_DDB_BW        (OPM_BRAM_DDB_BW),
        .OPM_BRAM_DDB_DEPTH     (`OPM_BRAM_DDB_DEPTH),

        .AXIS_BW                (AXIS_BW),
        .BRAM_IDB_BW            (BRAM_IDB_BW),
        .BRAM_IDB_DEPTH         (BRAM_IDB_DEPTH),

        .CFG_BW                 (CFG_BW)

    ) FCTA_INST (

        .clk                    (clk),
        .rstn                   (rstn),
        
        .s_axis_cfg_tvalid      (s_axis_cfg_tvalid),
        .s_axis_cfg_tlast       (s_axis_cfg_tlast),
        .s_axis_cfg_tdata       (s_axis_cfg_tdata),
        .s_axis_cfg_tready      (s_axis_cfg_tready),

        .tvalid_i               (s_axis_mm2s_tvalid),
        // .tlast_i                (s_axis_mm2s_tlast),
        .tdata_i                (s_axis_mm2s_tdata),
        .tready_o               (s_axis_mm2s_tready),
        
        .tvalid_o               (m_axis_s2mm_tvalid),
        .tlast_o                (m_axis_s2mm_tlast),
        .tdata_o                (m_axis_s2mm_tdata),
        .tready_i               (m_axis_s2mm_tready)

    );
    
    

endmodule
