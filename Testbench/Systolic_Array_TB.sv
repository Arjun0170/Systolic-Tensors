`timescale 1ns/10ps

module systolic_array_tb;

    parameter int ROWS = 64;
    parameter int COLS = 64;
    parameter int IP_WIDTH = 8;
    parameter int OP_WIDTH = 48;
    parameter int K_DIM = 128;
    
    logic clk;
    logic rst;
    logic en;
    logic clr;
    logic [ROWS*IP_WIDTH-1:0] input_matrix;
    logic [COLS*IP_WIDTH-1:0] weight_matrix;
    logic compute_done;
    logic [31:0] cycles_count;
    logic [ROWS*COLS*OP_WIDTH-1:0] output_matrix;
    
    logic [ROWS*IP_WIDTH-1:0] inputs_mem [0:K_DIM-1];
    logic [COLS*IP_WIDTH-1:0] weights_mem [0:K_DIM-1];
    logic [ROWS*COLS*OP_WIDTH-1:0] golden_ref_mem [0:0];

    systolic_array #(
        .ROWS(ROWS), .COLS(COLS), 
        .IP_WIDTH(IP_WIDTH), .OP_WIDTH(OP_WIDTH)
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
        
        for (int k=0; k < K_DIM; k++) begin
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
            $display("TEST PASSED! Dimensions: %0dx%0d", ROWS, COLS);
        end else begin
            $display("TEST FAILED!");
            $display("Expected: %h", golden_ref_mem[0]);
            $display("Got:      %h", output_matrix);
        end
        
        $finish;
    end

endmodule
