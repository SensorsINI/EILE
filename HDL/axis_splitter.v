
`timescale 1ps/1ps
`default_nettype none

module axis_splitter_v0_0_core #(
///////////////////////////////////////////////////////////////////////////////
// Parameter Definitions
///////////////////////////////////////////////////////////////////////////////
    parameter integer C_S_AXIS_TDATA_WIDTH      = 240,
    parameter integer C_NUM_MI_SLOTS            = 3,
    parameter integer C_M00_AXIS_TDATA_WIDTH    = 96,
    parameter integer C_M01_AXIS_TDATA_WIDTH    = 72,
    parameter integer C_M02_AXIS_TDATA_WIDTH    = 72,
    parameter integer C_M00_AXIS_TDATA_LSB      = 0,
    parameter integer C_M01_AXIS_TDATA_LSB      = 96,
    parameter integer C_M02_AXIS_TDATA_LSB      = 168
) (
///////////////////////////////////////////////////////////////////////////////
// Port Declarations
///////////////////////////////////////////////////////////////////////////////
    // System Signals
    input  wire                                 aclk,
    input  wire                                 aresetn,

    // Slave side
    input  wire                                 s_axis_tvalid,
    output wire                                 s_axis_tready,
    input  wire [C_S_AXIS_TDATA_WIDTH-1:0]      s_axis_tdata,

    // Master side
    output wire                                 m00_axis_tvalid,
    input  wire                                 m00_axis_tready,
    output wire [C_M00_AXIS_TDATA_WIDTH-1:0]    m00_axis_tdata,

    output wire                                 m01_axis_tvalid,
    input  wire                                 m01_axis_tready,
    output wire [C_M01_AXIS_TDATA_WIDTH-1:0]    m01_axis_tdata,

    output wire                                 m02_axis_tvalid,
    input  wire                                 m02_axis_tready,
    output wire [C_M02_AXIS_TDATA_WIDTH-1:0]    m02_axis_tdata
);

////////////////////////////////////////////////////////////////////////////////
// Wires/Reg declarations
////////////////////////////////////////////////////////////////////////////////
    wire                                        s_axis_tvalid_i;
    wire [C_NUM_MI_SLOTS-1:0]                   m_axis_tvalid;
    wire [C_NUM_MI_SLOTS-1:0]                   m_axis_tready;

////////////////////////////////////////////////////////////////////////////////
// BEGIN RTL
////////////////////////////////////////////////////////////////////////////////
    reg  [C_NUM_MI_SLOTS-1:0]                   m_ready_d;

    always @(posedge aclk) begin
        if (!aresetn) begin
            m_ready_d <= {C_NUM_MI_SLOTS{1'b0}};
        end else begin
            if (s_axis_tready) begin
                m_ready_d <= {C_NUM_MI_SLOTS{1'b0}};
            end else begin
                m_ready_d <= m_ready_d | (m_axis_tvalid & m_axis_tready);
            end
        end
    end

    assign s_axis_tready = (&(m_ready_d | m_axis_tready) & aresetn);
    assign s_axis_tvalid_i = (s_axis_tvalid & aresetn);
    assign m_axis_tvalid = {C_NUM_MI_SLOTS{s_axis_tvalid_i}} & ~m_ready_d;

    assign m_axis_tready = {m02_axis_tready, m01_axis_tready, m00_axis_tready};
    assign {m02_axis_tvalid, m01_axis_tvalid, m00_axis_tvalid} = m_axis_tvalid;

    assign m00_axis_tdata = s_axis_tdata[C_M00_AXIS_TDATA_LSB+:C_M00_AXIS_TDATA_WIDTH];
    assign m01_axis_tdata = s_axis_tdata[C_M01_AXIS_TDATA_LSB+:C_M01_AXIS_TDATA_WIDTH];
    assign m02_axis_tdata = s_axis_tdata[C_M02_AXIS_TDATA_LSB+:C_M02_AXIS_TDATA_WIDTH];

endmodule // axis_splitter_top

`default_nettype wire
