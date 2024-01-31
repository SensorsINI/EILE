
module MACC #(
    parameter NUM_PE    = 16,    //16
    parameter WEIGHT_QM = 8,
    parameter WEIGHT_QN = 8,
    parameter ACT_QM    = 8,
    parameter ACT_QN    = 8,
    parameter ACC_QM    = 16,
    parameter ACC_QN    = 16,
    localparam WEIGHT_BW = WEIGHT_QM + WEIGHT_QN,
    localparam ACT_BW    = ACT_QM + ACT_QN,
    localparam ACC_BW    = ACC_QM + ACC_QN
) (
    input logic clk,
    input logic en_mul,
    input logic en_add,
    input logic en_acc,
    input logic rstn,
    
    input logic [1:0]   mac_sel,
    input logic [1:0]   acc_sel,                                   // acc
    
    input logic signed[ACT_BW-1:0]      din_act[NUM_PE-1:0],
    input logic signed[WEIGHT_BW-1:0]   din_weight[NUM_PE-1:0],
    input logic signed[ACC_BW-1:0]      din_acc[NUM_PE:0],      // acc

    output logic signed[ACC_BW-1:0]     dout_acc[NUM_PE:0]      // acc
);
    
    logic signed[ACC_BW-1:0]    mac_mux_out[NUM_PE-1:0];
    logic signed[ACC_BW-1:0]    acc_mux_out;
    
    logic signed[ACT_BW-1:0]    mul_op0[NUM_PE-1:0];
    logic signed[WEIGHT_BW-1:0] mul_op1[NUM_PE-1:0];
    logic signed[ACC_BW-1:0]    mul_out[NUM_PE-1:0];
    logic signed[ACC_BW-1:0]    mul_out_r[NUM_PE-1:0];
    
    logic signed[ACC_BW-1:0]    add_op0[NUM_PE-1:0];
    logic signed[ACC_BW-1:0]    add_op1[NUM_PE-1:0];
    logic signed[ACC_BW-1:0]    add_out[NUM_PE-1:0];
    logic signed[ACC_BW-1:0]    add_out_r[NUM_PE-1:0];
    
    logic signed[ACC_BW-1:0]    acc_op0;
    logic signed[ACC_BW-1:0]    acc_op1;
    logic signed[ACC_BW-1:0]    acc_out;
    logic signed[ACC_BW-1:0]    acc_out_r;
    
    
    
    // MAC_MUX
    always_comb begin
        case (mac_sel)
            2'b00 : mac_mux_out = '{NUM_PE{'0}};
            2'b01 : mac_mux_out = din_acc[NUM_PE-1:0];
            2'b10 : mac_mux_out = add_out_r;
            2'b11 : begin
                mac_mux_out[0] = '0;
                for (int unsigned pe_idx = 1; pe_idx < NUM_PE; pe_idx++) begin
                    mac_mux_out[pe_idx] = add_out_r[pe_idx-1];
                end
            end
        endcase
    end
    
    // MAC Connections
    assign mul_op0 = din_act;
    assign mul_op1 = din_weight;
    assign add_op0 = mul_out_r;
    assign add_op1 = mac_mux_out;
    
    // MAC Computations
    always_comb begin
        for (int unsigned pe_idx = 0; pe_idx < NUM_PE; pe_idx++) begin
            mul_out[pe_idx] = mul_op0[pe_idx] * mul_op1[pe_idx];
            add_out[pe_idx] = add_op0[pe_idx] + add_op1[pe_idx];
        end
    end
    
    // MAC Registers
    always_ff @(posedge clk) begin
        if (!rstn) begin
            mul_out_r <= '{NUM_PE{'0}};
        end else if (en_mul) begin
            mul_out_r <= mul_out;
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            add_out_r <= '{NUM_PE{'0}};
        end else if (en_add) begin
            add_out_r <= add_out;
        end
    end



    // ACC_MUX
    always_comb begin
        case (acc_sel)
            2'b00 : acc_mux_out = '0;
            2'b01 : acc_mux_out = din_acc[NUM_PE];
            2'b10 : acc_mux_out = acc_out_r;
            2'b11 : acc_mux_out = '0;
        endcase
    end
    
    // ACC Connections
    assign acc_op0 = add_out_r[NUM_PE-1];
    assign acc_op1 = acc_mux_out;

    // ACC Computation
    always_comb begin
        acc_out = acc_op0 + acc_op1;
    end
    
    // ACC Register
    always_ff @(posedge clk) begin
        if (!rstn) begin
            acc_out_r <= '0;
        end else if (en_acc) begin
            acc_out_r <= acc_out;
        end
    end


    // Output Connections
    //assign dout_acc = {acc_out_r, add_out_r};

    generate
        always_comb dout_acc[NUM_PE] = acc_out_r;

        for (genvar PE_IDX = 0; PE_IDX < NUM_PE; PE_IDX++) begin
            always_comb dout_acc[PE_IDX] = add_out_r[PE_IDX];
        end
    endgenerate

endmodule


