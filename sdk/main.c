/******************************************************************************
*
* Copyright (C) 2010 - 2017 Xilinx, Inc.  All rights reserved.
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* Use of the Software is limited solely to applications:
* (a) running on a Xilinx device, or
* (b) that interact with a Xilinx device through a bus or interconnect.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
* XILINX  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
* WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
* OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*
* Except as contained in this notice, the name of the Xilinx shall not be used
* in advertising or otherwise to promote the sale, use or other dealings in
* this Software without prior written authorization from Xilinx.
*
******************************************************************************/
/*****************************************************************************/
/**
 *
 * @file xaxidma_example_simple_poll.c
 *
 * This file demonstrates how to use the xaxidma driver on the Xilinx AXI
 * DMA core (AXIDMA) to transfer packets in polling mode when the AXI DMA core
 * is configured in simple mode.
 *
 * This code assumes a loopback hardware widget is connected to the AXI DMA
 * core for data packet loopback.
 *
 * To see the debug print, you need a Uart16550 or uartlite in your system,
 * and please set "-DDEBUG" in your compiler options. You need to rebuild your
 * software executable.
 *
 * Make sure that MEMORY_BASE is defined properly as per the HW system. The
 * h/w system built in Area mode has a maximum DDR memory limit of 64MB. In
 * throughput mode, it is 512MB.  These limits are need to ensured for
 * proper operation of this code.
 *
 *
 * <pre>
 * MODIFICATION HISTORY:
 *
 * Ver   Who  Date     Changes
 * ----- ---- -------- -------------------------------------------------------
 * 4.00a rkv  02/22/11 New example created for simple DMA, this example is for
 *                 simple DMA
 * 5.00a srt  03/06/12 Added Flushing and Invalidation of Caches to fix CRs
 *             648103, 648701.
 *             Added V7 DDR Base Address to fix CR 649405.
 * 6.00a srt  03/27/12 Changed API calls to support MCDMA driver.
 * 7.00a srt  06/18/12 API calls are reverted back for backward compatibility.
 * 7.01a srt  11/02/12 Buffer sizes (Tx and Rx) are modified to meet maximum
 *             DDR memory limit of the h/w system built with Area mode
 * 7.02a srt  03/01/13 Updated DDR base address for IPI designs (CR 703656).
 * 9.1   adk  01/07/16 Updated DDR base address for Ultrascale (CR 799532) and
 *             removed the defines for S6/V6.
 * 9.3   ms   01/23/17 Modified xil_printf statement in main function to
 *                     ensure that "Successfully ran" and "Failed" strings are
 *                     available in all examples. This is a fix for CR-965028.
 *       ms   04/05/17 Modified Comment lines in functions to
 *                     recognize it as documentation block for doxygen
 *                     generation of examples.
 * </pre>
 *
 * ***************************************************************************

 */
/***************************** Include Files *********************************/
#include "platform.h"
#include "xparameters.h"
#include "xstatus.h"
#include "xdebug.h"
// #include "xaxidma.h"
// #include "xgpio.h"
#include "xtime_l.h"
#include "xil_mmu.h"
// #include "xuartps.h"
#include "xil_io.h"

#if defined(XPAR_UARTNS550_0_BASEADDR)
#include "xuartns550_l.h"       /* to use uartns550 */
#endif

#include <stdio.h>
#include "math.h"
#include "cfg_reg.h"
#include "A0.h"
#include "Y.h"
#include "W1.h"
#include "W2.h"
#include "W3.h"

/******************** Constant Definitions **********************************/

/*
 * Device hardware build related constants.
 */

// #define DMA_DEV_ID          XPAR_AXIDMA_0_DEVICE_ID
// #define GPIO_0_DEV_ID       XPAR_AXI_GPIO_0_DEVICE_ID
// #define GPIO_1_DEV_ID       XPAR_AXI_GPIO_1_DEVICE_ID
// #define UART_DEVICE_ID      XPAR_XUARTPS_0_DEVICE_ID

// #define DDR_BASE_ADDR       0x00200000  // 0x01000000
// #define MEM_BASE_ADDR       (DDR_BASE_ADDR + 0x1000000)
#define MEM_BASE_ADDR       0x80000000  // XPAR_BRAM_0_BASEADDR
#define FCTA_CTL_BASE_ADDR  0x40000000  // XPAR_FCTA_CTL_WRAPPER_0_BASEADDR
#define BRAM_CMD_BASE_ADDR  0x40008000  // XPAR_BRAM_1_BASEADDR
#define MAX_PKT_LEN         0x0001FFFF
#define XFER_TIMEOUT        0x01FFFFFF

/**************************** Type Definitions *******************************/


/***************** Macros (Inline Functions) Definitions *********************/


/************************** Function Prototypes ******************************/

#if (!defined(DEBUG))
extern void xil_printf(const char *format, ...);
#endif

// int XAxiDma_Init(void);
// int XAxiGpio_Init(void);
// int XUart_Init(void);

/************************** Variable Definitions *****************************/
/*
 * Device instance definitions
 */
// XAxiDma AxiDma;
// XGpio   AxiGpio0, AxiGpio1;
// XUartPs Uart_PS;

/*****************************************************************************/
/**
* The entry point for this example. It invokes the example function,
* and reports the execution status.
*
* @param    None.
*
* @return
*       - XST_SUCCESS if example finishes successfully
*       - XST_FAILURE if example fails.
*
* @note     None.
*
******************************************************************************/
#define             PRINT_LEVEL             2
#define             PLV_ERR                 1
#define             PLV_DOUT                0
#define             printf_lv(i, ...)       do {if (i <= PRINT_LEVEL) xil_printf(__VA_ARGS__);} while(0)

#define             TLBATTR_LENGTH          (1<<20)                 // Xil_SetTlbAttributes() applies to 1MB each call
#define             NONCACHE_START          ((UINTPTR)dZL_sw)
#define             NONCACHE_LENGTH         ((MAX_N*MAX_M)*(1)*(ACT_BW/8))
#define             NONCACHE_END            ((UINTPTR)(NONCACHE_START + NONCACHE_LENGTH))

