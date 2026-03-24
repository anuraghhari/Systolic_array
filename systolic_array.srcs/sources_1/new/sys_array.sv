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

/* WORKS TO BE DONE

MAKE START LATCHED ACCORDING TO DMA SIGNALS OF HANDSHAKE

START SHOULD BE MADE ZERO NEXT CLOCK OF SENDING LAST PIXEL 

START AND BRAM AND BIAS ADDRESS SHOULD COME AT SAME TIME ON NEXT CYCLE DATA COMES AND GOES TO SYSTOLIC ARRAY

*/

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
        input  wire    clk,
        input  wire    rst,   
        input  wire    last,

        input  wire signed [A_WIDTH-1:0] a,
        input  wire signed [B_WIDTH-1:0] b,
        input  wire                     valid_in_d,
        input  wire                     valid_in_w,
        output reg  [A_WIDTH-1:0] a_shifted,
        output reg  [B_WIDTH-1:0] b_shifted,
        output reg  last_shifted,

        output reg  signed [ACC_WIDTH-1:0] final_out,
        output reg                      valid_out_d,
        output reg                      valid_out_w,
        output reg buff_sel

    );

            wire  signed [ACC_WIDTH-1:0] acc;
            reg  signed [ACC_WIDTH-1:0] acc_out;
            reg last_reg;
            
            

            // ------------------------------------------------
            // Multiply and Accumulate (DSP)
            // ------------------------------------------------
            (* use_dsp = "yes" *)
            
            wire acc_done;
            assign acc_done  = last_reg;
            assign acc = (last_reg)? 'b0 : acc_out;
            


            always @(posedge clk) begin

                if (rst) begin
                   
                    acc_out     <= 0;
                    valid_out_d <= 0;
                    valid_out_w <= 0;
                    a_shifted   <= 0;
                    b_shifted   <= 0;
                    last_shifted <= 0;
                    buff_sel    <= 1'b0;
                    last_reg    <= 1'b0;

                end 

                else if  (valid_in_d && valid_in_w) begin

                    acc_out <= acc + a*b;     // SAME DSP adder   
                    a_shifted <= a;
                    b_shifted <= b;
                    valid_out_d <= 1'b1;
                    valid_out_w <= 1'b1;
                    last_shifted <= last;
                    last_reg <= last;

                    final_out <= (acc_done) ? acc_out : final_out;
                    buff_sel <= (acc_done) ? ~buff_sel : buff_sel;
                end
                
                else begin
                    last_shifted <= last;
                    last_reg <= last;
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

module delay_last #(
    parameter D = 1
)(
    input  logic             clk,
    input  logic             rst,
    input  logic             v_in,
    output logic             v_out
);

    generate
    if (D == 0) begin : gen_no_delay
        assign v_out = v_in;
    end
    else begin : gen_delay
        logic             shift_v [0:D-1];

        assign v_out = shift_v[D-1];

        always_ff @(posedge clk) begin
            if (rst) begin
                for (int i = 0; i < D; i++) begin
                    shift_v[i] <= 1'b0;
                end
            end else begin
                shift_v[0] <= v_in;

                for (int i = 1; i < D; i++) begin
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
    input logic last_in_shifted [0:N-1],
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

    wire   last [0:N-1][0:M];
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

    generate
        for (i = 0; i < N; i = i + 1) begin : init_tlast

        delay_last #(
            .D        (i)
        ) u_delay_last (
            .clk      (clk),
            .rst      (rst),
            .v_in     (last_in_shifted[i]),
            .v_out    (last[i][0])
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
                    .last           (last[j][k]),
                    .a_shifted      (data[j][k+1]),
                    .b_shifted      (weight[j+1][k]),
                    .last_shifted   (last[j][k+1]),
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
            //ready <= done;


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
    input  wire  [9:0] addr_in_w,
    input  wire [DATA_WIDTH*M-1:0] bram_read,   
    output reg  [DATA_WIDTH*M-1:0] bram_write,
    output wire [DATA_WIDTH*M-1:0] kernel, 
    output wire [9:0] bram_addr,
    output wire [(DATA_WIDTH*M)/8-1:0]  bram_wr_en,
    output         bram_en,
    output reg kernel_ready

);
    
    assign bram_wr_en = 'b0;
    
    assign kernel = bram_read;
    assign bram_en = start;
    assign bram_addr = addr_in_w;
   
    always @(posedge clk) begin
        if (rst) begin
            kernel_ready <= 1'b0;
            //bram_addr <= 'b0;
        end
        else if (start) begin
            //bram_addr <= bram_addr+1;
            kernel_ready <= bram_en;
        end
        else begin
            //bram_addr <= 'b0;
            kernel_ready <= 1'b0;
        end

    end
