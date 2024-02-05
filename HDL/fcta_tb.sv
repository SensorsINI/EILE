// 256 PE, MAXM = 1, 500 MHz
`timescale 100ps/1ps



import definesPkg::*;

`define TVALID_I_RND
`define TREADY_I_RND



module testbench;



    // Global
    parameter NUM_PE    = 256;           //16
    parameter NUM_ACT_FUNC = 2;

    parameter WEIGHT_QM = 2;
    parameter WEIGHT_QN = 14;
    parameter ACT_QM    = 8;
    parameter ACT_QN    = 8;
    parameter ACC_QM    = 10;
    parameter ACC_QN    = 22;

    parameter MAX_N     = 1024;         //1024
    // parameter MAX_M     = 32;           //32
    parameter MAX_M     = 1;           //32     // IL only
    parameter MAX_NoP   = MAX_N/NUM_PE; //64

    // IPM
    parameter IPM_BRAM_DDB_BW    = 16;
    // parameter IPM_BRAM_DDB_DEPTH = (MAX_M>NUM_PE)? (MAX_M+1):(NUM_PE+1);    //32
    parameter IPM_BRAM_DDB_DEPTH = (MAX_M>NUM_PE)? (MAX_M+8):(NUM_PE+8);    // NOTE: SRAM depth must be a multiple of 8 for sram mux 4

    // CCM
    parameter BRAM_MAC_DEPTH = MAX_M*MAX_NoP;   //2048
    parameter BRAM_ACC_DEPTH = MAX_M;           //32
    // parameter BRAM_ACC_DEPTH = BRAM_MAC_DEPTH;     // NOTE: P256 M1

    // OPM
    parameter OPM_BRAM_DDB_BW    = 16;
    // parameter OPM_BRAM_DDB_DEPTH = (MAX_M>NUM_PE)? (MAX_M):(NUM_PE);    //32    //DDB depth irrelevant?
    parameter OPM_BRAM_DDB_DEPTH = 4;          // NOTE: P256 M1

    // Shared
    // parameter AXIS_BW        = 1024;         //256
    parameter AXIS_BW        = 4096;            // NOTE: P256 M1
    parameter BRAM_IDB_BW    = 16;
    parameter BRAM_IDB_DEPTH = MAX_M*MAX_NoP*2;
    // parameter BRAM_IDB_DEPTH = 64;              // NOTE: P256 M1, min depth of sram_dp_hde_hvt_rvt is 64

    // CFG
    parameter CFG_BW    = 96;

    // Local
    localparam WEIGHT_BW = WEIGHT_QM + WEIGHT_QN;
    localparam ACT_BW    = ACT_QM + ACT_QN;
    localparam ACC_BW    = ACC_QM + ACC_QN;

    localparam ADDR_IDB_A  = 0;
    localparam ADDR_IDB_dZ = 0;
    localparam ADDR_IDB_dA = MAX_M*MAX_NoP;

    localparam MAX_CNT_RR = (MAX_M>MAX_NoP)? (MAX_M*MAX_N):(MAX_NoP*MAX_N);
    localparam MAX_CNT_DDO = (MAX_M>MAX_NoP)? (MAX_M*MAX_N):(MAX_NoP*MAX_N);



    // Testbench Constants
    localparam NUM_EPOCH        = 1;                // #Epoch
    localparam NUM_BATCH        = 1;                // #Batch
    localparam M                = 1;                // Batch size
    localparam L                = 3;                // #Layer
    // localparam int N[0:L]       = {832, 512, 256, 64};   // Layer size, padded, NUM_PE * integer (==1 or >=4, to overcome MACC BRAM latency)
    localparam int N[0:L]       = {1024, 256, 256, 256};    // NOTE: P256 M1
    localparam int N_up[0:L]    = {784, 256, 256, 10};   // Unpadded
    localparam logic [$clog2(NUM_ACT_FUNC)-1:0] AF[0:L] = {1'b0, 1'b1, 1'b1, 1'b0};   // Activation function
    // localparam int chk_num[0:L] = {0, 20, 6, 1};
    // localparam int chk_size[0:L] = {0, 314, 342, 257};  // 6280/20, 2052/6, 257/1, must be <= BRAM_MAC_DEPTH
    localparam int chk_num[0:L] = {0, 785, 257, 257};   // NOTE: P256 M1
    localparam int chk_size[0:L] = {0, 1, 1, 1};  // 785/785, 257/257, 257/257
    localparam string dir       = "C:/Workspace/Python/FCTA0.0_M1_L3/";

    // DRAM Data Allocation
    // W[1:L], dW[1:L], A[0:L], dZ[L]
    localparam DRAM_SIZE_W      = (MAX_N/NUM_PE*MAX_N);
    localparam DRAM_SIZE_dW     = (MAX_N/NUM_PE*MAX_N);
    localparam DRAM_SIZE_A      = (MAX_N/NUM_PE*MAX_M);
    localparam DRAM_SIZE_dZ     = (MAX_N/NUM_PE*MAX_M);
    localparam DRAM_DEPTH       = (DRAM_SIZE_W  * L     +
                                   DRAM_SIZE_dW * L     +
                                   DRAM_SIZE_A  * (L+1) +
                                   DRAM_SIZE_dZ * 1      );
    localparam DRAM_OFFSET_W    = (0);
    localparam DRAM_OFFSET_dW   = (DRAM_OFFSET_W  + DRAM_SIZE_W  * L    );
    localparam DRAM_OFFSET_A    = (DRAM_OFFSET_dW + DRAM_SIZE_dW * L    );
    localparam DRAM_OFFSET_dZ   = (DRAM_OFFSET_A  + DRAM_SIZE_A  * (L+1));



    logic   clk = 1;
    always #10 clk = ~clk;
    
    // const int T_SIM = 10 * 1000 * 1000;
    


    // IPM - FSM - states
    typedef enum logic [3:0] {  S_NCFG, S_CFG,
                                S_A0,
                                S_FP,
                                S_BPdZ,
                                S_BPdA,
                                S_BPdW,
                                S_PU} IPM_state_t;
    
    // CCM - FSM - states
    // typedef enum logic [3:0] {  S_NCFG, S_CFG,
    //                             S_FP,
    //                             S_BPdZ,
    //                             S_BPdA,
    //                             S_BPdW,
    //                             S_PU} CCM_state_t;
    
    // OPM - FSM - states
    // typedef enum logic [3:0] {  S_NCFG, S_CFG,
    //                             S_FP,
    //                             S_BPdZ,
    //                             S_BPdA,
    //                             S_BPdW,
    //                             S_PU} OPM_state_t;
    
    logic rstn;
    logic tvalid_i;
    logic tready_i;
    logic tvalid_o;
    logic tlast_o;
    logic tready_o;
    
    logic cfg_start;
    logic cfg_finish;
    stage_t                             cfg_stage;
    logic [$clog2(NUM_ACT_FUNC)-1:0]    cfg_act_func;
    logic [$clog2(MAX_M)-1:0]           cfg_m;
    logic [$clog2(MAX_NoP)-1:0]         cfg_n2op;
    logic [$clog2(MAX_N)-1:0]           cfg_n1;
    logic [$clog2(MAX_NoP*MAX_N*2)-1:0] cfg_cnt_ddi;
    logic [$clog2(MAX_CNT_DDO)-1:0]     cfg_cnt_ddo;
    logic [$clog2(BRAM_MAC_DEPTH)-1:0]  cfg_cnt_ba;
    logic [$clog2(MAX_N)-1:0]           cfg_cnt_ar;
    logic [$clog2(MAX_CNT_RR)-1:0]      cfg_cnt_rr;

    logic                               s_axis_cfg_tvalid;
    logic                               s_axis_cfg_tlast;
    logic [CFG_BW-1:0]                  s_axis_cfg_tdata;
    logic                               s_axis_cfg_tready;

    logic [AXIS_BW-1:0]                 tdata_i;
    logic [AXIS_BW-1:0]                 tdata_o;
    
    // logic [BRAM_IDB_BW-1:0]             BRAM_IDB[NUM_PE-1:0][BRAM_IDB_DEPTH-1:0];
    logic [AXIS_BW-1:0]                 DRAM[DRAM_DEPTH];
    // logic [$clog2(DRAM_DEPTH)-1:0]      addr_dram;

    logic [WEIGHT_BW-1:0]               Y[MAX_M];
    real sm[MAX_N][MAX_M];
    real loss_exa[MAX_M];
    real loss_bat;
    
    int  epo_idx = 0;
    int  bat_idx;
    int  lay_idx;

    
    
    // logic signed[WEIGHT_BW-1:0]         din_weight[NUM_PE-1:0];
    // logic signed[ACT_BW-1:0]            dout_act[NUM_PE-1:0];
    // always_comb begin
    //     for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         tdata_i[WEIGHT_BW*pe_idx +: WEIGHT_BW] = din_weight[pe_idx];
    //         dout_act[pe_idx] = tdata_o[WEIGHT_BW*pe_idx +: WEIGHT_BW];
    //     end
    // end

    // wire signed[WEIGHT_BW-1:0]          din_weight[NUM_PE-1:0];
    // wire signed[ACT_BW-1:0]             dout_act[NUM_PE-1:0];
    // generate
    //     for (genvar pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
    //         assign din_weight[pe_idx] = tdata_i[WEIGHT_BW*pe_idx +: WEIGHT_BW];
    //         assign dout_act[pe_idx]   = tdata_o[WEIGHT_BW*pe_idx +: WEIGHT_BW];
    //     end
    // endgenerate
    
    // generate
    //     for (genvar pe_idx=0; pe_idx<NUM_PE; pe_idx++) begin
    //         assign BRAM_IDB[pe_idx] = FCTA_DUT.genblk1[pe_idx].BRAM_INTERM_DATA_BUF.BRAM;
    //     end
    // endgenerate
    


    FCTA #(
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

    ) FCTA_DUT (
        .clk                (clk),
        .rstn               (rstn),
        .tready_i           (tready_i),
        .tvalid_i           (tvalid_i),
        // .tlast_i            (tlast_i),

        // .cfg_start          (cfg_start),
        // .cfg_stage          (cfg_stage),
        // .cfg_act_func       (cfg_act_func),
        // .cfg_m              (cfg_m),
        // .cfg_n2op           (cfg_n2op),
        // .cfg_n1             (cfg_n1),
        // .cfg_cnt_ddi        (cfg_cnt_ddi),
        // .cfg_cnt_ddo        (cfg_cnt_ddo),
        // .cfg_cnt_ba         (cfg_cnt_ba),
        // .cfg_cnt_ar         (cfg_cnt_ar),
        // .cfg_cnt_rr         (cfg_cnt_rr),
        .s_axis_cfg_tvalid  (s_axis_cfg_tvalid),
        .s_axis_cfg_tlast   (s_axis_cfg_tlast),
        .s_axis_cfg_tdata   (s_axis_cfg_tdata),
        .s_axis_cfg_tready  (s_axis_cfg_tready),

        .tdata_i            (tdata_i),
        .tvalid_o           (tvalid_o),
        .tlast_o            (tlast_o),
        .tready_o           (tready_o),
        // .cfg_finish         (cfg_finish),
        .tdata_o            (tdata_o)
    );

    assign cfg_start    = FCTA_DUT.cfg_start;
    // assign cfg_stage    = FCTA_DUT.cfg_stage;
    // assign cfg_act_func = FCTA_DUT.cfg_act_func;
    // assign cfg_m        = FCTA_DUT.cfg_m;
    // assign cfg_n2op     = FCTA_DUT.cfg_n2op;
    // assign cfg_n1       = FCTA_DUT.cfg_n1;
    // assign cfg_cnt_ddi  = FCTA_DUT.cfg_cnt_ddi;
    // assign cfg_cnt_ddo  = FCTA_DUT.cfg_cnt_ddo;
    // assign cfg_cnt_ba   = FCTA_DUT.cfg_cnt_ba;
    // assign cfg_cnt_ar   = FCTA_DUT.cfg_cnt_ar;
    // assign cfg_cnt_rr   = FCTA_DUT.cfg_cnt_rr;
    assign cfg_finish   = FCTA_DUT.cfg_finish;
    
    // assign cfg_start = FCTA_DUT.cfg_start;
    assign s_axis_cfg_tdata[94-:3]  = cfg_stage;
    assign s_axis_cfg_tdata[91-:1]  = cfg_act_func;
    assign s_axis_cfg_tdata[90-:1]  = cfg_m;
    assign s_axis_cfg_tdata[89-:4]  = cfg_n2op;
    assign s_axis_cfg_tdata[85-:12] = cfg_n1;
    assign s_axis_cfg_tdata[73-:17] = cfg_cnt_ddi;
    assign s_axis_cfg_tdata[56-:16] = cfg_cnt_ddo;
    assign s_axis_cfg_tdata[40-:4]  = cfg_cnt_ba;
    assign s_axis_cfg_tdata[36-:12] = cfg_cnt_ar;
    assign s_axis_cfg_tdata[24-:16] = cfg_cnt_rr;



    // DRAM Data Output
    IPM_state_t                         state_ddo;
    logic                               f_DDO;
    logic [$clog2(MAX_CNT_DDO)-1:0]     cnt_ddo;
    logic                               f_cnt_ddo;
    int                                 offset_ddo;

    // DRAM Data Output FSM
    always_ff @(posedge clk) begin
        if (!rstn) begin
            state_ddo <= S_NCFG;
            offset_ddo <= 0;
        end else begin
            case (state_ddo) inside
                S_NCFG : begin              // Not configured
                    if (FCTA_DUT.cfg_start) begin
                        state_ddo <= S_CFG;
                        offset_ddo <= 0;
                    end
                end
                S_CFG : begin               // Configuring
                    case (FCTA_DUT.cfg_stage)
                        STAGE_FP : begin
                            state_ddo <= S_FP;
                            offset_ddo <= DRAM_OFFSET_A + DRAM_SIZE_A*lay_idx;          // A[l]
                        end
                        STAGE_BPdW : begin
                            state_ddo <= S_BPdW;
                            offset_ddo <= DRAM_OFFSET_dW + DRAM_SIZE_dW*(lay_idx-1);    // dW[l]
                        end
                        STAGE_PU : begin
                            state_ddo <= S_PU;
                            offset_ddo <= DRAM_OFFSET_W + DRAM_SIZE_W*(lay_idx-1);      // W[l]
                        end
                        default : begin
                            state_ddo <= S_NCFG;
                            offset_ddo <= 0;
                        end
                    endcase
                end
                S_FP, S_BPdW, S_PU : begin
                    if (f_cnt_ddo && tvalid_o && tready_i) begin
                        state_ddo <= S_NCFG;
                        offset_ddo <= 0;
                    end
                end
                default : begin
                    state_ddo <= S_NCFG;
                    offset_ddo <= 0;
                end
            endcase
        end
    end
    
    assign f_DDO = state_ddo inside {S_FP, S_BPdW, S_PU};

    always_ff @(posedge clk) begin
        if (f_DDO && tvalid_o && tready_i) begin
            DRAM[offset_ddo + cnt_ddo] <= tdata_o;
        end
    end

    // DRAM Data Output Counter
    always_ff @(posedge clk) begin
        if (!rstn || (state_ddo == S_CFG)) begin
            cnt_ddo <= 0;
        end else if (f_DDO && tvalid_o && tready_i) begin
            if (cnt_ddo == FCTA_DUT.cfg_cnt_ddo) begin
                cnt_ddo <= 0;
            end else begin
                cnt_ddo <= cnt_ddo + 1;
            end
        end
    end

    assign f_cnt_ddo = (cnt_ddo == FCTA_DUT.cfg_cnt_ddo);
    


    // initial begin
    //     #T_SIM
    //     $finish;
    // end
    
    
    
    // Utility tasks & functions
    
    logic [WEIGHT_BW-1:0] dram_buf[MAX_N*MAX_N];
    task automatic file2DRAM (
        input string str_stage,
        input string file_name,
        input int    dram_offset,
        input int    dram_size,
        input int    file_offset = 0
    );
        int fi;
        int num_bytes;
        int dat_idx;
        int pe_idx;
        fi = $fopen(file_name, "rb");
        if (!fi) begin
            $error("%s [f->DRAM] Can not open \"%s\"!", str_stage, file_name);
        end else begin
            $fseek(fi, file_offset, 0);
            $display("%s [f->DRAM] At position (0x%08x).", str_stage, $ftell(fi));
            // num_bytes = $fread(DRAM, fi, dram_offset, dram_size);
            num_bytes = $fread(dram_buf, fi, 0, dram_size*NUM_PE);
            for (dat_idx=0; dat_idx<dram_size; dat_idx++) begin
                for(pe_idx=0; pe_idx<NUM_PE; pe_idx++) begin
                    // $write("%04x ", dram_buf[dat_idx*NUM_PE + pe_idx]);
                    DRAM[dram_offset + dat_idx][WEIGHT_BW*pe_idx +: WEIGHT_BW] = dram_buf[dat_idx*NUM_PE + pe_idx];
                end
                // $write("\n");
            end
            $display("%s [f->DRAM] (%d) bytes read from \"%s\".", str_stage, num_bytes, file_name);
            $display("%s [f->DRAM] At position (0x%08x).", str_stage, $ftell(fi));
        end
        $fclose(fi);
    endtask



    task automatic file2Y (
        input string str_stage,
        input string file_name,
        input int file_offset
    );
        int fi;
        int num_bytes;
        int dat_idx;
        fi = $fopen(file_name, "rb");
        if (!fi) begin
            $error("%s [f->Y] Can not open \"%s\"!", str_stage, file_name);
        end else begin
            $fseek(fi, file_offset, 0);
            $display("%s [f->Y] At position (0x%08x).", str_stage, $ftell(fi));
            num_bytes = $fread(Y, fi, 0, M);
            $display("%s [f->Y] (%d) bytes read from \"%s\".", str_stage, num_bytes, file_name);
            $display("%s [f->Y] At position (0x%08x).", str_stage, $ftell(fi));
        end
        $fclose(fi);
    endtask



    function automatic compute_softmax (
        ref real result[MAX_N][MAX_M],
        input int N,
        input int M
    );
        int row_idx;
        int exa_idx;
        int pe_idx;
        int signed a;
        int addr;
        real sum_exp[MAX_M] = '{default: 0.0};
        for (row_idx=0; row_idx<N; row_idx++) begin
            pe_idx = row_idx % NUM_PE;
            for (exa_idx=0; exa_idx<M; exa_idx++) begin
                // a = $signed(BRAM_IDB[pe_idx][ADDR_IDB_A + (row_idx/NUM_PE)*M + exa_idx]);
                addr = DRAM_OFFSET_A + DRAM_SIZE_A*L + (row_idx/NUM_PE)*M + exa_idx;
                a = $signed(DRAM[addr][WEIGHT_BW*pe_idx +: WEIGHT_BW]);
                // $write("%1.8f ", $itor(a)/(2.0**ACT_QN));
                sum_exp[exa_idx] += $exp($itor(a)/(2.0**ACT_QN));
            end
            // $write("\n");
        end
        // for (exa_idx=0; exa_idx<M; exa_idx++) begin
        //     $display(sum_exp[exa_idx]);
        // end
        for (row_idx=0; row_idx<N; row_idx++) begin
            pe_idx = row_idx % NUM_PE;
            for (exa_idx=0; exa_idx<M; exa_idx++) begin
                // a = $signed(BRAM_IDB[pe_idx][ADDR_IDB_A + (row_idx/NUM_PE)*M + exa_idx]);
                addr = DRAM_OFFSET_A + DRAM_SIZE_A*L + (row_idx/NUM_PE)*M + exa_idx;
                a = $signed(DRAM[addr][WEIGHT_BW*pe_idx +: WEIGHT_BW]);
                result[row_idx][exa_idx] = $exp($itor(a)/(2.0**ACT_QN)) / sum_exp[exa_idx];
            end
        end
    endfunction



    function automatic compute_loss (
        input int M
    );
        int exa_idx;
        real loss_exa_cur;
        // $write("    [LOSS] Loss_exa = [ ");
        loss_bat = 0;
        for (exa_idx=0; exa_idx<M; exa_idx++) begin
            // $display(Y[exa_idx]);
            // $display(sm[Y[exa_idx]][exa_idx]);
            loss_exa_cur = -$ln(sm[Y[exa_idx]][exa_idx]);
            loss_exa[exa_idx] = loss_exa_cur;
            loss_bat += loss_exa_cur;
            // $write("%f ", loss_exa_cur);
        end
        // $write("]\n");
        loss_bat = loss_bat / M;
        $display("    [LOSS] Loss_bat = %1.15f", loss_bat);
    endfunction



    function automatic compute_dZ (
        input int N,
        input int M
    );
        int row_idx;
        int exa_idx;
        int pe_idx;
        int addr;
        real r;
        for (row_idx=0; row_idx<N; row_idx+=NUM_PE) begin
            for (exa_idx=0; exa_idx<M; exa_idx++) begin
                for (pe_idx=0; pe_idx<NUM_PE; pe_idx++) begin
                    if ((row_idx + pe_idx) == Y[exa_idx]) begin
                        r = (sm[row_idx + pe_idx][exa_idx] - 1.0) / M;
                    end else begin
                        r = sm[row_idx + pe_idx][exa_idx] / M;
                    end
                    // $write("%1.8f ", r);
                    addr = DRAM_OFFSET_dZ + (row_idx/NUM_PE)*M + exa_idx;
                    DRAM[addr][WEIGHT_BW*pe_idx +: WEIGHT_BW] = r2qw(r);
                end
                // $write("\n");
            end
        end
    endfunction



    function logic signed[ACT_BW-1:0] i2qa(input int signed sint);
        logic signed[31:0] act_in;
        logic signed[ACT_BW-1:0] act_out;

        act_in = $signed(sint) <<< ACT_QN;

        if (act_in > 2**(ACT_BW-1)-1) begin
            act_out = 2**(ACT_BW-1)-1;
        end else if (act_in < -2**(ACT_BW-1)) begin
            act_out = -2**(ACT_BW-1);
        end else begin
            act_out = act_in;
        end

        return act_out;
    endfunction
    


    function logic signed[ACT_BW-1:0] r2qa(input real real_in);
        logic signed[31:0] act_in;
        logic signed[ACT_BW-1:0] act_out;
        
        `ifdef ROUND_FLOOR
            act_in = real_in * (2 ** ACT_QN);
        `else
            // act_in = real_in * (2 ** ACT_QN) + 0.5;
            act_in = (real_in + 2 ** (-1-ACT_QN)) * (2 ** ACT_QN);
        `endif
        
        if (act_in > 2**(ACT_BW-1)-1) begin
            act_out = 2**(ACT_BW-1)-1;
        end else if (act_in < -2**(ACT_BW-1)) begin
            act_out = -2**(ACT_BW-1);
        end else begin
            act_out = act_in;
        end

        return act_out;
    endfunction
    


    function logic signed[WEIGHT_BW-1:0] i2qw(input int signed sint);
        logic signed[31:0] weight_in;
        logic signed[WEIGHT_BW-1:0] weight_out;

        weight_in = $signed(sint) <<< WEIGHT_QN;

        if (weight_in > 2**(WEIGHT_BW-1)-1) begin
            weight_out = 2**(WEIGHT_BW-1)-1;
        end else if (weight_in < -2**(WEIGHT_BW-1)) begin
            weight_out = -2**(WEIGHT_BW-1);
        end else begin
            weight_out = weight_in;
        end

        return weight_out;
    endfunction
    


    function logic signed[WEIGHT_BW-1:0] r2qw(input real real_in);
        logic signed[31:0] weight_in;
        logic signed[WEIGHT_BW-1:0] weight_out;
        
        `ifdef ROUND_FLOOR
            weight_in = real_in * (2 ** WEIGHT_QN);
        `else
            // weight_in = real_in * (2 ** WEIGHT_QN) + 0.5;
            weight_in = (real_in + 2 ** (-1-WEIGHT_QN)) * (2 ** WEIGHT_QN);
        `endif

        if (weight_in > 2**(WEIGHT_BW-1)-1) begin
            weight_out = 2**(WEIGHT_BW-1)-1;
        end else if (weight_in < -2**(WEIGHT_BW-1)) begin
            weight_out = -2**(WEIGHT_BW-1);
        end else begin
            weight_out = weight_in;
        end

        return weight_out;
    endfunction
    

    
    /*
    logic TE_f;
    logic TG_f;
    logic [0:4] f_cur;
    logic [0:4] f_prev;
    
    assign f_cur = {FCTA_DUT.OPM.f_I,
                    FCTA_DUT.OPM.f_O};
    
    always @(posedge clk) begin
        f_prev <= f_cur;
    end
    
    assign TE_f = |(f_prev & ~f_cur);   // Trailing edge
    assign TG_f = |(f_prev ^ f_cur);    // Toggle
    */
    


    // Control Signal - tready_i
    initial begin
        $srandom(1);    // dW[2] incorrect  3 7 8 9
                        // dW[2] correct    4 10
                        // dA[2] stall      5 6
        
        // -------------------- INIT --------------------
        tready_i = 1'b0;
        #2;
        #20;

        // -------------------- TRAINING --------------------
        // #20;
`ifndef TREADY_I_RND
        tready_i = 1'b1;
        // #(T_SIM);