#define             NUM_PE                  64
#define             ACT_QM                  8
#define             ACT_QN                  8
#define             ACT_BW                  (ACT_QM + ACT_QN)
#define             WEIGHT_QM               2
#define             WEIGHT_QN               14
#define             WEIGHT_BW               (WEIGHT_QM + WEIGHT_QN)
#define             MAX_N                   1024
#define             MAX_M                   32
#define             M                       1                       // Batch size
#define             L                       3                       // #Layer
#define             NUM_EPOCH               10
#define             NUM_BATCH               1000

static const int    N           [L+1]       = {  832,  512,  256,   64};    // Layer size
static const int    N_up        [L+1]       = {  784,  512,  256,   10};    // Unpadded
static const int    AF          [L+1]       = {  0b0,  0b1,  0b1,  0b0};    // Activation function
static const int    chk_num     [L+1]       = {    0,   20,    6,    1};
static const int    chk_size    [L+1]       = {    0,  314,  342,  257};    // 6280/20, 2052/6, 257/1

// __attribute__ ((aligned(32)));
// s16                 W1          [MAX_N*MAX_N]       __attribute__ ((section (".non_cacheable")));   // __attribute__ ((section ("non_cacheable"), aligned(1048576)));
// s16                 W2          [MAX_N*MAX_N]       __attribute__ ((section (".non_cacheable")));   // __attribute__ ((section ("non_cacheable"), aligned(1048576)));
// s16                 W3          [MAX_N*MAX_N]       __attribute__ ((section (".non_cacheable")));
// s16                 dW1         [MAX_N*MAX_N]       __attribute__ ((section (".non_cacheable")));
// s16                 dW2         [MAX_N*MAX_N]       __attribute__ ((section (".non_cacheable")));
// s16                 dW3         [MAX_N*MAX_N]       __attribute__ ((section (".non_cacheable")));
// s16                 A           [L+1][MAX_N*MAX_M]  __attribute__ ((section (".non_cacheable")));
s16                 dZL_sw      [MAX_N*MAX_M]       __attribute__ ((section (".non_cacheable"))); //

double              AL_fl       [10][M];
double              lse         [M];
double              softmax     [10][M];
double              loss_exa    [M];
double              loss_bat    ;
double              dZL_fl      [10][M];

#define             W_BYTES(i)              (N[i]*(N_up[i-1]+1)*WEIGHT_BW/8)
#define             dW_BYTES(i)             (N[i]*(N_up[i-1]+1)*WEIGHT_BW/8)
#define             W_NB_BYTES(i)           (N[i]*(N_up[i-1])*WEIGHT_BW/8)     // w/o bias
#define             W_CHK_BYTES(i)          (chk_size[i]*NUM_PE*WEIGHT_BW/8)
#define             dW_CHK_BYTES(i)         (chk_size[i]*NUM_PE*WEIGHT_BW/8)
#define             A_BYTES(i)              (N[i]*M*ACT_BW/8)
#define             dZ_BYTES(i)             (N[i]*M*WEIGHT_BW/8)

static const s16*   W_i         [L+1]       = {    0, W1_i, W2_i, W3_i};
s16*                W           [L+1]       = {0};
s16*                dW          [L+1]       = {0};
s16*                A           [L+1]       = {0};
s16*                dZ          [L+1]       = {0};

#define             STAGE_IDLE              0b000
#define             STAGE_A0                0b001
#define             STAGE_FP                0b010
#define             STAGE_SOFTMAX           0b011
#define             STAGE_BPdZ              0b100
#define             STAGE_BPdA              0b101
#define             STAGE_BPdW              0b110
#define             STAGE_PU                0b111
// static const char*  stage_name  [8]         = {"STAGE_IDLE",
//                                                "STAGE_A0",
//                                                "STAGE_FP",
//                                                "STAGE_SOFTMAX",
//                                                "STAGE_BPdZ",
//                                                "STAGE_BPdA",
//                                                "STAGE_BPdW",
//                                                "STAGE_PU"};

#define             AXIDM_CMD_EOF           (0x40000000)
#define             AXIDM_CMD_TYPE_INCR     (0x00800000)
#define             AXIDM_STS_OK            (0x00000080)
#define             AXIDM_STS_SLVERR        (0x00000040)
#define             AXIDM_STS_DECERR        (0x00000020)
#define             AXIDM_STS_INTERR        (0x00000010)
#define             AXIDM_STS_MASK_TAG      (0x0000000F)

#define             AXIDM_CMD_BTT(i)        (i)
#define             AXIDM_CMD_SADDR(i)      (i)
#define             AXIDM_CMD_TAG(i)        (i)

#define             AXIDM_CMD_0             (0x40800000)

typedef struct {        // 256b
    u32 fcta_cfg_0;     //  96b fcta_cfg
    u32 fcta_cfg_1;
    u32 fcta_cfg_2;
    u32 mm2s_cmd_0;     //  72b mm2s_cmd
    u32 mm2s_cmd_1;
    u8  mm2s_cmd_2;
    u32 s2mm_cmd_0;     //  72b s2mm_cmd
    u32 s2mm_cmd_1;
    u8  s2mm_cmd_2;
    u16 ctrl;           //  16b ctrl
} __attribute__((packed, aligned(1))) CMD_T;

typedef struct {        // 8*4B
    u32 reg_start;
    u16 reg_num_cmd_mm2s;
    u16 reg_num_cmd_s2mm;
    u32 reg_num_rpt;
    u32 reg_rsv3;
    u32 reg_rpt_cur;
    u32 reg_cmd_cur;
    u16 reg_sts_mm2s_cur;
    u16 reg_sts_s2mm_cur;
    u32 reg_status;
} __attribute__((packed, aligned(1))) FCTA_CTL_T;

FCTA_CTL_T* fcta_ctl_ptr;