endmodule



/*module bias_reader #(
    parameter DATA_WIDTH = 16,
    parameter K = 9
)(
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         bias_valid,     // trigger pulse
    input  wire [9:0]                   addr_in_b,
    input  wire [DATA_WIDTH*K-1:0]      bias_read,
    output reg  [DATA_WIDTH*K-1:0]      bias_write,
    output wire [DATA_WIDTH*K-1:0]      bias,
    output wire [9:0]                   bias_addr,
    output wire [(DATA_WIDTH*K)/8-1:0]  bias_wr_en,
    output reg                          bias_en,
    output reg                          bias_data_valid  // 1 cycle after bias_en, data is ready
);

    logic [$clog2(K)-1:0] counter;

    assign bias_wr_en = '0;
    assign bias       = bias_read;
    assign bias_addr  = addr_in_b;

    always_ff @(posedge clk) begin
        if (rst) begin
            bias_en         <= 1'b0;
            bias_data_valid <= 1'b0;
            counter         <= '0;
        end

        else if (bias_valid) begin
            bias_en         <= 1'b1;   // enable BRAM, addr=0 this cycle
            bias_data_valid <= 1'b0;   // data not ready yet (BRAM needs 1 cycle)
            counter         <= '0;
        end

        else if (bias_en) begin
            bias_data_valid <= 1'b1;   // data is valid NOW (1 cycle after en)

            if (counter == K-1) begin
                bias_en         <= 1'b0;   // stop after K reads
                bias_data_valid <= 1'b0;   // last data consumed this cycle
                counter         <= '0;
            end
            else begin
                counter <= counter + 1;
            end
        end

        else begin
            bias_data_valid <= 1'b0;
        end
    end

endmodule*/

module bias_reader #(
    parameter DATA_WIDTH = 16,
    parameter K = 9
)(
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         bias_valid,
    input  wire                         tlast_sent,     // NEW: en goes low on tlast
    input  wire [9:0]                   addr_in_b,
    input  wire [DATA_WIDTH*K-1:0]      bias_read,
    output reg  [DATA_WIDTH*K-1:0]      bias_write,
    output wire [DATA_WIDTH*K-1:0]      bias,
    output wire [9:0]                   bias_addr,
    output wire [(DATA_WIDTH*K)/8-1:0]  bias_wr_en,
    output reg                          bias_en,
    output reg                          bias_data_valid
);

    assign bias_wr_en = '0;
    assign bias       = bias_read;
    assign bias_addr  = addr_in_b;

    always_ff @(posedge clk) begin
        if (rst) begin
            bias_en         <= 1'b0;
            bias_data_valid <= 1'b0;
        end

        else if (bias_valid) begin
            bias_en         <= 1'b1;   // turn on when result ready
            bias_data_valid <= 1'b0;
        end

        else if (tlast_sent) begin
            bias_en         <= 1'b0;   // turn off ONLY when tlast accepted
            bias_data_valid <= 1'b0;
        end

        else if (bias_en) begin
            bias_data_valid <= 1'b1;   // data valid 1 cycle after en
        end

        else begin
            bias_data_valid <= 1'b0;
        end
    end

endmodule


