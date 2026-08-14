// =============================================================================
// coef_gen_top.v
//
// Coefficient Generation Top Module
//
// Integrates:
//   1. retiming       — dispatches curr / prev pixels + counters
//   2. poly_exp_top   — polynomial expansion for "curr" frame  (inst: u_poly_curr)
//   3. poly_exp_top   — polynomial expansion for "prev" frame  (inst: u_poly_prev)
//
// Both polynomial expanders receive the same x/y counters and layer_config;
// they differ only in the pixel data they process.
// =============================================================================
module coef_gen_top #(
    parameter PIXEL_WIDTH = 8
)(
    input  wire               clk,
    input  wire               rst_n,

    // ── MRM interface ──────────────────────────────────────────────────────
    input  wire               data_ready,
    output wire               ready,
    input  wire [PIXEL_WIDTH-1:0] curr_data_out,
    input  wire [PIXEL_WIDTH-1:0] prev_data_out,

    // ── Configuration ──────────────────────────────────────────────────────
    input  wire [2:0]         layer_config,

    // ── curr-frame polynomial coefficients ────────────────────────────────
    output wire signed [14:0] curr_r2_out,
    output wire signed [16:0] curr_r3_out,
    output wire signed [13:0] curr_r4_out,
    output wire signed [16:0] curr_r5_out,
    output wire signed [14:0] curr_r6_out,
    output wire               curr_valid_out,

    // ── prev-frame polynomial coefficients ────────────────────────────────
    output wire signed [14:0] prev_r2_out,
    output wire signed [16:0] prev_r3_out,
    output wire signed [13:0] prev_r4_out,
    output wire signed [16:0] prev_r5_out,
    output wire signed [14:0] prev_r6_out,
    output wire               prev_valid_out,

    // ── Status ─────────────────────────────────────────────────────────────
    output wire               frame_done,
    output wire               frame_start
);

    // =========================================================================
    // Retiming instance
    // =========================================================================
    wire               curr_valid_in;
    wire [PIXEL_WIDTH-1:0] curr_pixel_in;
    wire [11:0]        curr_x_counter;
    wire [11:0]        curr_y_counter;

    wire               prev_valid_in;
    wire [PIXEL_WIDTH-1:0] prev_pixel_in;
    wire [11:0]        prev_x_counter;
    wire [11:0]        prev_y_counter;

    retiming #(
        .PIXEL_WIDTH (PIXEL_WIDTH)
    ) u_retiming (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_ready    (data_ready),
        .ready         (ready),
        .curr_data_out (curr_data_out),
        .prev_data_out (prev_data_out),
        .layer_config  (layer_config),
        // curr channel
        .curr_valid_in  (curr_valid_in),
        .curr_pixel_in  (curr_pixel_in),
        .curr_x_counter (curr_x_counter),
        .curr_y_counter (curr_y_counter),
        // prev channel
        .prev_valid_in  (prev_valid_in),
        .prev_pixel_in  (prev_pixel_in),
        .prev_x_counter (prev_x_counter),
        .prev_y_counter (prev_y_counter),
        // status
        .frame_width  (),
        .frame_height (),
        .frame_done   (frame_done),
        .frame_start  (frame_start)
    );

    // =========================================================================
    // Poly-Expansion — current frame
    // =========================================================================
    poly_exp_top u_poly_curr (
        .clk          (clk),
        .rst_n        (rst_n),
        .valid_in     (curr_valid_in),
        .layer_config (layer_config),
        .pixel_in     (curr_pixel_in),
        .x_counter    (curr_x_counter),
        .y_counter    (curr_y_counter),
        .r2_out       (curr_r2_out),
        .r3_out       (curr_r3_out),
        .r4_out       (curr_r4_out),
        .r5_out       (curr_r5_out),
        .r6_out       (curr_r6_out),
        .valid_out    (curr_valid_out)
    );

    // =========================================================================
    // Poly-Expansion — previous frame
    // =========================================================================
    poly_exp_top u_poly_prev (
        .clk          (clk),
        .rst_n        (rst_n),
        .valid_in     (prev_valid_in),
        .layer_config (layer_config),
        .pixel_in     (prev_pixel_in),
        .x_counter    (prev_x_counter),
        .y_counter    (prev_y_counter),
        .r2_out       (prev_r2_out),
        .r3_out       (prev_r3_out),
        .r4_out       (prev_r4_out),
        .r5_out       (prev_r5_out),
        .r6_out       (prev_r6_out),
        .valid_out    (prev_valid_out)
    );

endmodule