/************************ Inline Function Definitions ************************/

__attribute__((always_inline)) static inline void WR_BRAM_CMD (
    CMD_T* bram_addr,
    u8 stage, u8 lay_idx,
    u8 cmd_ctrl,
    UINTPTR mm2s_addr, u32 mm2s_len,
    UINTPTR s2mm_addr, u32 s2mm_len
) {
    CMD_T cmd;
    volatile CMD_T* bram_addr_v;
    
    if (cmd_ctrl & 0x0001) {
        cmd.fcta_cfg_0 = cfg_i2[stage][lay_idx];
        cmd.fcta_cfg_1 = cfg_i1[stage][lay_idx];
        cmd.fcta_cfg_2 = cfg_i0[stage][lay_idx];
    } else {
        cmd.fcta_cfg_0 = 0xFFFFFFFF;
        cmd.fcta_cfg_1 = 0xFFFFFFFF;
        cmd.fcta_cfg_2 = 0xFFFFFFFF;
    }

    if (cmd_ctrl & 0x0002) {
        cmd.mm2s_cmd_0 = AXIDM_CMD_0 | mm2s_len;
        cmd.mm2s_cmd_1 = mm2s_addr;
        cmd.mm2s_cmd_2 = stage;
    } else {
        cmd.mm2s_cmd_0 = 0xFFFFFFFF;
        cmd.mm2s_cmd_1 = 0xFFFFFFFF;
        cmd.mm2s_cmd_2 = 0xFF;
    }

    if (cmd_ctrl & 0x0004) {
        cmd.s2mm_cmd_0 = AXIDM_CMD_0 | s2mm_len;
        cmd.s2mm_cmd_1 = s2mm_addr;
        cmd.s2mm_cmd_2 = stage;
    } else {
        cmd.s2mm_cmd_0 = 0xFFFFFFFF;
        cmd.s2mm_cmd_1 = 0xFFFFFFFF;
        cmd.s2mm_cmd_2 = 0xFF;
    }
    
    cmd.ctrl = cmd_ctrl;

    printf_lv(
        1, "%04X | %02X %08X %08X | %02X %08X %08X | %08X %08X %08X\n",
        cmd.ctrl,
        cmd.s2mm_cmd_2, cmd.s2mm_cmd_1, cmd.s2mm_cmd_0,
        cmd.mm2s_cmd_2, cmd.mm2s_cmd_1, cmd.mm2s_cmd_0,
        cmd.fcta_cfg_2, cmd.fcta_cfg_1, cmd.fcta_cfg_0
    );

    // Write CMD to BRAM
    // *bram_addr = cmd;
    bram_addr_v = (volatile CMD_T *) bram_addr;
    *bram_addr_v = cmd;

    // u32* p = ((u32*)(bram_addr)) + 7;
    // for(int i=0; i<8; i++){
    //     printf_lv(1, "%08X ", *(p--));
    // }
    // printf_lv(1, "\n");

}








