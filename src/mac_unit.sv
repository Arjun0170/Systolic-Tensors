`timescale 1ns/10ps

module mac_unit #(
    parameter int IP_size = 8,
    parameter int OP_size = 32,
    parameter bit clr_load_first = 1'b1
)(
    input  logic clk,
    input  logic rst,
    input  logic en_in,
    input  logic clr_in,
    output logic en_out,
    output logic clr_out,
    input  logic signed [IP_size-1:0] x_new,
    input  logic signed [IP_size-1:0] w_new,
    output logic signed [IP_size-1:0] x_old,
    output logic signed [IP_size-1:0] w_old,
    output logic signed [OP_size-1:0] mac_out
);

    localparam int prod_w = 2 * IP_size;

    // =========================================================================
    // Robust Multiply-Accumulate Pipeline (Stage 1)
    // =========================================================================
    logic signed [IP_size-1:0] s1_x, s1_w;
    logic v1, c1;

    always_ff @(posedge clk) begin
        if (rst) begin
            s1_x    <= '0;
            s1_w    <= '0;
            v1      <= 1'b0;
            c1      <= 1'b0;
            x_old   <= '0;
            w_old   <= '0;
            en_out  <= 1'b0;
            clr_out <= 1'b0;
        end else begin
            // Register inputs
            s1_x  <= x_new;
            s1_w  <= w_new;
            x_old <= x_new;
            w_old <= w_new;
            //Valid and Clear signals propagation
            v1 <= en_in;
            c1 <= en_in & clr_in;
            en_out  <= en_in;
            clr_out <= en_in & clr_in;
        end
    end

    // =========================================================================
    // Robust Multiply-Accumulate Pipeline (Stage 2)
    // =========================================================================

    logic signed [prod_w-1:0] s2_p;
    logic v2, c2;

    always_ff @(posedge clk) begin
        if (rst) begin
            v2   <= 1'b0;
            c2   <= 1'b0;
            s2_p <= '0;
        end else begin
            v2   <= v1;
            c2   <= c1;
            s2_p <= v1 ? (prod_w'(s1_x) * prod_w'(s1_w)) : '0;
        end
    end

    // =========================================================================
    // Robust Multiply-Accumulate Pipeline (Stage 3)
    // =========================================================================
    logic signed [prod_w-1:0] s3_p;
    logic v3, c3;

    always_ff @(posedge clk) begin
        if (rst) begin
            v3   <= 1'b0;
            c3   <= 1'b0;
            s3_p <= '0;
        end else begin
            v3   <= v2;
            c3   <= c2;
            s3_p <= v2 ? s2_p : '0;
        end
    end

    // =========================================================================
    // Robust Accumulation (Stage 4)
    // =========================================================================

    always_ff @(posedge clk) begin
        if (rst) begin
            mac_out <= '0;
        end else if (v3) begin
            //Sign extend the product to match the MAC output width
            logic signed [OP_size-1:0] addend;
            addend = { { (OP_size - prod_w) {s3_p[prod_w-1]} }, s3_p };          
            if (c3) begin
                mac_out <= (clr_load_first) ? addend : '0;
            end else begin
                mac_out <= mac_out + addend;
            end
        end
    end

endmodule
