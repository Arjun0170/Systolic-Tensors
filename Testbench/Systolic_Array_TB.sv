`timescale 1ns/10ps

module systolic_array_tb;

    parameter int rows = 64;
    parameter int cols = 64;
    parameter int ip_width = 8;
    parameter int op_width = 48;
    parameter int k_dim = 128;
    
    logic clk;
    logic rst;
    logic en;
    logic clr;
    logic [rows*ip_width-1:0] input_matrix;
    logic [cols*ip_width-1:0] weight_matrix;
    logic compute_done;
    logic [31:0] cycles_count;
    logic [rows*cols*op_width-1:0] output_matrix;
    
    logic [rows*ip_width-1:0] inputs_mem [0:k_dim-1];
    logic [cols*ip_width-1:0] weights_mem [0:k_dim-1];
    logic [rows*cols*op_width-1:0] golden_ref_mem [0:0];

    systolic_array #(
        .rows(rows), .cols(cols), 
        .ip_width(ip_width), .op_width(op_width)
    ) dut (.*);

    always #5 clk = ~clk;

    initial begin
        $readmemh("input_matrix.hex", inputs_mem);
        $readmemh("weight_matrix.hex", weights_mem);
        $readmemh("golden_output.hex", golden_ref_mem);
        
        clk = 0; rst = 1; en = 0; clr = 0;
        input_matrix = 0; weight_matrix = 0;
        
        #105 rst = 0;
        
        @(posedge clk);
        #1;
        
        for (int k=0; k < k_dim; k++) begin
            en = 1;
            clr = (k == 0);
            input_matrix = inputs_mem[k];
            weight_matrix = weights_mem[k];
            @(posedge clk);
            #1;
        end
        
        en = 0; clr = 0;
        input_matrix = 0; weight_matrix = 0;
        
        wait(compute_done);
        
        #10;
        if (output_matrix == golden_ref_mem[0]) begin
            $display("TEST PASSED! Dimensions: %0dx%0d", rows, cols);
        end else begin
            $display("TEST FAILED!");
            $display("Expected: %h", golden_ref_mem[0]);
            $display("Got:      %h", output_matrix);
        end
        
        $finish;
    end

endmodule
