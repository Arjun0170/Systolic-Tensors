`timescale 1ns/10ps
module systolic_array #(
    parameter int rows = 64,
    parameter int cols = 64,
    parameter int ip_width = 8,
    parameter int op_width = 48
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

    wire signed [ip_width-1:0] x_grid [rows][cols+1];
    wire signed [ip_width-1:0] w_grid [rows+1][cols];
    wire en_grid  [rows][cols+1];
    wire clr_grid [rows][cols+1];

    genvar i, j;

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
                    x_delay_line[0]   <= en ? input_matrix[(i+1)*ip_width-1 -: ip_width] : '0;
                    en_delay_line[0]  <= en;
                    clr_delay_line[0] <= en ? clr : 1'b0;
                    for (int k = 1; k <= i; k++) begin
                        x_delay_line[k]   <= x_delay_line[k-1];
                        en_delay_line[k]  <= en_delay_line[k-1];
                        clr_delay_line[k] <= clr_delay_line[k-1];
                    end
                end
            end

            assign x_grid[i][0]   = x_delay_line[i];
            assign en_grid[i][0]  = en_delay_line[i];
            assign clr_grid[i][0] = clr_delay_line[i];
        end
    endgenerate

    generate
        for (j = 0; j < cols; j++) begin : col_input_skew
            logic signed [ip_width-1:0] w_delay_line [0:j];
            logic en_delay_line  [0:j];
            logic clr_delay_line [0:j];

            always_ff @(posedge clk) begin
                if (rst) begin
                    for (int k = 0; k <= j; k++) begin
                        w_delay_line[k]   <= '0;
                        en_delay_line[k]  <= '0;
                        clr_delay_line[k] <= '0;
                    end
                end else begin
                    w_delay_line[0]   <= en ? weight_matrix[(j+1)*ip_width-1 -: ip_width] : '0;
                    en_delay_line[0]  <= en;
                    clr_delay_line[0] <= en ? clr : 1'b0;
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

    generate
        for (i = 0; i < rows; i++) begin : PE_rows
            for (j = 0; j < cols; j++) begin : PE_cols
                mac_unit #(
                    .IP_size(ip_width),
                    .OP_size(op_width)
                ) pe_inst (
                    .clk(clk),
                    .rst(rst),

                    .en_in (en_grid[i][j]),
                    .clr_in(clr_grid[i][j]),
                    .en_out(en_grid[i][j+1]),
                    .clr_out(clr_grid[i][j+1]),

                    .x_new(x_grid[i][j]),
                    .w_new(w_grid[i][j]),
                    .x_old(x_grid[i][j+1]),
                    .w_old(w_grid[i+1][j]),

                    .mac_out(output_matrix[(i*cols + j)*op_width +: op_width])
                );
            end
        end
    endgenerate

    localparam int pipe_lat  = 3;
    localparam int flush_lat = (rows-1) + (cols-1) + pipe_lat;

    logic en_prev;
    logic running;
    logic [31:0] flush_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            cycles_count <= 32'd0;
            compute_done <= 1'b0;
            en_prev      <= 1'b0;
            running      <= 1'b0;
            flush_count  <= 32'd0;
        end else begin
            en_prev <= en;

            if (!running && en && !en_prev) begin
                running      <= 1'b1;
                compute_done <= 1'b0;
                cycles_count <= 32'd0;
                flush_count  <= 32'd0;
            end else if (running) begin
                if (en) begin
                    cycles_count <= cycles_count + 32'd1;
                    flush_count  <= 32'd0;
                end else begin
                    if (flush_count == 32'd0)
                        flush_count <= 32'd1;
                    else
                        flush_count <= flush_count + 32'd1;

                    if (flush_count == flush_lat[31:0]) begin
                        compute_done <= 1'b1;
                        running      <= 1'b0;
                        flush_count  <= 32'd0;
                    end
                end
            end
        end
    end

endmodule
