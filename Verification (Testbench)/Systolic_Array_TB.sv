`timescale 1ns/10ps

module systolic_array_tb;

    parameter int rows = 64;
    parameter int cols = 64;
    parameter int ip_width = 8;
    parameter int op_width = 32;
    parameter int k_dim = 128; // Length of the input stream (K dimension of matrix mult)
    
    logic clk;
    logic rst;
    logic en;
    logic clr;
    logic [rows*ip_width-1:0] input_matrix;
    logic [cols*ip_width-1:0] weight_matrix;
    logic compute_done;
    logic [31:0] cycles_count;
    logic [rows*cols*op_width-1:0] output_matrix;
    
    // Memories to hold test vectors
    // Packed Width: [rows * 8 bits] wide
    // Depth: [k_dim] deep
    logic [rows*ip_width-1:0] inputs_mem [0:k_dim-1];
    logic [cols*ip_width-1:0] weights_mem [0:k_dim-1];
    logic [rows*cols*op_width-1:0] golden_ref_mem [0:0]; // Single result for entire matrix mult

    systolic_array #(
        .rows(rows), .cols(cols), 
        .ip_width(ip_width), .op_width(op_width)
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

    // Clock Generation (10ns period)
    always #5 clk = ~clk;

    // Timeout Watchdog (Prevents infinite hang)
    initial begin
        #10000;
        $display("ERROR: Simulation Timed Out! compute_done never went high.");
        $finish;
    end

    initial begin
        // 1. Load Data
        // Ensure your hex files are formatted correctly! 
        $readmemh("input_matrix.hex", inputs_mem);
        $readmemh("weight_matrix.hex", weights_mem);
        $readmemh("golden_output.hex", golden_ref_mem);
        
        // 2. Initialize
        clk = 0; 
        rst = 1; 
        en = 0; 
        clr = 0;
        input_matrix = 0; 
        weight_matrix = 0;
        
        // 3. Reset Sequence
        repeat(10) @(posedge clk);
        #1 rst = 0;
        
        // 4. Feed Data
        $display("Starting Feed... K_DIM=%0d", k_dim);
        for (int k=0; k < k_dim; k++) begin
            @(posedge clk);
            #1; // Output delay to ensure setup time
            en = 1;
            // Clear accumulators on the FIRST input of the stream
            clr = (k == 0); 
            
            input_matrix = inputs_mem[k];
            weight_matrix = weights_mem[k];
        end
        
        // 5. End of Feed
        @(posedge clk);
        #1;
        en = 0; 
        clr = 0;
        input_matrix = 0; 
        weight_matrix = 0;
        
        $display("Feed Complete. Waiting for computation...");
        
        // 6. Wait for Result
        wait(compute_done);
        
        // 7. Check Result
        #10;
        if (output_matrix === golden_ref_mem[0]) begin
            $display("\n========================================");
            $display("   TEST PASSED! Dimensions: %0dx%0d", rows, cols);
            $display("========================================\n");
        end else begin
            $display("\n========================================");
            $display("   TEST FAILED!");
            // $display("Expected: %h", golden_ref_mem[0]);
            // $display("Got:      %h", output_matrix);
            // Uncomment for smaller simulations
            $display("========================================\n");
        end
        
        $finish;
    end

endmodule