`else
        while (1) begin
            tready_i = ($urandom_range(0, 3)) != 0;
            #($urandom_range(0, 40)*20);
        end
`endif
        // while ($stime < T_SIM) begin
        //     if (TG_f) begin
        //         tready_i = 1'b0;
        //     end else begin
        //         tready_i = ($urandom_range(0, 3)) != 0;
        //         // tready_i = ($urandom_range(0, 3)) == 0;
        //         // tready_i = ($urandom_range(0, 7)) == 0;
        //     end
        //     #10;
        // end
    end
    


    // Output Results of a FCTA Stage
    task automatic output_proc(
        input int l,
        input stage_t stage,
        input int is_dZL = 0
    );
        string str_stage = $sformatf("    [%s L%0d]", stage.name, l);
        string str_data_name;
        int    l_data;
        string file_name;
        int    fo;
        int    dram_offset;
        int    num_data;        // in DRAM
        int    num_bytes;
        int    dat_idx;
        int    pe_idx;
        
        case (stage)

            STAGE_A0 : begin
                if (is_dZL == 0) begin
                    str_data_name   = "A";
                    l_data          = l;
                    num_data        = N[l_data]/NUM_PE*M;
                    dram_offset     = DRAM_OFFSET_A + DRAM_SIZE_A*l;        // A[l]
                end else begin
                    str_data_name   = "dZ";
                    l_data          = l;
                    num_data        = N[l_data]/NUM_PE*M;
                    dram_offset     = DRAM_OFFSET_dZ;                       // dZ[L]
                end
            end
            
            STAGE_FP : begin
                str_data_name       = "A";
                l_data              = l;
                num_data            = N[l_data]/NUM_PE*M;
                dram_offset         = DRAM_OFFSET_A + DRAM_SIZE_A*l;        // A[l]
            end
            
            // STAGE_BPdZ : begin
            //     str_data_name       = "dZ";
            //     l_data              = l;
            //     num_data            = N[l_data]/NUM_PE*M;
            // end
            
            // STAGE_BPdA : begin
            //     str_data_name       = "dA";
            //     l_data              = l-1;
            //     num_data            = N[l_data-1]/NUM_PE*M;
            // end
            
            STAGE_BPdW : begin
                str_data_name      = "dW";
                l_data             = l;
                num_data           = N[l_data]/NUM_PE*(N_up[l_data-1]+1);
                dram_offset        = DRAM_OFFSET_dW + DRAM_SIZE_dW*(l-1);   // dW[l]
            end
            
            STAGE_PU : begin
                str_data_name      = "W";
                l_data             = l;
                num_data           = N[l_data]/NUM_PE*(N_up[l_data-1]+1);
                dram_offset        = DRAM_OFFSET_W + DRAM_SIZE_W*(l-1);     // W[l]
            end
            
            default : begin
                $error("%s [FILE_OUT] Invalid stage!", str_stage);
            end

        endcase
        
        file_name = $sformatf("%s%s%0d_hw.dat", dir, str_data_name, l_data);
        fo = $fopen(file_name, "wb");
        if (!fo) begin
            $error("%s [FILE_OUT] Can not open \"%s\"!", str_stage, file_name);
        end

        // for (dat_idx=0; dat_idx<num_data; dat_idx++) begin
        //     $fwrite(
        //         fo,
        //         "%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c",
        //         DRAM[dram_offset + dat_idx][8*01 +: 8], DRAM[dram_offset + dat_idx][8*00 +: 8],
        //         DRAM[dram_offset + dat_idx][8*03 +: 8], DRAM[dram_offset + dat_idx][8*02 +: 8],
        //         DRAM[dram_offset + dat_idx][8*05 +: 8], DRAM[dram_offset + dat_idx][8*04 +: 8],
        //         DRAM[dram_offset + dat_idx][8*07 +: 8], DRAM[dram_offset + dat_idx][8*06 +: 8],
        //         DRAM[dram_offset + dat_idx][8*09 +: 8], DRAM[dram_offset + dat_idx][8*08 +: 8],
        //         DRAM[dram_offset + dat_idx][8*11 +: 8], DRAM[dram_offset + dat_idx][8*10 +: 8],
        //         DRAM[dram_offset + dat_idx][8*13 +: 8], DRAM[dram_offset + dat_idx][8*12 +: 8],
        //         DRAM[dram_offset + dat_idx][8*15 +: 8], DRAM[dram_offset + dat_idx][8*14 +: 8],
        //         DRAM[dram_offset + dat_idx][8*17 +: 8], DRAM[dram_offset + dat_idx][8*16 +: 8],
        //         DRAM[dram_offset + dat_idx][8*19 +: 8], DRAM[dram_offset + dat_idx][8*18 +: 8],
        //         DRAM[dram_offset + dat_idx][8*21 +: 8], DRAM[dram_offset + dat_idx][8*20 +: 8],
        //         DRAM[dram_offset + dat_idx][8*23 +: 8], DRAM[dram_offset + dat_idx][8*22 +: 8],
        //         DRAM[dram_offset + dat_idx][8*25 +: 8], DRAM[dram_offset + dat_idx][8*24 +: 8],
        //         DRAM[dram_offset + dat_idx][8*27 +: 8], DRAM[dram_offset + dat_idx][8*26 +: 8],
        //         DRAM[dram_offset + dat_idx][8*29 +: 8], DRAM[dram_offset + dat_idx][8*28 +: 8],
        //         DRAM[dram_offset + dat_idx][8*31 +: 8], DRAM[dram_offset + dat_idx][8*30 +: 8]
        //     );
        //     // $display(
        //     //     "%08d | %04x %04x %04x %04x %04x %04x %04x %04x %04x %04x %04x %04x %04x %04x %04x %04x",
        //     //     dram_offset + dat_idx,
        //     //     DRAM[dram_offset + dat_idx][16*00 +: 16]
        //     //     DRAM[dram_offset + dat_idx][16*01 +: 16],
        //     //     DRAM[dram_offset + dat_idx][16*02 +: 16],
        //     //     DRAM[dram_offset + dat_idx][16*03 +: 16],
        //     //     DRAM[dram_offset + dat_idx][16*04 +: 16],
        //     //     DRAM[dram_offset + dat_idx][16*05 +: 16],
        //     //     DRAM[dram_offset + dat_idx][16*06 +: 16],
        //     //     DRAM[dram_offset + dat_idx][16*07 +: 16],
        //     //     DRAM[dram_offset + dat_idx][16*08 +: 16],
        //     //     DRAM[dram_offset + dat_idx][16*09 +: 16],
        //     //     DRAM[dram_offset + dat_idx][16*10 +: 16],
        //     //     DRAM[dram_offset + dat_idx][16*11 +: 16],
        //     //     DRAM[dram_offset + dat_idx][16*12 +: 16],
        //     //     DRAM[dram_offset + dat_idx][16*13 +: 16],
        //     //     DRAM[dram_offset + dat_idx][16*14 +: 16],
        //     //     DRAM[dram_offset + dat_idx][16*15 +: 16],
        //     // );
        // end
        for (dat_idx=0; dat_idx<num_data; dat_idx++) begin
            for (pe_idx=0; pe_idx<NUM_PE; pe_idx++) begin
                $fwrite(
                    fo,
                    "%c%c",
                    DRAM[dram_offset + dat_idx][(pe_idx*16+08) +: 8],
                    DRAM[dram_offset + dat_idx][(pe_idx*16+00) +: 8]
                );
            end
        end
        num_bytes = num_data*AXIS_BW/8;

        $display("%s [FILE_OUT] (%d) bytes written to \"%s\".", str_stage, num_bytes, file_name);
        $display("%s [FILE_OUT] At position (0x%08x).", str_stage, $ftell(fo));
        $fclose(fo);

    endtask



    /*
    // Output to File
    initial begin
        automatic int epo_idx = 0;
        automatic int bat_idx;
        automatic int exa_idx;
        automatic int lay_idx;

        // -------------------- INIT --------------------
        #1;
        #10;

        // -------------------- TRAINING --------------------
        for (bat_idx=0; bat_idx<NUM_BATCH; bat_idx++) begin

            // ---------------- Input Features ----------------

            // ---------------- Forward Propagation ----------------
            for (lay_idx=1; lay_idx<=L; lay_idx++) begin
            end

            // ---------------- Loss Function ----------------

            // ---------------- Backward Propagation ----------------
            // for (lay_idx=L; lay_idx>=1; lay_idx--) begin
            // end

        end
        
    end
    */

    

    // Run a Stage of FCTA
    task automatic FCTA_proc(
        input int l,
        input stage_t stage,
        input int is_dZL = 0
    );
        string str_stage = $sformatf("    [%s L%0d]", stage.name, l);
        time time_start;
        int offset;
        int offset2;
        int chk_idx;
        int dat_idx;

        // s_axis_cfg_tdata = 'b0;
        time_start = $time;

        $display("%s ---------------- started ----------------", str_stage);
        
        // S_NCFG
        tvalid_i    = 1'b0;
        // cfg_start   = 1'b1;
        s_axis_cfg_tvalid = 1'b1;
        cfg_stage   = stage;
        case (stage)
            STAGE_A0 : begin
                cfg_act_func = 1'b0;
                cfg_m        = 0;
                cfg_n2op     = 0;
                cfg_n1       = 0;
                cfg_cnt_ddi  = (N[l]/NUM_PE)*(M) - 1;
                cfg_cnt_ddo  = 0;
                cfg_cnt_ba   = 0;
                cfg_cnt_ar   = 0;
                cfg_cnt_rr   = 0;
                if (is_dZL == 0) begin
                    offset   = DRAM_OFFSET_A + DRAM_SIZE_A*l;       // A[l]
                end else begin
                    offset   = DRAM_OFFSET_dZ;                      // dZ[L]
                end
                offset2      = 0;
            end
            STAGE_FP : begin
                cfg_act_func = AF[l];
                cfg_m        = M                        - 1;
                cfg_n2op     = N[l]/NUM_PE              - 1;
                cfg_n1       = N_up[l-1]+1                 - 1;
                cfg_cnt_ddi  = N[l]/NUM_PE*(N_up[l-1]+1)   - 1;
                cfg_cnt_ddo  = N[l]/NUM_PE*M            - 1;
                cfg_cnt_ba   = N[l]/NUM_PE*M            - 1;
                cfg_cnt_ar   = N_up[l-1]+1                 - 1;
                cfg_cnt_rr   = 1                        - 1;
                offset       = DRAM_OFFSET_W + DRAM_SIZE_W*(l-1);   // W[l]
                offset2      = 0;
            end
            STAGE_BPdZ : begin
                cfg_act_func = 1'b0;
                cfg_m        = M                        - 1;
                cfg_n2op     = N[l]/NUM_PE              - 1;
                cfg_n1       = 1                        - 1;
                cfg_cnt_ddi  = N[l]/NUM_PE*M            - 1;
                cfg_cnt_ddo  = N[l]/NUM_PE*M            - 1;
                cfg_cnt_ba   = 1                        - 1;
                cfg_cnt_ar   = 1                        - 1;
                cfg_cnt_rr   = N[l]/NUM_PE*M            - 1;
                offset       = DRAM_OFFSET_A + DRAM_SIZE_A*l;       // A[l]
                offset2      = 0;
            end
            STAGE_BPdA : begin
                cfg_act_func = 1'b0;
                cfg_m        = M                        - 1;
                cfg_n2op     = N[l]/NUM_PE              - 1;
                cfg_n1       = N_up[l-1]                   - 1;
                cfg_cnt_ddi  = N[l]/NUM_PE*N_up[l-1]       - 1;
                cfg_cnt_ddo  = N_up[l-1]*M                 - 1;
                cfg_cnt_ba   = M                        - 1;
                cfg_cnt_ar   = N[l]/NUM_PE              - 1;
                cfg_cnt_rr   = N_up[l-1]                   - 1;
                offset       = DRAM_OFFSET_W + DRAM_SIZE_W*(l-1);   // W[l]
                offset2      = 0;
            end
            STAGE_BPdW : begin
                cfg_act_func = 1'b0;
                cfg_m        = M                        - 1;
                cfg_n2op     = N[l]/NUM_PE              - 1;
                cfg_n1       = N_up[l-1]+1                 - 1;
                cfg_cnt_ddi  = N[l-1]/NUM_PE*M          - 1;
                cfg_cnt_ddo  = N[l]/NUM_PE*(N_up[l-1]+1)   - 1;
                cfg_cnt_ba   = 1                        - 1;
                cfg_cnt_ar   = M                        - 1;
                cfg_cnt_rr   = N[l]/NUM_PE*(N_up[l-1]+1)   - 1;
                offset       = DRAM_OFFSET_A + DRAM_SIZE_A*(l-1);   // A[l-1]
                offset2      = 0;
            end
            STAGE_PU : begin
                cfg_act_func = 1'b0;
                cfg_m        = 2                        - 1;
                cfg_n2op     = N[l]/NUM_PE              - 1;
                cfg_n1       = N_up[l-1]+1                 - 1;
                cfg_cnt_ddi  = N[l]/NUM_PE*(N_up[l-1]+1)*2 - 1;
                cfg_cnt_ddo  = N[l]/NUM_PE*(N_up[l-1]+1)   - 1;
                cfg_cnt_ba   = chk_size[l]              - 1;
                cfg_cnt_ar   = 2                        - 1;
                cfg_cnt_rr   = chk_num[l]               - 1;
                offset       = DRAM_OFFSET_W + DRAM_SIZE_W*(l-1);   // W[l]
                offset2      = DRAM_OFFSET_dW + DRAM_SIZE_dW*(l-1); // dW[l]
            end
            default : begin
                $error("%s Invalid stage!", str_stage);
            end
        endcase
        #20;
        
        // S_CFG
        tvalid_i    = 1'b0;
        // cfg_start   = 1'b0;
        #20;
        
        // S_<stage>
        case (stage) inside

            STAGE_A0, STAGE_FP, STAGE_BPdZ, STAGE_BPdA, STAGE_BPdW : begin
                for (dat_idx=0; dat_idx<=cfg_cnt_ddi; dat_idx++) begin
