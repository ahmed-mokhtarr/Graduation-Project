// =============================================================================
// Module  : feature_saving
// Purpose : Captures corner coordinates from fast_top and stores them into:
//           1. Harvest Queue (ping-pong SDP BRAMs) — list of (col, row) coords
//           2. Grid Map (ping-pong SDP BRAMs) — 1-bit per pixel, marks corners
//
//           Has its OWN internal ping-pong (grid_hq_pp) that toggles on
//           frame_done. The exposed ports to tracking always serve the
//           just-completed (OLD) bank.
//
//           SYNC FIX: grid_hq_pp toggle is deferred while tracking_busy is
//           asserted, preventing the grid map from switching mid-tracking.
// =============================================================================

module feature_saving #(
    parameter IMG_WIDTH    = 1280,
    parameter IMG_HEIGHT   = 720,
    parameter MAX_FEATURES = 2048,
    parameter ADDR_WIDTH   = 11, // harvest
    parameter COL_W        = 11,
    parameter ROW_W        = 10,
    parameter DATA_WIDTH   = COL_W + ROW_W,
    parameter GRID_ADDR_W  = 20
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // ── From fast_top ───────────────────────────────────────────────────────
    input  wire                    corner_valid,
    input  wire [COL_W-1:0]        corner_col,
    input  wire [ROW_W-1:0]        corner_row,
    input  wire                    frame_done,
    input  wire                    track_bank_sel,

    // ── Tracking busy (from feature_tracking_merging) ───────────────────────
    input  wire                    tracking_busy,

    // ── Grid Map ports (exposed to tracking — OLD bank) ─────────────────────
    input  wire [GRID_ADDR_W-1:0]  grid_rd_addr,
    output wire                    grid_rd_data,
    input  wire [GRID_ADDR_W-1:0]  grid_wr_addr,
    input  wire                    grid_wr_data,   // 0 to consume
    input  wire                    grid_wr_en,

    // ── Harvest Queue read port (exposed to tracking — OLD bank) ────────────
    input  wire [ADDR_WIDTH-1:0]   harvest_rd_addr,
    output wire [DATA_WIDTH-1:0]   harvest_rd_data,

    // ── Status ──────────────────────────────────────────────────────────────
    output reg  [ADDR_WIDTH:0]     harvest_count,
    output reg                     frame_ready,
    output reg                     overflow
);

    // =========================================================================
    // Internal state
    // =========================================================================
    reg                grid_hq_pp;    // internal ping-pong
    reg [ADDR_WIDTH:0] feat_ptr;
    reg                overflow_flag;
    reg                pending_toggle;           // deferred toggle flag
    reg [ADDR_WIDTH:0] pending_harvest_count;    // latched count for deferred toggle

    wire accept = corner_valid && !frame_done && (feat_ptr < MAX_FEATURES);

    // ── Write data for Harvest Queue ────────────────────────────────────────
    wire [DATA_WIDTH-1:0] hq_wr_data = {corner_col, corner_row};
    wire [ADDR_WIDTH-1:0] hq_wr_addr = feat_ptr[ADDR_WIDTH-1:0];

    // ── Write address for Grid Map ──────────────────────────────────────────
    wire [GRID_ADDR_W-1:0] grid_wr_addr_int = corner_row * IMG_WIDTH + corner_col;

    // ── Bank selection (internal) ───────────────────────────────────────────
    wire hq_wr_en_a = accept && (grid_hq_pp == 1'b0);
    wire hq_wr_en_b = accept && (grid_hq_pp == 1'b1);

    wire grid_int_wr_en_a = accept && (grid_hq_pp == 1'b0);
    wire grid_int_wr_en_b = accept && (grid_hq_pp == 1'b1);

    // =========================================================================
    // Harvest Queue — 2× SDP BRAM (2048 × 21-bit, ping-pong)
    // =========================================================================
    wire [DATA_WIDTH-1:0] hq_rd_data_a, hq_rd_data_b;

    simple_dual_port_bram #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_harvest_q_a (
        .clk     (clk),
        .we      (hq_wr_en_a),
        .wr_addr (hq_wr_addr),
        .wr_data (hq_wr_data),
        .rd_addr (harvest_rd_addr),
        .rd_data (hq_rd_data_a)
    );

    simple_dual_port_bram #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_harvest_q_b (
        .clk     (clk),
        .we      (hq_wr_en_b),
        .wr_addr (hq_wr_addr),
        .wr_data (hq_wr_data),
        .rd_addr (harvest_rd_addr),
        .rd_data (hq_rd_data_b)
    );

    // Tracking reads the OLD bank (the one just completed, = track_bank_sel)
    assign harvest_rd_data = (track_bank_sel == 1'b1) ? hq_rd_data_a : hq_rd_data_b;

    // =========================================================================
    // Grid Map — 2× SDP BRAM (2^20 × 1-bit, ping-pong)
    // =========================================================================
    // ── Grid Map Bank A ─────────────────────────────────────────────────────
    wire                   grid_a_we;
    wire [GRID_ADDR_W-1:0] grid_a_wr_addr_w;
    wire                   grid_a_wr_data_w;
    wire [GRID_ADDR_W-1:0] grid_a_rd_addr_w;
    wire                   grid_a_rd_data;
    
    wire                   grid_b_we;
    wire [GRID_ADDR_W-1:0] grid_b_wr_addr_w;
    wire                   grid_b_wr_data_w;
    wire [GRID_ADDR_W-1:0] grid_b_rd_addr_w;
    wire                   grid_b_rd_data;

    // ── Grid bank routing uses grid_hq_pp for write/read address steering ───
    // When grid_hq_pp=0: Bank A = NEW (feature_saving writes), Bank B = OLD (tracking reads)
    // When grid_hq_pp=1: Bank B = NEW (feature_saving writes), Bank A = OLD (tracking reads)

    // Bank A mux
    assign grid_a_we        = (grid_hq_pp == 1'b0) ? grid_int_wr_en_a   : grid_wr_en;
    assign grid_a_wr_addr_w = (grid_hq_pp == 1'b0) ? grid_wr_addr_int   : grid_wr_addr;
    assign grid_a_wr_data_w = (grid_hq_pp == 1'b0) ? 1'b1               : grid_wr_data;
    assign grid_a_rd_addr_w = (grid_hq_pp == 1'b0) ? {GRID_ADDR_W{1'b0}}: grid_rd_addr;

    simple_dual_port_bram #(
        .DATA_WIDTH (1),
        .ADDR_WIDTH (GRID_ADDR_W)
    ) u_grid_map_a (
        .clk     (clk),
        .we      (grid_a_we),
        .wr_addr (grid_a_wr_addr_w),
        .wr_data (grid_a_wr_data_w),
        .rd_addr (grid_a_rd_addr_w),
        .rd_data (grid_a_rd_data)
    );

    // Bank B mux
    assign grid_b_we        = (grid_hq_pp == 1'b1) ? grid_int_wr_en_b   : grid_wr_en;
    assign grid_b_wr_addr_w = (grid_hq_pp == 1'b1) ? grid_wr_addr_int   : grid_wr_addr;
    assign grid_b_wr_data_w = (grid_hq_pp == 1'b1) ? 1'b1               : grid_wr_data;
    assign grid_b_rd_addr_w = (grid_hq_pp == 1'b1) ? {GRID_ADDR_W{1'b0}}: grid_rd_addr;

    simple_dual_port_bram #(
        .DATA_WIDTH (1),
        .ADDR_WIDTH (GRID_ADDR_W)
    ) u_grid_map_b (
        .clk     (clk),
        .we      (grid_b_we),
        .wr_addr (grid_b_wr_addr_w),
        .wr_data (grid_b_wr_data_w),
        .rd_addr (grid_b_rd_addr_w),
        .rd_data (grid_b_rd_data)
    );

    // Tracking reads the OLD bank — SINGLE assign using grid_hq_pp
    assign grid_rd_data = (grid_hq_pp == 1'b1) ? grid_a_rd_data : grid_b_rd_data;

    // =========================================================================
    // Write pointer + status
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            feat_ptr      <= {(ADDR_WIDTH+1){1'b0}};
            overflow_flag <= 1'b0;
        end else if (frame_done) begin
            feat_ptr      <= {(ADDR_WIDTH+1){1'b0}};
            overflow_flag <= 1'b0;
        end else begin
            if (corner_valid) begin
                if (feat_ptr < MAX_FEATURES)
                    feat_ptr <= feat_ptr + 1'b1;
                else
                    overflow_flag <= 1'b1;
            end
        end
    end

    // =========================================================================
    // Ping-pong toggle + frame handshake (with tracking_busy deferral)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            grid_hq_pp            <= 1'b0;
            harvest_count         <= {(ADDR_WIDTH+1){1'b0}};
            frame_ready           <= 1'b0;
            overflow              <= 1'b0;
            pending_toggle        <= 1'b0;
            pending_harvest_count <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            frame_ready <= 1'b0;   // pulse

            if (frame_done) begin
                if (!tracking_busy) begin
                    // Safe to toggle immediately
                    grid_hq_pp    <= ~grid_hq_pp;
                    harvest_count <= feat_ptr;
                    frame_ready   <= 1'b1;
                    overflow      <= overflow_flag;
                end else begin
                    // Tracking is active — defer the toggle
                    pending_toggle        <= 1'b1;
                    pending_harvest_count <= feat_ptr;
                end
            end

            // Apply deferred toggle once tracking finishes
            if (pending_toggle && !tracking_busy) begin
                grid_hq_pp            <= ~grid_hq_pp;
                harvest_count         <= pending_harvest_count;
                frame_ready           <= 1'b1;
                overflow              <= overflow_flag;
                pending_toggle        <= 1'b0;
            end
        end
    end

endmodule
