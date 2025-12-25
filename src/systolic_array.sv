`timescale 1ns/10ps

module systolic_array #(
    parameter int rows = 64,
    parameter int cols = 64,
    parameter int ip_width = 8,
    parameter int op_width = 32,
    parameter int pipe_lat = 3
)(
    input  logic clk,
    input  logic rst,

    input  logic en,
    input  logic clr,
    
    input  logic [rows*ip_width-1:0] input_matrix,
    input  logic [cols*ip_width-1:0] weight_matrix,
    
    output logic compute_done,
    output logic [31:0] cycles_count,
    
    output logic [rows*cols*op_width-1:0] output_matrix
);

    // Internal Grids
    wire signed [ip_width-1:0] x_grid [rows][cols+1];
    wire signed [ip_width-1:0] w_grid [rows+1][cols];
    
    // Control Grids
    wire en_grid  [rows][cols+1];
    wire clr_grid [rows][cols+1];

    genvar i, j;

    // =========================================================================
    // Row Skew Buffer (Triangular Delay for Inputs)
    // =========================================================================
    generate
        for (i = 0; i < rows; i++) begin : row_input_skew
            // Delay line depth = i (Row 0 = 0 delay, Row 1 = 1 delay...)
            logic signed [ip_width-1:0] x_delay_line [0:i];
            logic en_delay_line  [0:i];
            logic clr_delay_line [0:i];

            always_ff @(posedge clk) begin
                if (rst) begin
                    for (int k = 0; k <= i; k++) begin
                        x_delay_line[k]   <= '0;
                        en_delay_line[k]  <= '0;
                        clr_delay_line[k] <= '0;
                    end
                end else begin
                    // Feed the first stage of delay line
                    x_delay_line[0]   <= input_matrix[(i+1)*ip_width-1 -: ip_width]; 
                    en_delay_line[0]  <= en;
                    clr_delay_line[0] <= en & clr;

                    // Shift Register
                    for (int k = 1; k <= i; k++) begin
                        x_delay_line[k]   <= x_delay_line[k-1];
                        en_delay_line[k]  <= en_delay_line[k-1];
                        clr_delay_line[k] <= clr_delay_line[k-1];
                    end
                end
            end

            // Connect end of delay line to the grid edge
            assign x_grid[i][0]   = x_delay_line[i];
            assign en_grid[i][0]  = en_delay_line[i];
            assign clr_grid[i][0] = clr_delay_line[i];
        end
    endgenerate

    // =========================================================================
    // Column Skew Buffer (Triangular Delay for Weights)
    // =========================================================================
    generate
        for (j = 0; j < cols; j++) begin : col_input_skew
            logic signed [ip_width-1:0] w_delay_line [0:j];
            logic en_delay_line  [0:j];     // Unused but kept for symmetry if needed later
            logic clr_delay_line [0:j];    // Unused

            always_ff @(posedge clk) begin
                if (rst) begin
                    for (int k = 0; k <= j; k++) begin
                        w_delay_line[k]   <= '0;
                        en_delay_line[k]  <= '0;
                        clr_delay_line[k] <= '0;
                    end
                end else begin
                    w_delay_line[0]   <= weight_matrix[(j+1)*ip_width-1 -: ip_width];
                    en_delay_line[0]  <= en; // Dummy
                    clr_delay_line[0] <= en & clr; // Dummy

                    for (int k = 1; k <= j; k++) begin
                        w_delay_line[k]   <= w_delay_line[k-1];
                        en_delay_line[k]  <= en_delay_line[k-1];
                        clr_delay_line[k] <= clr_delay_line[k-1];
                    end
                end
            end

            assign w_grid[0][j]   = w_delay_line[j];
        end
    endgenerate

    // =========================================================================
    // PE Grid Instantiation
    // =========================================================================
    generate
        for (i = 0; i < rows; i++) begin : PE_rows
            for (j = 0; j < cols; j++) begin : PE_cols
                mac_unit #(
                    .IP_size(ip_width),
                    .OP_size(op_width),
                    .clr_load_first(1'b1)
                ) pe_inst (
                    .clk(clk),
                    .rst(rst),
                    // Control Flow
                    .en_in (en_grid[i][j]),
                    .clr_in(clr_grid[i][j]),
                    .en_out(en_grid[i][j+1]),
                    .clr_out(clr_grid[i][j+1]),
                    
                    // Data Flow
                    .x_new(x_grid[i][j]),
                    .w_new(w_grid[i][j]),
                    .x_old(x_grid[i][j+1]), // Output to neighbor (Right)
                    .w_old(w_grid[i+1][j]), // Output to neighbor (Bottom)
                    
                    // Accumulator Output
                    .mac_out(output_matrix[(i*cols + j)*op_width +: op_width])
                );
            end
        end
    endgenerate

    // =========================================================================
    // Control Logic
    // =========================================================================
    localparam int skew_lat   = (rows - 1) + (cols - 1);
    localparam int total_lat  = skew_lat + pipe_lat + rows;

    logic [31:0] active_tokens;
    logic array_idle;

    always_ff @(posedge clk) begin
        if (rst) begin
            cycles_count <= '0;
            compute_done <= 1'b0;
            active_tokens <= '0;
            array_idle <= 1'b1;
        end else begin
            // Cycle Counter
            if (!array_idle) begin
                cycles_count <= cycles_count + 1;
            end
            
            // Finite State Machine 
            if (en) begin
                array_idle <= 1'b0;
                compute_done <= 1'b0;
                // Whenever we get an Enable, we reset the countdown timer
                // This is a "re-triggerable" timer logic.
                // Assuming 'en' stays high for the duration of the stream.
                active_tokens <= total_lat; 
            end else if (!array_idle) begin
                if (active_tokens != 0) begin
                    active_tokens <= active_tokens - 1;
                end else begin
                    compute_done <= 1'b1;
                    array_idle <= 1'b1;
                end
            end
        end
    end

endmodule