/*****************************************************************************/
static INLINE int FCTA_Train () {

    int epo_idx, bat_idx, lay_idx = 0;
    int xfer_cnt, comp_cnt;
    int row_idx, pe_idx, exa_idx, chk_idx;
    XTime tStart, tEnd;
    XTime tStart_cnt, tEnd_cnt;
	XTime tSum_cnt[L+1] = {0};
    u64   t_cnt[L+1] = {0};

    // t_cnt =0;
    // tSum_cnt = 0;
    XTime_GetTime(&tStart);

    // ***** Training *****

    for (epo_idx = 0; epo_idx < NUM_EPOCH; epo_idx++) {

        printf_lv(2, "[E%03d] ################ STARTED ################\n", epo_idx);

        for (bat_idx = 0; bat_idx < NUM_BATCH; bat_idx++) {

// XTime_GetTime(&tStart_cnt);

            printf_lv(3, "[E%03d B%04d] ================ STARTED ================\n", epo_idx, bat_idx);

            // ---------------- Init ----------------

            if (bat_idx == 0) {
                memcpy(A[0], (A0_i + (N[0]*M) * bat_idx), A_BYTES(0));
                printf_lv(5, "    [A0] Writing input features to A0.\n");
            }

            // ---------------- Input Features ----------------
            // ---------------- Forward Propagation ----------------
            
            if (bat_idx == 0) {
                Xil_Out32((UINTPTR)(&(fcta_ctl_ptr->reg_start)), 0x80000000);   // CTL_START
            } else {
                Xil_Out32((UINTPTR)(&(fcta_ctl_ptr->reg_start)), 0x40000000);   // CTL_RESUME
            }
            Xil_Out32((UINTPTR)(&(fcta_ctl_ptr->reg_start)), 0x00000000);
            printf_lv(5, "    [FP] FP started.\n");
            
            comp_cnt = 0;
            while((Xil_In32((UINTPTR)(&(fcta_ctl_ptr->reg_status))) & 0x40000000) == 0x00000000) {  // CTL_PAUSED
                if ((comp_cnt++) >= XFER_TIMEOUT) {
                    printf_lv(PLV_ERR, 
                        "    [FP] TIME OUT!\n"
                    );
                    return XST_FAILURE;
                }
            }
            printf_lv(5, "    [FP] comp_cnt = %d\n", comp_cnt);
            
            // ---------------- Loss Function ----------------

            printf_lv(5, "    [LOSS] LOSS started.\n");

// XTime_GetTime(&tStart_cnt);

            for (exa_idx = 0; exa_idx < M; exa_idx++) {
                double se = 0;
                for (row_idx = 0; row_idx < (N[L]-NUM_PE); row_idx+=NUM_PE) {
                    for (pe_idx = 0; pe_idx < NUM_PE; pe_idx++) {
                        AL_fl[row_idx+pe_idx][exa_idx] = ((double)(A[L][row_idx*M+exa_idx*NUM_PE+pe_idx])) / (1 << ACT_QN);
                        se += exp(AL_fl[row_idx+pe_idx][exa_idx]);
                    }
                } { // the last chunk at row_idx
                    for (pe_idx = 0; pe_idx < (N_up[L]-(N[L]-NUM_PE)); pe_idx++) {
                        AL_fl[row_idx+pe_idx][exa_idx] = ((double)(A[L][row_idx*M+exa_idx*NUM_PE+pe_idx])) / (1 << ACT_QN);
                        se += exp(AL_fl[row_idx+pe_idx][exa_idx]);
                    }
                }
                lse[exa_idx] = log(se);
            }

            for (exa_idx = 0; exa_idx < M; exa_idx++) {
                for (row_idx = 0; row_idx < N_up[L]; row_idx++) {
                    softmax[row_idx][exa_idx] = exp(AL_fl[row_idx][exa_idx] - lse[exa_idx]);
                    dZL_fl[row_idx][exa_idx] = exp(AL_fl[row_idx][exa_idx] - lse[exa_idx]);
                }
            }

            for (exa_idx = 0; exa_idx < M; exa_idx++) {
                dZL_fl[Y[M*bat_idx+exa_idx]][exa_idx] -= 1.0;
            }

            for (row_idx = 0; row_idx < N_up[L]; row_idx++) {
                for (exa_idx = 0; exa_idx < M; exa_idx++) {
                    dZL_fl[row_idx][exa_idx] = round(dZL_fl[row_idx][exa_idx] / M * (1 << WEIGHT_QN));
                    dZL_fl[row_idx][exa_idx] = fmax(dZL_fl[row_idx][exa_idx], -(1 << (WEIGHT_BW-1)));
                    dZL_fl[row_idx][exa_idx] = fmin(dZL_fl[row_idx][exa_idx], (1 << (WEIGHT_BW-1))-1);
                }
            }

            for (exa_idx = 0; exa_idx < M; exa_idx++) {
                for (row_idx = 0; row_idx < (N[L]-NUM_PE); row_idx+=NUM_PE) {
                    for (pe_idx = 0; pe_idx < NUM_PE; pe_idx++) {
                        dZ[L][row_idx*M+exa_idx*NUM_PE+pe_idx] = (s16)(dZL_fl[row_idx+pe_idx][exa_idx]);
                    }
                } { // the last chunk at row_idx
                    for (pe_idx = 0; pe_idx < (N_up[L]-(N[L]-NUM_PE)); pe_idx++) {
                        dZ[L][row_idx*M+exa_idx*NUM_PE+pe_idx] = (s16)(dZL_fl[row_idx+pe_idx][exa_idx]);
                    }
                    for (; pe_idx < NUM_PE; pe_idx++) {     // Pad zeros
                        dZ[L][row_idx*M+exa_idx*NUM_PE+pe_idx] = 0;
                    }
                }
            }

// XTime_GetTime(&tEnd_cnt);
// printf_lv(5, "    [STATS L%d] %d clock cycles.\n", lay_idx, (tEnd_cnt-tStart_cnt)*2);
// fflush(stdout);
// t_cnt[lay_idx]++;
// tSum_cnt[lay_idx] += (tEnd_cnt-tStart_cnt);

            printf_lv(5, "    [LOSS] LOSS finished.\n");

            // ---------------- Backward Propagation ----------------

// XTime_GetTime(&tStart_cnt);

            Xil_Out32((UINTPTR)(&(fcta_ctl_ptr->reg_start)), 0x40000000);   // CTL_RESUME
            Xil_Out32((UINTPTR)(&(fcta_ctl_ptr->reg_start)), 0x00000000);
            printf_lv(5, "    [BP] BP started.\n");
            
            // while(Xil_In16((UINTPTR)(&(fcta_ctl_ptr->reg_sts_mm2s_cur))) <= 11);
            // while(Xil_In16((UINTPTR)(&(fcta_ctl_ptr->reg_sts_s2mm_cur))) <= 5);
            // while(Xil_In32((UINTPTR)(&(fcta_ctl_ptr->reg_cmd_cur))) <= 12);

            while(Xil_In32((UINTPTR)(&(fcta_ctl_ptr->reg_cmd_cur))) <= 26);
            if ((bat_idx+1) < NUM_BATCH) {                                  // Preload next A0
                memcpy(A[0], (A0_i + (N[0]*M) * (bat_idx+1)), A_BYTES(0));
                printf_lv(5, "    [A0] Writing (next) input features to A0.\n");
            }

            comp_cnt = 0;
            while((Xil_In32((UINTPTR)(&(fcta_ctl_ptr->reg_status))) & 0x40000000) == 0x00000000) {  // CTL_PAUSED
                if ((comp_cnt++) >= XFER_TIMEOUT) {
                    printf_lv(PLV_ERR, 
                        "    [BP] TIME OUT!\n"
                    );
                    return XST_FAILURE;
                }
            }
            printf_lv(5, "    [BP] comp_cnt = %d\n", comp_cnt);
            
// XTime_GetTime(&tEnd_cnt);
// printf_lv(5, "    [STATS L%d] %d clock cycles.\n", lay_idx, (tEnd_cnt-tStart_cnt)*2);
// fflush(stdout);
// t_cnt[lay_idx]++;
// tSum_cnt[lay_idx] += (tEnd_cnt-tStart_cnt);

            printf_lv(3, "[E%03d B%04d] ================ FINISHED ================\n", epo_idx, bat_idx);

        }

        // printf_lv(2, "[E%03d] ################ FINISHED ################\n", epo_idx);

    }

    XTime_GetTime(&tEnd);

    printf_lv(1, "[FINISH] FCTA_CTL.reg_start         = 0x%08X\n", fcta_ctl_ptr->reg_start);
    printf_lv(1, "[FINISH] FCTA_CTL.reg_num_cmd_mm2s  = 0x%04X\n", fcta_ctl_ptr->reg_num_cmd_mm2s);
    printf_lv(1, "[FINISH] FCTA_CTL.reg_num_cmd_s2mm  = 0x%04X\n", fcta_ctl_ptr->reg_num_cmd_s2mm);
    printf_lv(1, "[FINISH] FCTA_CTL.reg_num_rpt       = 0x%08X\n", fcta_ctl_ptr->reg_num_rpt);
    printf_lv(1, "[FINISH] FCTA_CTL.reg_rsv3          = 0x%08X\n", fcta_ctl_ptr->reg_rsv3);
    printf_lv(1, "[FINISH] FCTA_CTL.reg_rpt_cur       = 0x%08X\n", fcta_ctl_ptr->reg_rpt_cur);
    printf_lv(1, "[FINISH] FCTA_CTL.reg_cmd_cur       = 0x%08X\n", fcta_ctl_ptr->reg_cmd_cur);
    printf_lv(1, "[FINISH] FCTA_CTL.reg_sts_mm2s_cur  = 0x%04X\n", fcta_ctl_ptr->reg_sts_mm2s_cur);
    printf_lv(1, "[FINISH] FCTA_CTL.reg_sts_s2mm_cur  = 0x%04X\n", fcta_ctl_ptr->reg_sts_s2mm_cur);
    printf_lv(1, "[FINISH] FCTA_CTL.reg_status        = 0x%08X\n", fcta_ctl_ptr->reg_status);

    // -------- Output --------
    // for (lay_idx = 1; lay_idx <= L; lay_idx++) {
    //     printf_lv(0, "\nW%d = \n", lay_idx);
    //     for (int i = 0; i < (N[lay_idx]*(N[lay_idx-1]+1)); i++) {
    //         printf_lv(0, "%04X%c", W[lay_idx][i] & 0xFFFF, (((i&0x0F)==0x0F)? '\n':' '));
    //     }
    //     printf_lv(0, "dW%d = \n", lay_idx);
    //     for (int i = 0; i < (N[lay_idx]*(N[lay_idx-1]+1)); i++) {
    //         printf_lv(0, "%04X%c", dW[lay_idx][i] & 0xFFFF, (((i&0x0F)==0x0F)? '\n':' '));
    //     }
    // }
    
    {
        // printf_lv(PLV_DOUT, "[OUTPUT] Start data tx...\n");

        // u8* ptr;
        // for (int l = 1; l <= L; l++) {
        //     ptr = (u8*)(W[l]);
        //     for (int i = 0; i < W_BYTES(l); i++) {
        //         printf_lv(PLV_DOUT, "%c", ptr[i]);
        //     }
        // }
        // for (int l = 1; l <= L; l++) {
        //     ptr = (u8*)(dW[l]);
        //     for (int i = 0; i < dW_BYTES(l); i++) {
        //         printf_lv(PLV_DOUT, "%c", ptr[i]);
        //     }
        // }
        // for (int l = 1; l <= L; l++) {
        //     ptr = (u8*)(A[l]);
        //     for (int i = 0; i < A_BYTES(l); i++) {
        //         printf_lv(PLV_DOUT, "%c", ptr[i]);
        //     }
        // }
        // for (int l = L; l <= L; l++) {
        //     ptr = (u8*)(dZ[l]);
        //     for (int i = 0; i < dZ_BYTES(l); i++) {
        //         printf_lv(PLV_DOUT, "%c", ptr[i]);
        //     }
        // }

        // printf_lv(PLV_DOUT, "[OUTPUT] Data tx completed.\n");

        printf("[STATS] Training took %.8f s.\n", 1.0*(tEnd-tStart)/COUNTS_PER_SECOND);

        fflush(stdout);

for (lay_idx = 0; lay_idx <= L; lay_idx++) {
    printf_lv(1, "    [STATS L%d] Average: %d clock cycles.\n", lay_idx, (tSum_cnt[lay_idx])*2/t_cnt[lay_idx]);
}

    }

    return XST_SUCCESS;

}


























