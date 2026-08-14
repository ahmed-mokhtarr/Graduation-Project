// =============================================================================
// gf_pipeline_top.v
//
// Integrates:
//   1. zoom_in        — bilinear 2× upsample of upper-layer d-vector
//   2. accum_fifo     — buffers zoomed d for output accumulation
//   3. gf_calc_top    — existing GF calculation pipeline
//   4. Accumulation   — out = gf_delta + (zoom_d <<< 3), saturated to 8-bit
//
// Data-flow:
//   d_upper → zoom_in → (direct wire) → gf_calc_top.flow_upper (CBW)
//                      → [accum_fifo]  → <<3 → (+) → saturate → out_delta_accum
//   pixels  →                          → gf_calc_top → out_delta ──↗
//
// No FIFO between zoom_in and CBW — zoom_in output is connected directly.
// Pipeline stalls (ready=0) when zoom_in hasn't produced output yet.
// =============================================================================
module gf_pipeline_top #(
    parameter PIXEL_WIDTH = 8,
    parameter WSIZE       = 7,
    parameter DLIMIT      = 12,
    parameter FIFO_DEPTH  = 1048576,     // simulation-friendly: 2^20
    parameter FIFO_ADDR_W = 20
)(
    input  wire                       clk,
    input  wire                       rst_n,

    // ── Pixel streaming (current layer) ─────────────────────────────────
    input  wire                       data_ready,
    output wire                       ready,
    input  wire [PIXEL_WIDTH-1:0]     curr_data_in,
    input  wire [PIXEL_WIDTH-1:0]     prev_data_in,

    // ── Layer configuration ─────────────────────────────────────────────
    input  wire [2:0]                 layer_config,

    // ── Upper-layer d-vector input (from MRM-like testbench) ────────────
    input  wire                       flow_ready,
    input  wire [15:0]                flow_data,    // {dy[7:0], dx[7:0]}
    output wire                       flow_rd_en,
    input  wire                       operation_start,

    // ── Control ─────────────────────────────────────────────────────────
    input  wire                       skip_zoom,    // 1 = top layer (L4): bypass zoom

    // ── Final accumulated output ────────────────────────────────────────
    output reg                        valid_out,
    output reg  [15:0]                out_delta,    // {accum_dy[7:0], accum_dx[7:0]}

    // ── Status ──────────────────────────────────────────────────────────
    output wire                       frame_done,
    output wire                       frame_start,
    output wire                       zoom_done,
    output wire [3:0]                 dbg_zoom_state,
    output wire [2:0]                 dbg_ret_state
);
    // =====================================================================
    // 1.  CBW sampling detection
    //     CBW samples flow_upper when valid_in && tready inside CBW.
    //     Exposed as a proper output port through the hierarchy.
    // =====================================================================
    wire cbw_sampling;   // connected to gf_calc_top output port below

    // =====================================================================
    // 1b. Latched skip_zoom — stable throughout each layer's processing.
    //     External skip_zoom changes combinationally when the FSM transitions
    //     layers, but the pipeline may still be in VFLUSH for the previous
    //     layer.  The latch prevents accum_fifo corruption and spurious
    //     zoom_in advancement during that overlap window.
    // =====================================================================
    reg skip_zoom_latched;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            skip_zoom_latched <= 1'b1;   // default: L4 (top layer, skip)
        else if (frame_start)            // latch at retiming IDLE→ACT
            skip_zoom_latched <= skip_zoom;
    end

    // =====================================================================
    // 2.  zoom_in  (upper layer → 2× upsampled d-vectors)
    // =====================================================================
    // zoom_in receives the UPPER layer index (current + 1) so it computes
    // correct dimensions: (IMG_WIDTH/2) >> layer_upper
    wire [2:0] layer_upper = layer_config + 3'd1;

    wire [15:0] zi_dout;
    wire        zi_data_ready;   // zoom_in has valid output available

    zoom_in #(.DLIMIT(DLIMIT)) u_zoom_in (
        .clk              (clk),
        .rst_n            (rst_n),
        .operation_start  (operation_start && !skip_zoom),
        .curr_layer       (layer_config + 3'd1), // Zoom operates on upper layer data
        .flow_data        (flow_data),
        .flow_ready       (flow_ready && !skip_zoom),
        .flow_rd_en       (flow_rd_en),
        .zoom_done        (zoom_done),
        .zoomed_tready    (cbw_sampling && !skip_zoom_latched),
        .zoomed_flow_out  (zi_dout),
        .zoomed_data_ready(zi_data_ready)
    );

    assign dbg_zoom_state = 4'd0;   // debug outputs tied off for synthesis
    assign dbg_ret_state  = 3'd0;

    // =====================================================================
    // 3.  Direct connection: zoom_in → gf_calc_top.flow_upper
    //     (NO FIFO — zoom_in output drives flow_upper directly)
    // =====================================================================
    wire signed [7:0] flow_upper_x = skip_zoom_latched ? 8'sd0 : $signed(zi_dout[7:0]);
    wire signed [7:0] flow_upper_y = skip_zoom_latched ? 8'sd0 : $signed(zi_dout[15:8]);

    // =====================================================================
    // 4.  Accumulation FIFO (stores zoomed d for final accumulation)
    //     Written when CBW samples flow_upper (= when zoom_in is consumed)
    // =====================================================================
    wire        accum_fifo_empty;
    wire [15:0] accum_fifo_rd_data;
    wire        accum_pop;

    gf_sync_fifo #(
        .DATA_WIDTH (16),
        .ADDR_WIDTH (15)
    ) u_accum_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .flush   (frame_start),
        .wr_en   (cbw_sampling && !skip_zoom_latched),
        .din     (zi_dout),
        .rd_en   (accum_pop),
        .dout    (accum_fifo_rd_data),
        .empty   (accum_fifo_empty),
        .full    ()
    );


    // =====================================================================
    // 5.  gf_calc_top
    // =====================================================================
    wire        gf_valid_out;
    wire [15:0] gf_out_delta;
    wire        gf_ready;

    // Pipeline stalls when zoom_in doesn't have output ready (backpressure)
    // For L4 (skip_zoom=1), no backpressure from zoom_in.
    // Latch zoom_done to ungate pipeline when zoom_in has finished its rows but retiming is still flushing
    reg zoom_finished;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            zoom_finished <= 1'b0;
        else if (frame_start)
            zoom_finished <= 1'b0;
        else if (zoom_done)
            zoom_finished <= 1'b1;
    end

    assign ready = gf_ready && (skip_zoom || zi_data_ready || zoom_finished);

    // FIX: Gate data_ready so gf_calc_top doesn't consume the same pixel multiple times
    // while waiting for zoom_in to produce data (which happens when ready is dropped).
    wire gf_gated_data_ready = data_ready && (skip_zoom || zi_data_ready || zoom_finished);

    gf_calc_top #(.PIXEL_WIDTH(PIXEL_WIDTH), .WSIZE(WSIZE), .DLIMIT(DLIMIT)) u_gf_calc (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_ready     (gf_gated_data_ready),
        .ready          (gf_ready),
        .curr_data_in   (curr_data_in),
        .prev_data_in   (prev_data_in),
        .layer_config   (layer_config),
        .flow_upper_x   (flow_upper_x),
        .flow_upper_y   (flow_upper_y),
        .valid_out      (gf_valid_out),
        .out_delta      (gf_out_delta),
        .cbw_sampling   (cbw_sampling),
        .frame_done     (frame_done),
        .frame_start    (frame_start)
    );

    // ── accum_fifo pops on each gf_calc valid output ────────────────────
    assign accum_pop = gf_valid_out && !skip_zoom_latched;

    // =====================================================================
    // 6.  Output accumulation
    //     final = gf_delta + (zoom_d <<< 3),  saturated to [-128,+127]
    // =====================================================================
    wire signed [7:0] gf_dx = $signed(gf_out_delta[7:0]);
    wire signed [7:0] gf_dy = $signed(gf_out_delta[15:8]);

    wire signed [7:0] accum_fifo_dx = accum_fifo_rd_data[7:0];
    wire signed [7:0] accum_fifo_dy = accum_fifo_rd_data[15:8];
    wire signed [7:0] zoom_dx_shifted = accum_fifo_dx <<< 3;
    wire signed [7:0] zoom_dy_shifted = accum_fifo_dy <<< 3;

    // 9-bit addition
    wire signed [8:0] sum_dx = {gf_dx[7], gf_dx} + {zoom_dx_shifted[7], zoom_dx_shifted};
    wire signed [8:0] sum_dy = {gf_dy[7], gf_dy} + {zoom_dy_shifted[7], zoom_dy_shifted};

    // Saturate to signed 8-bit
    wire signed [7:0] sat_dx = (sum_dx >  9'sd127) ?  8'sd127 :
                               (sum_dx < -9'sd128) ? -8'sd128 :
                                sum_dx[7:0];
    wire signed [7:0] sat_dy = (sum_dy >  9'sd127) ?  8'sd127 :
                               (sum_dy < -9'sd128) ? -8'sd128 :
                                sum_dy[7:0];

    // Gate: for non-skip layers, suppress output when accum_fifo is empty
    // (this catches old-layer pipeline tail events after flush)
    wire gf_output_valid = gf_valid_out && (skip_zoom_latched || !accum_fifo_empty);

    // Register final output (1-cycle latency after gf_valid_out)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            out_delta <= 16'h0000;
        end else begin
            valid_out <= gf_output_valid;
            if (gf_output_valid) begin
                if (skip_zoom_latched)
                    out_delta <= gf_out_delta;          // pass-through for L4
                else
                    out_delta <= {sat_dy, sat_dx};      // accumulated
            end
        end
    end

    // =====================================================================
    // SIMULATION-ONLY DEBUG: trace accum_fifo behaviour per layer
    // =====================================================================
    // synthesis translate_off
    integer accum_wr_cnt, accum_rd_cnt;
    reg [2:0] dbg_layer_seen;

    initial begin
        accum_wr_cnt   = 0;
        accum_rd_cnt   = 0;
        dbg_layer_seen = 3'd7;
    end

    // On frame_start: print FIFO state and reset counters
    always @(posedge clk) begin
        if (frame_start) begin
            // $display("[ACCUM_DBG %0t] frame_start layer=%0d skip=%0d skip_latched=%0d | FIFO wr_ptr=%0d rd_ptr=%0d empty=%0d | prev_layer=%0d wr_cnt=%0d rd_cnt=%0d",
            //          $time, layer_config, skip_zoom, skip_zoom_latched,
            //          u_accum_fifo.wr_ptr, u_accum_fifo.rd_ptr, accum_fifo_empty,
            //          dbg_layer_seen, accum_wr_cnt, accum_rd_cnt);
            accum_wr_cnt   <= 0;
            accum_rd_cnt   <= 0;
            dbg_layer_seen <= layer_config;
        end
    end

    // Count and print first 10 writes per layer
    always @(posedge clk) begin
        if (cbw_sampling && !skip_zoom_latched) begin
            accum_wr_cnt <= accum_wr_cnt + 1;
            // if (accum_wr_cnt < 10)
            //     $display("[ACCUM_WR %0t] layer=%0d cnt=%0d zi_dout=%04h (dx=%0d dy=%0d) zi_rdy=%0d empty=%0d",
            //              $time, layer_config, accum_wr_cnt, zi_dout,
            //              $signed(zi_dout[7:0]), $signed(zi_dout[15:8]),
            //              zi_data_ready, accum_fifo_empty);
        end
    end

    // Count and print first 10 reads per layer
    always @(posedge clk) begin
        if (gf_valid_out && !skip_zoom_latched) begin
            accum_rd_cnt <= accum_rd_cnt + 1;
        end
    end
endmodule
