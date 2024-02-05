
`timescale 1ps/1ps
`default_nettype none

// Pad 0s to BRAM address LSB
module bram_address_pad_v0_0_core #(
///////////////////////////////////////////////////////////////////////////////
// Parameter Definitions
///////////////////////////////////////////////////////////////////////////////
    // Parameters of BRAM Master Interface BRAM
    parameter C_BRAM_ADDR_WIDTH     = 32,
    parameter C_BRAM_DATA_WIDTH     = 256,
    parameter C_BRAM_ADDR_PAD_WIDTH = 5
) (
///////////////////////////////////////////////////////////////////////////////
// Port Declarations
///////////////////////////////////////////////////////////////////////////////
    // Ports of BRAM Slave Interface S_BRAM
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM CLK" *)
    (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL,MEM_ECC NONE,MEM_WIDTH 256,MEM_SIZE 1024,READ_WRITE_MODE READ_WRITE" *)
    input  wire                                 s_bram_clk,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM RST" *)
    input  wire                                 s_bram_rst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM ADDR" *)
    input  wire [C_BRAM_ADDR_WIDTH-1 : 0]       s_bram_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM DIN" *)
    input  wire [C_BRAM_DATA_WIDTH-1 : 0]       s_bram_din,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM DOUT" *)
    output wire [C_BRAM_DATA_WIDTH-1 : 0]       s_bram_dout,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM EN" *)
    input  wire                                 s_bram_en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM WE" *)
    input  wire [(C_BRAM_DATA_WIDTH/8)-1 : 0]   s_bram_we,

    // Ports of BRAM Master Interface M_BRAM
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 M_BRAM CLK" *)
    (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL,MEM_ECC NONE,MEM_WIDTH 256,MEM_SIZE 1024,READ_WRITE_MODE READ_WRITE" *)
    output wire                                 m_bram_clk,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 M_BRAM RST" *)
    output wire                                 m_bram_rst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 M_BRAM ADDR" *)
    output wire [C_BRAM_ADDR_WIDTH + C_BRAM_ADDR_PAD_WIDTH - 1 : 0] m_bram_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 M_BRAM DIN" *)
    output wire [C_BRAM_DATA_WIDTH-1 : 0]       m_bram_din,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 M_BRAM DOUT" *)
    input  wire [C_BRAM_DATA_WIDTH-1 : 0]       m_bram_dout,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 M_BRAM EN" *)
    output wire                                 m_bram_en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 M_BRAM WE" *)
    output wire [(C_BRAM_DATA_WIDTH/8)-1 : 0]   m_bram_we

);

////////////////////////////////////////////////////////////////////////////////
// Wires/Reg declarations
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// BEGIN RTL
////////////////////////////////////////////////////////////////////////////////

    assign m_bram_clk   = s_bram_clk;
    assign m_bram_rst   = s_bram_rst;
    assign m_bram_addr  = {s_bram_addr, {C_BRAM_ADDR_PAD_WIDTH{1'b0}}};
    assign m_bram_din   = s_bram_din;
    assign s_bram_dout  = m_bram_dout;
    assign m_bram_en    = s_bram_en;
    assign m_bram_we    = s_bram_we;

endmodule // bram_address_pad_top

`default_nettype wire