/***************************** Main Function *********************************/

int main () {

    int Status;
    // XTime tStart, tEnd;
    int lay_idx, chk_idx;
    u8 cmd_ctrl;
    CMD_T* bram_ptr;
    int num_cmd_mm2s;
    int num_cmd_s2mm;

    // init_platform();

    printf_lv(1, "\n--- Entering main() --- \n");

    // ***** Initialize DMA device *****
    // Status = XAxiDma_Init();
    // if (Status != XST_SUCCESS) {
    //     printf_lv(PLV_ERR, "ERROR! AXI DMA initialization failed!\n");
    //     return XST_FAILURE;
    // }

    // ***** Initialize AXI GPIO *****
    // Status = XAxiGpio_Init();
    // if (Status != XST_SUCCESS) {
    //     printf_lv(PLV_ERR, "ERROR! AXI GPIO initialization failed!\n");
    //     return XST_FAILURE;
    // }

    // ***** Initialize UART *****
	// Status = XUart_Init();
    // if (Status != XST_SUCCESS) {
    //     printf_lv(PLV_ERR, "ERROR! UART initialization failed!\n");
    //     return XST_FAILURE;
    // }

    // printf_lv(1, "sizeof(CMD_T) = %d B.\n", sizeof(CMD_T));
    // printf_lv(1, "sizeof(FCTA_CTL_T) = %d B.\n", sizeof(FCTA_CTL_T));

    // fcta_ctl_ptr = (FCTA_CTL_T*)FCTA_CTL_BASE_ADDR;
    // printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_start         = 0x%08X\n", fcta_ctl_ptr->reg_start);
    // printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_num_cmd_mm2s  = 0x%04X\n", fcta_ctl_ptr->reg_num_cmd_mm2s);
    // printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_num_cmd_s2mm  = 0x%04X\n", fcta_ctl_ptr->reg_num_cmd_s2mm);
    // printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_num_rpt       = 0x%08X\n", fcta_ctl_ptr->reg_num_rpt);
    // printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_rsv3          = 0x%08X\n", fcta_ctl_ptr->reg_rsv3);
    // printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_rpt_cur       = 0x%08X\n", fcta_ctl_ptr->reg_rpt_cur);
    // printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_cmd_cur       = 0x%08X\n", fcta_ctl_ptr->reg_cmd_cur);
    // printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_sts_mm2s_cur  = 0x%04X\n", fcta_ctl_ptr->reg_sts_mm2s_cur);
    // printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_sts_s2mm_cur  = 0x%04X\n", fcta_ctl_ptr->reg_sts_s2mm_cur);
    // printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_status        = 0x%08X\n", fcta_ctl_ptr->reg_status);
    // return XST_SUCCESS;

    // ***** Initialize Pointers *****

    W[1] = (UINTPTR)MEM_BASE_ADDR;
    printf_lv(2, "[OVERALL INIT] W%d @ 0x%08X.\n", 1, W[1]);
    for (lay_idx = 2; lay_idx <= L; lay_idx++) {
        W[lay_idx] = (UINTPTR)(W[lay_idx-1]) + W_BYTES(lay_idx-1);
        printf_lv(2, "[OVERALL INIT] W%d @ 0x%08X.\n", lay_idx, W[lay_idx]);
    }

    dW[1] = (UINTPTR)(W[L]) + W_BYTES(L);
    printf_lv(2, "[OVERALL INIT] dW%d @ 0x%08X.\n", 1, dW[1]);
    for (lay_idx = 2; lay_idx <= L; lay_idx++) {
        // dW[lay_idx] = (UINTPTR)(dW[lay_idx-1]) + dW_BYTES(lay_idx-1);
        dW[lay_idx] = (UINTPTR)(dW[lay_idx-1]) + 0;
        printf_lv(2, "[OVERALL INIT] dW%d @ 0x%08X.\n", lay_idx, dW[lay_idx]);
    }

    // A[0] = (UINTPTR)(dW[L]) + dW_BYTES(L);
    A[0] = (UINTPTR)(dW[L]) + dW_BYTES(1);
    printf_lv(2, "[OVERALL INIT] A%d @ 0x%08X.\n", 0, A[0]);
    for (lay_idx = 1; lay_idx <= L; lay_idx++) {
        A[lay_idx] = (UINTPTR)(A[lay_idx-1]) + A_BYTES(lay_idx-1);
        printf_lv(2, "[OVERALL INIT] A%d @ 0x%08X.\n", lay_idx, A[lay_idx]);
    }

    dZ[L] = (UINTPTR)(A[L]) + A_BYTES(L);
    printf_lv(2, "[OVERALL INIT] dZ%d @ 0x%08X.\n", L, dZ[L]);
    printf_lv(2, "[OVERALL INIT] _End_ @ 0x%08X.\n", (UINTPTR)(dZ[L]) + dZ_BYTES(L));

    // ***** Initialize DRAM *****

    for (u8* ptr = NONCACHE_START; ptr < NONCACHE_END; ptr+=TLBATTR_LENGTH) {
        // printf_lv(1, "[OVERALL INIT] Setting TLB Attributes @0x%08X.\n", ptr);
        Xil_SetTlbAttributes((UINTPTR)ptr, NORM_NONCACHE);
    }

    // ***** Initialize Weight *****

    for (lay_idx = 1; lay_idx <= L; lay_idx++) {

        printf_lv(2, "[OVERALL INIT] W%d initialization started.\n", lay_idx);

        memcpy(W[lay_idx], W_i[lay_idx], W_BYTES(lay_idx));

    }
    
    // ***** Initialize BRAM_CMD *****

    num_cmd_mm2s = 0;
    num_cmd_s2mm = 0;
    bram_ptr = (CMD_T*)(BRAM_CMD_BASE_ADDR);
    // printf_lv(1, "bram_ptr = 0x%08X\n", bram_ptr);

    // STAGE_A0
    lay_idx = 0;
    WR_BRAM_CMD(
        bram_ptr, STAGE_A0, lay_idx, 0x0003,
        (UINTPTR)(A[lay_idx]), A_BYTES(lay_idx),
        0xFFFFFFFF, 0xFFFFFFFF
    );
    bram_ptr++;
    num_cmd_mm2s++;

    for (lay_idx = 1; lay_idx <= L; lay_idx++) {

        // STAGE_FP
        cmd_ctrl = 0x0007;
        if (lay_idx == L) cmd_ctrl |= 0x0010;       // CTL_PAUSE
        WR_BRAM_CMD(
            bram_ptr, STAGE_FP, lay_idx, cmd_ctrl,
            (UINTPTR)(W[lay_idx]), W_BYTES(lay_idx),
            (UINTPTR)(A[lay_idx]), A_BYTES(lay_idx)
        );
        bram_ptr++;
        num_cmd_mm2s++;
        num_cmd_s2mm++;

    }

    // STAGE_A0 (dZL)
    lay_idx = L;
    WR_BRAM_CMD(
        bram_ptr, STAGE_A0, lay_idx, 0x0003,
        (UINTPTR)(dZ[lay_idx]), dZ_BYTES(lay_idx),
        0xFFFFFFFF, 0xFFFFFFFF
    );
    bram_ptr++;
    num_cmd_mm2s++;

    for (lay_idx = L; lay_idx >= 1; lay_idx--) {

        // STAGE_BPdZ
        if (lay_idx < L) {
            WR_BRAM_CMD(
                bram_ptr, STAGE_BPdZ, lay_idx, 0x0003,
                (UINTPTR)(A[lay_idx]), A_BYTES(lay_idx),
                0xFFFFFFFF, 0xFFFFFFFF
            );
            bram_ptr++;
            num_cmd_mm2s++;
        }

        // STAGE_BPdA
        if (lay_idx > 1) {
            WR_BRAM_CMD(
                bram_ptr, STAGE_BPdA, lay_idx, 0x0003,
                (UINTPTR)(W[lay_idx]), W_NB_BYTES(lay_idx),
                0xFFFFFFFF, 0xFFFFFFFF
            );
            bram_ptr++;
            num_cmd_mm2s++;
        }

        // STAGE_BPdW
        WR_BRAM_CMD(
            bram_ptr, STAGE_BPdW, lay_idx, 0x000F,  // CTL_BARRIER
            (UINTPTR)(A[lay_idx-1]), A_BYTES(lay_idx-1),
            (UINTPTR)(dW[lay_idx]), dW_BYTES(lay_idx)
        );
        bram_ptr++;
        num_cmd_mm2s++;
        num_cmd_s2mm++;

    // }

    // for (lay_idx = L; lay_idx >= 1; lay_idx--) {

        // STAGE_PU
        for (chk_idx = 0; chk_idx < chk_num[lay_idx]; chk_idx++) {

            if (chk_idx == 0) {
                WR_BRAM_CMD(
                    bram_ptr, STAGE_PU, lay_idx, 0x0007,
                    (UINTPTR)(W[lay_idx]) + W_CHK_BYTES(lay_idx)*chk_idx, W_CHK_BYTES(lay_idx),
                    (UINTPTR)(W[lay_idx]), W_BYTES(lay_idx)
                );
                bram_ptr++;
                num_cmd_mm2s++;
                num_cmd_s2mm++;
            } else {
                WR_BRAM_CMD(
                    bram_ptr, STAGE_PU, lay_idx, 0x0002,
                    (UINTPTR)(W[lay_idx]) + W_CHK_BYTES(lay_idx)*chk_idx, W_CHK_BYTES(lay_idx),
                    0xFFFFFFFF, 0xFFFFFFFF
                );
                bram_ptr++;
                num_cmd_mm2s++;
            }

            if ((lay_idx == 1) && (chk_idx == chk_num[lay_idx] - 1)) {
                WR_BRAM_CMD(
                    bram_ptr, STAGE_PU, lay_idx, 0x0012,    // CTL_PAUSE
                    (UINTPTR)(dW[lay_idx]) + dW_CHK_BYTES(lay_idx)*chk_idx, dW_CHK_BYTES(lay_idx),
                    0xFFFFFFFF, 0xFFFFFFFF
                );
                bram_ptr++;
                num_cmd_mm2s++;
            } else {
                WR_BRAM_CMD(
                    bram_ptr, STAGE_PU, lay_idx, 0x0002,
                    (UINTPTR)(dW[lay_idx]) + dW_CHK_BYTES(lay_idx)*chk_idx, dW_CHK_BYTES(lay_idx),
                    0xFFFFFFFF, 0xFFFFFFFF
                );
                bram_ptr++;
                num_cmd_mm2s++;
            }
            
        }

    }

    printf_lv(1, "[OVERALL INIT] num_cmd_mm2s = %d, num_cmd_s2mm = %d\n", num_cmd_mm2s, num_cmd_s2mm);

    // CMD_T* bram_addr = (CMD_T*)(BRAM_CMD_BASE_ADDR);
    // for(int i=0; i<num_cmd_mm2s; i++) {
    //     printf_lv(1, "@0x%08X : ", (int)bram_addr);
    //     u32* p = ((u32*)(bram_addr++)) + 7;
    //     for(int i=0; i<8; i++){
    //         printf_lv(1, "%08X ", *(p--));
    //     }
    //     printf_lv(1, "\n");
    // }

    // ***** Initialize FCTA_CTL *****

    fcta_ctl_ptr = (FCTA_CTL_T*)FCTA_CTL_BASE_ADDR;
    printf_lv(1, "[OVERALL INIT] FCTA_CTL                   @ 0x%08X\n", fcta_ctl_ptr);
    printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_start         @ 0x%08X\n", &(fcta_ctl_ptr->reg_start));
    printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_num_cmd_mm2s  @ 0x%04X\n", &(fcta_ctl_ptr->reg_num_cmd_mm2s));
    printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_num_cmd_s2mm  @ 0x%04X\n", &(fcta_ctl_ptr->reg_num_cmd_s2mm));
    printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_status        @ 0x%08X\n", &(fcta_ctl_ptr->reg_status));

    fcta_ctl_ptr->reg_num_cmd_mm2s  = num_cmd_mm2s - 1;
    fcta_ctl_ptr->reg_num_cmd_s2mm  = num_cmd_s2mm - 1;
    fcta_ctl_ptr->reg_num_rpt       = NUM_BATCH - 1;

    printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_start         = 0x%08X\n", fcta_ctl_ptr->reg_start);
    printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_num_cmd_mm2s  = 0x%04X\n", fcta_ctl_ptr->reg_num_cmd_mm2s);
    printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_num_cmd_s2mm  = 0x%04X\n", fcta_ctl_ptr->reg_num_cmd_s2mm);
    printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_num_rpt       = 0x%08X\n", fcta_ctl_ptr->reg_num_rpt);
    printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_rsv3          = 0x%08X\n", fcta_ctl_ptr->reg_rsv3);
    printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_rpt_cur       = 0x%08X\n", fcta_ctl_ptr->reg_rpt_cur);
    printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_cmd_cur       = 0x%08X\n", fcta_ctl_ptr->reg_cmd_cur);
    printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_sts_mm2s_cur  = 0x%04X\n", fcta_ctl_ptr->reg_sts_mm2s_cur);
    printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_sts_s2mm_cur  = 0x%04X\n", fcta_ctl_ptr->reg_sts_s2mm_cur);
    printf_lv(1, "[OVERALL INIT] FCTA_CTL.reg_status        = 0x%08X\n", fcta_ctl_ptr->reg_status);

    // ***** Initiate FCTA Training *****

    Status = FCTA_Train();
    if (Status != XST_SUCCESS) {
        printf_lv(PLV_ERR, "ERROR! FCTA training failed!\n");
        printf_lv(PLV_ERR, "[ERROR] FCTA_CTL.reg_start         = 0x%08X\n", fcta_ctl_ptr->reg_start);
        printf_lv(PLV_ERR, "[ERROR] FCTA_CTL.reg_num_cmd_mm2s  = 0x%04X\n", fcta_ctl_ptr->reg_num_cmd_mm2s);
        printf_lv(PLV_ERR, "[ERROR] FCTA_CTL.reg_num_cmd_s2mm  = 0x%04X\n", fcta_ctl_ptr->reg_num_cmd_s2mm);
        printf_lv(PLV_ERR, "[ERROR] FCTA_CTL.reg_num_rpt       = 0x%08X\n", fcta_ctl_ptr->reg_num_rpt);
        printf_lv(PLV_ERR, "[ERROR] FCTA_CTL.reg_rsv3          = 0x%08X\n", fcta_ctl_ptr->reg_rsv3);
        printf_lv(PLV_ERR, "[ERROR] FCTA_CTL.reg_rpt_cur       = 0x%08X\n", fcta_ctl_ptr->reg_rpt_cur);
        printf_lv(PLV_ERR, "[ERROR] FCTA_CTL.reg_cmd_cur       = 0x%08X\n", fcta_ctl_ptr->reg_cmd_cur);
        printf_lv(PLV_ERR, "[ERROR] FCTA_CTL.reg_sts_mm2s_cur  = 0x%04X\n", fcta_ctl_ptr->reg_sts_mm2s_cur);
        printf_lv(PLV_ERR, "[ERROR] FCTA_CTL.reg_sts_s2mm_cur  = 0x%04X\n", fcta_ctl_ptr->reg_sts_s2mm_cur);
        printf_lv(PLV_ERR, "[ERROR] FCTA_CTL.reg_status        = 0x%08X\n", fcta_ctl_ptr->reg_status);
        return XST_FAILURE;
    }

    printf_lv(1, "--- Exiting main() --- \n");

    // cleanup_platform();

    return XST_SUCCESS;

}






















































