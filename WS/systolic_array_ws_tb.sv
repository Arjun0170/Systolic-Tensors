`timescale 1ns/10ps

module systolic_array_ws_tb;

    // ------------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------------
    parameter int rows     = 16;
    parameter int cols     = 16;
    parameter int ip_width = 8;
    parameter int op_width = 32;
    parameter int k_dim    = 128;
    parameter int pipe_lat = 3;

    localparam int num_blocks = (k_dim + rows - 1) / rows;
    localparam int m_dim      = rows; // output rows (C is rows x cols)

    // ------------------------------------------------------------------------
    // WS timing
    //
    // TB drives AFTER posedge ( @(posedge clk); #1; ... )
    // There are TWO registered boundaries before PE pipeline effectively starts:
    //  1) boundary row-skew registers sample input_matrix
    //  2) PE stage-1 registers sample x_grid/w/psum at next posedge
    // Hence +2.
localparam int ws_base   = (rows-1) * (pipe_lat + 1) + pipe_lat + 2;
localparam int drain_len = ws_base + (cols-1);

    // ------------------------------------------------------------------------
    // DUT I/O
    // ------------------------------------------------------------------------
    logic clk;
    logic rst;
    logic en;
    logic clr;

    logic [rows*ip_width-1:0] input_matrix;
    logic [cols*ip_width-1:0] weight_matrix;

    logic [cols*op_width-1:0] psum_init_vec;

    logic compute_done;
    logic [31:0] cycles_count;
    logic [rows*cols*op_width-1:0] output_matrix;

    // ------------------------------------------------------------------------
    // Test vector memories
    // ------------------------------------------------------------------------
    logic [rows*ip_width-1:0]      inputs_mem     [0:(num_blocks*m_dim)-1];
    logic [cols*ip_width-1:0]      weights_mem    [0:k_dim-1];
    logic [rows*cols*op_width-1:0] golden_ref_mem [0:0];

    logic [cols*op_width-1:0] psum_mem      [0:m_dim-1];
    logic [cols*op_width-1:0] next_psum_mem [0:m_dim-1];

    logic [rows*cols*op_width-1:0] final_packed;

    // ------------------------------------------------------------------------
    // DUT instantiation
    // ------------------------------------------------------------------------
    systolic_array_ws #(
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
        .psum_init_vec(psum_init_vec),
        .compute_done(compute_done),
        .cycles_count(cycles_count),
        .output_matrix(output_matrix)
    );

    // ------------------------------------------------------------------------
    // Clock (10ns)
    // ------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk <= ~clk;

    // ------------------------------------------------------------------------
    // Watchdog
    // ------------------------------------------------------------------------
    localparam int exp_total_cyc =
        num_blocks * (rows /*load*/ + m_dim /*compute*/ + drain_len /*drain*/) + 400;

    initial begin : watchdog
        int cyc = 0;
        wait (rst === 1'b0);
        while ((compute_done !== 1'b1) && (cyc < exp_total_cyc)) begin
            @(posedge clk);
            cyc++;
        end
        if (compute_done !== 1'b1) begin
            $display("ERROR: Timeout. compute_done never asserted.");
            $display("  rows=%0d cols=%0d k_dim=%0d num_blocks=%0d pipe_lat=%0d",
                     rows, cols, k_dim, num_blocks, pipe_lat);
            $display("  Timeout at %0d cycles (expected approx %0d).",
                     exp_total_cyc, num_blocks * (rows + m_dim + drain_len));
            $finish;
        end
    end

    // ------------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------------
    initial begin : main
        $display("WS RUN: rows=%0d cols=%0d ip=%0d op=%0d k_dim=%0d blocks=%0d pipe_lat=%0d",
                 rows, cols, ip_width, op_width, k_dim, num_blocks, pipe_lat);
        $display("WS timing: ws_base=%0d drain_len=%0d", ws_base, drain_len);

        $readmemh("input_matrix.hex",  inputs_mem);
        $readmemh("weight_matrix.hex", weights_mem);
        $readmemh("golden_output.hex", golden_ref_mem);

        // Reset init
        rst           = 1'b1;
        en            = 1'b0;
        clr           = 1'b0;
        input_matrix  = '0;
        weight_matrix = '0;
        psum_init_vec = '0;

        // Init partial sums to 0
        for (int m = 0; m < m_dim; m++) begin
            psum_mem[m] = '0;
        end

        repeat(10) @(posedge clk);
        #1 rst = 1'b0;

        // ------------------------------------------------------------
        // For each K-tile block:
        //   1) load weights (reverse order within tile)
        //   2) compute m_dim tokens, injecting psum_mem[m]
        //   3) capture skewed outputs into next_psum_mem[m][j]
        // ------------------------------------------------------------
        for (int b = 0; b < num_blocks; b++) begin
            int k_block = b * rows;

            $display("BLOCK %0d/%0d: k_block=[%0d..%0d]",
                     b+1, num_blocks, k_block, k_block + rows - 1);

            // -------------------------
            // 1) LOAD WEIGHTS (reverse)
            // -------------------------
            for (int kk = 0; kk < rows; kk++) begin
                int global_k = k_block + (rows - 1 - kk); // reverse inject
                @(posedge clk); #1;

                en           = 1'b1;
                clr          = 1'b1;   // LOAD mode
                input_matrix = '0;
                psum_init_vec = '0;

                if (global_k < k_dim) begin
                    weight_matrix = weights_mem[global_k];
                end else begin
                    weight_matrix = '0;  // padding for last partial block
                end
            end

            // -------------------------
            // 2) COMPUTE + 3) CAPTURE
            // -------------------------
            for (int m = 0; m < m_dim; m++) begin
                next_psum_mem[m] = '0;
            end

            for (int t = 0; t < (m_dim + drain_len); t++) begin
                @(posedge clk); #1;

                if (t < m_dim) begin
                    en            = 1'b1;
                    clr           = 1'b0;   // COMPUTE mode
                    input_matrix  = inputs_mem[b*m_dim + t];
                    weight_matrix = '0;
                    psum_init_vec = psum_mem[t];
                end else begin
                    en            = 1'b0;
                    clr           = 1'b0;
                    input_matrix  = '0;
                    weight_matrix = '0;
                    psum_init_vec = '0;
                end

                // CAPTURE (column-skew aware)
                for (int j = 0; j < cols; j++) begin
                    int signed m_out_s;
                    m_out_s = t - ws_base - j;

                    if ((m_out_s >= 0) && (m_out_s < m_dim)) begin
                        next_psum_mem[m_out_s][j*op_width +: op_width] =
                            output_matrix[((rows-1)*cols + j)*op_width +: op_width];
                    end
                end
            end

            // Update psum_mem for next block (or final)
            for (int m = 0; m < m_dim; m++) begin
                psum_mem[m] = next_psum_mem[m];
            end
        end

        // Stop driving
        @(posedge clk); #1;
        en            = 1'b0;
        clr           = 1'b0;
        input_matrix  = '0;
        weight_matrix = '0;
        psum_init_vec = '0;

        // Pack psum_mem (final C) into final_packed in same layout as golden
        final_packed = '0;
        for (int i = 0; i < rows; i++) begin
            for (int j = 0; j < cols; j++) begin
                final_packed[(i*cols + j)*op_width +: op_width] =
                    psum_mem[i][j*op_width +: op_width];
            end
        end

        wait (compute_done === 1'b1);
        #10;

        if (final_packed === golden_ref_mem[0]) begin
            $display("\n========================================");
            $display("   WS TEST PASSED! %0dx%0d, k_dim=%0d", rows, cols, k_dim);
            $display("   cycles_count (DUT compute-only): %0d", cycles_count);
            $display("========================================\n");
        end else begin
            $display("\n========================================");
            $display("   WS TEST FAILED!");
            $display("   cycles_count (DUT compute-only): %0d", cycles_count);
            $display("========================================\n");
        end

        // First mismatch locator
        if (final_packed !== golden_ref_mem[0]) begin
            for (int ii = 0; ii < rows; ii++) begin
                for (int jj = 0; jj < cols; jj++) begin
                    logic [op_width-1:0] got, exp;
                    got = final_packed[(ii*cols + jj)*op_width +: op_width];
                    exp = golden_ref_mem[0][(ii*cols + jj)*op_width +: op_width];
                    if (got !== exp) begin
                        $display("MISMATCH at C[%0d][%0d]: got=0x%08x exp=0x%08x", ii, jj, got, exp);
                        disable main;
                    end
                end
            end
        end

        $finish;
    end

endmodule
