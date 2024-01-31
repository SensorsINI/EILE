
import definesPkg::*;
// import npp_std_func_pkg::*;

// `define DEBUG



module FCTA #(

    // Global
    parameter NUM_PE    = 256,           //16
    parameter NUM_ACT_FUNC = 2,

    parameter WEIGHT_QM = 2,
    parameter WEIGHT_QN = 14,
    parameter ACT_QM    = 8,
    parameter ACT_QN    = 8,
    parameter ACC_QM    = 10,
    parameter ACC_QN    = 22,

    parameter MAX_N     = 1024,         //1024
    // parameter MAX_M     = 32,           //32
    parameter MAX_M     = 1,           //32     // IL only
    parameter MAX_NoP   = MAX_N/NUM_PE, //64

    // IPM
    parameter IPM_BRAM_DDB_BW    = 16,
    // parameter IPM_BRAM_DDB_DEPTH = (MAX_M>NUM_PE)? (MAX_M+1):(NUM_PE+1),    //32
    parameter IPM_BRAM_DDB_DEPTH = (MAX_M>NUM_PE)? (MAX_M+8):(NUM_PE+8),    // NOTE: SRAM depth must be a multiple of 8 for sram mux 4

    // CCM
    parameter BRAM_MAC_DEPTH = MAX_M*MAX_NoP,   //2048
    parameter BRAM_ACC_DEPTH = MAX_M,           //32
    // parameter BRAM_ACC_DEPTH = BRAM_MAC_DEPTH,     // NOTE: P256 M1

    // OPM
    parameter OPM_BRAM_DDB_BW    = 16,
    // parameter OPM_BRAM_DDB_DEPTH = (MAX_M>NUM_PE)? (MAX_M):(NUM_PE),    //32    //DDB depth irrelevant?
    parameter OPM_BRAM_DDB_DEPTH = 4,          // NOTE: P256 M1

    // Shared
    // parameter AXIS_BW        = 1024,         //256
    parameter AXIS_BW        = 4096,            // NOTE: P256 M1
    parameter BRAM_IDB_BW    = 16,
    parameter BRAM_IDB_DEPTH = MAX_M*MAX_NoP*2,
    // parameter BRAM_IDB_DEPTH = 64,              // NOTE: P256 M1, min depth of sram_dp_hde_hvt_rvt is 64

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

    input logic                             clk,
    input logic                             rstn,

    input logic                             tready_i,
    input logic                             tvalid_i,
    // input logic                             tlast_i,
    
    input logic [AXIS_BW-1:0]               tdata_i,
    
    input logic                             s_axis_cfg_tvalid,
    input logic                             s_axis_cfg_tlast,
    input logic [CFG_BW-1:0]                s_axis_cfg_tdata,

    output logic                            tvalid_o,
    output logic                            tlast_o,
    output logic                            tready_o,
    output logic [AXIS_BW-1:0]              tdata_o,

    output logic                            s_axis_cfg_tready

);

    // Configurations
    // (* mark_debug = "true" *)
    logic                                   cfg_start;
    // (* mark_debug = "true" *)
    stage_t                                 cfg_stage;
    // (* mark_debug = "true" *)
    logic [$clog2(NUM_ACT_FUNC)-1:0]        cfg_act_func;
    // (* mark_debug = "true" *)
    logic [$clog2(MAX_M)-1:0]               cfg_m;
    // (* mark_debug = "true" *)
    logic [$clog2(MAX_NoP)-1:0]             cfg_n2op;
    // (* mark_debug = "true" *)
    logic [$clog2(MAX_N)-1:0]               cfg_n1;
    // (* mark_debug = "true" *)
    logic [$clog2(MAX_NoP*MAX_N*2)-1:0]     cfg_cnt_ddi;
    // (* mark_debug = "true" *)
    logic [$clog2(MAX_CNT_DDO)-1:0]         cfg_cnt_ddo;                // m*n2op, m*n2op, m*n1, n2op*n1, n2op*n1
    // (* mark_debug = "true" *)
    logic [$clog2(BRAM_MAC_DEPTH)-1:0]      cfg_cnt_ba;
    // (* mark_debug = "true" *)
    logic [$clog2(MAX_N)-1:0]               cfg_cnt_ar;
    // (* mark_debug = "true" *)
    logic [$clog2(MAX_CNT_RR)-1:0]          cfg_cnt_rr;
    // (* mark_debug = "true" *)
    logic                                   cfg_finish;

    // (* mark_debug = "true" *)
    logic                                   f_ipm_finish;
    // (* mark_debug = "true" *)
    logic                                   f_opm_finish;

    // Module Control Signal Connections
    // (* mark_debug = "true" *)
    logic                                   ipm_valid_o;
    // (* mark_debug = "true" *)
    logic                                   ccm_valid_o;
    // (* mark_debug = "true" *)
    logic                                   ccm_ready_o;
    // (* mark_debug = "true" *)
    logic                                   opm_ready_o;

    // Module Data Connections
    // (* mark_debug = "true" *)
    logic signed[ACT_BW-1:0]                ipm_dout_act[NUM_PE-1:0];
    // (* mark_debug = "true" *)
    logic signed[WEIGHT_BW-1:0]             ipm_dout_weight[NUM_PE-1:0];
    // (* mark_debug = "true" *)
    logic signed[ACT_BW-1:0]                ccm_dout_act[NUM_PE:0];     // acc

    // BRAM_IDB
    logic                                   ipm_rstn_idb;
    logic [$clog2(BRAM_IDB_DEPTH)-1:0]      ipm_addr_idb[NUM_PE-1:0];
    logic                                   ipm_en_idb_rd[NUM_PE-1:0];
    // (* mark_debug = "true" *)
    logic                                   ipm_en_idb_wr[NUM_PE-1:0];
    logic                                   ipm_regce_idb[NUM_PE-1:0];
    // (* mark_debug = "true" *)
    logic signed[ACT_BW-1:0]                ipm_idb_out[NUM_PE-1:0];
    logic                                   opm_rstn_idb;
    logic [$clog2(BRAM_IDB_DEPTH)-1:0]      opm_addr_idb[NUM_PE-1:0];
    logic                                   opm_en_idb_wr[NUM_PE-1:0];
    logic signed[ACT_BW-1:0]                opm_idb_din[NUM_PE-1:0];
    
    

    assign cfg_finish = (f_ipm_finish || f_opm_finish);



    CFG #(
        .NUM_PE             (NUM_PE),
        .NUM_ACT_FUNC       (NUM_ACT_FUNC),

        .WEIGHT_QM          (WEIGHT_QM),
        .WEIGHT_QN          (WEIGHT_QN),
        .ACT_QM             (ACT_QM),
        .ACT_QN             (ACT_QN),
        .ACC_QM             (ACC_QM),
        .ACC_QN             (ACC_QN),

        .MAX_N              (MAX_N),
        .MAX_M              (MAX_M),
        .MAX_NoP            (MAX_NoP),
        
        .IPM_BRAM_DDB_BW    (IPM_BRAM_DDB_BW),
        .IPM_BRAM_DDB_DEPTH (IPM_BRAM_DDB_DEPTH),

        .BRAM_MAC_DEPTH     (BRAM_MAC_DEPTH),
        .BRAM_ACC_DEPTH     (BRAM_ACC_DEPTH),

        .OPM_BRAM_DDB_BW    (OPM_BRAM_DDB_BW),
        .OPM_BRAM_DDB_DEPTH (OPM_BRAM_DDB_DEPTH),

        .AXIS_BW            (AXIS_BW),
        .BRAM_IDB_BW        (BRAM_IDB_BW),
        .BRAM_IDB_DEPTH     (BRAM_IDB_DEPTH),

        .CFG_BW             (CFG_BW)
    ) CFG (
        .clk                (clk),
        .rstn               (rstn),
        .s_axis_cfg_tvalid  (s_axis_cfg_tvalid),
        .s_axis_cfg_tlast   (s_axis_cfg_tlast),
        .s_axis_cfg_tdata   (s_axis_cfg_tdata),
        .cfg_finish         (cfg_finish),
        .s_axis_cfg_tready  (s_axis_cfg_tready),
        .cfg_start          (cfg_start),
        .cfg_stage          (cfg_stage),
        .cfg_act_func       (cfg_act_func),
        .cfg_m              (cfg_m),
        .cfg_n2op           (cfg_n2op),
        .cfg_n1             (cfg_n1),
        .cfg_cnt_ddi        (cfg_cnt_ddi),
        .cfg_cnt_ddo        (cfg_cnt_ddo),
        .cfg_cnt_ba         (cfg_cnt_ba),
        .cfg_cnt_ar         (cfg_cnt_ar),
        .cfg_cnt_rr         (cfg_cnt_rr)
    );
    


    IPM #(
        .NUM_PE         (NUM_PE),
        .WEIGHT_QM      (WEIGHT_QM),
        .WEIGHT_QN      (WEIGHT_QN),
        .ACT_QM         (ACT_QM),
        .ACT_QN         (ACT_QN),
        .ACC_QM         (ACC_QM),
        .ACC_QN         (ACC_QN),
        .MAX_N          (MAX_N),
        .MAX_M          (MAX_M),
        .MAX_NoP        (MAX_NoP),
        .AXIS_BW        (AXIS_BW),
        .BRAM_DDB_BW    (IPM_BRAM_DDB_BW),
        .BRAM_DDB_DEPTH (IPM_BRAM_DDB_DEPTH),
        .BRAM_IDB_BW    (BRAM_IDB_BW),
        .BRAM_IDB_DEPTH (BRAM_IDB_DEPTH),
        .BRAM_MAC_DEPTH (BRAM_MAC_DEPTH)
    ) IPM (
        .clk            (clk),
        .rstn           (rstn),
        .ready_i        (ccm_ready_o),
        .tvalid         (tvalid_i),
        .cfg_start      (cfg_start),
        .cfg_stage      (cfg_stage),
        .cfg_m          (cfg_m),
        .cfg_n2op       (cfg_n2op),
        .cfg_n1         (cfg_n1),
        .cfg_cnt_ddi    (cfg_cnt_ddi),
        .cfg_cnt_ba     (cfg_cnt_ba),
        .tdata          (tdata_i),

        .tready         (tready_o),
        .valid_o        (ipm_valid_o),
        .f_ipm_finish   (f_ipm_finish),
        .dout_act       (ipm_dout_act),
        .dout_weight    (ipm_dout_weight),

        .rstn_idb       (ipm_rstn_idb),
        .addr_idb       (ipm_addr_idb),
        .en_idb_rd      (ipm_en_idb_rd),
        .en_idb_wr      (ipm_en_idb_wr),
        .regce_idb      (ipm_regce_idb),
        .idb_out        (ipm_idb_out)
    );
    


    CCM #(
        .NUM_PE         (NUM_PE),
        .WEIGHT_QM      (WEIGHT_QM),
        .WEIGHT_QN      (WEIGHT_QN),
        .ACT_QM         (ACT_QM),
        .ACT_QN         (ACT_QN),
        .ACC_QM         (ACC_QM),
        .ACC_QN         (ACC_QN),
        .MAX_N          (MAX_N),
        .MAX_M          (MAX_M),
        .MAX_NoP        (MAX_NoP),
        .NUM_ACT_FUNC   (NUM_ACT_FUNC),
        .BRAM_MAC_DEPTH (BRAM_MAC_DEPTH),
        .BRAM_ACC_DEPTH (BRAM_ACC_DEPTH)
    ) CCM (
        .clk            (clk),
        .rstn           (rstn),
        .valid_i        (ipm_valid_o),
        .ready_i        (opm_ready_o),
        .cfg_start      (cfg_start),
        .cfg_stage      (cfg_stage),
        .cfg_act_func   (cfg_act_func),
        .cfg_cnt_ba     (cfg_cnt_ba),
        .cfg_cnt_ar     (cfg_cnt_ar),
        .cfg_cnt_rr     (cfg_cnt_rr),
        .din_act        (ipm_dout_act),
        .din_weight     (ipm_dout_weight),
        .ready_o        (ccm_ready_o),
        .valid_o        (ccm_valid_o),
        .dout_act       (ccm_dout_act)
    );
    


    OPM #(
        .NUM_PE         (NUM_PE),
        .WEIGHT_QM      (WEIGHT_QM),
        .WEIGHT_QN      (WEIGHT_QN),
        .ACT_QM         (ACT_QM),
        .ACT_QN         (ACT_QN),
        .ACC_QM         (ACC_QM),
        .ACC_QN         (ACC_QN),
        .MAX_N          (MAX_N),
        .MAX_M          (MAX_M),
        .MAX_NoP        (MAX_NoP),
        .AXIS_BW        (AXIS_BW),
        .BRAM_DDB_BW    (OPM_BRAM_DDB_BW),
        .BRAM_DDB_DEPTH (OPM_BRAM_DDB_DEPTH),
        .BRAM_IDB_BW    (BRAM_IDB_BW),
        .BRAM_IDB_DEPTH (BRAM_IDB_DEPTH)
    ) OPM (
        .clk            (clk),
        .rstn           (rstn),
        .tready_i       (tready_i),
        .valid_i        (ccm_valid_o),
        .cfg_start      (cfg_start),
        .cfg_stage      (cfg_stage),
        .cfg_m          (cfg_m),
        // .cfg_n2op       (cfg_n2op),
        .cfg_n1         (cfg_n1),
        .cfg_cnt_ddo    (cfg_cnt_ddo),
        .din_act        (ccm_dout_act),

        .tvalid_o       (tvalid_o),
        .tlast_o        (tlast_o),
        .ready_o        (opm_ready_o),
        .f_opm_finish   (f_opm_finish),
        .tdata          (tdata_o),

        .rstn_idb       (opm_rstn_idb),
        .addr_idb       (opm_addr_idb),
        .en_idb_wr      (opm_en_idb_wr),
        .idb_din        (opm_idb_din)
    );
    


    // BRAM_IDB
    generate
        for (genvar pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            // (* ram_style = "block" *)
            BRAM_TDP_NC_1C #(
                .RAM_WIDTH(BRAM_IDB_BW),
                .RAM_DEPTH(BRAM_IDB_DEPTH),
                .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
                // .INIT_FILE($sformatf("idb_%2x_init.mem", pe_idx))
                .INIT_FILE("")
            ) BRAM_INTERM_DATA_BUF (
                .clka   (clk),

                .addra  (ipm_addr_idb[pe_idx]),
                .dina   (tdata_i[ACT_BW*pe_idx +: ACT_BW]),
                .wea    (ipm_en_idb_wr[pe_idx]),
                .ena    (ipm_en_idb_rd[pe_idx]),
                .rsta   ((!rstn) || (!ipm_rstn_idb)),
                .regcea (ipm_regce_idb[pe_idx]),
                .douta  (ipm_idb_out[pe_idx]),

                .addrb  (opm_addr_idb[pe_idx]),
                .dinb   (opm_idb_din[pe_idx]),
                .web    (opm_en_idb_wr[pe_idx]),
                .enb    (opm_en_idb_wr[pe_idx]),        // Synchronize with write enable
                .rstb   ((!rstn) || (!opm_rstn_idb)),
                .regceb (),
                .doutb  ()                              // IDB PortB Output not used
            );
        end
    endgenerate
    
    // logic [BRAM_IDB_BW-1:0] bram_idb_out [NUM_PE-1:0];
    // bank_status_datatype bram_idb_ena[NUM_PE-1:0];
    // memory_rw_datatype   bram_idb_opa[NUM_PE-1:0];
    // bank_status_datatype bram_idb_enb[NUM_PE-1:0];
    // memory_rw_datatype   bram_idb_opb[NUM_PE-1:0];

    // always_comb begin
    //     for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         if (ipm_en_idb_rd[pe_idx]) begin
    //             bram_idb_ena[pe_idx] = ENABLED;
    //         end else begin
    //             bram_idb_ena[pe_idx] = DISABLED;
    //         end
    //     end
    // end

    // always_comb begin
    //     for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         if (ipm_en_idb_wr[pe_idx]) begin
    //             bram_idb_opa[pe_idx] = WRITE;
    //         end else begin
    //             bram_idb_opa[pe_idx] = READ;
    //         end
    //     end
    // end
    
    // always_comb begin
    //     for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         if (opm_en_idb_wr[pe_idx]) begin
    //             bram_idb_enb[pe_idx] = ENABLED;
    //         end else begin
    //             bram_idb_enb[pe_idx] = DISABLED;
    //         end
    //     end
    // end

    // always_comb begin
    //     for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         if (opm_en_idb_wr[pe_idx]) begin
    //             bram_idb_opb[pe_idx] = WRITE;
    //         end else begin
    //             bram_idb_opb[pe_idx] = READ;
    //         end
    //     end
    // end
    
    // npp_std_if bram_idb_clk();
    // assign bram_idb_clk.clk = clk;
    // assign bram_idb_clk.resetn = rstn;

    // generate
    //     for (genvar pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         npp_memory_dp #(
    //             .WORD_NUM_BITS      (BRAM_IDB_BW),
    //             .NUM_ENTRIES        (BRAM_IDB_DEPTH)
    //         ) BRAM_IDB (
    //             .a_npp_std          (bram_idb_clk.slave),
    //             .a_input_address    (ipm_addr_idb[pe_idx]),
    //             .a_input_word       (tdata_i[ACT_BW*pe_idx +: ACT_BW]),
    //             .a_chip_enable      (bram_idb_ena[pe_idx]),
    //             .a_operation        (bram_idb_opa[pe_idx]),
    //             .a_output_word      (bram_idb_out[pe_idx]),

    //             .b_npp_std          (bram_idb_clk.slave),
    //             .b_input_address    (opm_addr_idb[pe_idx]),
    //             .b_input_word       (opm_idb_din[pe_idx]),
    //             .b_chip_enable      (bram_idb_enb[pe_idx]),
    //             .b_operation        (bram_idb_opb[pe_idx]),
    //             .b_output_word      ()
    //         );
    //     end
    // endgenerate

    // logic [BRAM_IDB_BW-1:0] bram_idb_out_reg [NUM_PE-1:0];
    // always_ff @(posedge clk) begin
    //     for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         if (!rstn || !ipm_rstn_idb) begin
    //             bram_idb_out_reg[pe_idx] <= '0;
    //         end else if (ipm_regce_idb[pe_idx]) begin
    //             bram_idb_out_reg[pe_idx] <= bram_idb_out[pe_idx];
    //         end
    //     end
    // end

    // always_comb begin
    //     for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         ipm_idb_out[pe_idx][BRAM_IDB_BW-1:0] = bram_idb_out_reg[pe_idx][BRAM_IDB_BW-1:0];
    //     end
    // end



`ifdef DEBUG
    logic [BRAM_IDB_BW-1:0]             BRAM_IDB[NUM_PE-1:0][BRAM_IDB_DEPTH-1:0];
    generate
        for (genvar pe_idx=0; pe_idx<NUM_PE; pe_idx++) begin
            assign BRAM_IDB[pe_idx] = genblk1[pe_idx].BRAM_INTERM_DATA_BUF.BRAM;
        end
    endgenerate
`endif


    
endmodule