`ifdef TVALID_I_RND
                    if ($urandom_range(0, 1000) < 100) begin
                        tvalid_i = 1'b0;
                        tdata_i = 'X;
                        #($urandom_range(0, 40)*20);
                    end
`endif
                    tvalid_i = 1'b1;
                    tdata_i = DRAM[offset + dat_idx];
                    #18;
                    while (!tready_o && tvalid_i) begin
                        #20;
                    end
                    // do @(posedge clk); while (!tready_o);
                    // #9
                    // while (!tready_o) @(posedge clk);
                    #2;
                end
            end

            STAGE_PU : begin
                for (chk_idx=0; chk_idx<chk_num[l]; chk_idx++) begin
                    for (dat_idx=0; dat_idx<chk_size[l]; dat_idx++) begin
`ifdef TVALID_I_RND
                        if ($urandom_range(0, 1000) < 100) begin
                            tvalid_i = 1'b0;
                            tdata_i = 'X;
                            #($urandom_range(0, 40)*20);
                        end
`endif
                        tvalid_i = 1'b1;
                        tdata_i = DRAM[offset + chk_idx*chk_size[l] + dat_idx];
                        #18;
                        while (!tready_o && tvalid_i) begin
                            #20;
                        end
                        #2;
                    end
                    for (dat_idx=0; dat_idx<chk_size[l]; dat_idx++) begin
