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
        parameter N = 9      
          
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

        output reg  signed [ACC_WIDTH-1:0] final_out,
        output reg                      valid_out_d,
        output reg                      valid_out_w,
        output reg buff_sel

    );

            wire  signed [ACC_WIDTH-1:0] acc;
            reg  signed [ACC_WIDTH-1:0] acc_out;
            

            // ------------------------------------------------
            // Multiply and Accumulate (DSP)
            // ------------------------------------------------
            (* use_dsp = "yes" *)
            localparam int CNT_W = $clog2(N+1);
            reg [CNT_W-1:0] mac_cnt;

            wire acc_done  = (mac_cnt == 0);
            assign acc = (mac_cnt == 0)? 'b0 : acc_out;
            


            always @(posedge clk) begin

                if (rst) begin
                   
                    acc_out   <= 0;
                    mac_cnt     <= 0;
                    valid_out_d <= 0;
                    valid_out_w <= 0;
                    a_shifted   <= 0;
                    b_shifted   <= 0;
                    buff_sel <= 1'b0;

                end 

                else if  (valid_in_d && valid_in_w) begin

                    acc_out <= acc + a*b;     // SAME DSP adder   
                    a_shifted <= a;
                    b_shifted <= b;
                    valid_out_d <= 1'b1;
                    valid_out_w <= 1'b1;

                    mac_cnt <= (mac_cnt == N-1) ? 0 : mac_cnt + 1;
                    final_out <= (acc_done) ? acc_out : final_out;
                    buff_sel <= (acc_done) ? ~buff_sel : buff_sel;
                end
                
                else begin
                    valid_out_d <= 1'b0;
                    valid_out_w <= 1'b0;
                    a_shifted <= 'b0;
                    b_shifted <= 'b0;
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
        assign dout  = din;
        assign v_out = v_in;
    end
    else begin : gen_delay
        logic [WIDTH-1:0] shift_d [0:D-1];
        logic             shift_v [0:D-1];

        assign dout  = shift_d[D-1];
        assign v_out = shift_v[D-1];

        always_ff @(posedge clk) begin
            if (rst) begin
                for (int i = 0; i < D; i++) begin
                    shift_d[i] <= '0;
                    shift_v[i] <= 1'b0;
                end
            end else begin
                shift_d[0] <= din;
                shift_v[0] <= v_in;

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
    parameter OUT_WIDTH = 32,
    parameter N = 9,
    parameter M = 9
)

(   
    input clk,
    input rst,
    input logic valid_in_d [0:N-1],
    input logic valid_in_w [0:M-1],
    input logic signed [A_WIDTH-1:0] data_in [0:N-1],
    input logic signed [B_WIDTH-1:0] weight_in [0:M-1],
    output logic signed [OUT_WIDTH-1:0] final_out [0:N-1][0:M-1],  // truncated
    output logic ready
    
);

    wire signed [A_WIDTH-1:0] data [0:N-1][0:M];
    wire signed [B_WIDTH-1:0] weight [0:N][0:M-1];
    reg  signed [OUT_WIDTH-1:0] acc_out [0:N-1][0:M-1];
    reg signed [OUT_WIDTH-1:0] acc_out1 [0:N-1][0:M-1];
    reg signed [OUT_WIDTH-1:0] acc_out2 [0:N-1][0:M-1];
    
    reg buff_sel[0:N-1][0:M-1];
    reg buff_ch;
    reg done;

    wire  valid_d [0:N-1][0:M];
    wire  valid_w [0:N][0:M-1];

   


    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : init_bram_d

           
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
        end
    endgenerate

    generate
        for (i = 0; i < M; i = i + 1) begin : init_bram_w

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
            for (k = 0; k < M; k = k + 1) begin : PE_col


                dsp_mac #(
                    .A_WIDTH        (A_WIDTH),
                    .B_WIDTH        (B_WIDTH),
                    .ACC_WIDTH      (OUT_WIDTH)
                ) u_dsp_mac (
                    .clk            (clk),
                    .rst            (rst),
                    .a              (data[j][k]),
                    .b              (weight[j][k]),
                    .valid_in_d     (valid_d[j][k]),
                    .valid_in_w     (valid_w[j][k]),
                    .a_shifted      (data[j][k+1]),
                    .b_shifted      (weight[j+1][k]),
                    .final_out      (acc_out[j][k]),
                    .valid_out_d    (valid_d[j][k+1]),
                    .valid_out_w    (valid_w[j+1][k]),
                    .buff_sel       (buff_sel[j][k])
                );

                        
        end
        end
    endgenerate

    

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int r = 0; r < N; r = r + 1)
                for (int c = 0; c < M; c = c + 1) begin
                    acc_out1[r][c] <= '0;
                    acc_out2[r][c] <= '0;
                end
        end
        else begin

            buff_ch <= buff_sel[N-1][M-1];
            ready <= buff_ch ^ buff_sel[N-1][M-1];
            //  ready <= done;


            for (int r = 0; r < N; r = r + 1)
                for (int c = 0; c < M; c = c + 1) begin
                    if (!buff_sel[r][c])
                        acc_out1[r][c] <= acc_out[r][c];
                    else
                        acc_out2[r][c] <= acc_out[r][c];
                end

            if (ready) begin
                for (int r = 0; r < N; r++)
                    for (int c = 0; c < M; c++)
                        final_out[r][c] = buff_sel[N-1][M-1] ? acc_out2[r][c][OUT_WIDTH-1:0] : acc_out1[r][c][OUT_WIDTH-1:0];
            end
                
        end
    end
  
    
