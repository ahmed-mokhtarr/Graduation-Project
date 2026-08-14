// ==============================================================================
// update_top.v
// ==============================================================================
// Top-level module integrating update_matrices and update_flow.
//
// PARAMETERIZATION:
//   The input parameters W_R2..W_R6 mirror the output widths of the
//   coefficient-generation (poly_exp / coef_gen) module exactly, so this
//   block can be dropped in at any pyramid level simply by overriding those.
//
// PIPELINE LATENCY:
//   update_matrices : 3 cycles
//   update_flow     : V_filter(4) + H_filter(4) + math(1) = 9+ cycles
//   Total end-to-end latency from first valid_in to first valid_out depends on
//   frame size and the number of padding rows/cols handled internally.
//
// OUTPUT FORMAT (16-bit):
//   out_delta[15:8] = delta_y  (signed 8-bit, Q8 fixed-point: divide by 256 for pixels)
//   out_delta[ 7:0] = delta_x  (signed 8-bit, Q8 fixed-point)
//
//   Values are saturated to [-128, 127] before packing.
// ==============================================================================
module update_top #(
    // --- Window size for averaging filter ---
    parameter WSIZE = 7,

    // --- Coef-gen output widths (match poly_exp / coef_bram_window outputs) ---
    parameter W_R2 = 47,    // r2 width  (b_x term)
    parameter W_R3 = 49,    // r3 width  (b_y term)
    parameter W_R4 = 46,    // r4 width  (A11 term)
    parameter W_R5 = 49,    // r5 width  (A22 term)
    parameter W_R6 = 47,    // r6 width  (A12 term, raw, before /4)

    // --- Derived update_matrices widths (computed from W_R*) ---
    parameter W_DB_X    = W_R2 + 1,
    parameter W_DB_Y    = W_R3 + 1,
    parameter W_A11     = W_R4 + 1,
    parameter W_A22     = W_R5 + 1,
    parameter W_A12     = W_R6 + 1,

    parameter W_A11_SQ  = 2 * W_A11,
    parameter W_A22_SQ  = 2 * W_A22,
    parameter W_A12_SQ  = 2 * W_A12,

    parameter W_H1_T1   = W_A11 + W_DB_X,
    parameter W_H1_T2   = W_A12 + W_DB_Y,
    parameter W_H2_T1   = W_A12 + W_DB_X,
    parameter W_H2_T2   = W_A22 + W_DB_Y,
    parameter W_A_TRACE = (W_A11 > W_A22 ? W_A11 : W_A22) + 1,

    parameter W_G11     = (W_A11_SQ > W_A12_SQ ? W_A11_SQ : W_A12_SQ) + 1,
    parameter W_G22     = (W_A12_SQ > W_A22_SQ ? W_A12_SQ : W_A22_SQ) + 1,
    parameter W_G12     = W_A12 + W_A_TRACE,
    parameter W_H1      = (W_H1_T1 > W_H1_T2 ? W_H1_T1 : W_H1_T2) + 1,
    parameter W_H2      = (W_H2_T1 > W_H2_T2 ? W_H2_T1 : W_H2_T2) + 1,

    // --- update_flow derived widths (using W_G11/G22/G12/H1/H2 as inputs) ---
    parameter NUMX_WIDTH   = (W_G22 + W_H1 + 4*$clog2(WSIZE) + 1),
    parameter NUMY_WIDTH   = (W_G11 + W_H2 + 4*$clog2(WSIZE) + 1),
    parameter DET_WIDTH    = (W_G11 + W_G22 + 4*$clog2(WSIZE) + 1),

    // --- Detector threshold (set so that near-zero determinants are zeroed) ---
    parameter [63:0] DET_THRESHOLD = 64'd0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [2:0]  layer_config,

    // --- Inputs: previous frame coefficients ---
    input  wire signed [W_R2-1:0]  prev_frame_r2,
    input  wire signed [W_R3-1:0]  prev_frame_r3,
    input  wire signed [W_R4-1:0]  prev_frame_r4,
    input  wire signed [W_R5-1:0]  prev_frame_r5,
    input  wire signed [W_R6-1:0]  prev_frame_r6,

    // --- Inputs: current frame coefficients ---
    input  wire signed [W_R2-1:0]  curr_frame_r2,
    input  wire signed [W_R3-1:0]  curr_frame_r3,
    input  wire signed [W_R4-1:0]  curr_frame_r4,
    input  wire signed [W_R5-1:0]  curr_frame_r5,
    input  wire signed [W_R6-1:0]  curr_frame_r6,

    // --- Output: 16-bit packed delta {delta_y[7:0], delta_x[7:0]} ---
    output reg         valid_out,
    output reg  [15:0] out_delta          // [15:8]=delta_y  [7:0]=delta_x
);

    // =========================================================================
    // Stage A: update_matrices  (3 pipeline stages)
    // =========================================================================
    wire                     mat_valid_out;
    wire signed [W_G11-1:0]  mat_G11;
    wire signed [W_G12-1:0]  mat_G12;
    wire signed [W_G22-1:0]  mat_G22;
    wire signed [W_H1-1:0]   mat_H1;
    wire signed [W_H2-1:0]   mat_H2;

    update_matrices #(
        .W_R2(W_R2),
        .W_R3(W_R3),
        .W_R4(W_R4),
        .W_R5(W_R5),
        .W_R6(W_R6)
    ) u_matrices (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid_in       (valid_in),

        .prev_frame_r2  (prev_frame_r2),
        .prev_frame_r3  (prev_frame_r3),
        .prev_frame_r4  (prev_frame_r4),
        .prev_frame_r5  (prev_frame_r5),
        .prev_frame_r6  (prev_frame_r6),

        .curr_frame_r2  (curr_frame_r2),
        .curr_frame_r3  (curr_frame_r3),
        .curr_frame_r4  (curr_frame_r4),
        .curr_frame_r5  (curr_frame_r5),
        .curr_frame_r6  (curr_frame_r6),

        .valid_out      (mat_valid_out),
        .matrix_G11_out (mat_G11),
        .matrix_G12_out (mat_G12),
        .matrix_G22_out (mat_G22),
        .vector_h1_out  (mat_H1),
        .vector_h2_out  (mat_H2)
    );

    // =========================================================================
    // Stage B: update_flow  (V-filter + H-filter + math stages)
    // =========================================================================
    wire                        flow_valid_out;
    wire signed [NUMX_WIDTH-1:0] flow_delta_x;
    wire signed [NUMY_WIDTH-1:0] flow_delta_y;

    update_flow #(
        .WSIZE        (WSIZE),
        .G11_WIDTH    (W_G11),
        .G22_WIDTH    (W_G22),
        .G12_WIDTH    (W_G12),
        .h1_WIDTH     (W_H1),
        .h2_WIDTH     (W_H2),
        .DET_THRESHOLD(DET_THRESHOLD)
    ) u_flow (
        .clk          (clk),
        .rst_n        (rst_n),
        .valid_in     (mat_valid_out),
        .layer_config (layer_config),

        .G11_in       (mat_G11),
        .G22_in       (mat_G22),
        .G12_in       (mat_G12),
        .h1_in        (mat_H1),
        .h2_in        (mat_H2),

        .valid_out    (flow_valid_out),
        .delta_x_out  (flow_delta_x),
        .delta_y_out  (flow_delta_y)
    );

    // =========================================================================
    // Stage C: Saturate & Pack into 16-bit output
    //   delta_x and delta_y are Q8 fixed-point (<<8 already applied internally
    //   in update_flow).  We clamp to signed 8-bit range [-128, +127] and pack.
    // =========================================================================
    localparam signed [NUMX_WIDTH-1:0] SAT_POS_X = { {(NUMX_WIDTH-8){1'b0}}, 8'sd127 };
    localparam signed [NUMX_WIDTH-1:0] SAT_NEG_X = { {(NUMX_WIDTH-8){1'b1}}, 8'sd128 };
    localparam signed [NUMY_WIDTH-1:0] SAT_POS_Y = { {(NUMY_WIDTH-8){1'b0}}, 8'sd127 };
    localparam signed [NUMY_WIDTH-1:0] SAT_NEG_Y = { {(NUMY_WIDTH-8){1'b1}}, 8'sd128 };

    wire signed [NUMX_WIDTH-1:0] sat_x = (flow_delta_x >  SAT_POS_X) ?  SAT_POS_X :
                                          (flow_delta_x <  SAT_NEG_X) ?  SAT_NEG_X :
                                           flow_delta_x;
    wire signed [NUMY_WIDTH-1:0] sat_y = (flow_delta_y >  SAT_POS_Y) ?  SAT_POS_Y :
                                          (flow_delta_y <  SAT_NEG_Y) ?  SAT_NEG_Y :
                                           flow_delta_y;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            out_delta <= 16'h0000;
        end else begin
            valid_out <= flow_valid_out;
            if (flow_valid_out) begin
                out_delta <= { sat_y[7:0], sat_x[7:0] };
            end
        end
    end

endmodule
