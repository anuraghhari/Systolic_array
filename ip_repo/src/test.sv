`timescale 1ns / 1ps
module tb_control;

    // --------------------------------------------------
    // Parameters
    // --------------------------------------------------
    parameter DATA_WIDTH = 16;
    parameter ACC_WIDTH  = 48;
    parameter OUT_WIDTH  = 32;
    parameter N          = 9;
    parameter M          = 9;

    // --------------------------------------------------
    // Stall knobs
    // --------------------------------------------------
    localparam STALL_AFTER_BEAT  = 3;
    localparam STALL_CYCLES      = 5;

    // Backpressure knobs (output side)
    localparam BP_AFTER_BEAT     = 2;   // pull tready LOW after this output beat
    localparam BP_CYCLES         = 6;   // how many cycles tready stays low

    localparam INTER_RUN_SETTLE  = 20;

    // --------------------------------------------------
    // DUT signals
    // --------------------------------------------------
    reg  clk, rst;

    reg                      s_axis_tvalid;
    reg                      s_axis_tlast;
    reg  [DATA_WIDTH*N-1:0]  s_axis_tdata;
    wire                     s_axis_tready;

    reg                      m_axis_tready;
    wire                     m_axis_tvalid;
    wire                     m_axis_tlast;
    wire [OUT_WIDTH*N-1:0]   m_axis_tdata;

    reg  [DATA_WIDTH*M-1:0]  bram_read;
    wire [DATA_WIDTH*M-1:0]  bram_write;
    wire [9:0]               bram_addr;
    wire [31:0]              bram_wr_en;
    wire                     bram_en;

    reg  [OUT_WIDTH*M-1:0]   bias_read;
    wire [DATA_WIDTH*M-1:0]  bias_write;
    wire [9:0]               bias_addr;
    wire [31:0]              bias_wr_en;
    wire                     bias_en;

    // --------------------------------------------------
    // TB-side memories
    // --------------------------------------------------
    reg [DATA_WIDTH*N-1:0]  pixel_mem  [0:255];
    reg [DATA_WIDTH*M-1:0]  weight_mem [0:255];
    reg [OUT_WIDTH*M-1:0]   bias_mem   [0:255];

    reg [OUT_WIDTH*N-1:0]   ref_mem   [0:63];
    reg [OUT_WIDTH*N-1:0]   stall_mem [0:63];
    reg [OUT_WIDTH*N-1:0]   bp_mem    [0:63];   // backpressure run capture
    integer                 ref_idx, stall_idx, bp_idx;

    reg [OUT_WIDTH*N-1:0]   out_mem [0:63];
    integer                 out_idx;

    // --------------------------------------------------
    // DUT instantiation
    // --------------------------------------------------
    sys_feeder #(
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .OUT_WIDTH  (OUT_WIDTH),
        .N          (N),
        .M          (M)
    ) u_feeder (
        .clk            (clk),
        .rst            (rst),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tlast   (s_axis_tlast),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tready  (s_axis_tready),
        .bram_read      (bram_read),
        .bram_write     (bram_write),
        .bram_addr      (bram_addr),
        .bram_wr_en     (bram_wr_en),
        .bram_en        (bram_en),
        .bias_read      (bias_read),
        .bias_write     (bias_write),
        .bias_addr      (bias_addr),
        .bias_wr_en     (bias_wr_en),
        .bias_en        (bias_en),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tlast   (m_axis_tlast),
        .m_axis_tdata   (m_axis_tdata)
    );

    // --------------------------------------------------
    // Clock 100 MHz
    // --------------------------------------------------
    initial clk = 0;
    always  #5 clk = ~clk;

    // --------------------------------------------------
    // BRAM weight model (1-cycle latency)
    // --------------------------------------------------
    always @(posedge clk) begin
        if (bram_en) bram_read <= weight_mem[bram_addr];
        else         bram_read <= '0;
    end

    // --------------------------------------------------
    // BRAM bias model (1-cycle latency)
    // --------------------------------------------------
    always @(posedge clk) begin
        if (bias_en) bias_read <= bias_mem[bias_addr];
        else         bias_read <= '0;
    end

    // --------------------------------------------------
    // Output monitor
    // --------------------------------------------------
    always @(posedge clk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            if (out_idx < 64) begin
                out_mem[out_idx] = m_axis_tdata;
                $display("[OUT] beat %0d : tdata=0x%0h  tlast=%0b  time=%0t",
                         out_idx, m_axis_tdata, m_axis_tlast, $time);
                out_idx = out_idx + 1;
            end
        end
    end

    // ==================================================
    // Task : wait_output_done
    // ==================================================
    task automatic wait_output_done;
        input string tag;
    begin
        wait (m_axis_tvalid && m_axis_tready && m_axis_tlast);
        @(posedge clk);
        $display("[%s]  m_axis_tlast seen — output complete  time=%0t", tag, $time);
        repeat (INTER_RUN_SETTLE) @(posedge clk);
        $display("[%s]  Settling done — ready for next run  time=%0t", tag, $time);
    end
    endtask

    // ==================================================
    // Task : send_beats
    // ==================================================
    task automatic send_beats;
        input logic   stall_en;
        input string  tag;
    begin
        integer i;

        @(negedge clk);
        s_axis_tvalid = 1'b1;

        i = 0;
        while (i < N) begin

            s_axis_tdata = pixel_mem[i];
            s_axis_tlast = (i == N-1) ? 1'b1 : 1'b0;

            wait (s_axis_tready === 1'b1);
            @(posedge clk);
            #1;

            $display("[%s]  beat %0d ACCEPTED  tdata=0x%0h  tlast=%0b  time=%0t",
                     tag, i, pixel_mem[i], s_axis_tlast, $time);

            if (stall_en && (i == STALL_AFTER_BEAT)) begin
                @(negedge clk);
                s_axis_tvalid = 1'b0;
                s_axis_tdata  = '0;
                $display("[%s]  >>> INPUT STALL: tvalid LOW for %0d cycles  time=%0t <<<",
                         tag, STALL_CYCLES, $time);

                repeat (STALL_CYCLES) @(posedge clk);

                @(negedge clk);
                s_axis_tdata  = pixel_mem[i+1];
                s_axis_tlast  = (i+1 == N-1) ? 1'b1 : 1'b0;
                @(negedge clk);
                s_axis_tvalid = 1'b1;
                $display("[%s]  >>> INPUT RESUME  time=%0t <<<", tag, $time);

                wait (s_axis_tready === 1'b1);
                @(posedge clk);
                #1;
                $display("[%s]  beat %0d ACCEPTED (post-stall)  tdata=0x%0h  tlast=%0b  time=%0t",
                         tag, i+1, pixel_mem[i+1], s_axis_tlast, $time);

                i = i + 2;
                continue;
            end

            i = i + 1;
        end

        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        s_axis_tdata  = '0;
        $display("[%s]  All input beats sent  time=%0t", tag, $time);
    end
    endtask

    // ==================================================
    // Task : send_beats_with_output_bp
    //   Sends a clean input burst BUT pulls m_axis_tready
    //   LOW after output beat BP_AFTER_BEAT for BP_CYCLES.
    //   Runs in parallel with a tready toggling thread.
    // ==================================================
    task automatic send_beats_with_output_bp;
        input string tag;
    begin
        integer i;

        // Launch tready backpressure thread in background
        fork
            begin : bp_thread
                // Wait until DUT starts producing output
                wait (m_axis_tvalid === 1'b1);

                // Let BP_AFTER_BEAT beats through normally
                repeat (BP_AFTER_BEAT) begin
                    wait (m_axis_tvalid && m_axis_tready);
                    @(posedge clk);
                end

                // Pull tready LOW
                @(negedge clk);
                m_axis_tready = 1'b0;
                $display("[%s]  >>> OUTPUT BP: tready LOW for %0d cycles  time=%0t <<<",
                         tag, BP_CYCLES, $time);

                // Hold low for BP_CYCLES
                repeat (BP_CYCLES) @(posedge clk);

                // Release tready
                @(negedge clk);
                m_axis_tready = 1'b1;
                $display("[%s]  >>> OUTPUT BP: tready HIGH again  time=%0t <<<", tag, $time);
            end
        join_none  // don't block — run alongside input sending

        // Send clean input burst (no input stall)
        @(negedge clk);
        s_axis_tvalid = 1'b1;

        i = 0;
        while (i < N) begin
            s_axis_tdata = pixel_mem[i];
            s_axis_tlast = (i == N-1) ? 1'b1 : 1'b0;

            wait (s_axis_tready === 1'b1);
            @(posedge clk);
            #1;

            $display("[%s]  beat %0d ACCEPTED  tdata=0x%0h  tlast=%0b  time=%0t",
                     tag, i, pixel_mem[i], s_axis_tlast, $time);
            i = i + 1;
        end

        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        s_axis_tdata  = '0;
        $display("[%s]  All input beats sent  time=%0t", tag, $time);
    end
    endtask

    // ==================================================
    // Task : capture_snapshot
    // ==================================================
    task automatic capture_snapshot;
        input  string                 tag;
        output reg [OUT_WIDTH*N-1:0]  dst_mem [0:63];
        output integer                dst_idx;
    begin
        integer k;
        dst_idx = out_idx;
        for (k = 0; k < dst_idx; k++)
            dst_mem[k] = out_mem[k];
        $display("[%s]  Snapshot: %0d beats captured  time=%0t",
                 tag, dst_idx, $time);
    end
    endtask

    // ==================================================
    // Task : compare_outputs
    // ==================================================
    task automatic compare_outputs;
        input string  label;
        input integer r_cnt;
        input integer s_cnt;
        input reg [OUT_WIDTH*N-1:0] r_mem [0:63];
        input reg [OUT_WIDTH*N-1:0] s_mem [0:63];
    begin
        integer b, pass;
        pass = 1;

        if (r_cnt !== s_cnt) begin
            $display("[CMP-%s] FAIL: count mismatch  ref=%0d  test=%0d", label, r_cnt, s_cnt);
            pass = 0;
        end else begin
            $display("[CMP-%s] Beat counts match: %0d", label, r_cnt);
            for (b = 0; b < r_cnt; b++) begin
                if (r_mem[b] !== s_mem[b]) begin
                    $display("[CMP-%s] MISMATCH beat %0d\n         ref =0x%0h\n         test=0x%0h",
                             label, b, r_mem[b], s_mem[b]);
                    pass = 0;
                end else begin
                    $display("[CMP-%s] OK beat %0d : 0x%0h", label, b, r_mem[b]);
                end
            end
        end

        $display("");
        if (pass)
            $display("[CMP-%s] *** PASS — outputs match reference ***", label);
        else
            $display("[CMP-%s] *** FAIL — output corrupted ***", label);
    end
    endtask

    // ==================================================
    // Main test sequence
    // ==================================================
    initial begin
        rst           = 1;
        s_axis_tvalid = 0;
        s_axis_tlast  = 0;
        s_axis_tdata  = '0;
        m_axis_tready = 1;
        bram_read     = '0;
        bias_read     = '0;
        out_idx       = 0;
        ref_idx       = 0;
        stall_idx     = 0;
        bp_idx        = 0;

        $readmemh("pixel.mem",   pixel_mem);
        $readmemh("weights.mem", weight_mem);
        $readmemh("bias.mem",    bias_mem);

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // ======================================================
        // RUN 1 : clean burst → golden reference
        // ======================================================
        $display("\n========================================");
        $display("[TB]  RUN 1: Clean burst (reference)");
        $display("========================================");

        send_beats(1'b0, "REF");
        wait_output_done("REF");
        capture_snapshot("REF", ref_mem, ref_idx);

        if (ref_idx > 0)
            $writememh("output_ref.hex", ref_mem, 0, ref_idx-1);
        else
            $display("[TB]  WARNING: RUN 1 produced no output beats!");

        out_idx = 0;

        // ======================================================
        // RUN 2 : input stall mid-burst
        // ======================================================
        $display("\n========================================");
        $display("[TB]  RUN 2: %0d-cycle INPUT stall after beat %0d",
                 STALL_CYCLES, STALL_AFTER_BEAT);
        $display("========================================");

        send_beats(1'b1, "STALL");
        wait_output_done("STALL");
        capture_snapshot("STALL", stall_mem, stall_idx);

        if (stall_idx > 0)
            $writememh("output_stall.hex", stall_mem, 0, stall_idx-1);
        else
            $display("[TB]  WARNING: RUN 2 produced no output beats!");

        out_idx = 0;

        // ======================================================
        // RUN 3 : output backpressure (tready goes LOW mid-output)
        // ======================================================
        $display("\n========================================");
        $display("[TB]  RUN 3: Output backpressure — tready LOW for %0d cycles after output beat %0d",
                 BP_CYCLES, BP_AFTER_BEAT);
        $display("========================================");

        m_axis_tready = 1'b1;   // start with tready high
        send_beats_with_output_bp("BP");
        wait_output_done("BP");
        capture_snapshot("BP", bp_mem, bp_idx);

        if (bp_idx > 0)
            $writememh("output_bp.hex", bp_mem, 0, bp_idx-1);
        else
            $display("[TB]  WARNING: RUN 3 produced no output beats!");

        // ======================================================
        // Comparisons
        // ======================================================
        $display("\n========================================");
        $display("[TB]  COMPARISON 1: REF vs INPUT-STALL");
        $display("========================================");
        compare_outputs("INP-STALL", ref_idx, stall_idx, ref_mem, stall_mem);

        $display("\n========================================");
        $display("[TB]  COMPARISON 2: REF vs OUTPUT-BACKPRESSURE");
        $display("========================================");
        compare_outputs("OUT-BP", ref_idx, bp_idx, ref_mem, bp_mem);

        $display("\n[TB]  Simulation complete  time=%0t", $time);
        $finish;
    end

    // --------------------------------------------------
    // Timeout watchdog
    // --------------------------------------------------
    initial begin
        #5_000_000;
        $display("[TB]  TIMEOUT — simulation exceeded 5 ms");
        $finish;
    end

    // --------------------------------------------------
    // Waveform dump
    // --------------------------------------------------
    initial begin
        $dumpfile("tb_control.vcd");
        $dumpvars(0, tb_control);
    end

endmodule
