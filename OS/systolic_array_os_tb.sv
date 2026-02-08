`timescale 1ns/10ps

module systolic_array__os_tb;

    // ------------------------------------------------------------------------
    // Config (must match generator + DUT params)
    // ------------------------------------------------------------------------
    parameter int rows     = 64;
    parameter int cols     = 64;
    parameter int ip_width = 8;
    parameter int op_width = 48;
    parameter int k_dim    = 128;   // stream length (K dimension)

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
    // Test vectors
    // input_matrix.hex  : k_dim lines, each packs rows x ip_width (Row0 at LSB)
    // weight_matrix.hex : k_dim lines, each packs cols x ip_width (Col0 at LSB)
    // golden_output.hex : 1 line, full flattened C[rows][cols] in output_matrix layout
    // ------------------------------------------------------------------------
    logic [rows*ip_width-1:0]        inputs_mem     [0:k_dim-1];
    logic [cols*ip_width-1:0]        weights_mem    [0:k_dim-1];
    logic [rows*cols*op_width-1:0]   golden_ref_mem [0:0];

    // ------------------------------------------------------------------------
    // DUT
    // NOTE: using .* relies on matching signal names (keep TB/DUT ports aligned)
    // ------------------------------------------------------------------------
    systolic_array_os #(
        .rows(rows),
        .cols(cols),
        .ip_width(ip_width),
        .op_width(op_width)
    ) dut (.*);

    // ------------------------------------------------------------------------
    // Clock (10ns period)
    // ------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------------
    // Main
    // OS protocol:
    //   - Drive one time-step per cycle for k=0..k_dim-1
    //   - Assert clr only on the first token (k==0) to reset PE accumulators
    //   - After feed, drop en and let the array drain until compute_done
    // ------------------------------------------------------------------------
    initial begin
        $readmemh("input_matrix.hex",  inputs_mem);
        $readmemh("weight_matrix.hex", weights_mem);
        $readmemh("golden_output.hex", golden_ref_mem);

        // init
        rst           = 1'b1;
        en            = 1'b0;
        clr           = 1'b0;
        input_matrix  = '0;
        weight_matrix = '0;

        // deassert reset off a clock boundary (simple but stable)
        #105 rst = 1'b0;

        @(posedge clk); #1;

        // stream K tokens
        for (int k = 0; k < k_dim; k++) begin
            en            = 1'b1;
            clr           = (k == 0);
            input_matrix  = inputs_mem[k];
            weight_matrix = weights_mem[k];

            @(posedge clk); #1;
        end

        // stop driving, drain
        en            = 1'b0;
        clr           = 1'b0;
        input_matrix  = '0;
        weight_matrix = '0;

        wait (compute_done);

        #10;
        if (output_matrix == golden_ref_mem[0]) begin
            $display("TEST PASSED! Dimensions: %0dx%0d", rows, cols);
            $display("cycles_count (DUT): %0d", cycles_count);
        end else begin
            $display("TEST FAILED!");
            $display("Expected: %h", golden_ref_mem[0]);
            $display("Got:      %h", output_matrix);
        end

        $finish;
    end

endmodule
