`timescale 1ns/10ps

module systolic_array_tb;

    // ------------------------------------------------------------------------
    // Parameters 
    // ------------------------------------------------------------------------
    parameter int rows     = 64;
    parameter int cols     = 64;
    parameter int ip_width = 8;
    parameter int op_width = 32;
    parameter int k_dim    = 128;  // Stream length (K dimension)
    parameter int pipe_lat = 3;    // Must match DUT unless overridden

    // ------------------------------------------------------------------------
    // DUT I/O
    // ------------------------------------------------------------------------
    logic clk;
    logic rst;
    logic en;
    logic clr;

    logic [rows*ip_width-1:0] input_matrix;
    logic [cols*ip_width-1:0] weight_matrix;

    logic compute_done;
    logic [31:0] cycles_count;
    logic [rows*cols*op_width-1:0] output_matrix;

    // ------------------------------------------------------------------------
    // Test vector memories
    // ------------------------------------------------------------------------
    logic [rows*ip_width-1:0]        inputs_mem     [0:k_dim-1];
    logic [cols*ip_width-1:0]        weights_mem    [0:k_dim-1];
    logic [rows*cols*op_width-1:0]   golden_ref_mem [0:0];

    // ------------------------------------------------------------------------
    // DUT instantiation
    // ------------------------------------------------------------------------
    systolic_array #(
        .rows(rows),
        .cols(cols),
        .ip_width(ip_width),
        .op_width(op_width),
        .pipe_lat(pipe_lat)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .clr(clr),
        .input_matrix(input_matrix),
        .weight_matrix(weight_matrix),
        .compute_done(compute_done),
        .cycles_count(cycles_count),
        .output_matrix(output_matrix)
    );

    // ------------------------------------------------------------------------
    // Clock Generation (10ns period)
    // ------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------------
    // Waveform / Activity Dump Controls (optional)
    // ------------------------------------------------------------------------

`ifdef DUMP_SHM
    initial begin
        $shm_open("waves.shm");
        $shm_probe(systolic_array_tb, "AS");
    end
`endif

`ifdef DUMP_ACTIVITY_VCD

    localparam int DUMP_START_CYC = 20;   // cycles after en first goes high
    localparam int DUMP_LEN_CYC   = 500;  // number of cycles to dump

    initial begin : activity_vcd_dump
        wait (rst === 1'b0);
        wait (en  === 1'b1);

        repeat (DUMP_START_CYC) @(posedge clk);

        $dumpfile("activity.vcd");
        $dumpvars(0, dut);

        repeat (DUMP_LEN_CYC) @(posedge clk);

        $dumpoff;

`ifdef POWER_ONLY
        $display("POWER_ONLY: dumped activity window, exiting early.");
        $finish;
`endif
    end
`elsif DUMP_VCD
    initial begin
        $dumpfile("waves.vcd");
        $dumpvars(0, dut);
    end
`endif

    // ------------------------------------------------------------------------
    // Scalable Timeout Watchdog (cycle-based, sweep-safe)
    // Total expected from first feed cycle to done ≈ k_dim + that + margin.
    // ------------------------------------------------------------------------
    localparam int skew_lat       = (rows - 1) + (cols - 1);
    localparam int postfeed_lat   = skew_lat + pipe_lat + rows;
    localparam int exp_total_cyc  = k_dim + postfeed_lat;
    localparam int timeout_cycles = exp_total_cyc + 200;

    initial begin : watchdog
        int cyc;
        cyc = 0;

        wait (rst === 1'b0);

        while ((compute_done !== 1'b1) && (cyc < timeout_cycles)) begin
            @(posedge clk);
            cyc++;
        end

        if (compute_done !== 1'b1) begin
            $display("ERROR: Simulation Timed Out! compute_done never went high.");
            $display("  rows=%0d cols=%0d ip=%0d op=%0d k=%0d pipe_lat=%0d",
                     rows, cols, ip_width, op_width, k_dim, pipe_lat);
            $display("  Timeout at %0d cycles (expected approx %0d).",
                     timeout_cycles, exp_total_cyc);
            $finish;
        end
    end

    // ------------------------------------------------------------------------
    // Main Test
    // ------------------------------------------------------------------------
    initial begin : main
        $display("RUN CFG: rows=%0d cols=%0d ip=%0d op=%0d k=%0d pipe_lat=%0d",
                 rows, cols, ip_width, op_width, k_dim, pipe_lat);
        $readmemh("input_matrix.hex",  inputs_mem);
        $readmemh("weight_matrix.hex", weights_mem);
        $readmemh("golden_output.hex", golden_ref_mem);
        rst           = 1'b1;
        en            = 1'b0;
        clr           = 1'b0;
        input_matrix  = '0;
        weight_matrix = '0;

        repeat(10) @(posedge clk);
        #1 rst = 1'b0;

        $display("Starting Feed... K_DIM=%0d", k_dim);
        for (int k = 0; k < k_dim; k++) begin
            @(posedge clk);
            #1;
            en           = 1'b1;
            clr          = (k == 0);
            input_matrix = inputs_mem[k];
            weight_matrix= weights_mem[k];
        end

        @(posedge clk);
        #1;
        en            = 1'b0;
        clr           = 1'b0;
        input_matrix  = '0;
        weight_matrix = '0;

        $display("Feed Complete. Waiting for computation...");


        wait (compute_done === 1'b1);


        #10;
        if (output_matrix === golden_ref_mem[0]) begin
            $display("\n========================================");
            $display("   TEST PASSED! Dimensions: %0dx%0d", rows, cols);
            $display("   cycles_count (DUT): %0d", cycles_count);
            $display("========================================\n");
        end else begin
            $display("\n========================================");
            $display("   TEST FAILED!");
            $display("   cycles_count (DUT): %0d", cycles_count);
            $display("========================================\n");
        end

        $finish;
    end

endmodule
