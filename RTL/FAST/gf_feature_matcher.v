// =============================================================================
// Module  : gf_feature_matcher
// Purpose : Two-pointer merge between the GF pixel stream (raster order) and
//           the sorted prevList. When the GF pixel position matches the next
//           sorted feature's position, capture (id, x, y, dx, dy) and push
//           into the FIFO. Never stalls the GF stream (tready always HIGH).
// =============================================================================

module gf_feature_matcher #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter DX_WIDTH   = 5,
    parameter DY_WIDTH   = 5,
    parameter FEAT_W     = 64,
    parameter COL_W      = 11,
    parameter ROW_W      = 10,
    parameter ADDR_W     = 11,
    parameter FIFO_W     = 64     // FIFO entry: {id[31:0], x[10:0], y[9:0], dx[4:0], dy[4:0], 3'b0}
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          enable,       // HIGH during TRACK state

    // ── AXI-Stream from GF ──────────────────────────────────────────────────
    input  wire [DX_WIDTH+DY_WIDTH-1:0]  s_axis_tdata, // {dy[4:0], dx[4:0]}
    input  wire                          s_axis_tvalid,
    output wire                          s_axis_tready,
    input  wire                          s_axis_tlast,

    // ── Sorted prevList BRAM read port ──────────────────────────────────────
    output reg  [ADDR_W-1:0]             sorted_rd_addr,
    input  wire [FEAT_W-1:0]             sorted_rd_data,

    // ── Prev feature count ──────────────────────────────────────────────────
    input  wire [ADDR_W:0]               prev_feat_count,

    // ── FIFO write port ─────────────────────────────────────────────────────
    output reg  [FIFO_W-1:0]             fifo_din,
    output reg                           fifo_wr_en,
    input  wire                          fifo_full,

    // ── Status ──────────────────────────────────────────────────────────────
    output reg                           stream_done
);

    // =========================================================================
    // Raster counter
    // =========================================================================
    reg [COL_W-1:0] pixel_x;
    reg [ROW_W-1:0] pixel_y;

    // =========================================================================
    // Feature Prefetch FIFO and BRAM Read Pipeline
    // =========================================================================
    wire [FEAT_W-1:0] prefetch_dout;
    wire              prefetch_empty;
    wire              prefetch_full;
    reg               prefetch_rd_en;

    reg [ADDR_W:0] fetch_ptr;
    reg [ADDR_W:0] matched_count; // Number of features popped from prefetch FIFO
    
    wire [ADDR_W:0] prefetch_occupancy = fetch_ptr - matched_count;
    wire can_fetch = (fetch_ptr < prev_feat_count) && (prefetch_occupancy < 5);
    
    reg [1:0] fetch_pending;

    fast_sync_fifo #(
        .DATA_WIDTH(FEAT_W),
        .DEPTH(8)
    ) u_prefetch_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .flush(!enable),
        .din(sorted_rd_data),
        .wr_en(fetch_pending[1]),
        .dout(prefetch_dout),
        .rd_en(prefetch_rd_en),
        .full(prefetch_full),
        .empty(prefetch_empty)
    );

    // =========================================================================
    // Comparison logic: is the current GF pixel at/past the sorted feature?
    // =========================================================================
    wire sorted_valid = !prefetch_empty;
    wire [COL_W-1:0] feat_x  = prefetch_dout[20:10];
    wire [ROW_W-1:0] feat_y  = prefetch_dout[9:0];
    wire [31:0]      feat_id = prefetch_dout[52:21];

    
    // GF tready - stall if output FIFO is full OR we are waiting for a feature pop
    assign s_axis_tready = enable && !fifo_full;

    // Raster comparison: (pixel_y, pixel_x) vs (feat_y, feat_x)
    wire pixel_matches = sorted_valid && !prefetch_rd_en &&
                         (pixel_y == feat_y) && (pixel_x == feat_x);
    wire pixel_past    = sorted_valid && !prefetch_rd_en &&
                         ((pixel_y > feat_y) || 
                          (pixel_y == feat_y && pixel_x > feat_x));

    // =========================================================================
    // Extract dx, dy from GF stream
    // =========================================================================
    wire signed [DX_WIDTH-1:0] dx = s_axis_tdata[DX_WIDTH-1:0];
    wire signed [DY_WIDTH-1:0] dy = s_axis_tdata[DX_WIDTH+DY_WIDTH-1:DX_WIDTH];

    // =========================================================================
    // Main logic
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_x          <= 0;
            pixel_y          <= 0;
            fifo_din         <= 0;
            fifo_wr_en       <= 1'b0;
            stream_done      <= 1'b0;
            fetch_ptr        <= 0;
            matched_count    <= 0;
            sorted_rd_addr   <= 0;
            fetch_pending    <= 0;
            prefetch_rd_en   <= 1'b0;
                    end else begin
            fifo_wr_en     <= 1'b0;
            stream_done    <= 1'b0;
            prefetch_rd_en <= 1'b0;

            if (!enable) begin
                // Reset state when not active
                pixel_x          <= 0;
                pixel_y          <= 0;
                fetch_ptr        <= 0;
                matched_count    <= 0;
                sorted_rd_addr   <= 0;
                fetch_pending    <= 0;
                            end else begin
                // ── BRAM Prefetch Pipeline ─────────────────────────────────
                if (can_fetch) begin
                    sorted_rd_addr <= fetch_ptr[ADDR_W-1:0];
                    fetch_ptr <= fetch_ptr + 1'b1;
                    fetch_pending[0] <= 1'b1;
                end else begin
                    fetch_pending[0] <= 1'b0;
                end
                fetch_pending[1] <= fetch_pending[0];

                if (prefetch_rd_en) begin
                    matched_count <= matched_count + 1'b1;
                end

                // ── Track features & Drop missed ones ──────────────────────
                if (pixel_matches && s_axis_tvalid && s_axis_tready) begin
                    // Push to FIFO: {1'b0, id[31:0], x[10:0], y[9:0], dx[4:0], dy[4:0]}
                    fifo_wr_en <= 1'b1;
                    fifo_din   <= {1'b0, feat_id, pixel_x, pixel_y, dx, dy};
                    prefetch_rd_en <= 1'b1;
                end else if (pixel_past) begin
                    // Feature was lost (not matched at exact pixel)
                    prefetch_rd_en <= 1'b1;
                end

                // ── Process GF pixel ───────────────────────────────────────
                if (s_axis_tvalid && s_axis_tready) begin
                    // Advance raster counter
                    if (pixel_x == IMG_WIDTH - 1) begin
                        pixel_x <= 0;
                        if (pixel_y == IMG_HEIGHT - 1) begin
                            pixel_y <= 0;
                            stream_done <= 1'b1;
                        end else begin
                            pixel_y <= pixel_y + 1'b1;
                        end
                    end else begin
                        pixel_x <= pixel_x + 1'b1;
                    end
                end
            end // enable
        end
    end

endmodule
