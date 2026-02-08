`timescale 1ns/10ps

module mac_unit_ws #(
    parameter int IP_size = 8,
    parameter int OP_size = 32,
    parameter bit clr_load_first = 1'b1
)(
    input  logic clk,
    input  logic rst,

    // Compute control (same semantics as your OS block)
    input  logic en_in,
    input  logic clr_in,
    output logic en_out,
    output logic clr_out,

    // WS weight-load control
    input  logic w_load_in,

    // Streams
    input  logic signed [IP_size-1:0] x_new,
    input  logic signed [IP_size-1:0] w_new,      // used only when w_load_in=1
    input  logic signed [OP_size-1:0] psum_in,     // from PE above

    // Forwarded streams
    output logic signed [IP_size-1:0] x_old,       // to PE right
    output logic signed [IP_size-1:0] w_old,       // to PE below during load

    // In WS, this is the registered psum_out (kept as mac_out for compatibility)
    output logic signed [OP_size-1:0] mac_out
);

    localparam int prod_w = 2 * IP_size;

    // =========================================================================
    // Stationary weight register (loaded only during LOAD phase)
    // =========================================================================
    logic signed [IP_size-1:0] w_reg;

    // =========================================================================
    // Pipeline Stage 1 (register inputs + control)
    // =========================================================================
    logic signed [IP_size-1:0] s1_x, s1_w;
    logic signed [OP_size-1:0] s1_psum;
    logic v1, c1;

    always_ff @(posedge clk) begin
        if (rst) begin
            s1_x    <= '0;
            s1_w    <= '0;
            s1_psum <= '0;
            v1      <= 1'b0;
            c1      <= 1'b0;

            w_reg   <= '0;

            x_old   <= '0;
            w_old   <= '0;
            en_out  <= 1'b0;
            clr_out <= 1'b0;
        end else begin
            // Weight load + vertical forward (for column loading)
            if (w_load_in) begin
                w_reg <= w_new;
                w_old <= w_new;     // shift weight downward during load
            end else begin
                w_old <= w_reg;     // hold/reflect stationary weight (harmless if unused)
            end

            // Forward activation to the right (1-cycle hop)
            x_old <= x_new;

            // Stage-1 registers used by the compute pipeline
            s1_x  <= x_new;
            s1_w  <= w_reg;         // WS: always multiply by stationary weight
            s1_psum <= en_in ? psum_in : '0;

            // Valid / clear propagation (unchanged semantics)
            v1 <= en_in;
            c1 <= en_in & clr_in;

            en_out  <= en_in;
            clr_out <= en_in & clr_in;
        end
    end

    // =========================================================================
    // Pipeline Stage 2 (multiply)
    // =========================================================================
    logic signed [prod_w-1:0] s2_p;
    logic signed [OP_size-1:0] s2_psum;
    logic v2, c2;

    always_ff @(posedge clk) begin
        if (rst) begin
            v2     <= 1'b0;
            c2     <= 1'b0;
            s2_p   <= '0;
            s2_psum<= '0;
        end else begin
            v2      <= v1;
            c2      <= c1;
            s2_p    <= v1 ? (prod_w'(s1_x) * prod_w'(s1_w)) : '0;
            s2_psum <= v1 ? s1_psum : '0;
        end
    end

    // =========================================================================
    // Pipeline Stage 3 (align/pipe)
    // =========================================================================
    logic signed [prod_w-1:0] s3_p;
    logic signed [OP_size-1:0] s3_psum;
    logic v3, c3;

    always_ff @(posedge clk) begin
        if (rst) begin
            v3      <= 1'b0;
            c3      <= 1'b0;
            s3_p    <= '0;
            s3_psum <= '0;
        end else begin
            v3      <= v2;
            c3      <= c2;
            s3_p    <= v2 ? s2_p : '0;
            s3_psum <= v2 ? s2_psum : '0;
        end
    end

    // =========================================================================
    // Stage 4: WS accumulate (psum_in + product) => mac_out (psum_out)
    // =========================================================================
    logic signed [OP_size-1:0] addend;

    always_comb begin
        // Sign-extend product to OP_size
        addend = { { (OP_size - prod_w) {s3_p[prod_w-1]} }, s3_p };
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mac_out <= '0;
        end else if (v3) begin
            if (c3) begin
                mac_out <= (clr_load_first) ? addend : '0;
            end else begin
                mac_out <= s3_psum + addend;
            end
        end
    end

endmodule
