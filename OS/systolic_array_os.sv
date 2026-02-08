`timescale 1ns/10ps

module systolic_array_os #(
    parameter int rows = 64,
    parameter int cols = 64,
    parameter int ip_width = 8,
    parameter int op_width = 48,
    parameter int pipe_lat = 3
)(
    input  logic clk,
    input  logic rst,

    // en=1 streams one "time-step" token into the array.
    // clr is sampled only when en=1 (clr token resets PE accumulators).
    input  logic en,
    input  logic clr,

    // Packed input vectors for the current time-step:
    //   input_matrix  packs rows entries  (Row 0 at LSB)
    //   weight_matrix packs cols entries  (Col 0 at LSB)
    input  logic [rows*ip_width-1:0] input_matrix,
    input  logic [cols*ip_width-1:0] weight_matrix,

    // Goes high once the last in-flight token has drained through the array.
    output logic compute_done,
    output logic [31:0] cycles_count,

    // Flattened [rows x cols] matrix of PE accumulators.
    // Layout: output_matrix[(i*cols + j)*op_width +: op_width] = C[i][j]
    output logic [rows*cols*op_width-1:0] output_matrix
);

    // ------------------------------------------------------------------------
    // OS dataflow summary:
    //   - x streams left -> right
    //   - w streams top  -> bottom
    //   - each PE holds its own psum locally (no vertical psum chain)
    //
    // To align wavefronts, we skew:
    //   - row i of x by i cycles
    //   - col j of w by j cycles
    // so that token (k) meets at PE(i,j) at the right time.
    // ------------------------------------------------------------------------

    // Grids are sized with +1 on the "output" edge so we can wire pass-through
    // without special casing the last row/col.
    wire signed [ip_width-1:0] x_grid [rows][cols+1];
    wire signed [ip_width-1:0] w_grid [rows+1][cols];

    // Valid/clear travel with the x stream horizontally.
    wire en_grid  [rows][cols+1];
    wire clr_grid [rows][cols+1];

    genvar i, j;

    // =========================================================================
    // Row skew for x (triangular delay)
    // Row 0 : 0-cycle delay
    // Row i : i-cycle delay
    // This lines up the x wavefront with the diagonal compute in the array.
    // =========================================================================
    generate
        for (i = 0; i < rows; i++) begin : row_input_skew
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
                    // Feed stage 0 from packed input (Row i)
                    x_delay_line[0]   <= input_matrix[(i+1)*ip_width-1 -: ip_width];
                    en_delay_line[0]  <= en;
                    clr_delay_line[0] <= en & clr;

                    // Shift through the delay line
                    for (int k = 1; k <= i; k++) begin
                        x_delay_line[k]   <= x_delay_line[k-1];
                        en_delay_line[k]  <= en_delay_line[k-1];
                        clr_delay_line[k] <= clr_delay_line[k-1];
                    end
                end
            end

            // Drive the left edge of the PE grid for this row
            assign x_grid[i][0]   = x_delay_line[i];
            assign en_grid[i][0]  = en_delay_line[i];
            assign clr_grid[i][0] = clr_delay_line[i];
        end
    endgenerate

    // =========================================================================
    // Column skew for w (triangular delay)
    // Col 0 : 0-cycle delay
    // Col j : j-cycle delay
    // Only data is used in OS w-grid boundary; control stays with x-grid.
    // =========================================================================
    generate
        for (j = 0; j < cols; j++) begin : col_input_skew
            logic signed [ip_width-1:0] w_delay_line [0:j];
            logic en_delay_line  [0:j];   // kept for symmetry/debug
            logic clr_delay_line [0:j];

            always_ff @(posedge clk) begin
                if (rst) begin
                    for (int k = 0; k <= j; k++) begin
                        w_delay_line[k]   <= '0;
                        en_delay_line[k]  <= '0;
                        clr_delay_line[k] <= '0;
                    end
                end else begin
                    // Feed stage 0 from packed weights (Col j)
                    w_delay_line[0]   <= weight_matrix[(j+1)*ip_width-1 -: ip_width];
                    en_delay_line[0]  <= en;
                    clr_delay_line[0] <= en & clr;

                    for (int k = 1; k <= j; k++) begin
                        w_delay_line[k]   <= w_delay_line[k-1];
                        en_delay_line[k]  <= en_delay_line[k-1];
                        clr_delay_line[k] <= clr_delay_line[k-1];
                    end
                end
            end

            // Drive the top edge of the PE grid for this column
            assign w_grid[0][j] = w_delay_line[j];
        end
    endgenerate

    // =========================================================================
    // PE grid instantiation
    // Each PE forwards x right and w down; accumulator output is exported.
    // =========================================================================
    generate
        for (i = 0; i < rows; i++) begin : PE_rows
            for (j = 0; j < cols; j++) begin : PE_cols
                mac_unit_os #(
                    .IP_size(ip_width),
                    .OP_size(op_width),
                    .clr_load_first(1'b1)
                ) pe_inst (
                    .clk(clk),
                    .rst(rst),

                    // control token travels with x to the right
                    .en_in (en_grid[i][j]),
                    .clr_in(clr_grid[i][j]),
                    .en_out(en_grid[i][j+1]),
                    .clr_out(clr_grid[i][j+1]),

                    // data streams
                    .x_new(x_grid[i][j]),
                    .w_new(w_grid[i][j]),
                    .x_old(x_grid[i][j+1]),
                    .w_old(w_grid[i+1][j]),

                    // local psum snapshot
                    .mac_out(output_matrix[(i*cols + j)*op_width +: op_width])
                );
            end
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Done logic: retriggerable drain timer
    // For OS:
    //   skew_lat = (rows-1) + (cols-1)  (wavefront travel)
    //   + pipe_lat                      (PE internal MAC pipeline)
    // compute_done asserts once last token has drained after en drops.
    // ------------------------------------------------------------------------
    localparam int skew_lat  = (rows - 1) + (cols - 1);
    localparam int total_lat = skew_lat + pipe_lat;

    logic [31:0] active_tokens;
    logic array_idle;

    always_ff @(posedge clk) begin
        if (rst) begin
            cycles_count  <= '0;
            compute_done  <= 1'b0;
            active_tokens <= '0;
            array_idle    <= 1'b1;
        end else begin
            if (!array_idle) begin
                cycles_count <= cycles_count + 1;
            end

            if (en) begin
                // new token stream seen -> start/refresh drain timer
                array_idle    <= 1'b0;
                compute_done  <= 1'b0;
                active_tokens <= total_lat;
            end else if (!array_idle) begin
                if (active_tokens != 0) begin
                    active_tokens <= active_tokens - 1;
                end else begin
                    compute_done <= 1'b1;
                    array_idle   <= 1'b1;
                end
            end
        end
    end

endmodule