/*****************************************************************************/
// int XAxiDma_Init() {
//     int Status;
//     XAxiDma_Config *CfgPtr;

//     // Initialize the XAxiDma device
//     CfgPtr = XAxiDma_LookupConfig(DMA_DEV_ID);
//     if (!CfgPtr) {
//         printf_lv(1, "[AXI_DMA] No config found for %d!\r\n", DMA_DEV_ID);
//         return XST_FAILURE;
//     }

//     Status = XAxiDma_CfgInitialize(&AxiDma, CfgPtr);
//     if (Status != XST_SUCCESS) {
//         printf_lv(PLV_ERR, "[AXI_DMA] Initialization failed %d!\r\n", Status);
//         return XST_FAILURE;
//     }

//     if(XAxiDma_HasSg(&AxiDma)){
//         printf_lv(PLV_ERR, "[AXI_DMA] Device configured as SG mode.\r\n");
//         return XST_FAILURE;
//     }

//     // Disable interrupts, use polling mode
//     XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
//     XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);

//     printf_lv(1, "[AXI_DMA] initialization completed.\n");
//     return XST_SUCCESS;
// }



// int XAxiGpio_Init() {
//     int Status;

//     // Initialize the XAxiGpio device
//     Status = XGpio_Initialize(&AxiGpio0, GPIO_0_DEV_ID);
//     if (Status != XST_SUCCESS) {
//         printf_lv(PLV_ERR, "[AXI_GPIO_0] Initialization failed %d!\r\n", Status);
//         return XST_FAILURE;
//     }

