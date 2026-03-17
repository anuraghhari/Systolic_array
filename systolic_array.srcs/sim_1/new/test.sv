`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/07/2026 08:55:28 PM
// Design Name: 
// Module Name: test
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



/*module tb_sys_array;

    localparam A_WIDTH   = 16;
    localparam B_WIDTH   = 16;
    localparam ACC_WIDTH = 48;

    logic clk;
    logic rst;

    logic valid_in_d [0:8];
    logic valid_in_w [0:8];
    logic signed [A_WIDTH-1:0] data_in   [0:8];
    logic signed [B_WIDTH-1:0] weight_in [0:8];
    logic signed [ACC_WIDTH-1:0] acc_out [0:8][0:8];

    reg signed [A_WIDTH-1:0] data [0:8][0:8];
    reg signed [B_WIDTH-1:0] weight [0:8][0:8];
    reg signed [ACC_WIDTH-1:0] out_flat [0:80];
    int idx;
    


        Sys_array_test #(
        .A_WIDTH       (16),
        .B_WIDTH       (16),
        .ACC_WIDTH     (48),
        .N             (9),
        .M             (9)
    ) u_Sys_array_test (
        .clk           (clk),
        .rst           (rst),
        .valid_in_d    (valid_in_d),
        .valid_in_w    (valid_in_w),
        .data_in       (data_in),
        .weight_in     (weight_in),
        .acc_out       (acc_out)
    );
    

    initial begin
        $readmemh("im2col.mem",data);
        $readmemh("weights.mem",weight);
    end

        

    // -------------------------------------------------
    // Clock: 10ns period
    // -------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------
    // Test
    // -------------------------------------------------
    initial begin
        clk = 0;
        rst = 1;

        valid_in_d = '{default:0};
        valid_in_w = '{default:0};
        data_in    = '{default:0};
        weight_in  = '{default:0};

        // Reset
        #20;
        rst = 0;

        // -----------------------------
        // Cycle 0: feed k = 0
        // A(:,0) and B(0,:)
        // -----------------------------
        

        for (int i=0; i<9; i+=1) begin
            @(posedge clk);

            valid_in_d = '{default:1};
            valid_in_w = '{default:1};
            for (int j=0; j<9; j+=1) begin
                data_in[j] <= data[j][i];
            end
            for (int j=0; j<9; j+=1) begin
                weight_in[j] <= weight[j][i];
            end
        end
        
        repeat (8) @(posedge clk);
        // -----------------------------
        // Stop input valids
        // -----------------------------
        @(posedge clk);
        valid_in_d = '{default:0};
        valid_in_w = '{default:0};
        data_in    = '{default:0};
        weight_in  = '{default:0};

        // Let systolic array drain
        repeat (50) @(posedge clk);

        for (int i = 0; i < 9; i++) begin        // kernels
                for (int j = 0; j < 9; j++) begin    // rows
                    out_flat[idx] = acc_out[j][i];
                    idx++;
                end
            end

        $writememh("output.hex", out_flat);
        $finish;


    end

endmodule*/


module tb_control;

    // --------------------------------------------------
    // Parameters
    // --------------------------------------------------
    parameter DATA_WIDTH = 16;
    parameter ACC_WIDTH  = 48;
    parameter OUT_WIDTH  = 32;
    parameter N = 9;
    parameter M = 9;

    // --------------------------------------------------
    // DUT signals
    // --------------------------------------------------
    reg clk;
    reg rst;
 

    reg  [DATA_WIDTH*N-1:0] pixel;
    reg  [DATA_WIDTH*M-1:0] bram_read;
    reg  [OUT_WIDTH*M-1:0]  bias_read;
    
    reg s_axis_tvalid   ;
    reg s_axis_tlast    ;
    reg [DATA_WIDTH*N-1:0] s_axis_tdata    ;
    wire s_axis_tready   ;

    reg  m_axis_tready;
    wire m_axis_tvalid;
    wire m_axis_tlast;
    wire [OUT_WIDTH*N-1:0] m_axis_tdata;
    

    wire [DATA_WIDTH*M-1:0] bram_write;
    wire [9:0]              bram_addr;
    wire [31:0]             bram_wr_en;
    wire                    bram_en;
    wire                    ready;

    wire [DATA_WIDTH*M-1:0] bias_write;
    wire [9:0]              bias_addr;
    wire [31:0]             bias_wr_en;
    wire                    bias_en;
    wire s_axis_tready;



    // --------------------------------------------------
    // TB-side memories
    // --------------------------------------------------
    reg [DATA_WIDTH*N-1:0] pixel_mem  [0:255];
    reg [DATA_WIDTH*M-1:0] weight_mem [0:255];
    reg [OUT_WIDTH*M-1:0]  bias_mem   [0:255];

    // --------------------------------------------------
    // DUT
    // --------------------------------------------------
    sys_feeder #(
    .DATA_WIDTH       (16),
    .ACC_WIDTH        (48),
    .OUT_WIDTH        (32),
    .N                (9),
    .M                (9)
) u_feeder (
    .clk              (clk),
    .rst              (rst),
    .s_axis_tvalid    (s_axis_tvalid),
    .s_axis_tlast     (s_axis_tlast),
    .s_axis_tdata     (s_axis_tdata),
    .s_axis_tready    (s_axis_tready),
    .bram_read        (bram_read),
    .bias_read        (bias_read),
    .bram_write       (bram_write),
    .bram_addr        (bram_addr),
    .bram_wr_en       (bram_wr_en),
    .bram_en          (bram_en),
    .bias_write       (bias_write),
    .bias_addr        (bias_addr),
    .bias_wr_en       (bias_wr_en),
    .bias_en          (bias_en),
    .m_axis_tready    (m_axis_tready),
    .m_axis_tvalid    (m_axis_tvalid),
    .m_axis_tlast     (m_axis_tlast),
    .m_axis_tdata     (m_axis_tdata)
);
    // --------------------------------------------------
    // Clock (100 MHz)
    // --------------------------------------------------
    always #5 clk = ~clk;

    // --------------------------------------------------
    // BRAM model (1-cycle latency)
    // --------------------------------------------------
    always @(posedge clk) begin
        if (bram_en)
            bram_read <= weight_mem[bram_addr];
    end

    always @(posedge clk) begin
        if (bias_en)
            bias_read <= bias_mem[bias_addr];
    end



    // --------------------------------------------------
    // Test sequence
    // --------------------------------------------------
    initial begin
        // Init
        clk   = 0;
        rst   = 1;
        //valid = 0;
        //last  = 0;
        s_axis_tdata = 0;
        bram_read = 0;
        bias_read = 0;

        s_axis_tlast =0;
        s_axis_tvalid =0;
        m_axis_tready =1;

        // Load memories
        $readmemh("pixel.mem",   pixel_mem);
        $readmemh("weights.mem", weight_mem);
        $readmemh("bias.mem",    bias_mem);

        // Reset
        repeat (4) @(posedge clk);
        rst = 0;


            // Start transaction
        @(negedge clk);
        s_axis_tvalid = 1'b1;

        for (int i = 0; i < 9; i++) begin

            // Wait until DUT is ready
            wait (s_axis_tready == 1'b1);

            @(negedge clk);
            s_axis_tdata = pixel_mem[i];
            s_axis_tlast = (i == 8);

        end

        // End transaction
        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;


        repeat(20) @(negedge clk);
            // Start transaction
        @(negedge clk);
        s_axis_tvalid = 1'b1;

        for (int i = 0; i < 9; i++) begin

            // Wait until DUT is ready
            wait (s_axis_tready == 1'b1);

            @(negedge clk);
            s_axis_tdata = pixel_mem[i];
            s_axis_tlast = (i == 8);

        end

        // End transaction
        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;

            $finish;
        end





endmodule