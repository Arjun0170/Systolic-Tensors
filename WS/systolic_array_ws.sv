`timescale 1ns/10ps

module systolic_array_ws #(
    parameter int rows = 16,
    parameter int cols = 16,
    parameter int ip_width = 8,
    parameter int op_width = 32,
    parameter int pipe_lat = 3
)(
    input  logic clk,
    input  logic rst,

    // Protocol:
    //   en=1, clr=1  -> LOAD weights (top -> bottom). PEs latch weight locally.
    //   en=1, clr=0  -> COMPUTE (x streams right, psum streams down)
    //   en=0         -> idle/drain
    input  logic en,
    input  logic clr,

    // Packed vectors per cycle:
    //   input_matrix  : rows entries (Row0 at LSB) used during COMPUTE
    //   weight_matrix : cols entries (Col0 at LSB) used during LOAD
    input  logic [rows*ip_width-1:0] input_matrix,
    input  logic [cols*ip_width-1:0] weight_matrix,

    // Per-token psum init (for K-tiling). One column vector per cycle.
    input  logic [cols*op_width-1:0] psum_init_vec,

    output logic compute_done,
    output logic [31:0] cycles_count,

    // Snapshot of all PE psums (flattened [rows x cols])
    output logic [rows*cols*op_width-1:0] output_matrix
);

    // ------------------------------------------------------------------------
    // Simple phase decode (kept explicit to avoid accidental overlap)
    // ------------------------------------------------------------------------
    logic w_load_mode;
    logic compute_mode;

    assign w_load_mode  = en &  clr;
    assign compute_mode = en & ~clr;

    // ------------------------------------------------------------------------
    // Internal grids (+1 edges so pass-through wiring is clean)
    // x_grid   : moves left -> right
    // w_grid   : shifts top -> bottom during load, then held in PE
    // psum_grid: moves top -> bottom every compute token
    // ------------------------------------------------------------------------
    wire signed [ip_width-1:0] x_grid    [rows][cols+1];
    wire signed [ip_width-1:0] w_grid    [rows+1][cols];
    wire signed [op_width-1:0] psum_grid [rows+1][cols];

    // Valid travels with x horizontally (same idea as OS)
    wire en_grid [rows][cols+1];

    // PE outputs (registered psum_out per PE)
    wire signed [op_width-1:0] pe_out [rows][cols];

    // Avoid empty pin + unused warnings (Verilator will complain otherwise)
    logic [rows*cols-1:0] clr_out_unused;
    logic unused_sink;

    genvar i, j;

    // =========================================================================
    // PSUM top injection (column-skewed)
    //
    // Reason: x takes 1 cycle per column hop, so column j needs psum_init delayed
    // by j cycles to line up with the token when it reaches that column.
    //
    // NOTE: D=j is correct with the current TB drive style (signals change after
    // posedge). If TB style changes, this is the first place to re-check.
    // =========================================================================
    generate
        for (j = 0; j < cols; j++) begin : psum_top_skew
            localparam int D = j;

            logic signed [op_width-1:0] psum_dly [0:D];

            always_ff @(posedge clk) begin
                if (rst) begin
                    for (int k = 0; k <= D; k++) begin
                        psum_dly[k] <= '0;
                    end
                end else begin
                    // stage0 takes current psum_init column value during compute
                    psum_dly[0] <= compute_mode
                        ? $signed(psum_init_vec[(j+1)*op_width-1 -: op_width])
                        : '0;

                    // shift to create the column skew
                    for (int k = 1; k <= D; k++) begin
                        psum_dly[k] <= psum_dly[k-1];
                    end
                end
            end

            assign psum_grid[0][j] = psum_dly[D];
        end
    endgenerate

    // =========================================================================
    // Row skew for x (WS-correct spacing)
    //
    // In WS, psum moves down with a registered hop each row.
    // So row spacing is (pipe_lat + 1), not 1 like OS.
    // Row i delay = i * (pipe_lat + 1)
    // =========================================================================
    generate
        for (i = 0; i < rows; i++) begin : row_input_skew
            localparam int D = i * (pipe_lat + 1);

            logic signed [ip_width-1:0] x_delay_line [0:D];
            logic en_delay_line [0:D];

            always_ff @(posedge clk) begin
                if (rst) begin
                    for (int k = 0; k <= D; k++) begin
                        x_delay_line[k]  <= '0;
                        en_delay_line[k] <= 1'b0;
                    end
                end else begin
                    // Feed stage0 from packed input row i
                    x_delay_line[0]  <= input_matrix[(i+1)*ip_width-1 -: ip_width];
                    en_delay_line[0] <= compute_mode;

                    for (int k = 1; k <= D; k++) begin
                        x_delay_line[k]  <= x_delay_line[k-1];
                        en_delay_line[k] <= en_delay_line[k-1];
                    end
                end
            end

            assign x_grid[i][0]  = x_delay_line[D];
            assign en_grid[i][0] = en_delay_line[D];
        end
    endgenerate

    // =========================================================================
    // Weight injection (top row only)
    // Actual "stationary" behavior happens inside mac_unit_ws (w_reg latch).
    // =========================================================================
    generate
        for (j = 0; j < cols; j++) begin : weight_top
            assign w_grid[0][j] = weight_matrix[(j+1)*ip_width-1 -: ip_width];
        end
    endgenerate

    // =========================================================================
    // PE grid
    // - x moves right
    // - weight shifts down only during w_load_mode, then held locally
    // - psum moves down every compute token
    // =========================================================================
    generate
        for (i = 0; i < rows; i++) begin : PE_rows
            for (j = 0; j < cols; j++) begin : PE_cols
                localparam int IDX = (i*cols + j);

                mac_unit_ws #(
                    .IP_size(ip_width),
                    .OP_size(op_width),
                    .clr_load_first(1'b1)
                ) pe_inst (
                    .clk(clk),
                    .rst(rst),

                    .en_in (en_grid[i][j]),
                    .clr_in(1'b0),                 // psum_init_vec handles per-token init
                    .en_out(en_grid[i][j+1]),
                    .clr_out(clr_out_unused[IDX]), // unused but connected

                    .w_load_in(w_load_mode),

                    .x_new  (x_grid[i][j]),
                    .w_new  (w_grid[i][j]),
                    .psum_in(psum_grid[i][j]),

                    .x_old(x_grid[i][j+1]),
                    .w_old(w_grid[i+1][j]),

                    .mac_out(pe_out[i][j])
                );

                // vertical psum chain
                assign psum_grid[i+1][j] = pe_out[i][j];

                // export snapshot
                assign output_matrix[(i*cols + j)*op_width +: op_width] = pe_out[i][j];
            end
        end
    endgenerate

    // =========================================================================
    // Consume boundary nets (avoid Verilator "unused" warnings on edge wires)
    // =========================================================================
    always_comb begin
        unused_sink = 1'b0;

        for (int r = 0; r < rows; r++) begin
            unused_sink ^= ^x_grid[r][cols];
            unused_sink ^=  en_grid[r][cols];
        end

        for (int c = 0; c < cols; c++) begin
            unused_sink ^= ^w_grid[rows][c];
            unused_sink ^= ^psum_grid[rows][c];
        end

        unused_sink ^= ^clr_out_unused;
    end

    // =========================================================================
    // Done / cycle counter (compute phase only)
    //
    // Output at bottom-right drains after:
    //   row travel:  (rows-1) * (pipe_lat+1)
    //   col travel:  (cols-1)
    //   PE latency:  pipe_lat
    // This counter is retriggerable while compute_mode stays high.
    // =========================================================================
    localparam int total_lat =
        (rows-1) * (pipe_lat + 1) + (cols-1) + pipe_lat;

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

            // Trigger only during compute phase (ignore weight load)
            if (compute_mode) begin
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
