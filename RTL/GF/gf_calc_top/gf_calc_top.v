// =============================================================================
// gf_calc_top.v
//
// Top-level module for Galois Field (GF) calculation.
// Integrates:
//   1. mapped_coef_gen_top (retiming + poly_exp + coef_bram_window + prev_coef_fifo)
//   2. row_gap_inserter (synchronizer)
//   3. update_top (update_matrices + update_flow)
//
// Pipeline:
//   MRM pixels -> mapped_coef_gen_top -> row_gap_inserter -> update_top -> deltas
// =============================================================================
module gf_calc_top #(
    parameter PIXEL_WIDTH = 8,
    parameter WSIZE       = 7,
    parameter DLIMIT      = 12
)(
    input  wire               clk,
    input  wire               rst_n,

    // ── MRM interface ───────────────────────────────────────────────────────
    input  wire               data_ready,
    output wire               ready,
    input  wire [PIXEL_WIDTH-1:0] curr_data_in,
    input  wire [PIXEL_WIDTH-1:0] prev_data_in,

    // ── Configuration ───────────────────────────────────────────────────────
    input  wire [2:0]         layer_config,

    // ── Flow upper (d vector) from zoom-in module ───────────────────────────
    input  wire signed [7:0]  flow_upper_x,
    input  wire signed [7:0]  flow_upper_y,

    // ── Output ──────────────────────────────────────────────────────────────────
    output wire               valid_out,
    output wire [15:0]        out_delta, // [15:8]=delta_y, [7:0]=delta_x

    // ── CBW sampling indicator ─────────────────────────────────────────────────
    output wire               cbw_sampling,

    // ── Status ──────────────────────────────────────────────────────────────
    output wire               frame_done,
    output wire               frame_start
);

    // =========================================================================
    // 1. mapped_coef_gen_top (retiming + poly_exp + CBW + prev_fifo)
    // =========================================================================
    wire               mcg_valid;
    wire signed [14:0] mcg_curr_r2, mcg_prev_r2;
    wire signed [16:0] mcg_curr_r3, mcg_prev_r3;
    wire signed [13:0] mcg_curr_r4, mcg_prev_r4;
    wire signed [16:0] mcg_curr_r5, mcg_prev_r5;
    wire signed [14:0] mcg_curr_r6, mcg_prev_r6;
    wire               mcg_frame_done;

    mapped_coef_gen_top #(.PIXEL_WIDTH(PIXEL_WIDTH), .DLIMIT(DLIMIT)) u_mapped_cg (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_ready     (data_ready),
        .ready          (ready),
        .curr_data_out  (curr_data_in),
        .prev_data_out  (prev_data_in),
        .layer_config   (layer_config),
        .flow_upper_x   (flow_upper_x),
        .flow_upper_y   (flow_upper_y),
        .curr_r2_out    (mcg_curr_r2),
        .curr_r3_out    (mcg_curr_r3),
        .curr_r4_out    (mcg_curr_r4),
        .curr_r5_out    (mcg_curr_r5),
        .curr_r6_out    (mcg_curr_r6),
        .prev_r2_out    (mcg_prev_r2),
        .prev_r3_out    (mcg_prev_r3),
        .prev_r4_out    (mcg_prev_r4),
        .prev_r5_out    (mcg_prev_r5),
        .prev_r6_out    (mcg_prev_r6),
        .valid_out      (mcg_valid),
        .cbw_sampling   (cbw_sampling),
        .frame_done     (mcg_frame_done),
        .frame_start    (frame_start)
    );

    assign frame_done = mcg_frame_done;

    // =========================================================================
    // 2. row_gap_inserter (synchronizer)
    // Guarantees >=8 blank cycles between rows for update_flow
    // =========================================================================
    // Pack all 10 coefficient channels (curr + prev) into one wide bus
    localparam RGI_WIDTH = 15+17+14+17+15 + 15+17+14+17+15; // = 156 bits
    wire [RGI_WIDTH-1:0] rgi_data_in = {
        mcg_curr_r6, mcg_curr_r5, mcg_curr_r4, mcg_curr_r3, mcg_curr_r2,
        mcg_prev_r6, mcg_prev_r5, mcg_prev_r4, mcg_prev_r3, mcg_prev_r2
    };

    wire               rgi_valid_out;
    wire [RGI_WIDTH-1:0] rgi_data_out;

    // Unpack row_gap_inserter output
    wire signed [14:0] rgi_prev_r2 = rgi_data_out[14:0];
    wire signed [16:0] rgi_prev_r3 = rgi_data_out[31:15];
    wire signed [13:0] rgi_prev_r4 = rgi_data_out[45:32];
    wire signed [16:0] rgi_prev_r5 = rgi_data_out[62:46];
    wire signed [14:0] rgi_prev_r6 = rgi_data_out[77:63];

    wire signed [14:0] rgi_curr_r2_out = rgi_data_out[78+14:78];
    wire signed [16:0] rgi_curr_r3_out = rgi_data_out[78+31:78+15];
    wire signed [13:0] rgi_curr_r4_out = rgi_data_out[78+45:78+32];
    wire signed [16:0] rgi_curr_r5_out = rgi_data_out[78+62:78+46];
    wire signed [14:0] rgi_curr_r6_out = rgi_data_out[78+77:78+63];

    row_gap_inserter #(
        .DATA_WIDTH (RGI_WIDTH),
        .GAP_CYCLES (4),
        .FIFO_DEPTH (4096)
    ) u_rgi (
        .clk          (clk),
        .rst_n        (rst_n),
        .layer_config (layer_config),
        .valid_in     (mcg_valid),
        .data_in      (rgi_data_in),
        .valid_out    (rgi_valid_out),
        .data_out     (rgi_data_out)
    );

    // =========================================================================
    // 3. update_top (update_matrices + update_flow)
    // Driven by row_gap_inserter's gap-aligned output.
    // =========================================================================
    update_top #(
        .WSIZE(WSIZE), .W_R2(15), .W_R3(17), .W_R4(14), .W_R5(17), .W_R6(15)
    ) u_update_top (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid_in       (rgi_valid_out),
        .layer_config   (layer_config),
        .prev_frame_r2  (rgi_prev_r2),
        .prev_frame_r3  (rgi_prev_r3),
        .prev_frame_r4  (rgi_prev_r4),
        .prev_frame_r5  (rgi_prev_r5),
        .prev_frame_r6  (rgi_prev_r6),
        .curr_frame_r2  (rgi_curr_r2_out),
        .curr_frame_r3  (rgi_curr_r3_out),
        .curr_frame_r4  (rgi_curr_r4_out),
        .curr_frame_r5  (rgi_curr_r5_out),
        .curr_frame_r6  (rgi_curr_r6_out),
        .valid_out      (valid_out),
        .out_delta      (out_delta)
    );

endmodule
