
import definesPkg::*;

`define ROUND_FLOOR

module CCM #(
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
    parameter NUM_ACT_FUNC = 2,
    parameter BRAM_MAC_DEPTH = MAX_M*MAX_NoP,   //2048
    parameter BRAM_ACC_DEPTH = MAX_M,           //32
    localparam WEIGHT_BW = WEIGHT_QM + WEIGHT_QN,
    localparam ACT_BW    = ACT_QM + ACT_QN,
    localparam ACC_BW    = ACC_QM + ACC_QN,
    localparam MAX_CNT_RR = (MAX_M>MAX_NoP)? (MAX_M*MAX_N):(MAX_NoP*MAX_N)
) (
    input logic         clk,
    input logic         rstn,
    input logic         ready_i,
    input logic         valid_i,
    
    // stage, m*(n2/P), n1
    input logic         cfg_start,
    input stage_t                               cfg_stage,
    input logic [$clog2(NUM_ACT_FUNC)-1:0]      cfg_act_func,
    input logic [$clog2(BRAM_MAC_DEPTH)-1:0]    cfg_cnt_ba,
    input logic [$clog2(MAX_N)-1:0]             cfg_cnt_ar,
    input logic [$clog2(MAX_CNT_RR)-1:0]        cfg_cnt_rr,
    
    input logic signed[ACT_BW-1:0]              din_act[NUM_PE-1:0],
    input logic signed[WEIGHT_BW-1:0]           din_weight[NUM_PE-1:0],
    
    output logic        valid_o,
    output logic        ready_o,
    output logic signed[ACT_BW-1:0]             dout_act[NUM_PE:0]      // acc
);

    // Overall - control signals
    logic                                   rstn_CFG;
    
    // Overall - flags
    logic [0:5]                             f_I;
    logic [0:5]                             f_O;
    logic [0:NUM_PE]                        f_I_MACC;
    logic [0:5]                             f_I_ACC;
    logic [0:5]                             f_O_ACC;
    
    // Input Signal
    logic                                   ready_i_eff;
    logic [0:5]                             valid_i_r;
    logic [0:NUM_PE]                        valid_i_macc;
    logic [0:5]                             valid_i_acc_r;

    // Output Signal
    logic [0:5]                             valid_o_pr;
    logic [0:5]                             valid_o_acc_pr;
    
    // FSM - states
    // (* mark_debug = "true" *)
    enum logic [3:0] {  S_NCFG, S_CFG,
                        S_FP,
                        S_BPdZ,
                        S_BPdA,
                        S_BPdW,
                        S_PU} state;
    
    // PE - control signal
    logic                                   rstn_PE;
    logic [0:4]                             en_mac_i0;
    logic [0:4]                             en_mac_i1;
    logic [0:4]                             en_mac_o0;
    logic [0:4]                             en_mac_o1;
    logic [0:4]                             en_acc_i0;
    logic [0:4]                             en_acc_i1;
    logic [0:4]                             en_acc_o0;
    logic [0:4]                             en_acc_o1;
    
    // PE - input data registers
    logic signed[ACT_BW-1:0]                din_act_r[NUM_PE-1:0];
    logic signed[WEIGHT_BW-1:0]             din_weight_r[NUM_PE-1:0];

    // PE - accumulating results
    logic signed[ACC_BW-1:0]                pe_din_acc[NUM_PE:0];  // acc
    logic signed[ACC_BW-1:0]                pe_dout_acc[NUM_PE:0]; // acc
    
    // PE - mux selections
    logic [1:0] mac_sel;
    logic [1:0] mac_sel_pr[0:2];
    logic [1:0] acc_sel;
    logic [1:0] acc_sel_pr[0:2];
    
    // BRAM_MAC - data/address counters
    logic [$clog2(BRAM_MAC_DEPTH)-1:0]      cnt_mac_br;
    logic [$clog2(BRAM_MAC_DEPTH)-1:0]      cnt_mac_bw;
    logic [$clog2(MAX_N)-1:0]               cnt_mac_ar;
    logic [$clog2(MAX_CNT_RR)-1:0]          cnt_mac_rr;
    logic                                   f_cnt_mac;
    logic [0:5]                             f_cnt_mac_r;
    logic [0:NUM_PE-1]                      f_cnt_macc;
    
    // BRAM_MAC - control signals
    logic                                   en_mac_rd;
    logic                                   en_mac_wr;
    logic [0:3]                             en_mac_wr_pr;
    logic                                   rstn_mac;
    logic                                   regce_mac;
    logic [0:1]                             regce_mac_pr;
    
    // BRAM_ACC - data/address counters
    logic [$clog2(BRAM_ACC_DEPTH)-1:0]      cnt_acc_br;
    logic [$clog2(BRAM_ACC_DEPTH)-1:0]      cnt_acc_bw;
    logic [$clog2(MAX_N)-1:0]               cnt_acc_ar;
    logic [$clog2(MAX_CNT_RR)-1:0]          cnt_acc_rr;
    logic                                   f_cnt_acc;
    logic [0:5]                             f_cnt_acc_r;
    
    // BRAM_ACC - control signals
    logic                                   en_acc_rd;
    logic                                   en_acc_wr;
    logic [0:3]                             en_acc_wr_pr;
    logic                                   rstn_acc;
    logic                                   regce_acc;
    logic [0:1]                             regce_acc_pr;
    
    // Quantization Output, Mux
    logic signed[ACC_BW-1:0]                mac_qnt_act_in[NUM_PE-1:0];
    logic signed[ACC_BW-1:0]                mac_qnt_weight_in[NUM_PE-1:0];
    logic signed[ACT_BW-1:0]                mac_qnt_act_out[NUM_PE-1:0];
    logic signed[WEIGHT_BW-1:0]             mac_qnt_weight_out[NUM_PE-1:0];
    logic signed[ACT_BW-1:0]                mac_qnt_out[NUM_PE-1:0];
    logic signed[ACT_BW-1:0]                mac_qnt_out_r[NUM_PE-1:0];
    logic                                   mac_qnt_sel;                // 2 entries
    logic                                   mac_qnt_sel_pr[0:3];
    logic signed[ACC_BW-1:0]                acc_qnt_act_in;
    logic signed[ACC_BW-1:0]                acc_qnt_weight_in;
    logic signed[ACT_BW-1:0]                acc_qnt_act_out;
    logic signed[WEIGHT_BW-1:0]             acc_qnt_weight_out;
    logic signed[ACT_BW-1:0]                acc_qnt_out;
    logic signed[ACT_BW-1:0]                acc_qnt_out_r;
    logic                                   acc_qnt_sel;                // 2 entries
    logic                                   acc_qnt_sel_pr[0:3];
    
    // Activation Function Output, Mux
    logic signed[ACT_BW-1:0]                mac_act_out[NUM_PE-1:0];
    logic signed[ACT_BW-1:0]                mac_act_out_r[NUM_PE-1:0];
    logic [$clog2(NUM_ACT_FUNC)-1:0]        mac_act_sel;                // 2 entries
    logic [$clog2(NUM_ACT_FUNC)-1:0]        mac_act_sel_pr[0:4];
    logic signed[ACT_BW-1:0]                acc_act_out;
    logic signed[ACT_BW-1:0]                acc_act_out_r;
    logic                                   acc_act_sel;                // 2 entries
    logic                                   acc_act_sel_pr[0:4];

    
    
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
                // Backward Prop - dZ, dW
                // Parameter Update
                S_FP, S_BPdZ, S_BPdW, S_PU : begin
                    if (f_cnt_mac_r[5] && valid_i_r[5] && ready_i_eff) begin
                        state <= S_NCFG;
                    end
                end
                
                // Backward Prop - dA
                S_BPdA : begin
                    if (f_cnt_acc_r[5] && valid_i_acc_r[5] && ready_i_eff) begin
                        state <= S_NCFG;
                    end
                end

                default : begin
                    state <= S_NCFG;
                end

            endcase
        end
    end
    


    // Control Signals
    
    // assign ready_i_eff = ready_i;
    // assign ready_i_eff = ready_i || !f_O[5];
    always_comb begin
        case (state) inside
            S_FP, S_BPdZ, S_BPdW, S_PU : begin
                ready_i_eff = ready_i || !f_O[5];
            end
            S_BPdA : begin
                ready_i_eff = ready_i || !f_O_ACC[5];
            end
            default : begin
                ready_i_eff = ready_i || !f_O[5];
                // ready_i_eff = 1'b0;
            end
        endcase
    end
    
    // assign valid_i_r[0] = valid_i;
    assign valid_i_r[0] = valid_i && f_I[0];
    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 5; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                valid_i_r[ps_idx] <= 1'b0;
            end else if ((f_I[ps_idx-1] || f_I[ps_idx]) && ready_i_eff) begin
                valid_i_r[ps_idx] <= valid_i_r[ps_idx-1];
            end
        end
    end

    // assign valid_i_macc[0] = valid_i;
    // assign valid_i_macc[0] = valid_i && f_I[0];
    // always_ff @(posedge clk) begin
    //     for (int unsigned ps_idx = 1; ps_idx <= NUM_PE; ps_idx++) begin
    //         if (!rstn || !rstn_CFG) begin
    //             valid_i_macc[ps_idx] <= 1'b0;
    //         end else if ((f_I_MACC[ps_idx-1] || f_I_MACC[ps_idx]) && ready_i_eff) begin
    //             valid_i_macc[ps_idx] <= valid_i_macc[ps_idx-1];
    //         end
    //     end
    // end
    always_comb begin
        for (int unsigned ps_idx = 0; ps_idx <= NUM_PE-1; ps_idx++) begin
            // valid_i_macc[ps_idx] = valid_i & f_I_MACC[ps_idx];
            valid_i_macc[ps_idx] = valid_i & f_I[0];    // enable_stage_0
        end
    end
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            valid_i_macc[NUM_PE] <= 1'b0;
        end else if ((f_I_MACC[NUM_PE-1] || f_I_MACC[NUM_PE]) && ready_i_eff) begin
            valid_i_macc[NUM_PE] <= valid_i_macc[NUM_PE-1];
        end
    end

    assign valid_i_acc_r[0] = valid_i_macc[NUM_PE];
    // assign valid_i_acc_r[0] = valid_i && f_I_ACC[0] && f_I[0];
    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 5; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                valid_i_acc_r[ps_idx] <= 1'b0;
            end else if ((f_I_ACC[ps_idx-1] || f_I_ACC[ps_idx]) && ready_i_eff) begin
                valid_i_acc_r[ps_idx] <= valid_i_acc_r[ps_idx-1];
            end
        end
    end
    
    always_comb begin
        case (state) inside
            S_FP, S_BPdZ, S_BPdW, S_PU : begin
                ready_o = f_I[0] && ready_i_eff;
            end
            S_BPdA: begin
                ready_o = f_I[0] && ready_i_eff;
            end
            default : begin
                // ready_o = f_I[0] && ready_i_eff;
                ready_o = 1'b0;
            end
        endcase
    end
    
    assign valid_o_pr[0:5] = f_O[0:5] & valid_i_r[0:5];
    assign valid_o_acc_pr[0:5] = f_O_ACC[0:5] & valid_i_acc_r[0:5];
    // assign valid_o = valid_o_pr[5];
    always_comb begin
        case (state) inside
            S_FP, S_BPdZ, S_BPdW, S_PU : begin
                valid_o = valid_o_pr[5];
            end
            S_BPdA: begin
                valid_o = valid_o_acc_pr[5];
            end
            default : begin
                // valid_o = valid_o_pr[5];
                valid_o = 1'b0;
            end
        endcase
    end



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
                S_FP, S_BPdZ, S_BPdW, S_PU : begin
                    // Deassert when last input data accepted
                    if (f_cnt_mac && valid_i && ready_i_eff) begin
                        f_I[0] <= 1'b0;
                    end
                end
                S_BPdA: begin
                    // Deassert when last input data accepted (+NUM_PE-1)
                    if (f_cnt_macc[NUM_PE-1] && valid_i && ready_i_eff) begin
                        f_I[0] <= 1'b0;
                    end
                end
                default : begin
                    f_I[0] <= 1'b0;
                end
            endcase
        end
    end
    
    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 5; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                f_I[ps_idx] <= 1'b0;
            end else if (en_mac_i1[ps_idx-1]) begin
                f_I[ps_idx] <= f_I[ps_idx-1];
            end
        end
    end
    
    // assign f_I_MACC[0] = f_I[0];
    assign f_I_MACC[0] = f_I[0] && (state == S_BPdA);
    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= NUM_PE; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                f_I_MACC[ps_idx] <= 1'b0;
            end else if ((f_I_MACC[ps_idx-1] || f_I_MACC[ps_idx]) && valid_i_macc[ps_idx-1] && ready_i_eff) begin
            // end else if ((f_I_MACC[ps_idx-1] || f_I_MACC[ps_idx]) && valid_i && ready_i_eff) begin
                f_I_MACC[ps_idx] <= f_I_MACC[ps_idx-1];
            end
        end
    end

    assign f_I_ACC[0] = f_I_MACC[NUM_PE];
    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 5; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                f_I_ACC[ps_idx] <= 1'b0;
            end else if (en_acc_i1[ps_idx-1]) begin
                f_I_ACC[ps_idx] <= f_I_ACC[ps_idx-1];
            end
        end
    end

    always_comb begin
        case (state) inside
            S_FP, S_BPdZ, S_BPdW, S_PU : begin
                f_O[0] = (cnt_mac_ar == cfg_cnt_ar); // && f_I[0];
            end
            // S_BPdA : begin                              // For ready_i_eff?
            //     f_O[0] = (cnt_acc_ar == cfg_cnt_ar); // && f_I_ACC[0];
            // end
            default : begin
                f_O[0] = 1'b0;
            end
        endcase
    end
    
    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 5; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                f_O[ps_idx] <= 1'b0;
            end else if (en_mac_o1[ps_idx-1]) begin
                f_O[ps_idx] <= f_O[ps_idx-1];
            end
        end
    end
    
    always_comb begin
        case (state) inside
            S_BPdA : begin
                f_O_ACC[0] = (cnt_acc_ar == cfg_cnt_ar); // && f_I_ACC[0];
            end
            default : begin
                f_O_ACC[0] = 1'b0;
            end
        endcase
    end
    
    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 5; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                f_O_ACC[ps_idx] <= 1'b0;
            end else if (en_acc_o1[ps_idx-1]) begin
                f_O_ACC[ps_idx] <= f_O_ACC[ps_idx-1];
            end
        end
    end
    
    
    
    // PE Control Signals
    assign rstn_PE = !(state == S_CFG);
    
    always_comb begin
        for (int unsigned ps_idx = 0; ps_idx <= 4; ps_idx++) begin
            // MAC Enables
            en_mac_i0[ps_idx] = f_I[ps_idx] && valid_i_r[ps_idx] && ready_i_eff;
            en_mac_i1[ps_idx] = (f_I[ps_idx] || f_I[ps_idx+1]) && valid_i_r[ps_idx] && ready_i_eff;
            en_mac_o0[ps_idx] = f_O[ps_idx] && valid_i_r[ps_idx] && ready_i_eff;
            en_mac_o1[ps_idx] = (f_O[ps_idx] || f_O[ps_idx+1]) && valid_i_r[ps_idx] && ready_i_eff;
            // ACC Enables
            en_acc_i0[ps_idx] = f_I_ACC[ps_idx] && valid_i_acc_r[ps_idx] && ready_i_eff;
            en_acc_i1[ps_idx] = (f_I_ACC[ps_idx] || f_I_ACC[ps_idx+1]) && valid_i_acc_r[ps_idx] && ready_i_eff;
            en_acc_o0[ps_idx] = f_O_ACC[ps_idx] && valid_i_acc_r[ps_idx] && ready_i_eff;
            en_acc_o1[ps_idx] = (f_O_ACC[ps_idx] || f_O_ACC[ps_idx+1]) && valid_i_acc_r[ps_idx] && ready_i_eff;
        end
    end



    // BRAM_MAC Counters - BRAM Address, Accumulation Round, Repetition Round
    always_ff @(posedge clk) begin
        if ((!rstn) || (!rstn_CFG)) begin
            cnt_mac_br <= 0;
            cnt_mac_ar <= 0;
            cnt_mac_rr <= 0;
        end else if (en_mac_i0[0]) begin
            if (cnt_mac_br == cfg_cnt_ba) begin
                cnt_mac_br <= 0;
                if (cnt_mac_ar == cfg_cnt_ar) begin
                    cnt_mac_ar <= 0;
                    if (cnt_mac_rr == cfg_cnt_rr) begin
                        cnt_mac_rr <= 0;
                    end else begin
                        cnt_mac_rr <= cnt_mac_rr + 1;
                    end
                end else begin
                    cnt_mac_ar <= cnt_mac_ar + 1;
                end
            end else begin
                cnt_mac_br <= cnt_mac_br + 1;
            end
        end
    end
    
    assign f_cnt_mac = (cnt_mac_rr == cfg_cnt_rr) && (cnt_mac_ar == cfg_cnt_ar) && (cnt_mac_br == cfg_cnt_ba);
    
    assign f_cnt_mac_r[0] = f_cnt_mac;
    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 5; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                f_cnt_mac_r[ps_idx] <= 1'b0;
            end else if (en_mac_i1[ps_idx-1]) begin
                f_cnt_mac_r[ps_idx] <= f_cnt_mac_r[ps_idx-1];
            end
        end
    end
    
    assign f_cnt_macc[0] = f_cnt_mac;
    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= NUM_PE-1; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                f_cnt_macc[ps_idx] <= 1'b0;
            end else if (en_mac_i1[0]) begin    // enable_stage_0
                f_cnt_macc[ps_idx] <= f_cnt_macc[ps_idx-1];
            end
        end
    end
    
    always_ff @(posedge clk) begin
        if ((!rstn) || (!rstn_CFG)) begin
            cnt_mac_bw <= 0;
        end else if (en_mac_i0[3]) begin
            if (cnt_mac_bw == cfg_cnt_ba) begin
                cnt_mac_bw <= 0;
            end else begin
                cnt_mac_bw <= cnt_mac_bw + 1;
            end
        end
    end

    
    
    // BRAM_MAC - control signals
    assign rstn_mac = !(state == S_CFG);
    
    always_comb begin
        case (state) inside
            S_FP, S_PU : begin
                en_mac_rd = f_I[0] && (cnt_mac_ar > 0) && valid_i && ready_i_eff;
                regce_mac_pr[0] = f_I[0] && (cnt_mac_ar > 0);
                en_mac_wr_pr[0] = f_I[0] && (cnt_mac_ar < cfg_cnt_ar);
                regce_mac = f_I[1] && regce_mac_pr[1] && valid_i_r[1] && ready_i_eff;
                en_mac_wr = f_I[3] && en_mac_wr_pr[3] && valid_i_r[3] && ready_i_eff;
            end
            default : begin
                en_mac_rd = 1'b0;
                regce_mac_pr[0] = 1'b0;
                en_mac_wr_pr[0] = 1'b0;
                regce_mac = f_I[1] && regce_mac_pr[1] && valid_i_r[1] && ready_i_eff;
                en_mac_wr = f_I[3] && en_mac_wr_pr[3] && valid_i_r[3] && ready_i_eff;
            end
        endcase
    end
    
    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 3; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                en_mac_wr_pr[ps_idx] <= '0;
            end else if (en_mac_i0[ps_idx-1]) begin
                en_mac_wr_pr[ps_idx] <= en_mac_wr_pr[ps_idx-1];
            end
        end
    end
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            regce_mac_pr[1] <= '0;
        end else if (en_mac_i0[0]) begin
            regce_mac_pr[1] <= regce_mac_pr[0];
        end
    end
    
    // BRAM_MAC
    generate
        for (genvar pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            // (* ram_style = "block" *)
            BRAM_SDP_1C #(
                .RAM_WIDTH(ACC_BW),
                .RAM_DEPTH(BRAM_MAC_DEPTH),
                .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
                .INIT_FILE("")
            ) BRAM_MAC (
                .addra  (cnt_mac_bw),
                .addrb  (cnt_mac_br),
                .dina   (pe_dout_acc[pe_idx]),
                .clka   (clk),
                .wea    (en_mac_wr),
                .enb    (en_mac_rd),
                .rstb   (!rstn || !rstn_mac),
                .regceb (regce_mac),
                .doutb  (pe_din_acc[pe_idx])
            );
        end
    endgenerate
    
    // logic [ACC_BW-1:0] bram_mac_out [NUM_PE-1:0];

    // npp_std_if bram_mac_clk();
    // assign bram_mac_clk.clk = clk;
    // assign bram_mac_clk.resetn = rstn;

    // generate
    //     for (genvar pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         npp_memory_2p #(
    //             .WORD_NUM_BITS      (ACC_BW),
    //             .NUM_ENTRIES        (BRAM_MAC_DEPTH)
    //         ) BRAM_MAC (
    //             .npp_std_write      (bram_mac_clk.slave),
    //             .npp_std_read       (bram_mac_clk.slave),
    //             .write_chip_enable  (!en_mac_wr),
    //             .read_chip_enable   (!en_mac_rd),
    //             .input_word         (pe_dout_acc[pe_idx]),
    //             .write_address      (cnt_mac_bw),
    //             .read_address       (cnt_mac_br),
    //             .output_word        (bram_mac_out[pe_idx])
    //         );
    //     end
    // endgenerate

    // logic [ACC_BW-1:0] bram_mac_out_reg [NUM_PE-1:0];
    // always_ff @(posedge clk) begin
    //     if (!rstn || !rstn_mac) begin
    //         bram_mac_out_reg <= '{NUM_PE{'0}};
    //     end else if (regce_mac) begin
    //         bram_mac_out_reg <= bram_mac_out;
    //     end
    // end

    // always_comb begin
    //     for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         pe_din_acc[pe_idx][ACC_BW-1:0] = bram_mac_out_reg[pe_idx][ACC_BW-1:0];
    //     end
    // end



    // MAC_MUX
    always_comb begin
        case (state)
            S_FP : begin
                if (cnt_mac_ar == 0) begin
                    mac_sel_pr[0] = 2'b00;
                end else if (cfg_cnt_ba > 0) begin
                    mac_sel_pr[0] = 2'b01;
                end else begin
                    mac_sel_pr[0] = 2'b10;
                end
            end
            S_BPdZ : begin
                mac_sel_pr[0] = 2'b00;
            end
            S_BPdA : begin
                if (f_I[0]) begin    // ???
                    mac_sel_pr[0] = 2'b11;
                end else begin
                    mac_sel_pr[0] = 2'b00;
                end
            end
            S_BPdW : begin
                if (cnt_mac_ar == 0) begin
                    mac_sel_pr[0] = 2'b00;
                end else begin
                    mac_sel_pr[0] = 2'b10;
                end
            end
            S_PU : begin
                if (cnt_mac_ar == 0) begin
                    mac_sel_pr[0] = 2'b00;
                end else if (cfg_cnt_ba > 0) begin
                    mac_sel_pr[0] = 2'b01;
                end else begin                      // PU chk_size == 1
                    mac_sel_pr[0] = 2'b10;
                end
            end
            default : begin
                mac_sel_pr[0] = 2'b00;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 2; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                mac_sel_pr[ps_idx] <= '0;
            end else if (en_mac_i0[ps_idx-1]) begin
                mac_sel_pr[ps_idx] <= mac_sel_pr[ps_idx-1];
            end
        end
    end

    assign mac_sel = mac_sel_pr[2];
    
    
    
    // MACC
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_PE) begin
            din_act_r <= '{NUM_PE{'0}};
        end else if (en_mac_i0[0]) begin
            din_act_r <= din_act;
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn || !rstn_PE) begin
            din_weight_r <= '{NUM_PE{'0}};
        end else if (en_mac_i0[0]) begin
            for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
                case (state) inside
                    S_FP, S_BPdA, S_BPdW, S_PU : begin
                        din_weight_r[pe_idx] <= din_weight[pe_idx];
                    end
                    S_BPdZ : begin                                              // ReLU'
                        if (din_weight[pe_idx] > 0) begin
                            din_weight_r[pe_idx] <= $signed(1) <<< WEIGHT_QN;   // qnt_weight(1)
                        end else begin
                            din_weight_r[pe_idx] <= 0;                          // 0
                        end
                    end
                    default : begin
                        din_weight_r[pe_idx] <= din_weight[pe_idx];
                    end
                endcase
            end
        end
    end

    MACC #(
        .NUM_PE     (NUM_PE),
        .WEIGHT_QM  (WEIGHT_QM),
        .WEIGHT_QN  (WEIGHT_QN),
        .ACT_QM     (ACT_QM),
        .ACT_QN     (ACT_QN),
        .ACC_QM     (ACC_QM),
        .ACC_QN     (ACC_QN)
    ) MACC_inst (
        .clk        (clk),
        .en_mul     (en_mac_i0[1]),
        .en_add     (en_mac_i0[2]),
        .en_acc     (en_acc_i0[2]),
        .rstn       (rstn && rstn_PE),
        .mac_sel    (mac_sel),
        .acc_sel    (acc_sel),
        .din_act    (din_act_r),
        .din_weight (din_weight_r),
        .din_acc    (pe_din_acc),
        .dout_acc   (pe_dout_acc)
    );
    

    
    // MAC_QNT_MUX
    always_comb begin
        case (state) inside
            S_FP, S_BPdZ, S_BPdA, S_PU : begin    // Q_ACC -> Q_ACT
                mac_qnt_sel_pr[0] = 1'b0;
            end
            S_BPdW : begin                        // Q_ACC -> Q_WEIGHT
                mac_qnt_sel_pr[0] = 1'b1;
            end
            default : begin
                mac_qnt_sel_pr[0] = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 3; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                mac_qnt_sel_pr[ps_idx] <= '0;
            end else if (en_mac_o0[ps_idx-1]) begin
                mac_qnt_sel_pr[ps_idx] <= mac_qnt_sel_pr[ps_idx-1];
            end
        end
    end
    
    assign mac_qnt_sel = mac_qnt_sel_pr[3];
    
    always_comb begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            // Clip fractional bits
            `ifdef ROUND_FLOOR
                mac_qnt_act_in[pe_idx] = $signed(pe_dout_acc[pe_idx]) >>> WEIGHT_QN;
            `else
                mac_qnt_act_in[pe_idx] = $signed( pe_dout_acc[pe_idx] +
                                                  { {(WEIGHT_QM)   {1'b0}},
                                                    {(ACT_BW)      {1'b0}},
                                                    {(1)           {1'b1}},     // 0.5
                                                    {(WEIGHT_QN-1) {1'b0}}
                                                  }
                                                ) >>> WEIGHT_QN;
            `endif
            // Clip integer bits
            if (mac_qnt_act_in[pe_idx] > 2 ** (ACT_BW-1) - 1) begin
                mac_qnt_act_out[pe_idx] = 2 ** (ACT_BW-1) - 1;
            end else if (mac_qnt_act_in[pe_idx] < - 2 ** (ACT_BW-1)) begin
                mac_qnt_act_out[pe_idx] = - 2 ** (ACT_BW-1);
            end else begin
                mac_qnt_act_out[pe_idx] = mac_qnt_act_in[pe_idx][ACT_BW-1:0];
            end

            // Clip fractional bits
            `ifdef ROUND_FLOOR
                mac_qnt_weight_in[pe_idx] = $signed(pe_dout_acc[pe_idx]) >>> ACT_QN;
            `else
                mac_qnt_weight_in[pe_idx] = $signed( pe_dout_acc[pe_idx] +
                                                     { {(ACT_QM)    {1'b0}},
                                                       {(WEIGHT_BW) {1'b0}},
                                                       {(1)         {1'b1}},    // 0.5
                                                       {(ACT_QN-1)  {1'b0}}
                                                     }
                                                   ) >>> ACT_QN;
            `endif
            // Clip integer bits
            if (mac_qnt_weight_in[pe_idx] > 2 ** (WEIGHT_BW-1) - 1) begin
                mac_qnt_weight_out[pe_idx] = 2 ** (WEIGHT_BW-1) - 1;
            end else if (mac_qnt_weight_in[pe_idx] < - 2 ** (WEIGHT_BW-1)) begin
                mac_qnt_weight_out[pe_idx] = - 2 ** (WEIGHT_BW-1);
            end else begin
                mac_qnt_weight_out[pe_idx] = mac_qnt_weight_in[pe_idx][WEIGHT_BW-1:0];
            end
        end
    end

    always_comb begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            case (mac_qnt_sel)
                1'b0 : begin                            // Q_ACC -> Q_ACT
                    // mac_qnt_out[pe_idx] = pe_dout_acc[pe_idx][ACC_BW-WEIGHT_QM:WEIGHT_QN];
                    mac_qnt_out[pe_idx] = mac_qnt_act_out[pe_idx];
                end
                1'b1 : begin                            // Q_ACC -> Q_WEIGHT
                    // mac_qnt_out[pe_idx] = pe_dout_acc[pe_idx][ACC_BW-ACT_QM:ACT_QN];
                    mac_qnt_out[pe_idx] = mac_qnt_weight_out[pe_idx];
                end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            mac_qnt_out_r <= '{NUM_PE{'0}};
        end else if (en_mac_o0[3]) begin
            mac_qnt_out_r <= mac_qnt_out;
        end
    end
    
    // MAC_ACT_MUX
    always_comb begin
        case (state) inside
            S_FP : begin
                mac_act_sel_pr[0] = cfg_act_func;       // Non / ReLU
            end
            S_BPdZ, S_BPdA, S_BPdW, S_PU : begin        // Non
                mac_act_sel_pr[0] = 1'b0;
            end
            default : begin
                mac_act_sel_pr[0] = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 4; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                mac_act_sel_pr[ps_idx] <= '0;
            end else if (en_mac_o0[ps_idx-1]) begin
                mac_act_sel_pr[ps_idx] <= mac_act_sel_pr[ps_idx-1];
            end
        end
    end
    
    assign mac_act_sel = mac_act_sel_pr[4];
    
    always_comb begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            case (mac_act_sel)
                1'b0 : begin                            // Non
                    mac_act_out[pe_idx] = mac_qnt_out_r[pe_idx];
                end
                1'b1 : begin                            // ReLU
                    if (mac_qnt_out_r[pe_idx] > 0) begin
                        mac_act_out[pe_idx] = mac_qnt_out_r[pe_idx];
                    end else begin
                        mac_act_out[pe_idx] = 0;
                    end
                end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            mac_act_out_r <= '{NUM_PE{'0}};
        end else if (en_mac_o0[4]) begin
           mac_act_out_r <= mac_act_out;
        end
    end
    


    // BRAM_ACC Counters - BRAM Address, Accumulation Round, Repetition Round
    always_ff @(posedge clk) begin
        if ((!rstn) || (!rstn_CFG)) begin
            cnt_acc_br <= 0;
            cnt_acc_ar <= 0;
            cnt_acc_rr <= 0;
        end else if (en_acc_i0[0]) begin
            if (cnt_acc_br == cfg_cnt_ba) begin
                cnt_acc_br <= 0;
                if (cnt_acc_ar == cfg_cnt_ar) begin
                    cnt_acc_ar <= 0;
                    if (cnt_acc_rr == cfg_cnt_rr) begin
                        cnt_acc_rr <= 0;
                    end else begin
                        cnt_acc_rr <= cnt_acc_rr + 1;
                    end
                end else begin
                    cnt_acc_ar <= cnt_acc_ar + 1;
                end
            end else begin
                cnt_acc_br <= cnt_acc_br + 1;
            end
        end
    end
    
    assign f_cnt_acc = (cnt_acc_rr == cfg_cnt_rr) && (cnt_acc_ar == cfg_cnt_ar) && (cnt_acc_br == cfg_cnt_ba);
    
    assign f_cnt_acc_r[0] = f_cnt_acc;
    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 5; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                f_cnt_acc_r[ps_idx] <= 1'b0;
            end else if (en_acc_i1[ps_idx-1]) begin
                f_cnt_acc_r[ps_idx] <= f_cnt_acc_r[ps_idx-1];
            end
        end
    end
    
    always_ff @(posedge clk) begin
        if ((!rstn) || (!rstn_CFG)) begin
            cnt_acc_bw <= 0;
        end else if (en_acc_i0[3]) begin
            if (cnt_acc_bw == cfg_cnt_ba) begin
                cnt_acc_bw <= 0;
            end else begin
                cnt_acc_bw <= cnt_acc_bw + 1;
            end
        end
    end



    // BRAM_ACC - control signals
    assign rstn_acc = !(state == S_CFG);
    
    always_comb begin
        case (state) inside
            S_BPdA : begin
                en_acc_rd = f_I_ACC[0] && (cnt_acc_ar > 0) && valid_i_acc_r[0] && ready_i_eff;
                regce_acc_pr[0] = f_I_ACC[0] && (cnt_acc_ar > 0);
                en_acc_wr_pr[0] = f_I_ACC[0] && (cnt_acc_ar < cfg_cnt_ar);
                regce_acc = f_I_ACC[1] && regce_acc_pr[1] && valid_i_acc_r[1] && ready_i_eff;
                en_acc_wr = f_I_ACC[3] && en_acc_wr_pr[3] && valid_i_acc_r[3] && ready_i_eff;
            end
            default : begin
                en_acc_rd = 1'b0;
                regce_acc_pr[0] = 1'b0;
                en_acc_wr_pr[0] = 1'b0;
                regce_acc = f_I_ACC[1] && regce_acc_pr[1] && valid_i_acc_r[1] && ready_i_eff;
                en_acc_wr = f_I_ACC[3] && en_acc_wr_pr[3] && valid_i_acc_r[3] && ready_i_eff;
            end
        endcase
    end
    
    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 3; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                en_acc_wr_pr[ps_idx] <= '0;
            end else if (en_acc_i0[ps_idx-1]) begin
                en_acc_wr_pr[ps_idx] <= en_acc_wr_pr[ps_idx-1];
            end
        end
    end
    
    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            regce_acc_pr[1] <= '0;
        end else if (en_acc_i0[0]) begin
            regce_acc_pr[1] <= regce_acc_pr[0];
        end
    end
    
    // BRAM_ACC
    generate
        // (* ram_style = "block" *)
        BRAM_SDP_1C #(
            .RAM_WIDTH(ACC_BW),
            .RAM_DEPTH(BRAM_ACC_DEPTH),
            .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
            .INIT_FILE("")
        ) BRAM_ACC (
            .addra  (cnt_acc_bw),
            .addrb  (cnt_acc_br),
            .dina   (pe_dout_acc[NUM_PE]),
            .clka   (clk),
            .wea    (en_acc_wr),
            .enb    (en_acc_rd),
            .rstb   (!rstn || !rstn_acc),
            .regceb (regce_acc),
            .doutb  (pe_din_acc[NUM_PE])
        );
    endgenerate
    
    // logic [ACC_BW-1:0] bram_acc_out;

    // npp_std_if bram_acc_clk();
    // assign bram_acc_clk.clk = clk;
    // assign bram_acc_clk.resetn = rstn;

    // generate
    //     npp_memory_2p #(
    //         .WORD_NUM_BITS      (ACC_BW),
    //         .NUM_ENTRIES        (BRAM_ACC_DEPTH)
    //     ) BRAM_ACC (
    //         .npp_std_write      (bram_acc_clk.slave),
    //         .npp_std_read       (bram_acc_clk.slave),
    //         .write_chip_enable  (!en_acc_wr),
    //         .read_chip_enable   (!en_acc_rd),
    //         .input_word         (pe_dout_acc[NUM_PE]),
    //         .write_address      (cnt_acc_bw),
    //         .read_address       (cnt_acc_br),
    //         .output_word        (bram_acc_out)
    //     );
    // endgenerate
    
    // logic [ACC_BW-1:0] bram_acc_out_reg;
    // always_ff @(posedge clk) begin
    //     if (!rstn || !rstn_acc) begin
    //         bram_acc_out_reg <= {ACC_BW{1'b0}};
    //     end else if (regce_acc) begin
    //         bram_acc_out_reg <= bram_acc_out;
    //     end
    // end
    // assign pe_din_acc[NUM_PE] = bram_acc_out_reg;



    // ACC_MUX
    always_comb begin
        case (state)
            S_FP, S_BPdZ, S_BPdW, S_PU : begin
                acc_sel_pr[0] = 2'b00;
            end
            S_BPdA : begin
                if (cnt_acc_ar == 0) begin
                    acc_sel_pr[0] = 2'b00;
                end else if (cfg_cnt_ba > 0) begin
                    acc_sel_pr[0] = 2'b01;
                end else begin
                    acc_sel_pr[0] = 2'b10;
                end
            end
            default : begin
                acc_sel_pr[0] = 2'b00;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 2; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                acc_sel_pr[ps_idx] <= '0;
            end else if (en_acc_i0[ps_idx-1]) begin
                acc_sel_pr[ps_idx] <= acc_sel_pr[ps_idx-1];
            end
        end
    end

    assign acc_sel = acc_sel_pr[2];
    


    // ACC_QNT_MUX
    always_comb begin
        case (state) inside
            S_BPdA : begin                              // Q_ACC -> Q_ACT
                acc_qnt_sel_pr[0] = 1'b0;
            end
            'X : begin                                  // Q_ACC -> Q_WEIGHT
                acc_qnt_sel_pr[0] = 1'b1;
            end
            default : begin
                acc_qnt_sel_pr[0] = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 3; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                acc_qnt_sel_pr[ps_idx] <= '0;
            end else if (en_acc_o0[ps_idx-1]) begin
                acc_qnt_sel_pr[ps_idx] <= acc_qnt_sel_pr[ps_idx-1];
            end
        end
    end
    
    assign acc_qnt_sel = acc_qnt_sel_pr[3];
    
    always_comb begin
        // Clip fractional bits
        `ifdef ROUND_FLOOR
            acc_qnt_act_in = $signed(pe_dout_acc[NUM_PE]) >>> WEIGHT_QN;
        `else
            acc_qnt_act_in = $signed( pe_dout_acc[NUM_PE] +
                                      { {(WEIGHT_QM)   {1'b0}},
                                        {(ACT_BW)      {1'b0}},
                                        {(1)           {1'b1}},     // 0.5
                                        {(WEIGHT_QN-1) {1'b0}}
                                      }
                                    ) >>> WEIGHT_QN;
        `endif
        // Clip integer bits
        if (acc_qnt_act_in > 2 ** (ACT_BW-1) - 1) begin
            acc_qnt_act_out = 2 ** (ACT_BW-1) - 1;
        end else if (acc_qnt_act_in < - 2 ** (ACT_BW-1)) begin
            acc_qnt_act_out = - 2 ** (ACT_BW-1);
        end else begin
            acc_qnt_act_out = acc_qnt_act_in[ACT_BW-1:0];
        end

        // Clip fractional bits
        `ifdef ROUND_FLOOR
            acc_qnt_weight_in = $signed(pe_dout_acc[NUM_PE]) >>> ACT_QN;
        `else
            acc_qnt_weight_in = $signed( pe_dout_acc[NUM_PE] +
                                         { {(ACT_QM)    {1'b0}},
                                           {(WEIGHT_BW) {1'b0}},
                                           {(1)         {1'b1}},    // 0.5
                                           {(ACT_QN-1)  {1'b0}}
                                         }
                                       ) >>> ACT_QN;
        `endif
        // Clip integer bits
        if (acc_qnt_weight_in > 2 ** (WEIGHT_BW-1) - 1) begin
            acc_qnt_weight_out = 2 ** (WEIGHT_BW-1) - 1;
        end else if (acc_qnt_weight_in < - 2 ** (WEIGHT_BW-1)) begin
            acc_qnt_weight_out = - 2 ** (WEIGHT_BW-1);
        end else begin
            acc_qnt_weight_out = acc_qnt_weight_in[WEIGHT_BW-1:0];
        end
    end

    always_comb begin
        case (acc_qnt_sel)
            1'b0 : begin                                // Q_ACC -> Q_ACT
                acc_qnt_out = acc_qnt_act_out;
            end
            1'b1 : begin                                // Q_ACC -> Q_WEIGHT
                acc_qnt_out = acc_qnt_weight_out;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            acc_qnt_out_r <= '0;
        end else if (en_acc_o0[3]) begin
            acc_qnt_out_r <= acc_qnt_out;
        end
    end
    
    // ACC_ACT_MUX
    always_comb begin
        case (state) inside
            S_BPdA : begin                              // Non
                acc_act_sel_pr[0] = 1'b0;
            end
            'X : begin                                  // ln
                acc_act_sel_pr[0] = 1'b1;
            end
            default : begin
                acc_act_sel_pr[0] = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        for (int unsigned ps_idx = 1; ps_idx <= 4; ps_idx++) begin
            if (!rstn || !rstn_CFG) begin
                acc_act_sel_pr[ps_idx] <= '0;
            end else if (en_acc_o0[ps_idx-1]) begin
                acc_act_sel_pr[ps_idx] <= acc_act_sel_pr[ps_idx-1];
            end
        end
    end
    
    assign acc_act_sel = acc_act_sel_pr[4];
    
    always_comb begin
        case (acc_act_sel)
            1'b0 : begin                                // Non
                acc_act_out = acc_qnt_out_r;
            end
            1'b1 : begin                                // ln???
                acc_act_out = acc_qnt_out_r;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rstn || !rstn_CFG) begin
            acc_act_out_r <= '0;
        end else if (en_acc_o0[4]) begin
            acc_act_out_r <= acc_act_out;
        end
    end
    


    // Output Data
    generate
        always_comb dout_act[NUM_PE] = acc_act_out_r;

        for (genvar PE_IDX = 0; PE_IDX < NUM_PE; PE_IDX++) begin
            always_comb dout_act[PE_IDX] = mac_act_out_r[PE_IDX];
        end
    endgenerate

    
endmodule
