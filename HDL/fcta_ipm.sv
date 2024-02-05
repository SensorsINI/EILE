
import definesPkg::*;

module IPM #(
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
    parameter BRAM_DDB_DEPTH = (MAX_M>NUM_PE)? (MAX_M+1):(NUM_PE+1),    //32
    parameter BRAM_IDB_BW    = 16,
    parameter BRAM_IDB_DEPTH = MAX_M*MAX_NoP*2,
    parameter BRAM_MAC_DEPTH = MAX_M*MAX_NoP,   //2048
    // parameter BRAM_ACC_DEPTH = MAX_M,           //32
    localparam WEIGHT_BW = WEIGHT_QM + WEIGHT_QN,
    localparam ACT_BW    = ACT_QM + ACT_QN,
    localparam ACC_BW    = ACC_QM + ACC_QN,
    localparam ADDR_IDB_A  = 0,
    localparam ADDR_IDB_dZ = 0,
    localparam ADDR_IDB_dA = MAX_M*MAX_NoP
) (
    input logic         clk,
    input logic         rstn,
    input logic         ready_i,
    input logic         tvalid,
    // input logic         tlast,
    
    // stage, m*(n2/P), n1
    input logic         cfg_start,
    input stage_t                               cfg_stage,
    input logic [$clog2(MAX_M)-1:0]             cfg_m,
    input logic [$clog2(MAX_NoP)-1:0]           cfg_n2op,
    input logic [$clog2(MAX_N)-1:0]             cfg_n1,
    input logic [$clog2(MAX_NoP*MAX_N*2)-1:0]   cfg_cnt_ddi,
    input logic [$clog2(BRAM_MAC_DEPTH)-1:0]    cfg_cnt_ba,
    // input logic [$clog2(MAX_N)-1:0]             cfg_cnt_ar,
    // input logic [$clog2(MAX_NoP*MAX_N)-1:0]     cfg_cnt_rr,
    
    input logic [AXIS_BW-1:0]                   tdata,
    
    output logic        tready,
    output logic        valid_o,
    output logic        f_ipm_finish,
    output logic signed[ACT_BW-1:0]             dout_act[NUM_PE-1:0],
    output logic signed[WEIGHT_BW-1:0]          dout_weight[NUM_PE-1:0],
    
    // BRAM_IDB
    output logic                                rstn_idb,
    output logic [$clog2(BRAM_IDB_DEPTH)-1:0]   addr_idb[NUM_PE-1:0],
    output logic                                en_idb_rd[NUM_PE-1:0],
    output logic                                en_idb_wr[NUM_PE-1:0],
    output logic                                regce_idb[NUM_PE-1:0],
    input  logic signed[ACT_BW-1:0]             idb_out[NUM_PE-1:0]
);

    // Overall - control signals
    logic               rstn_CFG;
    
    // Overall - flags
    // (* mark_debug = "true" *)
    logic               f_I;
    // logic [0:4]         f_O;
    logic [0:3+NUM_PE]  f_O;
    
    // Output Signal
    // logic [0:3]         valid_o_pr;
    logic [0:2+NUM_PE]  valid_o_pr;
    
    // FSM - states
    // (* mark_debug = "true" *)
    enum logic [3:0] {  S_NCFG, S_CFG,
                        S_A0,               // Transfer A0 from DRAM to BRAM_IDB
                        S_FP,
                        S_BPdZ,
                        S_BPdA,
                        S_BPdW,
                        S_PU} state;
    
    // DRAM Data I/O Counter
    // (* mark_debug = "true" *)
    logic [$clog2(MAX_NoP*MAX_N*2)-1:0]     cnt_ddi;
    logic                                   f_cnt_i;
    logic [$clog2(MAX_M)-1:0]               cnt_m;
    logic [$clog2(MAX_NoP)-1:0]             cnt_n2op;
    logic [$clog2(MAX_N)-1:0]               cnt_n1;
    logic                                   f_cnt_o;
    // logic [0:3]                             f_cnt_o_r;
    logic [0:2+NUM_PE]                      f_cnt_o_r;
    logic [$clog2(BRAM_MAC_DEPTH)-1:0]      cnt_ba;
    logic                                   param_sel;
    
    // BRAM_DDB Control Signal, Pointer, Data Counter, Flag
    logic                                   en_ddb_rd[NUM_PE-1:0];
    logic                                   en_ddb_rd_cm[NUM_PE-1:0];   // Cascade Mode
    logic                                   en_ddb_rrd[NUM_PE-1:0];     // Repetive Read
    logic                                   en_ddb_wr[NUM_PE-1:0];
    logic                                   rstn_ddb;
    logic                                   regce_ddb[NUM_PE-1:0];
    logic                                   regce_ddb_p[NUM_PE-1:0];
    logic                                   regce_ddb_pr[NUM_PE-1:0];
    logic                                   regce_ddb_cm[NUM_PE-1:0];   // Cascade Mode
    logic [$clog2(BRAM_DDB_DEPTH)-1:0]      pt_ddb_rd[NUM_PE-1:0];
    logic [$clog2(BRAM_DDB_DEPTH)-1:0]      pt_ddb_rd_s[NUM_PE-1:0];    // Repetive Read - Saved copy
    logic [$clog2(BRAM_DDB_DEPTH)-1:0]      pt_ddb_rd_sv[NUM_PE-1:0];   // Repetive Read - Save
    logic [$clog2(BRAM_DDB_DEPTH)-1:0]      pt_ddb_rd_ld[NUM_PE-1:0];   // Repetive Read - Load
    logic [$clog2(BRAM_DDB_DEPTH)-1:0]      pt_ddb_wr[NUM_PE-1:0];
    logic [$clog2(BRAM_DDB_DEPTH+1)-1:0]    cnt_ddb[NUM_PE-1:0];
    logic                                   f_ddb_full[NUM_PE-1:0];
    logic                                   f_ddb_full_eff[NUM_PE-1:0];
    logic                                   f_ddb_full_eff_any;
    logic                                   f_ddb_empty[NUM_PE-1:0];
    logic                                   f_ddb_empty_eff[NUM_PE-1:0];
    logic                                   f_ddb_empty_eff_any;
    logic                                   f_ddb_empty_eff_any_r[0:1];

    // DDB_MUX Data, Control Signal
    logic signed[WEIGHT_BW-1:0]             ddb_out[NUM_PE-1:0];
    logic signed[WEIGHT_BW-1:0]             ddb_out_r[NUM_PE-1:0];
    logic signed[WEIGHT_BW-1:0]             ddb_mux0_out;
    logic [$clog2(NUM_PE+1)-1:0]            ddb_sel0;
    logic [$clog2(NUM_PE+1)-1:0]            ddb_sel0_p;
    logic [$clog2(NUM_PE+1)-1:0]            ddb_sel0_pr[0:1];
    logic signed[WEIGHT_BW-1:0]             ddb_mux1_out[NUM_PE-1:0];
    logic                                   ddb_sel1;
    logic                                   ddb_sel1_p;
    logic                                   ddb_sel1_pr[0:2];
    
    // BRAM_IDB Control Signal, Address
    // logic                                   en_idb_rd[NUM_PE-1:0];
    logic                                   en_idb_rd_cm[NUM_PE-1:0];   // Cascade Mode
    // logic                                   en_idb_wr[NUM_PE-1:0];
    // logic                                   rstn_idb;
    // logic                                   regce_idb[NUM_PE-1:0];
    logic                                   regce_idb_p[NUM_PE-1:0];
    logic                                   regce_idb_pr[NUM_PE-1:0];
    logic                                   regce_idb_cm[NUM_PE-1:0];   // Cascade Mode
    // logic [$clog2(BRAM_IDB_DEPTH)-1:0]      addr_idb[NUM_PE-1:0];
    logic [$clog2(BRAM_IDB_DEPTH)-1:0]      addr_idb_cm[NUM_PE-1:0];    // Cascade Mode
    
    // IDB_MUX Data, Control Signal
    // logic signed[ACT_BW-1:0]                idb_out[NUM_PE-1:0];
    logic signed[ACT_BW-1:0]                idb_out_r[NUM_PE-1:0];
    logic signed[ACT_BW-1:0]                idb_mux0_out;
    logic [$clog2(NUM_PE+3)-1:0]            idb_sel0;
    logic [$clog2(NUM_PE+3)-1:0]            idb_sel0_p;
    logic [$clog2(NUM_PE+3)-1:0]            idb_sel0_pr[0:1];
    logic signed[ACT_BW-1:0]                idb_mux1_out[NUM_PE-1:0];
    logic                                   idb_sel1;
    logic                                   idb_sel1_p;
    logic                                   idb_sel1_pr[0:2];
    
    
    
    // FSM
    always_ff @(posedge clk) begin
        if (!rstn) begin
            state <= S_NCFG;
        end else begin
            case (state)
    
                S_NCFG : begin              // Not configured
                    if (cfg_start) begin
                        state <= S_CFG;
                    end
                end
                
                S_CFG : begin               // Configuring
                    case (cfg_stage)
                        STAGE_A0 : begin
                            state <= S_A0;
                        end
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
                
                S_A0 : begin                // Transfer A0 from DRAM to BRAM_IDB
                    if (f_cnt_i && tvalid) begin
                        state <= S_NCFG;
                    end
                end
                
                S_FP : begin                // Forward Prop
                    if (f_cnt_o_r[3] && ready_i) begin
                        state <= S_NCFG;
                    end
                end
                
                S_BPdZ : begin              // Backward Prop - dZ
                    if (f_cnt_o_r[3] && ready_i) begin
                        state <= S_NCFG;
                    end
                end
                
                S_BPdA : begin              // Backward Prop - dA
                    if (f_cnt_o_r[2+NUM_PE] && ready_i) begin  // NUM_PE
                        state <= S_NCFG;
                    end
                end
                
                S_BPdW : begin              // Backward Prop - dW
                    if (f_cnt_o_r[3] && ready_i) begin
                        state <= S_NCFG;
                    end
                end
                
                S_PU : begin                // Parameter Update
                    if (f_cnt_o_r[3] && ready_i) begin
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
            f_ipm_finish <= 1'b1;
        end else begin
            case (state) inside
                // Deassert when a process is started
                S_NCFG : begin
                    if (cfg_start) begin
                        f_ipm_finish <= 1'b0;
                    end
                end
                // Assert when a process is finished
                S_A0 : begin
                    if (f_cnt_i && tvalid) begin
                        f_ipm_finish <= 1'b1;
                    end
                end
                default : begin
                    f_ipm_finish <= 1'b0;
                end
            endcase
        end
    end



    // Control Signals
    
    always_comb begin
        case (state) inside
            // S_A0 : begin
                // tready = f_I;
            // end
            S_A0, S_FP, S_BPdZ, S_BPdA, S_BPdW, S_PU : begin
                tready = f_I && !f_ddb_full_eff_any;
            end
            default : begin
                tready = 1'b0;
            end
        endcase
    end
    
    // always_ff @(posedge clk) begin
    //     if (!rstn || !rstn_CFG) begin
    //         valid_o_pr <= '0;
    //     // end else if ((|f_O[0:4]) && ready_i) begin // || !valid_o
    //         // valid_o_pr[0:3] <= {f_O[0] && !f_ddb_empty_eff_any,
    //                             // valid_o_pr[0:2]};
    //     end else if ((|f_O[0:3+NUM_PE]) && ready_i) begin // || !valid_o
    //         valid_o_pr[0:2+NUM_PE] <= { f_O[0] && !f_ddb_empty_eff_any,
    //                                     valid_o_pr[0:1+NUM_PE]};
    //     end
    // end
    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 0; ps_idx < NUM_PE+3; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                valid_o_pr[ps_idx] <= 1'b0;
            end else if ((|f_O[0:3+NUM_PE]) && ready_i) begin
                valid_o_pr[ps_idx] <= f_O[ps_idx] && !f_ddb_empty_eff_any;
            end
        end
    end
    
    // assign valid_o = valid_o_pr[3];
    always_comb begin
        case (state) inside
            S_A0 : begin
                valid_o = 1'b0;
            end
            S_FP, S_BPdZ, S_BPdW, S_PU : begin
                valid_o = valid_o_pr[3];
            end
            S_BPdA : begin
                // valid_o = valid_o_pr[2+NUM_PE];
                valid_o = ( (f_O[4]) && valid_o_pr[3] ||
                            (!f_O[4] && f_O[3+NUM_PE]) && valid_o_pr[2+NUM_PE]);
            end
            default : begin
                valid_o = valid_o_pr[3];
            end
        endcase
    end
    
    assign rstn_CFG = !(state == S_CFG);
    
    
    
    // Flags
    always_ff @(posedge clk) begin
        if (!rstn) begin    // No || !rstn_CFG
            f_I <= 1'b0;
        end else begin
            case (state) inside
                S_CFG : begin
                    if (cfg_stage inside {STAGE_A0, STAGE_FP, STAGE_BPdZ, STAGE_BPdA, STAGE_BPdW, STAGE_PU}) begin
                        f_I <= 1'b1;
                    end else begin
                        f_I <= 1'b0;
                    end
                end
                // S_A0 : begin
                    // // Deassert when last input data written
                    // if (f_cnt_i && tvalid) begin
                        // f_I <= 1'b0;
                    // end
                // end
                S_A0, S_FP, S_BPdZ, S_BPdA, S_BPdW, S_PU : begin
                    // Deassert when last input data written
                    if (f_cnt_i && tvalid && !f_ddb_full_eff_any) begin
                        f_I <= 1'b0;
                    end
                end
                default : begin
                    f_I <= 1'b0;
                end
            endcase
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
                S_FP : begin
                    // Assert when first input data written
                    // Deassert when last data read and held for necessary cycles
                    if (f_I && tvalid && !f_ddb_full_eff_any) begin
                        f_O[0] <= 1'b1;
                    end else if (f_cnt_o && ready_i && !f_ddb_empty_eff_any) begin
                        f_O[0] <= 1'b0;
                    end
                end
                S_BPdZ, S_BPdW, S_PU : begin
                    // Assert when first input data written
                    // Deassert when last data read
                    if (f_I && tvalid && !f_ddb_full_eff_any) begin
                        f_O[0] <= 1'b1;
                    end else if (f_cnt_o && ready_i && !f_ddb_empty_eff_any) begin
                        f_O[0] <= 1'b0;
                    end
                end
                S_BPdA : begin
                    // Assert when first input data written
                    // Deassert when last data read
                    if (f_I && tvalid && !f_ddb_full_eff_any) begin
                        f_O[0] <= 1'b1;
                    end else if (f_cnt_o && ready_i && !f_ddb_empty_eff_any) begin // NUM_PE?
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
            // f_O[1:4] <= '0;
        // end else if ((|f_O[0:4]) && !f_ddb_empty_eff_any && ready_i) begin
            // f_O[1:4] <= f_O[0:3];
            f_O[1:3+NUM_PE] <= '0;
        end else if ((|f_O[0:3+NUM_PE]) && !f_ddb_empty_eff_any && ready_i) begin
            f_O[1:3+NUM_PE] <= f_O[0:2+NUM_PE];
        end
    end
    
    
    
    // DRAM Data Input Counter
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            cnt_ddi <= '0;
        end else if (f_I && tvalid && !f_ddb_full_eff_any) begin
            if (cnt_ddi == cfg_cnt_ddi) begin
                cnt_ddi <= '0;
            end else begin
                cnt_ddi <= cnt_ddi + 1;
            end
        end
    end
    
    assign f_cnt_i = (cnt_ddi == cfg_cnt_ddi);
    
    // DRAM Data Output Counter
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            cnt_m    <= '0;
            cnt_n2op <= '0;
            cnt_n1   <= '0;
        end else if (f_O[0] && !f_ddb_empty_eff_any && ready_i) begin
            if (cnt_m == cfg_m) begin
                if (cnt_n2op == cfg_n2op) begin
                    if (cnt_n1 == cfg_n1) begin
                        cnt_n1 <= '0;
                    end else begin
                        cnt_n1 <= cnt_n1 + 1;
                    end
                    cnt_n2op <= '0;
                end else begin
                    cnt_n2op <= cnt_n2op + 1;
                end
                cnt_m <= '0;
            end else begin
                cnt_m <= cnt_m + 1;
            end
        end
    end
    
    assign f_cnt_o = (cnt_n1 == cfg_n1) && (cnt_n2op == cfg_n2op) && (cnt_m == cfg_m);
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            f_cnt_o_r <= '0;
        // end else if ((|f_O[0:4]) && !f_ddb_empty_eff_any && ready_i) begin
            // f_cnt_o_r[0:3] <= {f_cnt_o, f_cnt_o_r[0:2]};
        end else if ((|f_O[0:3+NUM_PE]) && !f_ddb_empty_eff_any && ready_i) begin
            f_cnt_o_r[0:2+NUM_PE] <= {f_cnt_o, f_cnt_o_r[0:1+NUM_PE]};
        end
    end
    
    // BRAM Address Counter - for switching '1'/'η' at S_PU
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            cnt_ba <= '0;
            param_sel <= 1'b0;
        end else if (f_O[0] && !f_ddb_empty_eff_any && ready_i) begin
            if (cnt_ba == cfg_cnt_ba) begin
                cnt_ba <= '0;
                param_sel <= ~param_sel;
            end else begin
                cnt_ba <= cnt_ba + 1;
            end
        end
    end
    
    
    
    // BRAM_DDB - control signals
    assign rstn_ddb = !(state == S_CFG);
    
    always_comb begin
        case (state)
            S_A0 : begin
                en_ddb_rrd = '{NUM_PE{'0}};
                pt_ddb_rd_sv = '{NUM_PE{'0}};
                pt_ddb_rd_ld = '{NUM_PE{'0}};
                en_ddb_wr = '{NUM_PE{'0}};
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    en_ddb_rd[pe_idx] = f_O[0] && (cnt_m == 0) && !f_ddb_empty_eff[pe_idx] && ready_i;
                    // regce_ddb_p[pe_idx] = f_O[0] && (cnt_m == 0) && !f_ddb_empty_eff[pe_idx];
                    // regce_ddb[pe_idx] = (|f_O[0:1]) && regce_ddb_pr[pe_idx] && ready_i;
                    regce_ddb_p[pe_idx] = f_O[0] && (cnt_m == 0);
                    regce_ddb[pe_idx] = (|f_O[0:1]) && regce_ddb_pr[pe_idx] && !f_ddb_empty_eff_any_r[0] && ready_i;
                end
            end
            // Stall input if any FIFO is effectively full
            S_FP : begin
                en_ddb_rrd = '{NUM_PE{'0}};
                pt_ddb_rd_sv = '{NUM_PE{'0}};
                pt_ddb_rd_ld = '{NUM_PE{'0}};
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    en_ddb_wr[pe_idx] = f_I && tvalid && !f_ddb_full_eff_any;
                    en_ddb_rd[pe_idx] = f_O[0] && (cnt_m == 0) && !f_ddb_empty_eff[pe_idx] && ready_i;
                    // regce_ddb_p[pe_idx] = f_O[0] && (cnt_m == 0) && !f_ddb_empty_eff[pe_idx];
                    // regce_ddb[pe_idx] = (|f_O[0:1]) && regce_ddb_pr[pe_idx] && ready_i;
                    regce_ddb_p[pe_idx] = f_O[0] && (cnt_m == 0);
                    regce_ddb[pe_idx] = (|f_O[0:1]) && regce_ddb_pr[pe_idx] && !f_ddb_empty_eff_any_r[0] && ready_i;
                end
            end
            S_BPdZ, S_PU : begin
                en_ddb_rrd = '{NUM_PE{'0}};
                pt_ddb_rd_sv = '{NUM_PE{'0}};
                pt_ddb_rd_ld = '{NUM_PE{'0}};
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    en_ddb_wr[pe_idx] = f_I && tvalid && !f_ddb_full_eff_any;
                    en_ddb_rd[pe_idx] = f_O[0] && !f_ddb_empty_eff[pe_idx] && ready_i;
                    // regce_ddb_p[pe_idx] = f_O[0] && !f_ddb_empty_eff[pe_idx];
                    // regce_ddb[pe_idx] = (|f_O[0:1]) && regce_ddb_pr[pe_idx] && ready_i;
                    regce_ddb_p[pe_idx] = f_O[0];
                    regce_ddb[pe_idx] = (|f_O[0:1]) && regce_ddb_pr[pe_idx] && !f_ddb_empty_eff_any_r[0] && ready_i;
                end
            end
            S_BPdA : begin
                en_ddb_rrd = '{NUM_PE{'0}};
                pt_ddb_rd_sv = '{NUM_PE{'0}};
                pt_ddb_rd_ld = '{NUM_PE{'0}};
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    en_ddb_wr[pe_idx] = f_I && tvalid && !f_ddb_full_eff_any;
                    // f_O[-1+pe_idx] &&        // NUM_PE
                    en_ddb_rd[pe_idx] = en_ddb_rd_cm[pe_idx] && !f_ddb_empty_eff_any && ready_i;
                    // Unused
                    regce_ddb_p[pe_idx] = f_O[0] && !f_ddb_empty_eff_any;
                    // (|f_O[0:pe_idx]) &&   // NUM_PE
                    regce_ddb[pe_idx] = regce_ddb_cm[pe_idx] && !f_ddb_empty_eff_any_r[0] && ready_i;
                end
            end
            S_BPdW : begin
                logic [$clog2(NUM_PE)-1:0] cnt_n1mp;    // cnt_n1[$clog2(NUM_PE)-1:0]
                cnt_n1mp = cnt_n1;
                en_ddb_rd = '{NUM_PE{'0}};
                en_ddb_rrd = '{NUM_PE{'0}};
                pt_ddb_rd_sv = '{NUM_PE{'0}};
                pt_ddb_rd_ld = '{NUM_PE{'0}};
                regce_ddb_p = '{NUM_PE{'0}};
                // regce_ddb = '{NUM_PE{'0}};
                if (cnt_n1mp < (NUM_PE-1)) begin
                    en_ddb_rd[cnt_n1mp] = f_O[0] && (cnt_n2op == 0) && !f_ddb_empty_eff_any && ready_i;
                    en_ddb_rrd[cnt_n1mp] = f_O[0] && (cnt_n2op > 0) && !f_ddb_empty_eff_any && ready_i;
                end else begin
                    en_ddb_rd[cnt_n1mp] = f_O[0] && (cnt_n2op == cfg_n2op) && !f_ddb_empty_eff_any && ready_i;
                    en_ddb_rrd[cnt_n1mp] = f_O[0] && (cnt_n2op < cfg_n2op) && !f_ddb_empty_eff_any && ready_i;
                end
                pt_ddb_rd_sv[cnt_n1mp] = f_O[0] && (cnt_n2op < cfg_n2op) && (cnt_m == 0) && !f_ddb_empty_eff_any && ready_i;
                pt_ddb_rd_ld[cnt_n1mp] = f_O[0] && (cnt_n2op < cfg_n2op) && (cnt_m == cfg_m) && !f_ddb_empty_eff_any && ready_i;
                regce_ddb_p[cnt_n1mp] = f_O[0];
                // regce_ddb[cnt_n1mp] = (|f_O[0:1]) && regce_ddb_pr[cnt_n1mp] && !f_ddb_empty_eff_any_r[0] && ready_i;
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    en_ddb_wr[pe_idx] = f_I && tvalid && !f_ddb_full_eff_any;
                    regce_ddb[pe_idx] = (|f_O[0:1]) && regce_ddb_pr[pe_idx] && !f_ddb_empty_eff_any_r[0] && ready_i;
                end
            end
            default : begin
                en_ddb_rrd = '{NUM_PE{'0}};
                pt_ddb_rd_sv = '{NUM_PE{'0}};
                pt_ddb_rd_ld = '{NUM_PE{'0}};
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    en_ddb_wr[pe_idx] = f_I && tvalid && !f_ddb_full_eff_any;
                    en_ddb_rd[pe_idx] = f_O[0] && !f_ddb_empty_eff[pe_idx] && ready_i;
                    // regce_ddb_p[pe_idx] = f_O[0] && !f_ddb_empty_eff[pe_idx];
                    // regce_ddb[pe_idx] = (|f_O[0:1]) && regce_ddb_pr[pe_idx] && ready_i;
                    regce_ddb_p[pe_idx] = f_O[0];
                    regce_ddb[pe_idx] = (|f_O[0:1]) && regce_ddb_pr[pe_idx] && !f_ddb_empty_eff_any_r[0] && ready_i;
                end
            end
        endcase
    end
    
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                regce_ddb_pr[pe_idx] <= '0;
            // end else if ((|f_O[0:1]) && ready_i) begin
            end else if ((|f_O[0:1]) && !f_ddb_empty_eff_any && ready_i) begin
                regce_ddb_pr[pe_idx] <= regce_ddb_p[pe_idx];
            end
        end
    end
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            f_ddb_empty_eff_any_r <= '{2{'0}};
        // end else if ((|f_O[0:1]) && ready_i) begin  // NUM_PE
        // end else if ((|f_O[0:4]) && ready_i) begin
        end else if ((|f_O[0:3+NUM_PE]) && ready_i) begin
            f_ddb_empty_eff_any_r[0] <= f_ddb_empty_eff_any;
            f_ddb_empty_eff_any_r[1] <= f_ddb_empty_eff_any_r[0];
        end
    end
    
    assign en_ddb_rd_cm[0] = f_O[0] && (cnt_m == 0);
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 1; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                en_ddb_rd_cm[pe_idx] <= '0;
            // end else if ((|f_O[pe_idx-1:pe_idx]) && !f_ddb_empty_eff_any && ready_i) begin
            // end else if ((|f_O[0:4]) && !f_ddb_empty_eff_any && ready_i) begin
            end else if ((|f_O[0:3+NUM_PE]) && !f_ddb_empty_eff_any && ready_i) begin
                en_ddb_rd_cm[pe_idx] <= en_ddb_rd_cm[pe_idx-1];
            end
        end
    end
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            regce_ddb_cm[0] <= '0;
        end else if ((|f_O[0:1]) && !f_ddb_empty_eff_any && ready_i) begin  // NUM_PE
            regce_ddb_cm[0] <= f_O[0] && (cnt_m == 0);
        end
    end
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 1; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                regce_ddb_cm[pe_idx] <= '0;
            // end else if ((|f_O[pe_idx:pe_idx+1]) && !f_ddb_empty_eff_any && ready_i) begin
            // end else if ((|f_O[0:4]) && !f_ddb_empty_eff_any && ready_i) begin
            end else if ((|f_O[1:3+NUM_PE]) && !f_ddb_empty_eff_any && ready_i) begin
                regce_ddb_cm[pe_idx] <= regce_ddb_cm[pe_idx-1];
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
                pt_ddb_rd_s[pe_idx] <= '0;
            end else if (en_ddb_rd[pe_idx] || en_ddb_rrd[pe_idx]) begin
                if (pt_ddb_rd_ld[pe_idx]) begin
                    // pt_ddb_rd[pe_idx] <= pt_ddb_rd_s[pe_idx];    // Load
                    if (!pt_ddb_rd_sv[pe_idx]) begin
                        pt_ddb_rd[pe_idx] <= pt_ddb_rd_s[pe_idx];    // Load
                    end
                end else if (pt_ddb_rd[pe_idx] == BRAM_DDB_DEPTH-1) begin
                    pt_ddb_rd[pe_idx] <= 0;
                end else begin
                    pt_ddb_rd[pe_idx] <= pt_ddb_rd[pe_idx] + 1;
                end
                // if (pt_ddb_rd_sv[pe_idx]) begin
                if (pt_ddb_rd_sv[pe_idx] && !pt_ddb_rd_ld[pe_idx]) begin
                    pt_ddb_rd_s[pe_idx] <= pt_ddb_rd[pe_idx];    // Save
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
        f_ddb_empty_eff_any = 1'b0;
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            f_ddb_full[pe_idx]       = cnt_ddb[pe_idx] == BRAM_DDB_DEPTH;
            f_ddb_full_eff[pe_idx]   = f_ddb_full[pe_idx] && !en_ddb_rd[pe_idx];
            // f_ddb_full_eff_any      |= f_ddb_full_eff[pe_idx];
            f_ddb_empty[pe_idx]      = cnt_ddb[pe_idx] == 0;
            f_ddb_empty_eff[pe_idx]  = f_ddb_empty[pe_idx] && f_I;
            f_ddb_empty_eff_any     |= f_ddb_empty_eff[pe_idx];
        end
        f_ddb_full_eff_any  = f_ddb_full_eff[NUM_PE-1]; // DDB[NUM_PE-1] always first to be full
        // f_ddb_empty_eff_any = f_ddb_empty_eff[0];       // DDB[0] always first to be empty
    end
    
    // // BRAM_DDB
    // generate
    //     for (genvar pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         // (* ram_style = "block" *)
    //         BRAM_SDP_1C #(
    //             .RAM_WIDTH(BRAM_DDB_BW),
    //             .RAM_DEPTH(BRAM_DDB_DEPTH),
    //             .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
    //             .INIT_FILE("")
    //         ) BRAM_DDR_DATA_BUF (
    //             .addra  (pt_ddb_wr[pe_idx]),
    //             .addrb  (pt_ddb_rd[pe_idx]),
    //             .dina   (tdata[WEIGHT_BW*pe_idx +: WEIGHT_BW]),
    //             .clka   (clk),
    //             .wea    (en_ddb_wr[pe_idx]),
    //             // .enb    (en_ddb_rd[pe_idx]),
    //             .enb    (en_ddb_rd[pe_idx] || en_ddb_rrd[pe_idx]),
    //             .rstb   ((!rstn) || (!rstn_ddb)),
    //             .regceb (regce_ddb[pe_idx]),
    //             .doutb  (ddb_out[pe_idx])
    //         );
    //     end
    // endgenerate
    
    logic [BRAM_DDB_BW-1:0] bram_ddb_out [NUM_PE-1:0];

    // npp_std_if bram_ddb_clk();
    // assign bram_ddb_clk.clk = clk;
    // assign bram_ddb_clk.resetn = rstn;

    generate
        for (genvar pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            // logic gclk;
            // logic en_lo;
            // always_latch begin
            //     if (~clk) begin
            //         en_lo = (en_ddb_wr[pe_idx]) || (en_ddb_rd[pe_idx] || en_ddb_rrd[pe_idx]);
            //     end
            // end
            // assign gclk = en_lo && clk;

            logic gclk_wr;
            PREICG_X16B_A7TSL_C30 latch_wr (
                .CK(clk),
                .E(en_ddb_wr[pe_idx]),
                .SE(1'b0),
                .ECK(gclk_wr)
            );
            npp_std_if bram_ddb_clk_wr();
            assign bram_ddb_clk_wr.clk = gclk_wr;
            assign bram_ddb_clk_wr.resetn = rstn;

            logic gclk_rd;
            PREICG_X16B_A7TSL_C30 latch_rd (
                .CK(clk),
                .E(en_ddb_rd[pe_idx] || en_ddb_rrd[pe_idx]),
                .SE(1'b0),
                .ECK(gclk_rd)
            );
            npp_std_if bram_ddb_clk_rd();
            assign bram_ddb_clk_rd.clk = gclk_rd;
            assign bram_ddb_clk_rd.resetn = rstn;

            npp_memory_2p #(
                .WORD_NUM_BITS      (BRAM_DDB_BW),
                .NUM_ENTRIES        (BRAM_DDB_DEPTH)
            ) BRAM_DDB (
                .npp_std_write      (bram_ddb_clk_wr.slave),
                .npp_std_read       (bram_ddb_clk_rd.slave),
                .write_chip_enable  (!en_ddb_wr[pe_idx]),
                .read_chip_enable   (!(en_ddb_rd[pe_idx] || en_ddb_rrd[pe_idx])),
                .input_word         (tdata[WEIGHT_BW*pe_idx +: WEIGHT_BW]),
                .write_address      (pt_ddb_wr[pe_idx]),
                .read_address       (pt_ddb_rd[pe_idx]),
                .output_word        (bram_ddb_out[pe_idx])
            );

            // rf_2p_hde_hvt_rvt_264x16m4 #(
            // ) BRAM_DDB (
            //     .CLKA       (gclk),
            //     .CENA       (!(en_ddb_rd[pe_idx] || en_ddb_rrd[pe_idx])),
            //     .AA         (pt_ddb_rd[pe_idx]),
            //     .QA         (bram_ddb_out[pe_idx]),
            //     .CLKB       (gclk),
            //     .CENB       (!en_ddb_wr[pe_idx]),
            //     .AB         (pt_ddb_wr[pe_idx]),
            //     .DB         (tdata[WEIGHT_BW*pe_idx +: WEIGHT_BW]),
            //     .EMAA       (3'b000),
            //     .EMAB       (3'b000),
            //     .RET1N      (1'b1),
            //     .COLLDISN   (1'b1)
            // );
        
        end

    endgenerate

    logic [BRAM_DDB_BW-1:0] bram_ddb_out_reg [NUM_PE-1:0];
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            if ((!rstn) || (!rstn_ddb)) begin
                bram_ddb_out_reg[pe_idx] <= '0;
            end else if (regce_ddb[pe_idx]) begin
                bram_ddb_out_reg[pe_idx] <= bram_ddb_out[pe_idx];
            end
        end
    end

    always_comb begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            ddb_out[pe_idx][BRAM_DDB_BW-1:0] = bram_ddb_out_reg[pe_idx][BRAM_DDB_BW-1:0];
        end
    end

    // DDB_MUX0 - broadcast channel
    always_comb begin
        case (state) inside
            S_FP, S_BPdZ, S_BPdA, S_PU: begin
                ddb_sel0_p = '0;
            end
            S_BPdW : begin
                // ddb_sel0_p = cnt_n1[$clog2(NUM_PE)-1:0];
                if (cnt_n1 < cfg_n1) begin
                    ddb_sel0_p = cnt_n1[$clog2(NUM_PE)-1:0];
                end else begin                  // BPdW, qnt_act(1) * dZ
                    ddb_sel0_p = NUM_PE;
                end
            end
            default : begin
                ddb_sel0_p = '0;
            end
        endcase
    end
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            ddb_sel0_pr <= '{2{'0}};
        end else if ((|f_O[0:2]) && !f_ddb_empty_eff_any_r[0] && ready_i) begin
        // end else if ((|f_O[0:1+NUM_PE]) && !f_ddb_empty_eff_any && ready_i) begin
        // end else if (valid_o_pr[0] && ready_i) begin                // Broadcast not used in Cascade Mode
            ddb_sel0_pr[0] <= ddb_sel0_p;
            ddb_sel0_pr[1] <= ddb_sel0_pr[0];
        end
    end
    assign ddb_sel0 = ddb_sel0_pr[1];
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            ddb_out_r <= '{NUM_PE{'0}};
        // end else if (valid_o_pr[1] && ready_i) begin
        end else if ((|valid_o_pr[1:NUM_PE]) && ready_i) begin
            ddb_out_r <= ddb_out;
        end
    end
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            ddb_mux0_out <= '0;
        end else if (valid_o_pr[1] && ready_i) begin
        // end else if ((|valid_o_pr[1:NUM_PE]) && ready_i) begin  // Broadcast not used in Cascade Mode
            case (ddb_sel0) inside
                [0 : NUM_PE-1]  : ddb_mux0_out <= ddb_out[ddb_sel0];
                (NUM_PE)        : ddb_mux0_out <= $signed(1) <<< ACT_QN;    // BPdW, qnt_act(1) * dZ
                default         : ddb_mux0_out <= $signed(1) <<< ACT_QN;
            endcase
        end
    end
    
    // DDB_MUX1 - cast type
    always_comb begin
        case (state) inside
            S_FP, S_BPdZ, S_BPdA, S_PU : begin
                ddb_sel1_p = 1'b0;              // Unicast
            end
            S_BPdW : begin
                ddb_sel1_p = 1'b1;              // Broadcast
            end
            default : begin
                ddb_sel1_p = 1'b0;
            end
        endcase
    end
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            ddb_sel1_pr <= '{3{1'b0}};
        // end else if ((|f_O[0:3]) && !f_ddb_empty_eff_any && ready_i) begin
        end else if ((|f_O[0:2+NUM_PE]) && !f_ddb_empty_eff_any_r[1] && ready_i) begin
        // end else if ((|valid_o_pr[0:NUM_PE]) && ready_i) begin
            ddb_sel1_pr[0] <= ddb_sel1_p;
            ddb_sel1_pr[1] <= ddb_sel1_pr[0];
            ddb_sel1_pr[2] <= ddb_sel1_pr[1];
        end
    end
    assign ddb_sel1 = ddb_sel1_pr[2];
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            ddb_mux1_out <= '{NUM_PE{'0}};
        // end else if (valid_o_pr[2] && ready_i) begin
        end else if ((|valid_o_pr[2:1+NUM_PE]) && ready_i) begin
            case (ddb_sel1)
                1'b0: ddb_mux1_out <= ddb_out_r;
                1'b1: ddb_mux1_out <= '{NUM_PE{ddb_mux0_out}};
            endcase
        end
    end
    
    assign dout_weight = ddb_mux1_out;
    
    
    
    // BRAM_IDB - control signals
    assign rstn_idb = !(state == S_CFG);
    // assign en_idb_wr = '{NUM_PE{1'b0}};
    
    always_comb begin
        case (state)
            S_A0 : begin    // A[0]
                // addr_idb = '{NUM_PE{ADDR_IDB_A | cnt_ddi}};
                addr_idb = '{NUM_PE{ADDR_IDB_A | cnt_ddi}}; // ($clog2(MAX_M) - $clog2(cfg_m))
            end
            S_FP : begin    // A[l-1]
                addr_idb = '{NUM_PE{'0}};
                // addr_idb[cnt_n1[$clog2(NUM_PE)-1:0]] = ADDR_IDB_A | {cnt_n1 >> $clog2(NUM_PE), cnt_m};
                addr_idb[cnt_n1[$clog2(NUM_PE)-1:0]] = ADDR_IDB_A | {cnt_n1 >> $clog2(NUM_PE)};
            end
            S_BPdZ : begin  // dA[l]
                // addr_idb = '{NUM_PE{ADDR_IDB_dA | {cnt_n2op, cnt_m}}};
                addr_idb = '{NUM_PE{ADDR_IDB_dA | {cnt_n2op}}};
            end
            S_BPdA : begin  // dZ[l]
                addr_idb = addr_idb_cm;
            end
            S_BPdW : begin  // dZ[l]
                // addr_idb = '{NUM_PE{ADDR_IDB_dZ | {cnt_n2op, cnt_m}}};
                addr_idb = '{NUM_PE{ADDR_IDB_dZ | {cnt_n2op}}};
            end
            S_PU : begin    // 1 or -η
                addr_idb = '{NUM_PE{'0}};
            end
            default : begin 
                addr_idb = '{NUM_PE{'0}};
            end
        endcase
    end
    
    // assign addr_idb_cm[0] = {ADDR_IDB_dZ | {cnt_n2op, cnt_m}};
    assign addr_idb_cm[0] = {ADDR_IDB_dZ | {cnt_n2op}};
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 1; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                addr_idb_cm[pe_idx] <= '0;
            // end else if ((|f_O[pe_idx-1:pe_idx]) && !f_ddb_empty_eff_any && ready_i) begin
            // end else if ((|f_O[0:4]) && !f_ddb_empty_eff_any && ready_i) begin
            end else if ((|f_O[0:3+NUM_PE]) && !f_ddb_empty_eff_any && ready_i) begin
                addr_idb_cm[pe_idx] <= addr_idb_cm[pe_idx-1];
            end
        end
    end
    
    always_comb begin
        case (state) inside
            S_A0 : begin
                regce_idb_p = '{NUM_PE{'0}};
                regce_idb = '{NUM_PE{'0}};
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    en_idb_wr[pe_idx] = f_I && tvalid;
                    en_idb_rd[pe_idx] = f_I && tvalid;
                end
            end
            S_FP : begin
                en_idb_wr = '{NUM_PE{'0}};
                en_idb_rd = '{NUM_PE{'0}};
                regce_idb_p = '{NUM_PE{'0}};
                // regce_idb = '{NUM_PE{'0}};
                en_idb_rd[cnt_n1[$clog2(NUM_PE)-1:0]] = f_O[0] && !f_ddb_empty_eff[cnt_n1[$clog2(NUM_PE)-1:0]] && ready_i;
                regce_idb_p[cnt_n1[$clog2(NUM_PE)-1:0]] = f_O[0];
                // regce_idb[cnt_n1[$clog2(NUM_PE)-1:0]] = (|f_O[0:1]) && regce_idb_pr[cnt_n1[$clog2(NUM_PE)-1:0]] && !f_ddb_empty_eff_any_r[0] && ready_i;
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    regce_idb[pe_idx] = (|f_O[0:1]) && regce_idb_pr[pe_idx] && !f_ddb_empty_eff_any_r[0] && ready_i;
                end
            end
            S_BPdZ : begin
                en_idb_wr = '{NUM_PE{'0}};
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    en_idb_rd[pe_idx] = f_O[0] && !f_ddb_empty_eff[pe_idx] && ready_i;
                    // regce_idb_p[pe_idx] = f_O[0] && !f_idb_empty_eff[pe_idx];
                    // regce_idb[pe_idx] = (|f_O[0:1]) && regce_idb_pr[pe_idx] && ready_i;
                    regce_idb_p[pe_idx] = f_O[0];
                    regce_idb[pe_idx] = (|f_O[0:1]) && regce_idb_pr[pe_idx] && !f_ddb_empty_eff_any_r[0] && ready_i;
                end
            end
            S_BPdA : begin
                en_idb_wr = '{NUM_PE{'0}};
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    // f_O[-1+pe_idx] &&        // NUM_PE
                    en_idb_rd[pe_idx] = en_idb_rd_cm[pe_idx] && !f_ddb_empty_eff_any && ready_i;
                    // Unused
                    regce_idb_p[pe_idx] = f_O[0] && !f_ddb_empty_eff_any;
                    // (|f_O[0:pe_idx]) &&   // NUM_PE
                    regce_idb[pe_idx] = regce_idb_cm[pe_idx] && !f_ddb_empty_eff_any_r[0] && ready_i;
                end
            end
            S_BPdW : begin
                en_idb_wr = '{NUM_PE{'0}};
                for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                    en_idb_rd[pe_idx] = f_O[0] && !f_ddb_empty_eff_any && ready_i;
                    regce_idb_p[pe_idx] = f_O[0];
                    regce_idb[pe_idx] = (|f_O[0:1]) && regce_idb_pr[pe_idx] && !f_ddb_empty_eff_any_r[0] && ready_i;
                end
            end
            S_PU : begin
                en_idb_wr = '{NUM_PE{'0}};
                en_idb_rd = '{NUM_PE{'0}};
                regce_idb_p = '{NUM_PE{'0}};
                regce_idb = '{NUM_PE{'0}};
            end
            default : begin
                en_idb_wr = '{NUM_PE{'0}};
                en_idb_rd = '{NUM_PE{'0}};
                regce_idb_p = '{NUM_PE{'0}};
                regce_idb = '{NUM_PE{'0}};
            end
        endcase
    end
    
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                regce_idb_pr[pe_idx] <= '0;
            // end else if ((|f_O[0:1]) && ready_i) begin
            end else if ((|f_O[0:1]) && !f_ddb_empty_eff_any && ready_i) begin
                regce_idb_pr[pe_idx] <= regce_idb_p[pe_idx];
            end
        end
    end
    
    assign en_idb_rd_cm[0] = f_O[0];
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 1; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                en_idb_rd_cm[pe_idx] <= '0;
            // end else if ((|f_O[pe_idx-1:pe_idx]) && !f_ddb_empty_eff_any && ready_i) begin
            // end else if ((|f_O[0:4]) && !f_ddb_empty_eff_any && ready_i) begin
            end else if ((|f_O[0:3+NUM_PE]) && !f_ddb_empty_eff_any && ready_i) begin
                en_idb_rd_cm[pe_idx] <= en_idb_rd_cm[pe_idx-1];
            end
        end
    end
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            regce_idb_cm[0] <= '0;
        end else if ((|f_O[0:1]) && !f_ddb_empty_eff_any && ready_i) begin  // NUM_PE
            regce_idb_cm[0] <= f_O[0];
        end
    end
    always_ff @(posedge clk) begin
        for (int unsigned pe_idx = 1; pe_idx < NUM_PE; pe_idx++) begin
            if (!rstn || !rstn_CFG) begin
                regce_idb_cm[pe_idx] <= '0;
            // end else if ((|f_O[pe_idx:pe_idx+1]) && !f_ddb_empty_eff_any && ready_i) begin
            // end else if ((|f_O[0:4]) && !f_ddb_empty_eff_any && ready_i) begin
            end else if ((|f_O[1:3+NUM_PE]) && !f_ddb_empty_eff_any && ready_i) begin
                regce_idb_cm[pe_idx] <= regce_idb_cm[pe_idx-1];
            end
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
    //             .addra(addr_idb[pe_idx]),
    //             .addrb(),
    //             .dina(tdata[ACT_BW*pe_idx +: ACT_BW]),
    //             .dinb(),
    //             .clka(clk),
    //             .wea(en_idb_wr[pe_idx]),
    //             .web(),
    //             .ena(en_idb_rd[pe_idx]),
    //             .enb(),
    //             .rsta((!rstn) || (!rstn_idb)),
    //             .rstb(),
    //             .regcea(regce_idb[pe_idx]),
    //             .regceb(),
    //             .douta(idb_out[pe_idx]),
    //             .doutb()
    //         );
    //     end
    // endgenerate
    
    // IDB_MUX0 - broadcast channel
    always_comb begin
        case (state) inside
            S_FP : begin
                if (cnt_n1 < cfg_n1) begin
                    idb_sel0_p = cnt_n1[$clog2(NUM_PE)-1:0];
                end else begin                  // FP, qnt_act(1) * b
                    idb_sel0_p = NUM_PE;
                end
            end
            S_BPdZ, S_BPdA, S_BPdW : begin
                idb_sel0_p = '0;
            end
            S_PU : begin
                if (param_sel == 1'b0) begin    // PU, qnt_weight(1) * W
                    idb_sel0_p = NUM_PE + 1;
                end else begin                  // PU, qnt_weight(-η) * dW
                    idb_sel0_p = NUM_PE + 2;
                end
            end
            default : begin
                idb_sel0_p = '0;
            end
        endcase
    end
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            idb_sel0_pr <= '{2{'0}};
        end else if ((|f_O[0:2]) && !f_ddb_empty_eff_any_r[0] && ready_i) begin
        // end else if ((|f_O[0:1+NUM_PE]) && !f_ddb_empty_eff_any && ready_i) begin
        // end else if (valid_o_pr[0] && ready_i) begin                // Broadcast not used in Cascade Mode
            idb_sel0_pr[0] <= idb_sel0_p;
            idb_sel0_pr[1] <= idb_sel0_pr[0];
        end
    end
    assign idb_sel0 = idb_sel0_pr[1];
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            idb_out_r <= '{NUM_PE{'0}};
        // end else if (valid_o_pr[1] && ready_i) begin
        end else if ((|valid_o_pr[1:NUM_PE]) && ready_i) begin
            idb_out_r <= idb_out;
        end
    end
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            idb_mux0_out <= '0;
        end else if (valid_o_pr[1] && ready_i) begin
        // end else if ((|valid_o_pr[1:NUM_PE]) && ready_i) begin  // Broadcast not used in Cascade Mode
            case (idb_sel0) inside
                [0 : NUM_PE-1]  : idb_mux0_out <= idb_out[idb_sel0];
                (NUM_PE    )    : idb_mux0_out <= $signed(1) <<< ACT_QN;    // FP, qnt_act(1) * b
                (NUM_PE + 1)    : idb_mux0_out <= $signed(1) <<< WEIGHT_QN; // PU, qnt_weight(1) * W
                (NUM_PE + 2)    : idb_mux0_out <= $signed(-164);            // PU, qnt_weight(-η) * dW
                default         : idb_mux0_out <= $signed(1) <<< ACT_QN;
            endcase
        end
    end
    
    // IDB_MUX1 - cast type
    always_comb begin
        case (state) inside
            S_FP, S_PU : begin
                idb_sel1_p = 1'b1;              // Broadcast
            end
            S_BPdZ, S_BPdA, S_BPdW : begin
                idb_sel1_p = 1'b0;              // Unicast
            end
            default : begin
                idb_sel1_p = 1'b0;
            end
        endcase
    end
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            idb_sel1_pr <= '{3{1'b0}};
        // end else if ((|f_O[0:3]) && !f_ddb_empty_eff_any && ready_i) begin
        end else if ((|f_O[0:2+NUM_PE]) && !f_ddb_empty_eff_any_r[1] && ready_i) begin
        // end else if ((|valid_o_pr[0:NUM_PE]) && ready_i) begin
            idb_sel1_pr[0] <= idb_sel1_p;
            idb_sel1_pr[1] <= idb_sel1_pr[0];
            idb_sel1_pr[2] <= idb_sel1_pr[1];
        end
    end
    assign idb_sel1 = idb_sel1_pr[2];
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            idb_mux1_out <= '{NUM_PE{'0}};
        // end else if (valid_o_pr[2] && ready_i) begin
        end else if ((|valid_o_pr[2:1+NUM_PE]) && ready_i) begin
            case (idb_sel1)
                1'b0: idb_mux1_out <= idb_out_r;
                1'b1: idb_mux1_out <= '{NUM_PE{idb_mux0_out}};
            endcase
        end
    end
    
    assign dout_act = idb_mux1_out;
    
    
    
endmodule



module PREICG_X16B_A7TSL_C30 (
    input logic CK,
    input logic E,
    input logic SE,
    output logic ECK
);
    logic E_lo;

    always_latch begin
        if (~CK) begin
            E_lo = E || SE;
        end
    end

    assign ECK = E_lo && CK;

endmodule
