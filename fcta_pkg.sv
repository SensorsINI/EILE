
`ifndef DEF_PKG
`define DEF_PKG

package definesPkg;

    localparam STAGE_BW = 3;
    
    typedef enum logic [STAGE_BW-1:0] { STAGE_IDLE,
                                        STAGE_A0,
                                        STAGE_FP,
                                        STAGE_SOFTMAX,
                                        STAGE_BPdZ,
                                        STAGE_BPdA,
                                        STAGE_BPdW,
                                        STAGE_PU} stage_t;
    
endpackage

`endif
