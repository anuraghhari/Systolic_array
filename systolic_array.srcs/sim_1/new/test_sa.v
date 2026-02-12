`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/07/2026 08:52:10 PM
// Design Name: 
// Module Name: test_sa
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

`timescale 1ns/1ps

module tb_sys_array;

    localparam A_WIDTH   = 16;
    localparam B_WIDTH   = 16;
    localparam ACC_WIDTH = 40;

    logic clk;
    logic rst;

    logic valid_in_d [0:1];
    logic valid_in_w [0:1];
    logic [A_WIDTH-1:0] data_in   [0:1];
    logic [B_WIDTH-1:0] weight_in [0:1];

    // DUT
    Sys_array_test dut (
        .clk        (clk),
        .rst        (rst),
        .valid_in_d (valid_in_d),
        .valid_in_w (valid_in_w),
        .data_in    (data_in),
        .weight_in  (weight_in)
    );

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
        @(posedge clk);
        valid_in_d[0] = 1; data_in[0] = 1; // A[0][0]
        valid_in_d[1] = 1; data_in[1] = 3; // A[1][0]

        valid_in_w[0] = 1; weight_in[0] = 5; // B[0][0]
        valid_in_w[1] = 1; weight_in[1] = 6; // B[0][1]

        // -----------------------------
        // Cycle 1: feed k = 1
        // A(:,1) and B(1,:)
        // -----------------------------
        @(posedge clk);
        data_in[0] = 2; // A[0][1]
        data_in[1] = 4; // A[1][1]

        weight_in[0] = 7; // B[1][0]
        weight_in[1] = 8; // B[1][1]

        // -----------------------------
        // Stop input valids
        // -----------------------------
        @(posedge clk);
        valid_in_d = '{default:0};
        valid_in_w = '{default:0};
        data_in    = '{default:0};
        weight_in  = '{default:0};

        // Let systolic array drain
        repeat (6) @(posedge clk);

        $display("C[0][0] = %0d (expected 19)", dut.acc_out[0][0]);
        $display("C[0][1] = %0d (expected 22)", dut.acc_out[0][1]);
        $display("C[1][0] = %0d (expected 43)", dut.acc_out[1][0]);
        $display("C[1][1] = %0d (expected 50)", dut.acc_out[1][1]);

        $finish;
    end

endmodule