module sys_feeder#(
    parameter DATA_WIDTH = 16,
    parameter ACC_WIDTH =48,
    parameter OUT_WIDTH = 32,
    parameter N = 9,
    parameter M = 9
    
)
(
    input clk,
    input rst,


    input s_axis_tvalid,
    input s_axis_tlast,
    input wire signed [DATA_WIDTH*N-1:0] s_axis_tdata,
    output reg s_axis_tready,

    input  wire signed [DATA_WIDTH*M-1:0] bram_read, 
    input  wire signed [OUT_WIDTH*M-1:0] bias_read,     
    output reg  [DATA_WIDTH*M-1:0] bram_write,
    output reg  [9:0] bram_addr,
    output wire [31:0]  bram_wr_en,
    output wire        bram_en,
    output reg  [DATA_WIDTH*M-1:0] bias_write,
    output reg  [9:0] bias_addr,
    output wire [31:0]  bias_wr_en,
    output wire        bias_en,

    input  m_axis_tready,
    output reg m_axis_tvalid,
    output reg m_axis_tlast,
    output reg [OUT_WIDTH*N-1:0] m_axis_tdata
    
);

    reg signed [DATA_WIDTH-1:0] data_in [0:N-1];
    reg signed [DATA_WIDTH-1:0] weight_in [0:M-1];
    reg signed [OUT_WIDTH-1:0] final_out [0:N-1][0:M-1]; // TRUNCATED TO OUT WIDTH
    reg signed [OUT_WIDTH*N-1:0] bias;  //TRUNCATED TO OUT WIDTH
    reg valid_in_d [0:N-1];
    reg valid_in_w [0:M-1];
    reg last_in_shifted [0:N-1];
    reg kernel_ready, bias_ready;
    reg [DATA_WIDTH*M-1:0] kernel;
    reg bias_start,acc_start,started;
    reg [$clog2(N)-1:0] counter;
    wire ready;

    reg signed [OUT_WIDTH*M-1:0] data_array [0:N-1];

    reg [9:0] addr_in_w;
    reg [9:0] addr_in_b;
    reg start,last;

    reg bias_start_d;
    reg tvalid_d;
    reg [9:0] addr_in_w_saved,addr_in_b_saved;   // holds address at moment of stall
    reg stream_active;
    reg bias_data_valid;  
    reg output_active;
    reg bp_latched;

    wire tlast_sent = m_axis_tvalid && m_axis_tready && m_axis_tlast;
    wire bias_pause   = m_axis_tvalid && !m_axis_tready;




    genvar i, j;
    generate
        for (i = 0; i < N; i++) begin : ROWS
            for (j = 0; j < M; j++) begin : COLS
                assign data_array[i][(M-j)*OUT_WIDTH-1 -: OUT_WIDTH] = final_out[i][j];
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
        .last_in_shifted (last_in_shifted),
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
        .addr_in_w       (addr_in_w),
        .bram_read       (bram_read),
        .bram_write      (bram_write),
        .kernel          (kernel),
        .bram_addr       (bram_addr),
        .bram_wr_en      (bram_wr_en),
        .bram_en         (bram_en),
        .kernel_ready    (kernel_ready)
    );
    
        bias_reader #(
        .DATA_WIDTH (16), .K (9)
    ) u_bias_reader (
        .clk            (clk),
        .rst            (rst),
        .bias_valid     (ready),
        .tlast_sent     (tlast_sent),   // en goes low here
        .addr_in_b      (addr_in_b),
        .bias_read      (bias_read),
        .bias_write     (bias_write),
        .bias           (bias),
        .bias_addr      (bias_addr),
        .bias_wr_en     (bias_wr_en),
        .bias_en        (bias_en),
        .bias_data_valid(bias_data_valid)
    );
        

    always @(posedge clk) begin

        last <= s_axis_tlast;
        bias_start<=ready;
        bias_start_d <= bias_start;
       
        if(rst) begin
            counter <= 'b0;
            started <= 1'b0;
            start <= 1'b0;
            tvalid_d <= 1'b0;
            addr_in_w_saved <= 'b0;
            addr_in_w <= 'b0;
            addr_in_b_saved <= 'b0;
            addr_in_b <= 'b0;
            stream_active <= 1'b0;

            m_axis_tvalid  <= 1'b0;
            m_axis_tlast   <= 1'b0;
            m_axis_tdata   <= '0;
            output_active  <= 1'b0;


            for (int i = 0; i < N; i++) begin
                data_in[i] <= 'b0;
                valid_in_d[i] <='b0;
                last_in_shifted[i] <= 1'b0;
            end
            for (int j = 0; j < M; j++) begin
                weight_in[j] <= 'b0;
                valid_in_w[j] <='b0;
            end

        end

        else begin
         
           // stream_active: set on first tvalid after idle, cleared after tlast
            stream_active <= s_axis_tlast  ? 1'b0 :
                             s_axis_tvalid ? 1'b1 :
                             stream_active;
            
            tvalid_d <= s_axis_tvalid & stream_active;
            
            start         <= tvalid_d;
            s_axis_tready <= start;
                        
            
            if (s_axis_tvalid && start) begin
                addr_in_w       <= addr_in_w + 1;
                addr_in_w_saved <= addr_in_w;     // save address BEFORE increment
            end
            else begin
                addr_in_w <= addr_in_w_saved;
            end

            if (ready) begin
                addr_in_b <= '0;
                bp_latched <= 1'b0;
            end
            else if (bias_pause & !bp_latched) begin
                // tready just went low or is still low —
                // hold addr at (current - 1) so BRAM re-presents
                // the value that hasn't been consumed yet
                addr_in_b <= addr_in_b - 1;
                bp_latched <= 1'b1;
            end
            else if (!bias_pause && bp_latched ) begin
                bp_latched <= 1'b0;            // clear latch when tready returns
            end

            else if (bias_en && !bias_pause) begin
                addr_in_b  <= addr_in_b + 1;  // normal advance
            end
            

            if (kernel_ready) begin
                if (last) begin
                    for (int k = 0; k < N; k++) begin
                        data_in[k] <= 'b0;
                        valid_in_d[k] <= 1'b1;
                        last_in_shifted[k] <= s_axis_tlast;
                    end
                    for (int l = 0; l < M; l++) begin
                        weight_in[l] <= 'b0;
                        valid_in_w[l] <= 1'b1;
                    end
                end
            
                else begin
                    for (int k = 0; k < N; k++) begin
                            data_in[k] <= s_axis_tdata[(N-1-k)*DATA_WIDTH +: DATA_WIDTH];
                            valid_in_d[k] <= 1'b1;
                            last_in_shifted[k] <= s_axis_tlast;
                        end
                        for (int l = 0; l < M; l++) begin
                            weight_in[l] <= kernel[(M-1-l)*DATA_WIDTH +: DATA_WIDTH];
                            valid_in_w[l] <= 1'b1;
                        end
                    end
            end
                

            else begin
                for (int i = 0; i < N; i++) begin
                    valid_in_d[i] <='b0;
                end
                for (int j = 0; j < M; j++) begin
                    valid_in_w[j] <='b0;
                end
            end 

            if (bias_start_d) begin
                // First word — present it, wait for handshake
                m_axis_tvalid  <= 1'b1;
                m_axis_tlast   <= (N == 1) ? 1'b1 : 1'b0;
                m_axis_tdata   <= bias + data_array[counter];
              //  output_active  <= 1'b1;
                // DO NOT increment counter yet — wait for tready
            end

            else if (m_axis_tvalid && m_axis_tready) begin
                // Handshake complete — DMA accepted this word
                
                if (counter == N-1) begin
                    // Last word sent
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;
                    counter       <= '0;
                   // output_active <= 1'b0;
                end
                else begin
                    // More words to send — load next
                    counter      <= counter + 1;
                    m_axis_tdata <= bias + data_array[counter + 1];
                    m_axis_tlast <= (counter + 1 == N-1) ? 1'b1 : 1'b0;
                    // tvalid stays 1
                end
            end
        end
    end


endmodule


































/*module double_buffer
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

endmodule*/