endmodule


module bram_reader #(

    parameter DATA_WIDTH = 16,
    parameter M = 9

)
(

    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [DATA_WIDTH*M-1:0] bram_read,   
    output reg  [DATA_WIDTH*M-1:0] bram_write,
    output  wire [DATA_WIDTH*M-1:0] kernel, 
    output reg  [9:0] bram_addr,
    output wire [31:0]  bram_wr_en,
    output reg        bram_en,
    output reg kernel_ready

);

    
    reg [9:0] addr_countr;
   
    assign bram_wr_en = 32'b0;
    
    assign kernel = bram_read;

    always @(posedge clk) begin
        if (rst) begin
            addr_countr  <= 'b0;
            bram_addr    <= 'b0;
            bram_en  <= 1'b0;
            kernel_ready <= 1'b0;
        end
        else if (start) begin
            bram_en <= 1'b1;
            bram_addr  <= addr_countr;
            addr_countr <= addr_countr + 1; // add limit if needed
            kernel_ready <= bram_en;
        end
        else begin
            bram_en <= 1'b0;
            bram_addr  <= 'b0;
            addr_countr <= 'b0;   // add limit if needed
            kernel_ready <= 1'b0;
        end

    end
endmodule

module bias_reader #(
    parameter DATA_WIDTH = 16,
    parameter K = 9
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     bias_valid,   // trigger pulse
    input  wire                     start,        // run enable
    input  wire [DATA_WIDTH*K-1:0]  bias_read,

    output reg  [DATA_WIDTH*K-1:0]  bias_write,
    output wire [DATA_WIDTH*K-1:0]  bias,
    output reg  [9:0]               bias_addr,
    output wire [31:0]              bias_wr_en,
    output reg                      bias_en,
    output reg                     bias_ready
);

    reg       started;   // sticky latch

    assign bias_wr_en = 32'b0;
    assign bias       = bias_read;

    always_ff @(posedge clk) begin
        if (rst) begin
            bias_addr   <= '0;
            bias_en     <= 1'b0;
            started     <= 1'b0;
            bias_ready <= 1'b0;
        end


        else if (bias_valid) begin
            started <= 1'b1;
            bias_addr <= bias_addr + 1;
        end

        else if (started) begin
            bias_addr <= bias_addr + 1;
            started <= start;
        end

        else if (start) begin
            bias_en <= 1'b1;
            bias_addr <= 'b0;
        end

    end

endmodule


