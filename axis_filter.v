
`timescale 1ps/1ps
`default_nettype none

module axis_filter_v0_0_core #(
///////////////////////////////////////////////////////////////////////////////
// Parameter Definitions
///////////////////////////////////////////////////////////////////////////////
    parameter integer C_AXIS_TDATA_WIDTH    = 96,
    parameter         C_FILTER_MASK         = 'h800000000000000000000000,
    parameter         C_FILTER_VALUE        = 'h800000000000000000000000
) (
///////////////////////////////////////////////////////////////////////////////
// Port Declarations
///////////////////////////////////////////////////////////////////////////////
    // System Signals
    input  wire                             aclk,
    input  wire                             aresetn,

    // Slave side
    input  wire                             s_axis_tvalid,
    output wire                             s_axis_tready,
    input  wire [C_AXIS_TDATA_WIDTH-1:0]    s_axis_tdata,

    // Master side
    output reg                              m_axis_tvalid,
    input  wire                             m_axis_tready,
    output reg  [C_AXIS_TDATA_WIDTH-1:0]    m_axis_tdata
);

////////////////////////////////////////////////////////////////////////////////
// Wires/Reg declarations
////////////////////////////////////////////////////////////////////////////////
    // wire                                    m_axis_tready_eff;
    wire                                    f_filter;

////////////////////////////////////////////////////////////////////////////////
// BEGIN RTL
////////////////////////////////////////////////////////////////////////////////
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tdata <= {C_AXIS_TDATA_WIDTH{1'b0}};
        end else if (m_axis_tready && !f_filter && s_axis_tvalid) begin
            m_axis_tdata <= s_axis_tdata;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tvalid <= 1'b0;
        end else if (m_axis_tready) begin
            m_axis_tvalid <= s_axis_tvalid && !f_filter;
        end
    end

    // assign m_axis_tready_eff = m_axis_tready || !m_axis_tvalid;

    assign f_filter = (s_axis_tdata & C_FILTER_MASK) == (C_FILTER_VALUE & C_FILTER_MASK);

    assign s_axis_tready = m_axis_tready;

endmodule // axis_filter_top

`default_nettype wire
