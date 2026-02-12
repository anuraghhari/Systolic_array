`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/07/2026 04:08:02 PM
// Design Name: 
// Module Name: Sys_array_test
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
//====================================================
// DSP-based Multiply Accumulate (MAC)
// Uses 1 DSP slice (DSP48)
//====================================================
     module dsp_mac #
    (
        parameter A_WIDTH = 16,
        parameter B_WIDTH = 16,
        parameter ACC_WIDTH = 48,
        parameter N = 2      
          
    )
    (
        input  wire                     clk,
        input  wire                     rst,

        input  wire signed [A_WIDTH-1:0] a,
        input  wire signed [B_WIDTH-1:0] b,
        input  wire                     valid_in_d,
        input  wire                     valid_in_w,
        output reg  [A_WIDTH-1:0] a_shifted,
        output reg  [B_WIDTH-1:0] b_shifted,

        output reg  signed [ACC_WIDTH-1:0] acc_out,
        output reg                      valid_out_d,
        output reg                      valid_out_w

    );

            // ------------------------------------------------
            // Multiply and Accumulate (DSP)
            // ------------------------------------------------
            (* use_dsp = "yes" *)
           
            reg valid_mul;
            localparam int CNT_W = $clog2(N+1);
            reg [CNT_W-1:0] mac_cnt;
            wire acc_done  = (mac_cnt == N-1);
            reg acc_clr;
            
            


            always @(posedge clk) begin
                if (rst) begin
                    
                    valid_mul   <= 0;
                    acc_out     <= 0;
                    mac_cnt     <= 0;
                    valid_out_d <= 0;
                    valid_out_w <= 0;
                    a_shifted   <= 0;
                    b_shifted   <= 0;

                end 

                else if (acc_clr) begin
                    acc_out <= '0;            // clear BEFORE next matrix
                    acc_clr <= 0;
                end

                else if  (valid_in_d && valid_in_w) begin

                    /*if (mac_cnt == 0) begin
                        acc_out <= a*b ;
                    end
                    
                    else begin*/
                    acc_out <=acc_out + a*b;   // DSP inferred
                    //end
                    
                        
                    a_shifted <= a;
                    b_shifted <= b;
                    valid_out_d <= 1'b1;
                    valid_out_w <= 1'b1;

                    mac_cnt <= (mac_cnt == N-1) ? 0 : mac_cnt + 1;
                    acc_clr <= (mac_cnt == N-1) ? 1 : 0;
                end
                
                else begin
                    //acc_out <= 0;
                    valid_out_d <= 1'b0;
                    valid_out_w <= 1'b0;
                end
                                
            end
endmodule



module delay #(
    parameter WIDTH = 16,
    parameter D = 1
)(
    input  logic             clk,
    input  logic             rst,
    input  logic [WIDTH-1:0] din,
    input  logic             v_in,
    output logic [WIDTH-1:0] dout,
    output logic             v_out
);

generate
    if (D == 0) begin : gen_no_delay
        // Pure combinational bypass
        assign dout  = din;
        assign v_out = v_in;
    end
    else begin : gen_delay
        logic [WIDTH-1:0] shift_d [0:D-1];
        logic             shift_v [0:D-1];

        always_ff @(posedge clk) begin
            if (rst) begin
                for (int i = 0; i < D; i++) begin
                    shift_d[i] <= '0;
                    shift_v[i] <= 1'b0;
                end
            end else begin
                shift_d[0] <= din;
                shift_v[0] <= v_in;
                dout  <= shift_d[D-1];
                v_out <= shift_v[D-1];
                for (int i = 1; i < D; i++) begin
                    shift_d[i] <= shift_d[i-1];
                    shift_v[i] <= shift_v[i-1];
                end
            end
        end

       
    end
endgenerate

endmodule


module Sys_array_test #
(
    parameter A_WIDTH = 16,
    parameter B_WIDTH = 16,
    parameter ACC_WIDTH = 48,
    parameter N = 2 
)

(   
    input clk,
    input rst,
    input logic valid_in_d [0:N-1],
    input logic valid_in_w [0:N-1],
    input logic [A_WIDTH-1:0] data_in [0:N-1],
    input logic [B_WIDTH-1:0] weight_in [0:N-1],
    output logic [ACC_WIDTH-1:0] acc_out [0:N-1][0:N-1]
);

    wire [A_WIDTH-1:0] data [0:N-1][0:N];
    wire [B_WIDTH-1:0] weight [0:N][0:N-1];
    
    wire  valid_d [0:N-1][0:N];
    wire  valid_w [0:N][0:N-1];


    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : init_bram

           
            delay #(
                .WIDTH    (16),
                .D        (i)
            ) d_delay (
                .rst      (rst),
                .clk      (clk),
                .din      (data_in[i]),
                .v_in     (valid_in_d[i]),
                .dout     (data[i][0]),
                .v_out    (valid_d[i][0])
            );




             delay #(
                 .WIDTH    (16),
                 .D        (i)
             ) w_delay (
                 .clk      (clk),
                 .rst      (rst),
                 .din      (weight_in[i]),
                 .v_in     (valid_in_w[i]),
                 .dout     (weight[0][i]),
                 .v_out    (valid_w[0][i])
             );
            
        end
    endgenerate


    genvar j,k;
    generate
        for (j = 0; j < N; j = j + 1) begin : PE_row
            for (k = 0; k < N; k = k + 1) begin : PE_col


                dsp_mac #(
                    .A_WIDTH        (16),
                    .B_WIDTH        (16),
                    .ACC_WIDTH      (40)
                ) u_dsp_mac (
                    .clk            (clk),
                    .rst            (rst),
                    .a              (data[j][k]),
                    .b              (weight[j][k]),
                    .valid_in_d     (valid_d[j][k]),
                    .valid_in_w     (valid_w[j][k]),
                    .a_shifted      (data[j][k+1]),
                    .b_shifted      (weight[j+1][k]),
                    .acc_out        (acc_out[j][k]),
                    .valid_out_d    (valid_d[j][k+1]),
                    .valid_out_w    (valid_w[j+1][k])
                );
                        
        end
        end
    endgenerate
  
    
endmodule