module control#(
    parameter DATA_WIDTH = 16,
    parameter ACC_WIDTH =48,
    parameter OUT_WIDTH = 32,
    parameter N = 9,
    parameter M = 9
    
)
(
    input clk,
    input rst,
    input start,
    input logic [DATA_WIDTH*N-1:0] pixel,
    input  wire [DATA_WIDTH*M-1:0] bram_read,   
    output reg  [DATA_WIDTH*M-1:0] bram_write,
    output reg  [9:0] bram_addr,
    output wire [31:0]  bram_wr_en,
    output wire        bram_en,

    input  wire [DATA_WIDTH*M-1:0] bias_read,   
    output reg  [DATA_WIDTH*M-1:0] bias_write,
    output reg  [9:0] bias_addr,
    output wire [31:0]  bias_wr_en,
    output wire        bias_en,

    output reg [OUT_WIDTH*N-1:0] data_out
    
);

    logic signed [DATA_WIDTH-1:0] data_in [0:N-1];
    logic signed [DATA_WIDTH-1:0] weight_in [0:M-1];
    logic signed [OUT_WIDTH-1:0] final_out [0:N-1][0:M-1]; // TRUNCATED TO DATA WIDTH
    logic signed [OUT_WIDTH*N-1:0] bias;  //TRUNCATED TO DATA WIDTH
    logic valid_in_d [0:N-1];
    logic valid_in_w [0:M-1];
    logic kernel_ready, bias_ready;
    logic [DATA_WIDTH*M-1:0] kernel;
    logic ready;
    logic bias_start,acc_start,started;
    logic [$clog2(N)-1:0] counter;

    logic signed [OUT_WIDTH*M-1:0] data_array [0:N-1];

    genvar i, j;
    generate
        for (i = 0; i < N; i++) begin : ROWS
            for (j = 0; j < M; j++) begin : COLS
                assign data_array[i][(M-j)*OUT_WIDTH-1 -: OUT_WIDTH]
                    = final_out[i][j];
            end
        end
    endgenerate
    
   

        Sys_array_test #(
        .A_WIDTH       (DATA_WIDTH),
        .B_WIDTH       (DATA_WIDTH),
        .ACC_WIDTH     (ACC_WIDTH),
        .OUT_WIDTH     (OUT_WIDTH),
        .N             (N),
        .M             (M)
    ) u_Sys_array_test (
        .clk           (clk),
        .rst           (rst),
        .valid_in_d    (valid_in_d),
        .valid_in_w    (valid_in_w),
        .data_in       (data_in),
        .weight_in     (weight_in),
        .final_out     (final_out),
        .ready         (ready)
    );

        bram_reader #(
        .DATA_WIDTH      (DATA_WIDTH),
        .M               (M)
        ) u_bram_weights (
        .clk             (clk),
        .rst             (rst),
        .start           (start),
        .bram_read       (bram_read),
        .bram_write      (bram_write),
        .kernel          (kernel),
        .bram_addr       (bram_addr),
        .bram_wr_en      (bram_wr_en),
        .bram_en         (bram_en),
        .kernel_ready    (kernel_ready)
    );

        bias_reader #(
        .DATA_WIDTH    (DATA_WIDTH),
        .K             (M)
    ) u_bias_reader (
        .clk           (clk),
        .rst           (rst),
        .bias_valid    (ready),
        // trigger pulse
        .start         (start),
        // run enable
        .bias_read     (bias_read),
        .bias_write    (bias_write),
        .bias          (bias),
        .bias_addr     (bias_addr),
        .bias_wr_en    (bias_wr_en),
        .bias_en       (bias_en)
    );

        

    always @(posedge clk) begin

        bias_start <= ready;
        //acc_start  <= bias_start;

        /*if (bias_start) begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < M; j++) begin
                    data_array[i][(M-j)*OUT_WIDTH-1 -: OUT_WIDTH]
                        <= final_out[i][j];
                end
            end
        end*/

        if(rst) begin
            counter <= 'b0;
            started <= 1'b0;
            for (int i = 0; i < N; i++) begin
                data_in[i] <= 'b0;
                valid_in_d[i] <='b0;
            end
            for (int j = 0; j < M; j++) begin
                weight_in[j] <= 'b0;
                valid_in_w[j] <='b0;
            end

        end

        else if (start && kernel_ready) begin
           for (int k = 0; k < N; k++) begin
                data_in[k] <= pixel[(N-1-k)*DATA_WIDTH +: DATA_WIDTH];
                valid_in_d[k] <= 1'b1;
            end
            for (int l = 0; l < M; l++) begin
                weight_in[l] <= kernel[(M-1-l)*DATA_WIDTH +: DATA_WIDTH];
                valid_in_w[l] <='b1;
            end
        end

        else begin
            for (int i = 0; i < N; i++) begin
                data_in[i] <= 'b0;
                valid_in_d[i] <='b0;
            end
            for (int j = 0; j < M; j++) begin
                weight_in[j] <= 'b0;
                valid_in_w[j] <='b0;
            end
        end 

        if (bias_start) begin
            started <= 1'b1;
            counter <= (counter == N-1) ? 'b0 : counter+1;
            data_out <= bias + data_array[counter];
        end

        else if (started) begin
            started <= start;
            counter <= (counter == N-1) ? 'b0 : counter+1;
            data_out <= bias + data_array[counter];
        end
    end



endmodule


module double_buffer
#(
    parameter DATA_WIDTH = 16,
    parameter N = 9,
    parameter M = 9

)
(
    input   logic clk,
    input   logic rst,
    input   logic sel,
    input   logic preload,
    input   logic [DATA_WIDTH-1:0] data,
    output  logic    [$clog2(N*M)-1:0] addr,
    output  logic         we,ready,done,
    output  logic [DATA_WIDTH-1:0] data_out [0:N-1]
            
            
);

    
    reg [$clog2(M)-1:0] counter;
    reg [DATA_WIDTH-1:0] buff [0:N-1][0:M-1];
    reg [$clog2(N)-1:0] row;
    reg [$clog2(M)-1:0] col;



    always @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < M; j++) begin
                    buff[i][j] <= '0;
                end
            end
            for (int i = 0; i < N; i++) begin
                data_out[i] <= '0;
            end
            addr <='b0;
            we <=1'b0;
            counter <= 'b0;
            row <= 'b0;
            col <= 'b0;
            ready <= 1'b0;
            done <= 1'b0;

        end

        else if (preload && ~ready) begin

            buff[row][col] <= data;
            addr <= addr + 1;

            if (col == M-1) begin
                col <= 0;
                row <= row + 1;
            end else begin
                col <= col + 1;
            end
           
            
            if (row == N-1 && col == M-1) begin
                ready <= 1'b1;
                row <='b0;
                col <='b0; 
                done <= 1'b0;
            end

        end

        else if (sel && ~done) begin
            // ---- OUTPUT ONE COLUMN PER CLOCK ----
        
            for (int i = 0; i < N; i++) begin
                data_out[i] <= buff[i][counter];
            end
            if (counter == M-1) begin
                counter <= 'b0; 
                done <= 1'b1;  
                ready <= 1'b0;
                addr <='b0;
            end       
            else begin
                counter <= counter + 1; 
            end
            end

    end

endmodule

