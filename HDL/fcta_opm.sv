
import definesPkg::*;

module OPM #(
    parameter NUM_PE    = 16,           //16
    parameter WEIGHT_QM = 8,
    parameter WEIGHT_QN = 8,
    parameter ACT_QM    = 8,
    parameter ACT_QN    = 8,
    parameter ACC_QM    = 16,
    parameter ACC_QN    = 16,
    parameter MAX_N     = 1024,         //1024
    parameter MAX_M     = 32,           //32
    parameter MAX_NoP   = MAX_N/NUM_PE, //64
    parameter AXIS_BW   = 256,          //256
    parameter BRAM_DDB_BW    = 16,
    parameter BRAM_DDB_DEPTH = (MAX_M>NUM_PE)? (MAX_M):(NUM_PE),    //32    //DDB depth irrelevant?
    parameter BRAM_IDB_BW    = 16,
    parameter BRAM_IDB_DEPTH = MAX_M*MAX_NoP*2,
    // parameter BRAM_PE_DEPTH  = MAX_M*MAX_NoP,   //2048
    // parameter BRAM_ACC_DEPTH = MAX_M,           //32
    localparam WEIGHT_BW = WEIGHT_QM + WEIGHT_QN,
    localparam ACT_BW    = ACT_QM + ACT_QN,
    localparam ACC_BW    = ACC_QM + ACC_QN,
    localparam ADDR_IDB_A  = 0,
    localparam ADDR_IDB_dZ = 0,
    localparam ADDR_IDB_dA = MAX_M*MAX_NoP,
    localparam MAX_CNT_DDO = (MAX_M>MAX_NoP)? (MAX_M*MAX_N):(MAX_NoP*MAX_N)
) (
    input logic         clk,
    input logic         rstn,
    input logic         tready_i,
    input logic         valid_i,
    
    // stage, m*(n2/P), n1
    input logic         cfg_start,
    input stage_t                           cfg_stage,
    input logic [$clog2(MAX_M)-1:0]         cfg_m,              // Used in BPdA only
    // input logic [$clog2(MAX_NoP)-1:0]       cfg_n2op,
    input logic [$clog2(MAX_N)-1:0]         cfg_n1,             // Used in BPdA only
    input logic [$clog2(MAX_CNT_DDO)-1:0]   cfg_cnt_ddo,        // m*n2op, m*n2op, m*n1, n2op*n1, n2op*n1
    // input logic [$clog2(BRAM_PE_DEPTH)-1:0] cfg_cnt_ba,
    // input logic [$clog2(MAX_N)-1:0]         cfg_cnt_ar,
    // input logic [$clog2(MAX_NoP*MAX_N)-1:0] cfg_cnt_rr,
    
    input logic signed[ACT_BW-1:0]          din_act[NUM_PE:0],  // acc
    
    output logic        tvalid_o,
    output logic        tlast_o,
    output logic        ready_o,
    output logic        f_opm_finish,
    output logic [AXIS_BW-1:0]              tdata,

    // BRAM_IDB
    output logic                              rstn_idb,
    output logic [$clog2(BRAM_IDB_DEPTH)-1:0] addr_idb[NUM_PE-1:0],
    output logic                              en_idb_wr[NUM_PE-1:0],
    output logic signed[ACT_BW-1:0]           idb_din[NUM_PE-1:0]
);

    // Overall - control signals
    logic               rstn_CFG;
    
    // Overall - flags
    logic [0:1]         f_I;
    logic [0:2]         f_O;
    
    // Input Signal
    logic               tready_i_eff;
    logic               valid_i_r;

    // Output Signal
    logic               tvalid_o_p;
    logic [0:1]         tvalid_o_pr;
    logic               tlast_o_p;
    logic [0:1]         tlast_o_pr;
    
    // FSM - states
    // (* mark_debug = "true" *)
    enum logic [3:0] {  S_NCFG, S_CFG,
                        S_FP,
                        S_BPdZ,
                        S_BPdA,
                        S_BPdW,
                        S_PU} state;
    
    // DRAM Data I/O Counter
    logic [$clog2(MAX_CNT_DDO)-1:0]         cnt_i;
    logic                                   f_cnt_i;
    logic [0:0]                             f_cnt_i_r;
    // (* mark_debug = "true" *)
    logic [$clog2(MAX_CNT_DDO)-1:0]         cnt_ddo;
    logic [$clog2(MAX_M)-1:0]               cnt_m;              // Used in BPdA only
    // logic [$clog2(MAX_NoP)-1:0]             cnt_n2op;
    logic [$clog2(MAX_N)-1:0]               cnt_n1;             // Used in BPdA only
    logic                                   f_cnt_o;
    logic [0:1]                             f_cnt_o_r;
    
    // BRAM_DDB Control Signal, Pointer, Data Counter, Flag
    logic                                   en_ddb_rd[NUM_PE-1:0];
    logic                                   en_ddb_wr[NUM_PE-1:0];
    logic                                   en_ddb_wr_p[NUM_PE-1:0];
    logic                                   en_ddb_wr_pr[NUM_PE-1:0];
    logic                                   rstn_ddb;
    logic                                   regce_ddb[NUM_PE-1:0];
    logic                                   regce_ddb_p[NUM_PE-1:0];
    logic                                   regce_ddb_pr[NUM_PE-1:0];
    logic [$clog2(BRAM_DDB_DEPTH)-1:0]      pt_ddb_rd[NUM_PE-1:0];
    logic [$clog2(BRAM_DDB_DEPTH)-1:0]      pt_ddb_wr[NUM_PE-1:0];
    logic [$clog2(BRAM_DDB_DEPTH+1)-1:0]    cnt_ddb[NUM_PE-1:0];
    logic                                   f_ddb_full[NUM_PE-1:0];
    logic                                   f_ddb_full_eff[NUM_PE-1:0];
    logic                                   f_ddb_full_eff_any;
    logic                                   f_ddb_empty[NUM_PE-1:0];
    logic                                   f_ddb_empty_eff[NUM_PE-1:0];
    logic                                   f_ddb_empty_eff_r[NUM_PE-1:0];
    logic                                   f_ddb_empty_eff_any;
    // logic                                   f_ddb_empty_eff_any_r;

    // DDB Input Data Register
    logic signed[ACT_BW-1:0]                ddb_in_r[NUM_PE-1:0];
    
    // BRAM_IDB Control Signal, Address
    // logic                                   en_idb_rd[NUM_PE-1:0];  // 0
    // logic                                   en_idb_wr[NUM_PE-1:0];
    logic                                   en_idb_wr_p[NUM_PE-1:0];
    logic                                   en_idb_wr_pr[NUM_PE-1:0];
    // logic                                   rstn_idb;
    // logic                                   regce_idb[NUM_PE-1:0];  // 0
    // logic [$clog2(BRAM_IDB_DEPTH)-1:0]      addr_idb[NUM_PE-1:0];
    logic [$clog2(BRAM_IDB_DEPTH)-1:0]      addr_idb_p[NUM_PE-1:0];
    logic [$clog2(BRAM_IDB_DEPTH)-1:0]      addr_idb_pr[NUM_PE-1:0];
    
    // IDB_MUX Data, Control Signal
    logic signed[ACT_BW-1:0]                idb_mux_out[NUM_PE-1:0];
    logic                                   idb_sel;
    
    
    
    // FSM
    always_ff @(posedge clk) begin
        if (!rstn) begin
            state <= S_NCFG;
        end else begin
            case (state) inside
    
                S_NCFG : begin              // Not configured
                    if (cfg_start) begin
                        state <= S_CFG;
                    end
                end
                
                S_CFG : begin               // Configuring
                    case (cfg_stage)
                        STAGE_FP : begin
                            state <= S_FP;
                        end
                        STAGE_BPdZ : begin
                            state <= S_BPdZ;
                        end
                        STAGE_BPdA : begin
                            state <= S_BPdA;
                        end
                        STAGE_BPdW : begin
                            state <= S_BPdW;
                        end
                        STAGE_PU : begin
                            state <= S_PU;
                        end
                        default : begin
                            state <= S_NCFG;
                        end
                    endcase
                end
                
                // Forward Prop
                // Backward Prop - dW
                // Parameter Update
                S_FP, S_BPdW, S_PU : begin
                    if (f_cnt_o_r[1] && tready_i_eff) begin
                        state <= S_NCFG;
                    end
                end
                
                // Backward Prop - dZ, dA
                S_BPdZ, S_BPdA : begin
                    if (f_cnt_i_r[0]) begin
                        state <= S_NCFG;
                    end
                end

                default : begin
                    state <= S_NCFG;
                end

            endcase
        end
    end
    
    
    
    // Configure Signal
    always_ff @(posedge clk) begin
        if (!rstn) begin
            f_opm_finish <= 1'b1;
        end else begin
            case (state) inside
                // Deassert when a process is started
                S_NCFG : begin
                    if (cfg_start) begin
                        f_opm_finish <= 1'b0;
                    end
                end
                // Assert when a process is finished
                S_FP, S_BPdW, S_PU : begin
                    if (f_cnt_o_r[1] && tready_i_eff) begin
                        f_opm_finish <= 1'b1;
                    end
                end
                S_BPdZ, S_BPdA : begin
                    if (f_cnt_i_r[0]) begin
                        f_opm_finish <= 1'b1;
                    end
                end
                default : begin
                    f_opm_finish <= 1'b0;
                end
            endcase
        end
    end



    // Control Signals
    
    assign tready_i_eff = tready_i;
    // always_comb begin
    //     case (state) inside
    //         S_FP, S_BPdW, S_PU : begin
    //             tready_i_eff = tready_i;
    //         end
    //         S_BPdZ, S_BPdA : begin          // No DRAM output
    //             tready_i_eff = 1'b1;
    //         end
    //         default : begin
    //             tready_i_eff = 1'b1;
    //         end
    //     endcase
    // end
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            valid_i_r <= 1'b0;
        end else if (f_I[0:1] && !f_ddb_full_eff_any) begin
            // valid_i_r <= valid_i;
            valid_i_r <= valid_i && f_I[0];
        end
    end
    
    always_comb begin
        case (state) inside
            S_FP, S_BPdZ, S_BPdA, S_BPdW, S_PU : begin
                ready_o = f_I[0] && !f_ddb_full_eff_any;
            end
            default : begin
                ready_o = 1'b0;
            end
        endcase
    end
    
    // assign tvalid_o_p = f_O[0] && !f_ddb_empty_eff_any;
    always_comb begin
        case (state) inside
            S_FP, S_BPdW, S_PU : begin
                tvalid_o_p = f_O[0] && !f_ddb_empty_eff_any;
                tlast_o_p  = f_O[0] && f_cnt_o && !f_ddb_empty_eff_any;
            end
            S_BPdZ, S_BPdA : begin          // No DRAM output
                tvalid_o_p = 1'b0;
                tlast_o_p  = 1'b0;
            end
            default : begin
                tvalid_o_p = 1'b0;
                tlast_o_p  = 1'b0;
            end
        endcase
    end
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            tvalid_o_pr <= '0;
            tlast_o_pr  <= '0;
        end else if (f_O[0:2] && tready_i_eff) begin // || !valid_o
            tvalid_o_pr[0:1] <= {tvalid_o_p, tvalid_o_pr[0]};
            tlast_o_pr[0:1]  <= {tlast_o_p,  tlast_o_pr[0]};
        end
    end
    assign tvalid_o = tvalid_o_pr[1];
    assign tlast_o  = tlast_o_pr[1];

    assign rstn_CFG = !(state == S_CFG);
    
    
    
    // Flags
    always_ff @(posedge clk) begin
        if (!rstn) begin    // No || !rstn_CFG
            f_I[0] <= 1'b0;
        end else begin
            case (state) inside
                S_CFG : begin
                    if (cfg_stage inside {STAGE_FP, STAGE_BPdZ, STAGE_BPdA, STAGE_BPdW, STAGE_PU}) begin
                        f_I[0] <= 1'b1;
                    end else begin
                        f_I[0] <= 1'b0;
                    end
                end
                S_FP, S_BPdZ, S_BPdA, S_BPdW, S_PU : begin
                    // Deassert when last input data accepted
                    if (f_cnt_i && valid_i && !f_ddb_full_eff_any) begin
                        f_I[0] <= 1'b0;
                    end
                end
                default : begin
                    f_I[0] <= 1'b0;
                end
            endcase
        end
    end
    
    // always_ff @(posedge clk) begin
    //     if (!rstn || !rstn_CFG) begin
    //         f_I[1] <= 1'b0;
    //     end else if (f_I[0:1] && valid_i && !f_ddb_full_eff_any) begin
    //         f_I[1] <= f_I[0];
    //     end
    // end

    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            f_I[1] <= 1'b0;
        end else if ((f_I[0] && valid_i   && !f_ddb_full_eff_any) ||
                     (f_I[1] && valid_i_r && !f_ddb_full_eff_any)   ) begin
            f_I[1] <= f_I[0];
        end
    end
    
    
    always_ff @(posedge clk) begin
        if (!rstn) begin
            f_O[0] <= 1'b0;
        end else begin
            case (state) inside
                S_CFG : begin
                    f_O[0] <= 1'b0;
                end
                S_FP, S_BPdW, S_PU : begin
                    // Assert when first input data written
                    // Deassert when last data read
                    if (f_I[1] && valid_i_r && !f_ddb_full_eff_any) begin
                        f_O[0] <= 1'b1;
                    end else if (f_cnt_o && !f_ddb_empty_eff_any && tready_i_eff) begin
                        f_O[0] <= 1'b0;
                    end
                end
                default : begin
                    f_O[0] <= 1'b0;
                end
            endcase
        end
    end
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            f_O[1:2] <= '0;
        end else if (f_O[0:2] && !f_ddb_empty_eff_any && tready_i_eff) begin
            f_O[1:2] <= f_O[0:1];
        end
    end
    
    
    
    // Input Data Counter
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            cnt_i <= '0;
        end else if (f_I[0] && valid_i && !f_ddb_full_eff_any) begin
            if (cnt_i == cfg_cnt_ddo) begin
                cnt_i <= '0;
            end else begin
                cnt_i <= cnt_i + 1;
            end
        end
    end
    
    assign f_cnt_i = (cnt_i == cfg_cnt_ddo);
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            f_cnt_i_r <= '0;
        end else if (f_I[0:1] && valid_i && !f_ddb_full_eff_any) begin
            f_cnt_i_r[0] <= f_cnt_i;
        end
    end
    
    // BRAM Data Input Counter (Used in BPdA only)
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            cnt_m    <= 0;
            cnt_n1   <= 0;
        end else if (f_I[0] && valid_i && !f_ddb_full_eff_any) begin
            if (cnt_m == cfg_m) begin
                if (cnt_n1 == cfg_n1) begin
                    cnt_n1 <= 0;
                end else begin
                    cnt_n1 <= cnt_n1 + 1;
                end
                cnt_m <= 0;
            end else begin
                cnt_m <= cnt_m + 1;
            end
        end
    end
    
    // DRAM Data Output Counter
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            cnt_ddo <= '0;
        end else if (f_O[0] && !f_ddb_empty_eff_any && tready_i_eff) begin
            if (cnt_ddo == cfg_cnt_ddo) begin
                cnt_ddo <= '0;
            end else begin
                cnt_ddo <= cnt_ddo + 1;
            end
        end
    end

    assign f_cnt_o = (cnt_ddo == cfg_cnt_ddo);
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            f_cnt_o_r <= '0;
        end else if (f_O[0:2] && !f_ddb_empty_eff_any && tready_i_eff) begin
            f_cnt_o_r[0:1] <= {f_cnt_o, f_cnt_o_r[0]};
        end
    end
    
    
    
    // BRAM_DDB - control signals
    assign rstn_ddb = !(state == S_CFG);
    
    always_comb begin
        case (state) inside
            S_FP, S_BPdW, S_PU : begin
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    en_ddb_wr_p[pe_idx] = f_I[0];
                    en_ddb_wr[pe_idx] = f_I[0:1] && en_ddb_wr_pr[pe_idx] && valid_i_r && !f_ddb_full_eff[pe_idx];
                    en_ddb_rd[pe_idx] = f_O[0] && !f_ddb_empty_eff[pe_idx] && tready_i_eff;
                    regce_ddb_p[pe_idx] = f_O[0];
                    regce_ddb[pe_idx] = f_O[0:1] && regce_ddb_pr[pe_idx] && !f_ddb_empty_eff_r[pe_idx] && tready_i_eff;
                end
            end
            default : begin
                en_ddb_wr_p = '{NUM_PE{'0}};
                en_ddb_rd = '{NUM_PE{'0}};
                regce_ddb_p = '{NUM_PE{'0}};
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    en_ddb_wr[pe_idx] = f_I[0:1] && en_ddb_wr_pr[pe_idx] && valid_i_r && !f_ddb_full_eff[pe_idx];
                    regce_ddb[pe_idx] = f_O[0:1] && regce_ddb_pr[pe_idx] && !f_ddb_empty_eff_r[pe_idx] && tready_i_eff;
                end
            end
        endcase
    end
    
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                en_ddb_wr_pr[pe_idx] <= '0;
            end else if (f_I[0:1] && valid_i && !f_ddb_full_eff[pe_idx]) begin
                en_ddb_wr_pr[pe_idx] <= en_ddb_wr_p[pe_idx];
            end
        end
    end
    
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                regce_ddb_pr[pe_idx] <= '0;
            end else if (f_O[0:1] && !f_ddb_empty_eff[pe_idx] && tready_i_eff) begin
                regce_ddb_pr[pe_idx] <= regce_ddb_p[pe_idx];
            end
        end
    end
    
    // BRAM_DDB - pointers
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                pt_ddb_wr[pe_idx] <= '0;
            end else if (en_ddb_wr[pe_idx]) begin
                if (pt_ddb_wr[pe_idx] == BRAM_DDB_DEPTH-1) begin
                    pt_ddb_wr[pe_idx] <= 0;
                end else begin
                    pt_ddb_wr[pe_idx] <= pt_ddb_wr[pe_idx] + 1;
                end
            end
        end
    end
    
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                pt_ddb_rd[pe_idx] <= '0;
            end else if (en_ddb_rd[pe_idx]) begin
                if (pt_ddb_rd[pe_idx] == BRAM_DDB_DEPTH-1) begin
                    pt_ddb_rd[pe_idx] <= 0;
                end else begin
                    pt_ddb_rd[pe_idx] <= pt_ddb_rd[pe_idx] + 1;
                end
            end
        end
    end
    
    // BRAM_DDB - counters
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                cnt_ddb[pe_idx] <= '0;
            end else if (en_ddb_wr[pe_idx] && !en_ddb_rd[pe_idx] && (cnt_ddb[pe_idx] != BRAM_DDB_DEPTH)) begin
                cnt_ddb[pe_idx] <= cnt_ddb[pe_idx] + 1;
            end else if (!en_ddb_wr[pe_idx] && en_ddb_rd[pe_idx] && (cnt_ddb[pe_idx] != 0)) begin
                cnt_ddb[pe_idx] <= cnt_ddb[pe_idx] - 1;
            end
        end
    end
    
    // BRAM_DDB - flags
    always_comb begin
        // f_ddb_full_eff_any  = 1'b0;
        // f_ddb_empty_eff_any = 1'b0;
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            f_ddb_full[pe_idx]      = cnt_ddb[pe_idx] == BRAM_DDB_DEPTH;
            f_ddb_full_eff[pe_idx]  = f_ddb_full[pe_idx] && !en_ddb_rd[pe_idx];
            // f_ddb_full_eff_any      |= f_ddb_full_eff[pe_idx];
            f_ddb_empty[pe_idx]     = cnt_ddb[pe_idx] == 0;
            f_ddb_empty_eff[pe_idx] = f_ddb_empty[pe_idx] && f_I[0:1];
            // f_ddb_empty_eff[pe_idx] = f_ddb_empty[pe_idx] && f_I && (state inside {S_FP, S_BPdW, S_PU});
            // f_ddb_empty_eff_any     |= f_ddb_empty_eff[pe_idx];
        end
        f_ddb_full_eff_any  = f_ddb_full_eff[NUM_PE-1]; // DDB[NUM_PE-1] always first to be full
        f_ddb_empty_eff_any = f_ddb_empty_eff[0];       // DDB[0] always first to be empty
    end
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            f_ddb_empty_eff_r <= '{NUM_PE{'0}};
            // f_ddb_empty_eff_any_r <= 1'b0;
        end else if (f_O[0:1] && tready_i_eff) begin
            f_ddb_empty_eff_r <= f_ddb_empty_eff;
            // f_ddb_empty_eff_any_r <= f_ddb_empty_eff_any;
        end
    end
    
    // DDB Input Data Register
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                ddb_in_r[pe_idx] <= '0;
            end else if (f_I[0] && valid_i && !f_ddb_full_eff[pe_idx]) begin    // (state inside {S_FP, S_BPdW, S_PU})
                ddb_in_r[pe_idx] <= din_act[pe_idx];
            end
        end
    end
    
    // BRAM_DDB
    generate
        for (genvar pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            // (* ram_style = "block" *)
            BRAM_SDP_1C #(
                .RAM_WIDTH(BRAM_DDB_BW),
                .RAM_DEPTH(BRAM_DDB_DEPTH),
                .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
                .INIT_FILE("")
            ) BRAM_DDR_DATA_BUF (
                .addra  (pt_ddb_wr[pe_idx]),
                .addrb  (pt_ddb_rd[pe_idx]),
                .dina   (ddb_in_r[pe_idx]),
                .clka   (clk),
                .wea    (en_ddb_wr[pe_idx]),
                .enb    (en_ddb_rd[pe_idx]),
                .rstb   ((!rstn) || (!rstn_ddb)),
                .regceb (regce_ddb[pe_idx]),
                .doutb  (tdata[WEIGHT_BW*pe_idx +: WEIGHT_BW])
            );
        end
    endgenerate
    
    // logic [BRAM_DDB_BW-1:0] bram_ddb_out [NUM_PE-1:0];

    // npp_std_if bram_ddb_clk();
    // assign bram_ddb_clk.clk = clk;
    // assign bram_ddb_clk.resetn = rstn;

    // generate
    //     for (genvar pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         npp_memory_2p #(
    //             .WORD_NUM_BITS      (BRAM_DDB_BW),
    //             .NUM_ENTRIES        (BRAM_DDB_DEPTH)
    //         ) BRAM_DDB (
    //             .npp_std_write      (bram_ddb_clk.slave),
    //             .npp_std_read       (bram_ddb_clk.slave),
    //             .write_chip_enable  (!en_ddb_wr[pe_idx]),
    //             .read_chip_enable   (!en_ddb_rd[pe_idx]),
    //             .input_word         (ddb_in_r[pe_idx]),
    //             .write_address      (pt_ddb_wr[pe_idx]),
    //             .read_address       (pt_ddb_rd[pe_idx]),
    //             .output_word        (bram_ddb_out[pe_idx])
    //         );
    //     end
    // endgenerate

    // logic [BRAM_DDB_BW-1:0] bram_ddb_out_reg [NUM_PE-1:0];
    // always_ff @(posedge clk) begin
    //     for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         if ((!rstn) || (!rstn_ddb)) begin
    //             bram_ddb_out_reg[pe_idx] <= '0;
    //         end else if (regce_ddb[pe_idx]) begin
    //             bram_ddb_out_reg[pe_idx] <= bram_ddb_out[pe_idx];
    //         end
    //     end
    // end

    // always_comb begin
    //     for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         tdata[WEIGHT_BW*pe_idx +: WEIGHT_BW] = bram_ddb_out_reg[pe_idx][BRAM_DDB_BW-1:0];
    //     end
    // end

    
    
    // BRAM_IDB - control signals
    assign rstn_idb = !(state == S_CFG);
    // assign en_idb_rd = '{NUM_PE{1'b0}};
    // assign regce_idb = '{NUM_PE{1'b0}};
    
    // BRAM_IDB - address
    always_comb begin
        case (state)
            S_FP : begin    // A[l]
                // addr_idb_p = '{NUM_PE{ADDR_IDB_A | cnt_i}};
                addr_idb_p = '{NUM_PE{ADDR_IDB_A | cnt_i}}; // ($clog2(MAX_M) - $clog2(cfg_m))
            end
            S_BPdZ : begin  // dZ[l]
                // addr_idb_p = '{NUM_PE{ADDR_IDB_dZ | cnt_i}};
                addr_idb_p = '{NUM_PE{ADDR_IDB_dZ | cnt_i}}; // ($clog2(MAX_M) - $clog2(cfg_m))
            end
            S_BPdA : begin  // dA[l-1]
                // addr_idb_p = '{NUM_PE{ADDR_IDB_dA | {cnt_n1 >> $clog2(NUM_PE), cnt_m}}};
                addr_idb_p = '{NUM_PE{ADDR_IDB_dA | {cnt_n1 >> $clog2(NUM_PE)}}};
                // addr_idb_p = '{NUM_PE{'0}};
                // addr_idb_p[cnt_n1[$clog2(NUM_PE)-1:0]] = ADDR_IDB_dA | {cnt_n1 >> $clog2(NUM_PE), cnt_m};
            end
            default : begin 
                addr_idb_p = '{NUM_PE{'0}};
            end
        endcase
    end
    
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                addr_idb_pr[pe_idx] <= '0;
            end else if (f_I[0] && valid_i && !f_ddb_full_eff[pe_idx]) begin
                addr_idb_pr[pe_idx] <= addr_idb_p[pe_idx];
            end
        end
    end

    assign addr_idb = addr_idb_pr;
    
    always_comb begin
        case (state) inside
            S_FP, S_BPdZ : begin
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    en_idb_wr_p[pe_idx] = f_I[0];
                    en_idb_wr[pe_idx] = f_I[0:1] && en_idb_wr_pr[pe_idx] && valid_i_r && !f_ddb_full_eff[pe_idx];
                end
            end
            S_BPdA : begin
                en_idb_wr_p = '{NUM_PE{'0}};
                en_idb_wr_p[cnt_n1[$clog2(NUM_PE)-1:0]] = f_I[0];
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    en_idb_wr[pe_idx] = f_I[0:1] && en_idb_wr_pr[pe_idx] && valid_i_r && !f_ddb_full_eff[pe_idx];
                end
            end
            default : begin
                en_idb_wr_p = '{NUM_PE{'0}};
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    en_idb_wr[pe_idx] = f_I[0:1] && en_idb_wr_pr[pe_idx] && valid_i_r && !f_ddb_full_eff[pe_idx];
                end
            end
        endcase
    end
    
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                en_idb_wr_pr[pe_idx] <= '0;
            end else if (f_I[0:1] && valid_i && !f_ddb_full_eff[pe_idx]) begin
                en_idb_wr_pr[pe_idx] <= en_idb_wr_p[pe_idx];
            end
        end
    end
    
    // IDB_MUX - input select
    always_comb begin
        case (state) inside
            S_FP, S_BPdZ : begin
                idb_sel = 1'b0;                 // From PEs
            end
            S_BPdA : begin
                idb_sel = 1'b1;                 // From ACC
            end
            default : begin
                idb_sel = 1'b0;
            end
        endcase
    end
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            idb_mux_out <= '{NUM_PE{'0}};
        end else if (f_I[0] && valid_i && !f_ddb_full_eff_any) begin
            case (idb_sel)
                1'b0: idb_mux_out <= din_act[NUM_PE-1:0];
                1'b1: idb_mux_out <= '{NUM_PE{din_act[NUM_PE]}};
            endcase
        end
    end
    
    // BRAM_IDB
    // generate
    //     for (genvar pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         // (* ram_style = "block" *)
    //         BRAM_TDP_NC_1C #(
    //             .RAM_WIDTH(BRAM_IDB_BW),
    //             .RAM_DEPTH(BRAM_IDB_DEPTH),
    //             .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
    //             .INIT_FILE($sformatf("idb%0d_init.mem", pe_idx))
    //         ) BRAM_INTERM_DATA_BUF (
    //             .addra(),
    //             .addrb(addr_idb[pe_idx]),
    //             .dina(),
    //             .dinb(idb_mux_out[pe_idx]),
    //             .clka(clk),
    //             .wea(),
    //             .web(en_idb_wr[pe_idx]),
    //             .ena(),
    //             .enb(en_idb_wr[pe_idx]),        // Synchronize with write enable
    //             .rsta(),
    //             .rstb((!rstn) || (!rstn_idb)),
    //             .regcea(),
    //             .regceb(regce_idb[pe_idx]),
    //             .douta(),
    //             .doutb()                        // IDB PortB Output not used
    //         );
    //     end
    // endgenerate

    assign idb_din = idb_mux_out;
    
    
    
endmodule
