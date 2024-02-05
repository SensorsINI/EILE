
`timescale 1 ns / 1 ps

module FCTA_CTL #
(
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
    parameter AXI_DM_STS_WIDTH  = 8,

    // Parameters of AXIS Master Bus Interface M_AXIS_CMD
    localparam C_M_AXIS_CMD_DATA_WIDTH = CFG_BW+AXI_DM_CMD_WIDTH*2,

    localparam CNT_BW           = 16

) (

    input  logic                                clk,
    input  logic                                rstn,

    // Ports of AXILite Slave Bus Interface S_AXI
    input  logic [C_S_AXI_ADDR_WIDTH-1 : 0]     s_axi_awaddr,
    input  logic [2 : 0]                        s_axi_awprot,
    input  logic                                s_axi_awvalid,
    output logic                                s_axi_awready,
    input  logic [C_S_AXI_DATA_WIDTH-1 : 0]     s_axi_wdata,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1 : 0] s_axi_wstrb,
    input  logic                                s_axi_wvalid,
    output logic                                s_axi_wready,
    output logic [1 : 0]                        s_axi_bresp,
    output logic                                s_axi_bvalid,
    input  logic                                s_axi_bready,
    input  logic [C_S_AXI_ADDR_WIDTH-1 : 0]     s_axi_araddr,
    input  logic [2 : 0]                        s_axi_arprot,
    input  logic                                s_axi_arvalid,
    output logic                                s_axi_arready,
    output logic [C_S_AXI_DATA_WIDTH-1 : 0]     s_axi_rdata,
    output logic [1 : 0]                        s_axi_rresp,
    output logic                                s_axi_rvalid,
    input  logic                                s_axi_rready,

    // Ports of BRAM Master Interface BRAM
    output logic                                bram_clkb,
    output logic                                bram_rstb,
    output logic [C_BRAM_ADDR_WIDTH-1 : 0]      bram_addrb,
    output logic [C_BRAM_DATA_WIDTH-1 : 0]      bram_dinb,
    input  logic [C_BRAM_DATA_WIDTH-1 : 0]      bram_doutb,
    output logic                                bram_enb,
    output logic [(C_BRAM_DATA_WIDTH/8)-1 : 0]  bram_web,

    // // Ports of AXIS Master Bus Interface M_AXIS_FCTA_CFG
    // output logic                                m_axis_fcta_cfg_tvalid,
    // output logic                                m_axis_fcta_cfg_tlast,
    // output logic [CFG_BW-1 : 0]                 m_axis_fcta_cfg_tdata,
    // input  logic                                m_axis_fcta_cfg_tready,

    // // Ports of AXIS Master Bus Interface M_AXIS_MM2S_CMD
    // output logic                                m_axis_mm2s_cmd_tvalid,
    // output logic [AXI_DM_CMD_WIDTH-1 : 0]       m_axis_mm2s_cmd_tdata,
    // input  logic                                m_axis_mm2s_cmd_tready,

    // // Ports of AXIS Master Bus Interface M_AXIS_S2MM_CMD
    // output logic                                m_axis_s2mm_cmd_tvalid,
    // output logic [AXI_DM_CMD_WIDTH-1 : 0]       m_axis_s2mm_cmd_tdata,
    // input  logic                                m_axis_s2mm_cmd_tready,

    // Ports of AXIS Master Bus Interface M_AXIS_CMD
    output logic                                m_axis_cmd_tvalid,
    output logic [C_M_AXIS_CMD_DATA_WIDTH-1 : 0] m_axis_cmd_tdata,
    input  logic                                m_axis_cmd_tready,

    // Ports of AXIS Slave Bus Interface S_AXIS_MM2S_STS
    input  logic                                s_axis_mm2s_sts_tvalid,
    input  logic                                s_axis_mm2s_sts_tlast,
    input  logic [AXI_DM_STS_WIDTH-1 : 0]       s_axis_mm2s_sts_tdata,
    output logic                                s_axis_mm2s_sts_tready,

    // Ports of AXIS Slave Bus Interface S_AXIS_S2MM_STS
    input  logic                                s_axis_s2mm_sts_tvalid,
    input  logic                                s_axis_s2mm_sts_tlast,
    input  logic [AXI_DM_STS_WIDTH-1 : 0]       s_axis_s2mm_sts_tdata,
    output logic                                s_axis_s2mm_sts_tready

    // // Ports of AXIS Slave Bus Interface S_AXIS_STS
    // input  logic                                s_axis_sts_tvalid,
    // input  logic                                s_axis_sts_tlast,
    // input  logic [AXI_DM_STS_WIDTH-1 : 0]       s_axis_sts_tdata,
    // output logic                                s_axis_sts_tready

);

    // Global Signals

    // FSM - states
    (* mark_debug = "true" *)
    enum logic [1:0] {  S_IDLE,
                        S_STRM,
                        S_PAUS,
                        S_WAIT  }               state;
    
    (* mark_debug = "true" *)
    logic [0:1]                                 f_I;
    (* mark_debug = "true" *)
    logic                                       f_O;

    logic                                       en_sts_mm2s;
    logic                                       en_sts_s2mm;

    // Counters
    (* mark_debug = "true" *)
    logic [CNT_BW-1:0]                          cnt_rpt;
    (* mark_debug = "true" *)
    logic [CNT_BW-1:0]                          cnt_cmd;
    // logic [CNT_BW-1:0]                          cnt_cmd_s2mm; // cannot count cmd_s2mm before CMD(.MASK) is read
    logic [CNT_BW-1:0]                          cnt_rpt_d;
    logic [CNT_BW-1:0]                          cnt_cmd_mm2s_d;
    logic [CNT_BW-1:0]                          cnt_cmd_s2mm_d;
    logic [CNT_BW-1:0]                          cnt_cmd_mm2s_sv;
    logic [CNT_BW-1:0]                          cnt_cmd_s2mm_sv;
    logic [CNT_BW-1:0]                          cnt_rpt_mm2s;
    logic [CNT_BW-1:0]                          cnt_sts_mm2s;
    logic [CNT_BW-1:0]                          cnt_rpt_s2mm;
    logic [CNT_BW-1:0]                          cnt_sts_s2mm;

    logic                                       f_cnt_cmd_rp;
    logic                                       f_cnt_rpt_cmd;
    logic                                       f_cnt_rpt_cmd_r;
    logic                                       f_cnt_rpt_cmd_rp;

    logic                                       f_cnt_rpt_sts;
    logic                                       f_cnt_rpt_sts_mm2s;
    logic                                       f_cnt_rpt_sts_mm2s_r;
    logic                                       f_cnt_rpt_sts_s2mm;
    logic                                       f_cnt_rpt_sts_s2mm_r;

    logic                                       f_cnt_sts_sv;
    logic                                       f_cnt_sts_mm2s_sv;
    logic                                       f_cnt_sts_mm2s_sv_r;
    logic                                       f_cnt_sts_s2mm_sv;
    logic                                       f_cnt_sts_s2mm_sv_r;

    // Control Registers
    //          REG_START
    // ┌───────┬────────┬─────────┐
    // │  31   │   30   │  29:0   │
    // ├───────┼────────┼─────────┤
    // │ START │ RESUME │    -    │
    // └───────┴────────┴─────────┘
    //                      REG_STATUS
    // ┌───────┬────────┬─────────┬──────────┬──────────┐
    // │  31   │   30   │  29:16  │   15:8   │   7:0    │
    // ├───────┼────────┼─────────┼──────────┼──────────┤
    // │  END  │ PAUSED │    -    │ S2MM_STS │ MM2S_STS │
    // └───────┴────────┴─────────┴──────────┴──────────┘
    logic [C_S_AXI_DATA_WIDTH-1:0]              reg_start;
    logic [C_S_AXI_DATA_WIDTH-1:0]              reg_num_cmd;
    logic [C_S_AXI_DATA_WIDTH-1:0]              reg_num_rpt;
    logic [C_S_AXI_DATA_WIDTH-1:0]              reg_rsv3;
    logic [C_S_AXI_DATA_WIDTH-1:0]              reg_rpt_cur;
    logic [C_S_AXI_DATA_WIDTH-1:0]              reg_cmd_cur;
    logic [C_S_AXI_DATA_WIDTH-1:0]              reg_sts_cur;
    logic [C_S_AXI_DATA_WIDTH-1:0]              reg_status;

    logic [CNT_BW-1:0]                          num_cmd;
    logic [CNT_BW-1:0]                          num_cmd_s2mm;

    logic                                       ctl_start;
    logic                                       ctl_start_r;
    logic                                       ctl_start_re;
    logic                                       ctl_resume;
    logic                                       ctl_resume_r;
    logic                                       ctl_resume_re;

    // logic [C_BRAM_DATA_WIDTH-1:0]               ctl_command;
    // logic [CFG_BW-1:0]                          fcta_cfg;
    // logic [AXI_DM_CMD_WIDTH-1:0]                mm2s_cmd;
    // logic [AXI_DM_CMD_WIDTH-1:0]                s2mm_cmd;
    logic [2:0]                                 ctl_mask;
    logic                                       ctl_barrier;
    logic                                       ctl_pause;

    logic                                       ctl_paused;
    logic                                       ctl_end;

    // logic [AXI_DM_STS_WIDTH-1:0]                mm2s_sts;
    // logic                                       mm2s_okay;
    logic                                       sts_mm2s_err;
    // logic [AXI_DM_STS_WIDTH-1:0]                s2mm_sts;
    // logic                                       s2mm_okay;
    logic                                       sts_s2mm_err;

    logic                                       bram_enb_i;
    logic [0:1]                                 bram_enb_r;
    logic                                       bram_enb_rp;



    // FSM
    always_ff @(posedge clk) begin
        if (!rstn) begin
            state <= S_IDLE;
        end else begin
            case (state)
                S_IDLE : begin
                    if (ctl_start_re) begin
                        state <= S_STRM;
                    end
                end
                S_STRM : begin
                    if (sts_mm2s_err || sts_s2mm_err) begin
                        state <= S_IDLE;
                    end else if (f_cnt_rpt_cmd_r && m_axis_cmd_tready) begin // && bram_enb_r[1]
                        state <= S_WAIT;
                    end else if ((ctl_barrier || ctl_pause) && m_axis_cmd_tvalid && m_axis_cmd_tready) begin
                        state <= S_WAIT;
                    end
                end
                S_WAIT : begin
                    if (sts_mm2s_err || sts_s2mm_err) begin
                        state <= S_IDLE;
                    end else if (f_cnt_rpt_sts) begin // && (s_axis_mm2s_sts_tvalid || s_axis_s2mm_sts_tvalid)
                        state <= S_IDLE;
                    end else if (f_cnt_sts_sv && ctl_pause) begin
                        state <= S_PAUS;
                    end else if (f_cnt_sts_sv) begin // &&! ctl_pause
                        state <= S_STRM;
                    end
                end
                S_PAUS : begin
                    if (ctl_resume_re) begin
                        state <= S_STRM;
                    end
                end
                default : begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
    


    always_ff @(posedge clk) begin
        if (!rstn) begin
            f_I[0] <= 1'b0;
        end else begin
            case (state)
                S_IDLE : begin
                    if (ctl_start_re) begin
                        f_I[0] <= 1'b1;
                    end
                end
                S_STRM : begin
                    if (f_cnt_rpt_cmd && m_axis_cmd_tready) begin // bram_enb
                        f_I[0] <= 1'b0;
                    end else if ((ctl_barrier || ctl_pause) && m_axis_cmd_tvalid && m_axis_cmd_tready) begin
                        f_I[0] <= 1'b0;
                    end
                end
                S_WAIT : begin
                    if (f_cnt_sts_sv && !ctl_pause) begin
                        f_I[0] <= 1'b1;
                    end
                end
                S_PAUS : begin
                    if (ctl_resume_re) begin
                        f_I[0] <= 1'b1;
                    end
                end
                default : begin
                    f_I[0] <= 1'b0;
                end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            f_I[1] <= 1'b0;
        end else if ((f_I[0] && bram_enb_r[0] && m_axis_cmd_tready) ||
                     (f_I[1] && bram_enb_r[1] && m_axis_cmd_tready)   ) begin // && m_axis_cmd_tvalid
            f_I[1] <= f_I[0];
        end
    end
    


    always_ff @(posedge clk) begin
        if (!rstn) begin
            f_O <= 1'b0;
        end else begin
            case (state)
                S_STRM : begin
                    if (bram_enb_i) begin // (f_I[0] && bram_enb)
                        f_O <= 1'b1;
                    end else if (f_cnt_rpt_cmd_r && m_axis_cmd_tready) begin // && !bram_enb
                        f_O <= 1'b0;
                    end else if ((ctl_barrier || ctl_pause) && m_axis_cmd_tvalid && m_axis_cmd_tready) begin
                        f_O <= 1'b0;
                    end
                end
                default : begin
                    f_O <= 1'b0;
                end
            endcase
        end
    end



    assign ctl_start = reg_start[31] && (state == S_IDLE);

    always_ff @(posedge clk) begin
        if (!rstn) begin
            ctl_start_r <= 1'b0;
        end else begin
            ctl_start_r <= ctl_start;
        end
    end

    assign ctl_start_re = (ctl_start_r == 0) && (ctl_start == 1);



    assign ctl_resume = reg_start[30] && (state == S_PAUS);

    always_ff @(posedge clk) begin
        if (!rstn) begin
            ctl_resume_r <= 1'b0;
        end else begin
            ctl_resume_r <= ctl_resume;
        end
    end

    assign ctl_resume_re = (ctl_resume_r == 0) && (ctl_resume == 1);



    assign reg_status[30] = ctl_paused;

    always_ff @(posedge clk) begin
        if (!rstn) begin
            ctl_paused <= 1'b1;
        end else begin
            case (state)
                S_IDLE : begin
                    if (ctl_start_re) begin
                        ctl_paused <= 1'b0;
                    end
                end
                S_WAIT : begin
                    if (ctl_pause && f_cnt_sts_sv) begin
                        ctl_paused <= 1'b1;
                    end
                end
                S_PAUS : begin
                    if (ctl_resume_re) begin
                        ctl_paused <= 1'b0;
                    end
                end
                default : begin
                    ctl_paused <= ctl_paused;
                end
            endcase
        end
    end



    assign reg_status[31] = ctl_end;

    always_ff @(posedge clk) begin
        if (!rstn) begin
            ctl_end <= 1'b1;
        end else begin
            case (state)
                S_IDLE : begin
                    if (ctl_start_re) begin
                        ctl_end <= 1'b0;
                    end
                end
                S_STRM : begin
                    if (sts_mm2s_err || sts_s2mm_err) begin
                        ctl_end <= 1'b1;
                    end
                end
                S_WAIT : begin
                    if (sts_mm2s_err || sts_s2mm_err) begin
                        ctl_end <= 1'b1;
                    end else if (f_cnt_rpt_sts) begin
                        ctl_end <= 1'b1;
                    end
                end
                default : begin
                    ctl_end <= ctl_end;
                end
            endcase
        end
    end



    assign sts_mm2s_err = (reg_status[4 +: 3] != 3'b000);
    assign sts_s2mm_err = (reg_status[AXI_DM_STS_WIDTH+4 +: 3] != 3'b000);



    CTL_REG # ( 
        .C_S_AXI_DATA_WIDTH (C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH (C_S_AXI_ADDR_WIDTH)
    ) CTL_REG_inst (
        .ctl_reg0           (reg_start),
        .ctl_reg1           (reg_num_cmd),
        .ctl_reg2           (reg_num_rpt),
        .ctl_reg3           (reg_rsv3),
        .ctl_reg4           (reg_rpt_cur),
        .ctl_reg5           (reg_cmd_cur),
        .ctl_reg6           (reg_sts_cur),
        .ctl_reg7           (reg_status),
        .S_AXI_ACLK         (clk),
        .S_AXI_ARESETN      (rstn),
        .S_AXI_AWADDR       (s_axi_awaddr),
        .S_AXI_AWPROT       (s_axi_awprot),
        .S_AXI_AWVALID      (s_axi_awvalid),
        .S_AXI_AWREADY      (s_axi_awready),
        .S_AXI_WDATA        (s_axi_wdata),
        .S_AXI_WSTRB        (s_axi_wstrb),
        .S_AXI_WVALID       (s_axi_wvalid),
        .S_AXI_WREADY       (s_axi_wready),
        .S_AXI_BRESP        (s_axi_bresp),
        .S_AXI_BVALID       (s_axi_bvalid),
        .S_AXI_BREADY       (s_axi_bready),
        .S_AXI_ARADDR       (s_axi_araddr),
        .S_AXI_ARPROT       (s_axi_arprot),
        .S_AXI_ARVALID      (s_axi_arvalid),
        .S_AXI_ARREADY      (s_axi_arready),
        .S_AXI_RDATA        (s_axi_rdata),
        .S_AXI_RRESP        (s_axi_rresp),
        .S_AXI_RVALID       (s_axi_rvalid),
        .S_AXI_RREADY       (s_axi_rready)
    );
 
    assign num_cmd      = reg_num_cmd[0 +: CNT_BW];
    assign num_cmd_s2mm = reg_num_cmd[CNT_BW +: CNT_BW];




    assign reg_rpt_cur = cnt_rpt;
    assign reg_cmd_cur = cnt_cmd;

    always_ff @(posedge clk) begin
        if (!rstn) begin
            cnt_cmd <= 0;
            cnt_rpt <= 0;
        end else if (bram_enb) begin
            if (cnt_cmd + 0 == num_cmd) begin
                if (cnt_rpt + 0 == reg_num_rpt) begin
                    cnt_rpt <= 0;
                end else begin
                    cnt_rpt <= cnt_rpt + 1;
                end
                cnt_cmd <= 0;
            end else begin
                cnt_cmd <= cnt_cmd + 1;
            end
        end
    end

    assign f_cnt_rpt_cmd = (cnt_cmd + 0 == num_cmd) && (cnt_rpt + 0 == reg_num_rpt);

    always_ff @(posedge clk) begin
        if (!rstn) begin
            f_cnt_rpt_cmd_r <= 1'b0;
        // end else if ((f_I[0] && bram_enb_r[0] && m_axis_cmd_tready) ||
        //              (f_I[1] && bram_enb_r[1] && m_axis_cmd_tready)   ) begin
        end else if (f_I[0:1] && m_axis_cmd_tready) begin // && m_axis_cmd_tvalid
            f_cnt_rpt_cmd_r <= f_cnt_rpt_cmd; // && f_I[0];
        end
    end
    


    assign bram_clkb = clk;
    assign bram_rstb = ~rstn;   // 1'b0
    assign bram_dinb = {C_BRAM_DATA_WIDTH{1'b0}};       // Read Only
    assign bram_web  = {(C_BRAM_DATA_WIDTH/8){1'b0}};

    assign bram_addrb = cnt_cmd;

    always_ff @(posedge clk) begin
        if (!rstn || bram_enb_i) begin
            bram_enb_i <= 1'b0;
        end else if (ctl_start_re || ctl_resume_re || (f_cnt_sts_sv && !ctl_pause)) begin
            bram_enb_i <= 1'b1;
        end
    end

    assign bram_enb = bram_enb_i || (f_I[0] && !(ctl_barrier || ctl_pause) && m_axis_cmd_tready);

    assign bram_enb_r[0] = bram_enb_i || f_I[0];

    always_ff @(posedge clk) begin
        if (!rstn) begin
            bram_enb_r[1] <= 1'b0;
        end else if (f_I[0:1] && m_axis_cmd_tready) begin // && m_axis_cmd_tvalid
            bram_enb_r[1] <= bram_enb_r[0] && f_I[0];
        end
    end
    


    assign m_axis_cmd_tdata = bram_doutb[0 +: C_M_AXIS_CMD_DATA_WIDTH];
    
    // always_ff @(posedge clk) begin
    //     if (!rstn) begin
    //         m_axis_cmd_tvalid <= 1'b0;
    //     end else begin
    //         if (!m_axis_cmd_tvalid && f_I[0]) begin
    //             m_axis_cmd_tvalid <= 1'b1;
    //         end else if (m_axis_cmd_tvalid && m_axis_cmd_tready && !f_I[0]) begin
    //             m_axis_cmd_tvalid <= 1'b0;
    //         end
    //     end
    // end
    assign m_axis_cmd_tvalid = f_O;



    assign reg_sts_cur[0 +: CNT_BW] = cnt_sts_mm2s;

    always_ff @(posedge clk) begin
        if (!rstn) begin
            cnt_sts_mm2s <= 0;
            cnt_rpt_mm2s <= 0;
        end else if (en_sts_mm2s) begin
            if (cnt_sts_mm2s + 0 == num_cmd) begin
                if (cnt_rpt_mm2s + 0 == reg_num_rpt) begin
                    cnt_rpt_mm2s <= 0;
                end else begin
                    cnt_rpt_mm2s <= cnt_rpt_mm2s + 1;
                end
                cnt_sts_mm2s <= 0;
            end else begin
                cnt_sts_mm2s <= cnt_sts_mm2s + 1;
            end
        end
    end

    assign f_cnt_rpt_sts_mm2s = (cnt_sts_mm2s + 0 == num_cmd) && (cnt_rpt_mm2s + 0 == reg_num_rpt);

    assign en_sts_mm2s = s_axis_mm2s_sts_tvalid && s_axis_mm2s_sts_tready;

    // assign s_axis_mm2s_sts_tready = 1'b1;
    // ? Deassert when (cnt_sts_mm2s == cnt_cmd)
    assign s_axis_mm2s_sts_tready = state inside {S_STRM, S_WAIT}; // && !f_cnt_rpt_sts_mm2s_r
    // always_ff @(posedge clk) begin
    //     if (!rstn || state == S_IDLE) begin
    //         s_axis_mm2s_sts_tready <= 1'b0;
    //     end else if (state inside {S_STRM}) begin
    //         s_axis_mm2s_sts_tready <= 1'b1;
    //     end
    // end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            reg_status[0 +: AXI_DM_STS_WIDTH] <= '0;
        end else if (en_sts_mm2s) begin
            reg_status[0 +: AXI_DM_STS_WIDTH] <= s_axis_mm2s_sts_tdata;
        end
    end



    assign reg_sts_cur[CNT_BW +: CNT_BW] = cnt_sts_s2mm;

    always_ff @(posedge clk) begin
        if (!rstn) begin
            cnt_sts_s2mm <= 0;
            cnt_rpt_s2mm <= 0;
        end else if (en_sts_s2mm) begin
            if (cnt_sts_s2mm + 0 == num_cmd_s2mm) begin
                if (cnt_rpt_s2mm + 0 == reg_num_rpt) begin
                    cnt_rpt_s2mm <= 0;
                end else begin
                    cnt_rpt_s2mm <= cnt_rpt_s2mm + 1;
                end
                cnt_sts_s2mm <= 0;
            end else begin
                cnt_sts_s2mm <= cnt_sts_s2mm + 1;
            end
        end
    end

    assign f_cnt_rpt_sts_s2mm = (cnt_sts_s2mm + 0 == num_cmd_s2mm) && (cnt_rpt_s2mm + 0 == reg_num_rpt);

    assign en_sts_s2mm = s_axis_s2mm_sts_tvalid && s_axis_s2mm_sts_tready;

    // assign s_axis_s2mm_sts_tready = 1'b1;
    // ? Deassert when (cnt_sts_s2mm == cnt_cmd)
    assign s_axis_s2mm_sts_tready = state inside {S_STRM, S_WAIT}; // && !f_cnt_rpt_sts_s2mm_r
    // always_ff @(posedge clk) begin
    //     if (!rstn || state == S_IDLE) begin
    //         s_axis_s2mm_sts_tready <= 1'b0;
    //     end else if (state inside {S_STRM}) begin
    //         s_axis_s2mm_sts_tready <= 1'b1;
    //     end
    // end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            reg_status[AXI_DM_STS_WIDTH +: AXI_DM_STS_WIDTH] <= '0;
        end else if (en_sts_s2mm) begin
            reg_status[AXI_DM_STS_WIDTH +: AXI_DM_STS_WIDTH] <= s_axis_s2mm_sts_tdata;
        end
    end



    always_ff @(posedge clk) begin
        if (!rstn || f_cnt_rpt_sts) begin
            f_cnt_rpt_sts_mm2s_r <= 1'b0;
        end else if (en_sts_mm2s && f_cnt_rpt_sts_mm2s) begin
            f_cnt_rpt_sts_mm2s_r <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn || f_cnt_rpt_sts) begin
            f_cnt_rpt_sts_s2mm_r <= 1'b0;
        end else if (en_sts_s2mm && f_cnt_rpt_sts_s2mm) begin
            f_cnt_rpt_sts_s2mm_r <= 1'b1;
        end
    end

    assign f_cnt_rpt_sts = (((f_cnt_rpt_sts_mm2s && s_axis_mm2s_sts_tvalid) || f_cnt_rpt_sts_mm2s_r) &&
                            ((f_cnt_rpt_sts_s2mm && s_axis_s2mm_sts_tvalid) || f_cnt_rpt_sts_s2mm_r));



    assign ctl_mask = bram_doutb[C_M_AXIS_CMD_DATA_WIDTH +: 3];

    always_ff @(posedge clk) begin
        if (!rstn) begin
            bram_enb_rp <= 1'b0;
        end else if (bram_enb) begin
            bram_enb_rp <= 1'b1;
        end else if (bram_enb_rp) begin
            bram_enb_rp <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn || f_cnt_rpt_cmd_rp) begin
            f_cnt_rpt_cmd_rp <= 1'b0;
        end else if (bram_enb && f_cnt_rpt_cmd) begin
            f_cnt_rpt_cmd_rp <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn || f_cnt_rpt_cmd_rp) begin            // ? || state == S_IDLE
            cnt_rpt_d <= 0;
        end else if (bram_enb_rp && f_cnt_cmd_rp) begin
            cnt_rpt_d <= cnt_rpt_d + 1;
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn || f_cnt_cmd_rp) begin
            f_cnt_cmd_rp <= 1'b0;
        end else if (bram_enb && (cnt_cmd + 0 == num_cmd)) begin
            f_cnt_cmd_rp <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn || f_cnt_cmd_rp) begin                // ? || state == S_IDLE
            cnt_cmd_mm2s_d <= 0;
        end else if (bram_enb_rp && ctl_mask[1]) begin
            cnt_cmd_mm2s_d <= cnt_cmd_mm2s_d + 1;
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn || f_cnt_cmd_rp) begin                // ? || state == S_IDLE
            cnt_cmd_s2mm_d <= 0;
        end else if (bram_enb_rp && ctl_mask[2]) begin
            if (cnt_cmd_s2mm_d + 0 == num_cmd_s2mm) begin
                // cnt_cmd_s2mm_d <= 0;                 // Delay to sync with cnt_cmd_mm2s_d <= 0
            end else begin
                cnt_cmd_s2mm_d <= cnt_cmd_s2mm_d + 1;
            end
        end
    end

    assign ctl_barrier = bram_doutb[C_M_AXIS_CMD_DATA_WIDTH+3];
    assign ctl_pause = bram_doutb[C_M_AXIS_CMD_DATA_WIDTH+4];

    always_ff @(posedge clk) begin
        if (!rstn || ctl_start_re) begin
            cnt_cmd_mm2s_sv <= num_cmd;         // '1
        end else if (bram_enb_rp && (ctl_barrier || ctl_pause)) begin
            cnt_cmd_mm2s_sv <= cnt_cmd_mm2s_d;
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn || ctl_start_re) begin
            cnt_cmd_s2mm_sv <= num_cmd_s2mm;    // '1
        end else if (bram_enb_rp && (ctl_barrier || ctl_pause)) begin
            cnt_cmd_s2mm_sv <= cnt_cmd_s2mm_d;
        end
    end



    assign f_cnt_sts_mm2s_sv = (cnt_sts_mm2s + 0 == cnt_cmd_mm2s_sv); // && (cnt_rpt_mm2s + 0 == reg_num_rpt);
    assign f_cnt_sts_s2mm_sv = (cnt_sts_s2mm + 0 == cnt_cmd_s2mm_sv); // && (cnt_rpt_s2mm + 0 == reg_num_rpt);

    always_ff @(posedge clk) begin
        if (!rstn || f_cnt_sts_sv) begin
            f_cnt_sts_mm2s_sv_r <= 1'b0;
        end else if (en_sts_mm2s && f_cnt_sts_mm2s_sv) begin
            f_cnt_sts_mm2s_sv_r <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn || f_cnt_sts_sv) begin
            f_cnt_sts_s2mm_sv_r <= 1'b0;
        end else if (en_sts_s2mm && f_cnt_sts_s2mm_sv) begin
            f_cnt_sts_s2mm_sv_r <= 1'b1;
        end
    end

    assign f_cnt_sts_sv = (((f_cnt_sts_mm2s_sv && s_axis_mm2s_sts_tvalid) || f_cnt_sts_mm2s_sv_r) &&
                           ((f_cnt_sts_s2mm_sv && s_axis_s2mm_sts_tvalid) || f_cnt_sts_s2mm_sv_r));

    


endmodule
