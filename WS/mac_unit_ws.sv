`timescale 1ns/10ps

module mac_unit_ws #(
    parameter int IP_size = 8,
    parameter int OP_size = 32,
    parameter bit clr_load_first = 1'b1
)(
    input  logic clk,
    input  logic rst,

    // ------------------------------------------------------------------------
    // Compute token control (same "valid + optional clear" idea as OS)
    // en_in  : valid compute token for this PE
    // clr_in : sampled only when en_in=1, used to initialize psum for a new output
    // These propagate horizontally with x (en_out/clr_out -> PE to the right).
    // ------------------------------------------------------------------------
    input  logic en_in,
    input  logic clr_in,
    output logic en_out,
    output logic clr_out,

    // ------------------------------------------------------------------------
    // WS-only control
    // w_load_in=1 => capture incoming weight into local register AND forward down
    // w_load_in=0 => hold stationary weight (w_reg) for multiply during compute
    // ------------------------------------------------------------------------
    input  logic w_load_in,

    // ------------------------------------------------------------------------
    // Streams
    // x_new   : activation from left
    // w_new   : weight from top (only meaningful during load)
    // psum_in : partial sum from PE above (vertical chain)
    // ------------------------------------------------------------------------
    input  logic signed [IP_size-1:0] x_new,
    input  logic signed [IP_size-1:0] w_new,
    input  logic signed [OP_size-1:0] psum_in,

    // Forwarded streams
    output logic signed [IP_size-1:0] x_old,   // to PE right (1-cycle hop)
    output logic signed [IP_size-1:0] w_old,   // to PE below during load

    // In WS: mac_out is the registered psum_out for this PE (kept name for compatibility)
    output logic signed [OP_size-1:0] mac_out
);

    localparam int prod_w = 2 * IP_size;

    // =========================================================================
    // WS principle in one line:
    //   hold weight locally (w_reg), stream x across, stream psum down
    // =========================================================================

    // Local stationary weight (loaded in LOAD phase, held during COMPUTE)
    logic signed [IP_size-1:0] w_reg;

    // =========================================================================
    // Pipeline overview (kept similar to OS to keep latency predictable)
    //   S1: register x + psum + control, and manage weight load/hold
    //   S2: multiply pipe stage
    //   S3: align/pipe stage
    //   S4: psum_out = psum_in + (x * w_reg)
    // =========================================================================

    // Stage 1 regs
    logic signed [IP_size-1:0]  s1_x, s1_w;
    logic signed [OP_size-1:0]  s1_psum;
    logic v1, c1;

    always_ff @(posedge clk) begin
        if (rst) begin
            s1_x     <= '0;
            s1_w     <= '0;
            s1_psum  <= '0;
            v1       <= 1'b0;
            c1       <= 1'b0;

            w_reg    <= '0;

            x_old    <= '0;
            w_old    <= '0;
            en_out   <= 1'b0;
            clr_out  <= 1'b0;
        end else begin
            // ----------------------------------------------------------------
            // Weight behavior:
            // LOAD  : latch w_new into w_reg and push it down the column (w_old)
            // COMPUTE: keep w_reg stationary; w_old isn't really used, but driving
            //          it doesn't hurt and keeps wiring simple.
            // ----------------------------------------------------------------
            if (w_load_in) begin
                w_reg <= w_new;
                w_old <= w_new;   // shift weights downward during load
            end else begin
                w_old <= w_reg;   // hold/reflect stationary weight
            end

            // Activation streams right
            x_old <= x_new;

            // Stage-1 pipeline registers:
            // - multiply always uses stationary weight (w_reg)
            // - psum_in is only meaningful when token is valid
            s1_x    <= x_new;
            s1_w    <= w_reg;
            s1_psum <= en_in ? psum_in : '0;

            // Token control propagation (same semantics as OS)
            v1 <= en_in;
            c1 <= en_in & clr_in;

            en_out  <= en_in;
            clr_out <= en_in & clr_in;
        end
    end

    // =========================================================================
    // Stage 2: multiply
    // =========================================================================
    logic signed [prod_w-1:0]  s2_p;
    logic signed [OP_size-1:0] s2_psum;
    logic v2, c2;

    always_ff @(posedge clk) begin
        if (rst) begin
            v2      <= 1'b0;
            c2      <= 1'b0;
            s2_p    <= '0;
            s2_psum <= '0;
        end else begin
            v2      <= v1;
            c2      <= c1;
            s2_p    <= v1 ? (prod_w'(s1_x) * prod_w'(s1_w)) : '0;
            s2_psum <= v1 ? s1_psum : '0;
        end
    end

    // =========================================================================
    // Stage 3: extra pipe stage for timing + alignment with psum
    // =========================================================================
    logic signed [prod_w-1:0]  s3_p;
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
    // Stage 4: psum update
    // For a valid token:
    //   - if c3=1 (init token), either load-first (common) or force 0
    //   - else psum_out = incoming psum + current product
    // =========================================================================
    logic signed [OP_size-1:0] addend;

    always_comb begin
        // sign-extend product to OP_size (assumes OP_size >= prod_w in this project)
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