`ifdef TVALID_I_RND
                        if ($urandom_range(0, 1000) < 100) begin
                            tvalid_i = 1'b0;
                            tdata_i = 'X;
                            #($urandom_range(0, 40)*20);
                        end
`endif
                        tvalid_i = 1'b1;
                        tdata_i = DRAM[offset2 + chk_idx*chk_size[l] + dat_idx];
                        #18;
                        while (!tready_o && tvalid_i) begin
                            #20;
                        end
                        #2;
                    end
                end
            end

            default : begin
                $error("%s Invalid stage!", str_stage);
            end

        endcase

        tvalid_i = 1'bX;
        tdata_i = 'X;
        
        // Wait for S_NCFG
        case (stage) inside
            // STAGE_A0 : begin
            //     while (FCTA_DUT.IPM.state != S_NCFG) begin
            //         #10;
            //     end
            // end
            // STAGE_FP, STAGE_BPdZ, STAGE_BPdA, STAGE_BPdW, STAGE_PU: begin
            //     while (cfg_finish == 0) begin
            //         #10;
            //     end
            // end
            STAGE_A0, STAGE_FP, STAGE_BPdZ, STAGE_BPdA, STAGE_BPdW, STAGE_PU: begin
                while (s_axis_cfg_tready == 0) begin
                    #20;
                end
            end
            default : begin
                $error("%s Invalid stage!", str_stage);
            end
        endcase

        // s_axis_cfg_tvalid = 1'b0;

        // $display("%s ---------------- finished ----------------", str_stage);
        $display("%s Simulation time = %t", str_stage, $time - time_start);

    endtask



    // Main
    initial begin
        // automatic int epo_idx = 0;
        // automatic int bat_idx;
        // automatic int lay_idx;

        // -------------------- INIT --------------------
        $srandom(1);
        rstn        = 1'b1;
        tvalid_i    = 1'b0;
        // cfg_start   = 1'b0;
        cfg_stage   = STAGE_IDLE;
        cfg_act_func = '0;
        cfg_m       = '0;
        cfg_n2op    = '0;
        cfg_n1      = '0;
        cfg_cnt_ddi = '0;
        cfg_cnt_ddo = '0;
        cfg_cnt_ba  = '0;
        cfg_cnt_ar  = '0;
        cfg_cnt_rr  = '0;
        tdata_i     = 'X;
        s_axis_cfg_tvalid = 1'b0;
        s_axis_cfg_tlast  = 1'b0;
        // s_axis_cfg_tdata  = 'X;
        
        #2;
        
        rstn        = 1'b0;
        #20;
        
        rstn        = 1'b1;
        
        for (lay_idx=1; lay_idx<=L; lay_idx++) begin
            file2DRAM(          // W[l], shape(N[l]*N_up[l-1],)
                .str_stage      ("[OVERALL INIT]"),
                .file_name      ($sformatf("%sW%0d.dat", dir, lay_idx)),
                .dram_offset    (DRAM_OFFSET_W+DRAM_SIZE_W*(lay_idx-1)),
                .dram_size      (N[lay_idx]/NUM_PE*(N_up[lay_idx-1]+1))
            );
            // output_proc(lay_idx, STAGE_PU);
        end

        // -------------------- TRAINING --------------------
        for (epo_idx=0; epo_idx<NUM_EPOCH; epo_idx++) begin

            for (bat_idx=0; bat_idx<NUM_BATCH; bat_idx++) begin

                $display("[E%03d B%04d] ================ STARTED ================", epo_idx, bat_idx);

                file2DRAM(          // A0[bat_idx], shape((N[l]/NUM_PE)*(M)*(NUM_PE),)
                    .str_stage      ("    [INIT]"),
                    .file_name      ($sformatf("%sA%0d.dat", dir, 0)),
                    .dram_offset    (DRAM_OFFSET_A),
                    .dram_size      (N[0]/NUM_PE*M),
                    .file_offset    (N[0]*M*ACT_BW/8*bat_idx)
                );

                file2Y(             // Y[bat_idx], shape(M,)
                    .str_stage      ("    [INIT]"),
                    .file_name      ($sformatf("%sY.dat", dir)),
                    .file_offset    (M*WEIGHT_BW/8*bat_idx)
                );

                // ---------------- Input Features ----------------
                FCTA_proc(0, STAGE_A0);
                // output_proc(0, STAGE_A0);

                // ########################################################################
                // begin   // ******** Print BRAM_IDB ********
                //     // logic [3:0] test1;
                //     // logic [7:0] test2;
                //     automatic int dat_idx;
                //     automatic int pe_idx;
                //     lay_idx = 0;
                //     $write("    [OUTPUT] A0\n");
                //     for (dat_idx=0; dat_idx<(N[lay_idx]/NUM_PE*M); dat_idx++) begin
                //         for(pe_idx=0; pe_idx<NUM_PE; pe_idx++) begin
                //             $write(
                //                 "%04x ",
                //                 FCTA_DUT.BRAM_IDB[pe_idx][ADDR_IDB_A + (dat_idx << ($clog2(MAX_M) - $clog2(cfg_m)))]
                //             );
                //         end
                //         $write("\n");
                //     end
                //     // test1 = 4'b1010;
                //     // test2 = 4'b1111;
                //     // for(int i=$clog2(M)-1; i>=0; i--) begin
                //     //     test2 = {test2, test1[i]};
                //     // end
                //     // $write("test2 = %b\n", test2);
                // end
                // ########################################################################
                
                // ---------------- Forward Propagation ----------------
                for (lay_idx=1; lay_idx<=L; lay_idx++) begin
                    FCTA_proc(lay_idx, STAGE_FP);
                    // output_proc(lay_idx, STAGE_FP);     // A[l]
                end

                // ########################################################################
                // break;
                // ########################################################################

                $display("    [LOSS] ---------------- started ----------------");
                sm = '{default: 0.0};
                compute_softmax(sm, N_up[L], M);
                compute_loss(M);
                compute_dZ(N[L], M);
                // output_proc(L, STAGE_A0, 1);            // dZ[l]
                // $display("    [LOSS] ---------------- finished ----------------");
                
                // ---------------- Backward Propagation ----------------
                
                for (lay_idx=L; lay_idx>=1; lay_idx--) begin
                    if (lay_idx == L) begin
                        FCTA_proc(lay_idx, STAGE_A0, 1);
                    end else begin
                        FCTA_proc(lay_idx, STAGE_BPdZ);
                    end
                    if (lay_idx > 1) begin
                        FCTA_proc(lay_idx, STAGE_BPdA);
                    end
                    FCTA_proc(lay_idx, STAGE_BPdW);
                    // output_proc(lay_idx, STAGE_BPdW);    // dW[l]
                    FCTA_proc(lay_idx, STAGE_PU);
                    // output_proc(lay_idx, STAGE_PU);      // W[l]
                end

                // $display("[E%03d B%04d] ================ FINISHED ================", epo_idx, bat_idx);

            end

        end

        s_axis_cfg_tvalid = 1'b0;

        for (lay_idx=1; lay_idx<=L; lay_idx++) begin
            output_proc(lay_idx, STAGE_PU);      // W[l]
        end

        $stop;
        
    end


    
endmodule
