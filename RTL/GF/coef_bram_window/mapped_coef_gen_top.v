// =============================================================================
// mapped_coef_gen_top.v
//
// Mapped Coefficient Generation Top Module
//
// Integrates:
//   1. coef_gen_top    — retiming + 2x poly_exp (curr & prev channels)
//   2. coef_bram_window — BRAM-based spatial shift of curr coefficients
//   3. prev_coef_fifo  — delays prev coefficients to align with CBW output
//
// Pipeline:
//   MRM pixels → retiming → poly_exp(curr) → coef_bram_window ─→ curr_r* out
//                          → poly_exp(prev) → prev_coef_fifo   ─→ prev_r* out
//                                             rd_en = cbw_valid_out
//
// Output valid_out fires when BOTH curr (shifted) and prev (delayed) are ready.
// Output has 1-cycle read latency from cbw_valid_out (registered outputs).
// Directly drives update_top.
// =============================================================================
module mapped_coef_gen_top #(
    parameter PIXEL_WIDTH = 8,
    parameter DLIMIT      = 12
)(
    input  wire               clk,
    input  wire               rst_n,

    // ── MRM interface ───────────────────────────────────────────────────────
    input  wire               data_ready,
    output wire               ready,
    input  wire [PIXEL_WIDTH-1:0] curr_data_out,
    input  wire [PIXEL_WIDTH-1:0] prev_data_out,

    // ── Configuration ───────────────────────────────────────────────────────
    input  wire [2:0]         layer_config,

    // ── Flow upper (d vector) from zoom-in module ───────────────────────────
    input  wire signed [7:0]  flow_upper_x,
    input  wire signed [7:0]  flow_upper_y,

    // ── Aligned output: curr (shifted) coefficients ─────────────────────────
    output reg  signed [14:0] curr_r2_out,
    output reg  signed [16:0] curr_r3_out,
    output reg  signed [13:0] curr_r4_out,
    output reg  signed [16:0] curr_r5_out,
    output reg  signed [14:0] curr_r6_out,

    // ── Aligned output: prev (delayed) coefficients ─────────────────────────
    output wire signed [14:0] prev_r2_out,
    output wire signed [16:0] prev_r3_out,
    output wire signed [13:0] prev_r4_out,
    output wire signed [16:0] prev_r5_out,
    output wire signed [14:0] prev_r6_out,

    // ── Synchronized valid output ───────────────────────────────────────────
    output reg                valid_out,

    // ── CBW sampling indicator (valid_in && tready) ─────────────────────────
    output wire               cbw_sampling,

    // ── Status ──────────────────────────────────────────────────────────────
    output wire               frame_done,
    output wire               frame_start
);

    // =========================================================================
    // 1. coef_gen_top (retiming + 2x poly_exp_top)
    // =========================================================================
    wire signed [14:0] cg_curr_r2, cg_prev_r2;
    wire signed [16:0] cg_curr_r3, cg_prev_r3;
    wire signed [13:0] cg_curr_r4, cg_prev_r4;
    wire signed [16:0] cg_curr_r5, cg_prev_r5;
    wire signed [14:0] cg_curr_r6, cg_prev_r6;
    wire               cg_curr_valid, cg_prev_valid;

    coef_gen_top #(.PIXEL_WIDTH(PIXEL_WIDTH)) u_coef_gen (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_ready     (data_ready),
        .ready          (ready),
        .curr_data_out  (curr_data_out),
        .prev_data_out  (prev_data_out),
        .layer_config   (layer_config),
        .curr_r2_out    (cg_curr_r2),
        .curr_r3_out    (cg_curr_r3),
        .curr_r4_out    (cg_curr_r4),
        .curr_r5_out    (cg_curr_r5),
        .curr_r6_out    (cg_curr_r6),
        .curr_valid_out (cg_curr_valid),
        .prev_r2_out    (cg_prev_r2),
        .prev_r3_out    (cg_prev_r3),
        .prev_r4_out    (cg_prev_r4),
        .prev_r5_out    (cg_prev_r5),
        .prev_r6_out    (cg_prev_r6),
        .prev_valid_out (cg_prev_valid),
        .frame_done     (frame_done),
        .frame_start    (frame_start)
    );

    // =========================================================================
    // =========================================================================
    // 2. coef_bram_window (curr channel: BRAM shift lookup + self-drain)
    // =========================================================================
    wire               cbw_tready;
    wire               cbw_valid_out;
    wire signed [14:0] cbw_r2, cbw_r6;
    wire signed [16:0] cbw_r3, cbw_r5;
    wire signed [13:0] cbw_r4;

    // CBW sampling: when CBW accepts a new pixel (valid_in && tready)
    assign cbw_sampling = cg_curr_valid && cbw_tready;

    coef_bram_window #(.DLIMIT(DLIMIT)) u_cbw (
        .clk            (clk),
        .rst_n          (rst_n),
        .layer_config   (layer_config),
        .valid_in       (cg_curr_valid),
        .r2_curr        (cg_curr_r2),
        .r3_curr        (cg_curr_r3),
        .r4_curr        (cg_curr_r4),
        .r5_curr        (cg_curr_r5),
        .r6_curr        (cg_curr_r6),
        .flow_upper_x   (flow_upper_x),
        .flow_upper_y   (flow_upper_y),
        .tready         (cbw_tready),
        .valid_out       (cbw_valid_out),
        .r2_shifted     (cbw_r2),
        .r3_shifted     (cbw_r3),
        .r4_shifted     (cbw_r4),
        .r5_shifted     (cbw_r5),
        .r6_shifted     (cbw_r6)
    );

    // =========================================================================
    // 3. prev_coef_fifo (prev channel: delay to align with CBW output)
    //    Write: coef_gen prev_valid_out
    //    Read:  cbw_valid_out (1-cycle read latency → aligns with curr_d1)
    // =========================================================================
    wire               fifo_rd_valid;

    prev_coef_fifo #(.DLIMIT(DLIMIT)) u_prev_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (cg_prev_valid),
        .wr_r2   (cg_prev_r2),
        .wr_r3   (cg_prev_r3),
        .wr_r4   (cg_prev_r4),
        .wr_r5   (cg_prev_r5),
        .wr_r6   (cg_prev_r6),
        .rd_en   (cbw_valid_out),
        .rd_r2   (prev_r2_out),
        .rd_r3   (prev_r3_out),
        .rd_r4   (prev_r4_out),
        .rd_r5   (prev_r5_out),
        .rd_r6   (prev_r6_out),
        .rd_valid(fifo_rd_valid)
    );

    // =========================================================================
    // 4. Output alignment (1-cycle register for curr to match FIFO latency)
    // =========================================================================
    // cbw_valid_out fires at cycle N:
    //   - cbw_r* available (curr shifted data)
    //   - FIFO rd_en triggers read
    // Cycle N+1:
    //   - curr_r*_out = registered cbw_r*
    //   - prev_r*_out = FIFO rd_data (1-cycle latency)
    //   - valid_out = cbw_valid_out_d1 = fifo_rd_valid

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out    <= 1'b0;
            curr_r2_out  <= 15'd0;
            curr_r3_out  <= 17'd0;
            curr_r4_out  <= 14'd0;
            curr_r5_out  <= 17'd0;
            curr_r6_out  <= 15'd0;
        end else begin
            valid_out    <= cbw_valid_out;
            curr_r2_out  <= cbw_r2;
            curr_r3_out  <= cbw_r3;
            curr_r4_out  <= cbw_r4;
            curr_r5_out  <= cbw_r5;
            curr_r6_out  <= cbw_r6;
        end
    end

endmodule
