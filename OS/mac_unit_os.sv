`timescale 1ns/10ps

module mac_unit_os #(
    parameter int IP_size = 8,
    parameter int OP_size = 48,
    parameter bit clr_load_first = 1'b1
)(
    input  logic clk,
    input  logic rst,

    // ------------------------------------------------------------------------
    // Control token
    // en_in  : valid for this compute token (drives pipeline + accumulator update)
    // clr_in : sampled only when en_in=1, used to clear/initialize the local psum
    // Both signals propagate along with x as they move across the PE row.
    // ------------------------------------------------------------------------
    input  logic en_in,
    input  logic clr_in,
    output logic en_out,
    output logic clr_out,

    // ------------------------------------------------------------------------
    // Operand streams (Output-Stationary PE)
    // x_new streams left -> right  (registered pass-through via x_old)
    // w_new streams top  -> bottom (registered pass-through via w_old)
    // mac_out is local state (psum) held inside this PE.
    // ------------------------------------------------------------------------
    input  logic signed [IP_size-1:0] x_new,
    input  logic signed [IP_size-1:0] w_new,
    output logic signed [IP_size-1:0] x_old,
    output logic signed [IP_size-1:0] w_old,

    output logic signed [OP_size-1:0] mac_out
);

    localparam int prod_w = 2 * IP_size;

    // =========================================================================
    // Pipeline overview
    //   S1: register x/w + forward to neighbors, align control (v/c)
    //   S2: multiply stage (registered)
    //   S3: multiply pipeline stage (registered)
    //   S4: accumulator update (registered psum)
    //
    // NOTE: s2/s3 are explicit stages to keep latency predictable and consistent
    //       across array sizes / toolflows.
    // =========================================================================

    // Stage 1 regs (operands + control)
    logic signed [IP_size-1:0] s1_x, s1_w;
    logic v1, c1;

    // Stage 2 regs (product + control)
    logic signed [prod_w-1:0] s2_p;
    logic v2, c2;

    // Stage 3 regs (product + control)
    logic signed [prod_w-1:0] s3_p;
    logic v3, c3;

    // Sign-extend product to accumulator width (or truncate if OP_size < prod_w)
    function automatic logic signed [OP_size-1:0] sext_prod(input logic signed [prod_w-1:0] p);
        if (OP_size >= prod_w)
            sext_prod = {{(OP_size - prod_w){p[prod_w-1]}}, p};
        else
            sext_prod = p[OP_size-1:0];
    endfunction

    // =========================================================================
    // Stage 1: register operands + propagate token control
    // =========================================================================
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
            // Registered pass-through to neighbors
            s1_x  <= x_new;
            s1_w  <= w_new;
            x_old <= x_new;
            w_old <= w_new;

            // Control token follows the compute wavefront
            v1 <= en_in;
            c1 <= en_in & clr_in;

            en_out  <= en_in;
            clr_out <= en_in & clr_in;
        end
    end

    // =========================================================================
    // Stage 2: multiply (registered)
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            v2   <= 1'b0;
            c2   <= 1'b0;
            s2_p <= '0;
        end else begin
            v2   <= v1;
            c2   <= c1;
            s2_p <= v1 ? (s1_x * s1_w) : '0;
        end
    end

    // =========================================================================
    // Stage 3: extra pipe stage for timing/latency control
    // =========================================================================
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
    // Stage 4: accumulate into local psum
    // clr behavior:
    //   - when c3=1 (valid clr token): either load first product (common GEMM init)
    //     or clear to zero depending on clr_load_first.
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            mac_out <= '0;
        end else if (v3) begin
            logic signed [OP_size-1:0] addend;
            addend = sext_prod(s3_p);

            if (c3) begin
                mac_out <= (clr_load_first) ? addend : '0;
            end else begin
                mac_out <= mac_out + addend;
            end
        end
    end

endmodule