//     XGpio_DiscreteWrite(&AxiGpio0, 1, 0x0000);
//     XGpio_DiscreteWrite(&AxiGpio0, 2, 0x0000);

//     Status = XGpio_Initialize(&AxiGpio1, GPIO_1_DEV_ID);
//     if (Status != XST_SUCCESS) {
//         printf_lv(PLV_ERR, "[AXI_GPIO_1] Initialization failed %d!\r\n", Status);
//         return XST_FAILURE;
//     }

//     XGpio_DiscreteWrite(&AxiGpio1, 1, 0x0000);
//     XGpio_DiscreteWrite(&AxiGpio1, 2, 0x0000);

//     printf_lv(1, "[AXI_GPIO] initialization completed.\n");
//     return XST_SUCCESS;
// }



// int XUart_Init() {
//     int Status;
// 	XUartPs_Config *CfgPtr;

// 	CfgPtr = XUartPs_LookupConfig(UART_DEVICE_ID);
// 	if (!CfgPtr) {
//         printf_lv(1, "[UART] No config found for %d!\r\n", UART_DEVICE_ID);
//         return XST_FAILURE;
// 	}

// 	Status = XUartPs_CfgInitialize(&Uart_PS, CfgPtr, CfgPtr->BaseAddress);
// 	if (Status != XST_SUCCESS) {
//         printf_lv(PLV_ERR, "[UART] Initialization failed %d!\r\n", Status);
// 		return XST_FAILURE;
// 	}

// 	// Status = XUartPs_SelfTest(&Uart_PS);
// 	// if (Status != XST_SUCCESS) {
// 	// 	return XST_FAILURE;
// 	// }

// 	XUartPs_SetOperMode(&Uart_PS, XUARTPS_OPER_MODE_NORMAL);

//     printf_lv(1, "[UART] initialization completed.\n");
//     return XST_SUCCESS;
// }
/*****************************************************************************/
































#if defined(XPAR_UARTNS550_0_BASEADDR)
/*****************************************************************************/
/*
*
* Uart16550 setup routine, need to set baudrate to 9600, and data bits to 8
*
* @param	None.
*
* @return	None
*
* @note		None.
*
******************************************************************************/
static void Uart550_Setup(void)
{

	/* Set the baudrate to be predictable
	 */
	XUartNs550_SetBaud(XPAR_UARTNS550_0_BASEADDR,
			XPAR_XUARTNS550_CLOCK_HZ, 9600);

	XUartNs550_SetLineControlReg(XPAR_UARTNS550_0_BASEADDR,
			XUN_LCR_8_DATA_BITS);

}
#endif


