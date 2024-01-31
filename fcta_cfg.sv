
import definesPkg::*;



module CFG #(

    // Global
    parameter NUM_PE    = 16,           //16
    parameter NUM_ACT_FUNC = 2,

    parameter WEIGHT_QM = 8,
    parameter WEIGHT_QN = 8,
    parameter ACT_QM    = 8,
    parameter ACT_QN    = 8,
    parameter ACC_QM    = 16,
    parameter ACC_QN    = 16,

    parameter MAX_N     = 1024,         //1024
    parameter MAX_M     = 32,           //32
    parameter MAX_NoP   = MAX_N/NUM_PE, //64

    // IPM
    parameter IPM_BRAM_DDB_BW    = 16,
    parameter IPM_BRAM_DDB_DEPTH = (MAX_M>NUM_PE)? (MAX_M+1):(NUM_PE+1),    //32

    // CCM
    parameter BRAM_MAC_DEPTH = MAX_M*MAX_NoP,   //2048
    parameter BRAM_ACC_DEPTH = MAX_M,           //32

    // OPM
    parameter OPM_BRAM_DDB_BW    = 16,
    parameter OPM_BRAM_DDB_DEPTH = (MAX_M>NUM_PE)? (MAX_M):(NUM_PE),    //32    //DDB depth irrelevant?

    // Shared
    parameter AXIS_BW        = 256,         //256
    parameter BRAM_IDB_BW    = 16,
    parameter BRAM_IDB_DEPTH = MAX_M*MAX_NoP*2,

    // CFG
    parameter CFG_BW    = 96,

    // Local
    localparam WEIGHT_BW = WEIGHT_QM + WEIGHT_QN,
    localparam ACT_BW    = ACT_QM + ACT_QN,
    localparam ACC_BW    = ACC_QM + ACC_QN,

    localparam ADDR_IDB_A  = 0,
    localparam ADDR_IDB_dZ = 0,
    localparam ADDR_IDB_dA = MAX_M*MAX_NoP,

    localparam MAX_CNT_RR = (MAX_M>MAX_NoP)? (MAX_M*MAX_N):(MAX_NoP*MAX_N),
    localparam MAX_CNT_DDO = (MAX_M>MAX_NoP)? (MAX_M*MAX_N):(MAX_NoP*MAX_N)

) (

    input logic         clk,
    input logic         rstn,

    input logic                                 s_axis_cfg_tvalid,
    input logic                                 s_axis_cfg_tlast,
    input logic [CFG_BW-1:0]                    s_axis_cfg_tdata,

    input logic                                 cfg_finish,
    
    output logic                                s_axis_cfg_tready,

    // Configuration
    output logic                                cfg_start,
    output stage_t                              cfg_stage,
    output logic [$clog2(NUM_ACT_FUNC)-1:0]     cfg_act_func,
    output logic [$clog2(MAX_M)-1:0]            cfg_m,
    output logic [$clog2(MAX_NoP)-1:0]          cfg_n2op,
    output logic [$clog2(MAX_N)-1:0]            cfg_n1,
    output logic [$clog2(MAX_NoP*MAX_N*2)-1:0]  cfg_cnt_ddi,
    output logic [$clog2(MAX_CNT_DDO)-1:0]      cfg_cnt_ddo,
    output logic [$clog2(BRAM_MAC_DEPTH)-1:0]   cfg_cnt_ba,
    output logic [$clog2(MAX_N)-1:0]            cfg_cnt_ar,
    output logic [$clog2(MAX_CNT_RR)-1:0]       cfg_cnt_rr
    
);

    logic [CFG_BW-1:0]                          cfg_reg_i;
    logic                                       f_tvalid;



    // always_ff @(posedge clk) begin
    //     if (!rstn) begin
    //         s_axis_cfg_tready <= 1'b1;
    //     end else if (s_axis_cfg_tvalid && s_axis_cfg_tready) begin
    //         s_axis_cfg_tready <= 1'b0;
    //     end else if (cfg_finish) begin
    //         s_axis_cfg_tready <= 1'b1;
    //     end
    // end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            f_tvalid <= 1'b0;
        end else if (!f_tvalid && cfg_finish) begin
            f_tvalid <= s_axis_cfg_tvalid;
        end else if (f_tvalid) begin  // && cfg_finish && cfg_start
            f_tvalid <= 1'b0;
        end
    end

    assign s_axis_cfg_tready = cfg_finish && (!f_tvalid);

    // Configuration register - cfg_start
    always_ff @(posedge clk) begin
        if (!rstn) begin
            cfg_start <= 1'b0;
        end else if (cfg_start) begin
            cfg_start <= 1'b0;
        end else if (s_axis_cfg_tvalid && s_axis_cfg_tready) begin
            cfg_start <= 1'b1;
        end
    end

    // Configuration registers
    always_ff @(posedge clk) begin
        if (!rstn) begin
            cfg_reg_i <= '0;
        end else if (s_axis_cfg_tvalid && s_axis_cfg_tready) begin
            cfg_reg_i <= s_axis_cfg_tdata;
        end
    end

    // assign cfg_start    = cfg_reg_i[95];
    assign cfg_stage    = stage_t'(cfg_reg_i[94-:3]);
    assign cfg_act_func = cfg_reg_i[91-:1];
    assign cfg_m        = cfg_reg_i[90-:1];
    assign cfg_n2op     = cfg_reg_i[89-:4];
    assign cfg_n1       = cfg_reg_i[85-:12];
    assign cfg_cnt_ddi  = cfg_reg_i[73-:17];
    assign cfg_cnt_ddo  = cfg_reg_i[56-:16];
    assign cfg_cnt_ba   = cfg_reg_i[40-:4];
    assign cfg_cnt_ar   = cfg_reg_i[36-:12];
    assign cfg_cnt_rr   = cfg_reg_i[24-:16];

endmodule
