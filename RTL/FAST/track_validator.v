// =============================================================================
// Module  : track_validator
// Purpose : Pops features from the FIFO, computes new position (x+dx, y+dy),
//           validates against the FAST Grid Map using a parameterized WxW
//           window, and writes tracked features to the Feature List.
// =============================================================================

module track_validator #(
    parameter IMG_WIDTH    = 1280,
    parameter IMG_HEIGHT   = 720,
    parameter MAX_FEATURES = 2048,
    parameter WINDOW_HALF  = 1,          // 1→3×3, 2→5×5
    parameter DX_WIDTH     = 5,
    parameter DY_WIDTH     = 5,
    parameter FEAT_W       = 64,
    parameter ADDR_W       = 11,
    parameter COL_W        = 11,
    parameter ROW_W        = 10,
    parameter GRID_ADDR_W  = 20,
    parameter FIFO_W       = 64
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   enable,

    // ── FIFO read port ──────────────────────────────────────────────────────
    input  wire [FIFO_W-1:0]      fifo_dout,
    input  wire                   fifo_empty,
    output reg                    fifo_rd_en,

    // ── Grid Map (read + consume) ───────────────────────────────────────────
    output reg  [GRID_ADDR_W-1:0] grid_addr,
    output reg                    grid_we,
    output reg                    grid_din,    // always 0 for consume
    input  wire                   grid_dout,

    // ── Feature List write port ─────────────────────────────────────────────
    output reg  [ADDR_W-1:0]      flist_wr_addr,
    output reg  [FEAT_W-1:0]      flist_wr_data,
    output reg                    flist_wr_en,

    // ── Status ──────────────────────────────────────────────────────────────
    input  wire                   stream_done, // from gf_feature_matcher
    output reg  [ADDR_W:0]        tracked_count,
    output reg                    idle         // no work left
);

    // =========================================================================
    // Window iteration parameters
    // =========================================================================
    localparam WINDOW_SIZE = 2 * WINDOW_HALF + 1;
    localparam signed [COL_W:0] W_NEG = -WINDOW_HALF;
    localparam signed [COL_W:0] W_POS =  WINDOW_HALF;

    // =========================================================================
    // FSM states
    // =========================================================================
    localparam [2:0]
        V_IDLE    = 3'd0,
        V_POP     = 3'd1,
        V_CALC    = 3'd2,
        V_SCAN    = 3'd3,
        V_SWAIT   = 3'd4,   // wait for grid BRAM read latency
        V_CHECK   = 3'd5,
        V_WRITE   = 3'd6,
        V_CONSUME = 3'd7;

    reg [2:0] state;

    // =========================================================================
    // Registered feature data
    // =========================================================================
    reg [31:0]              feat_id;
    reg signed [COL_W:0]    x_new;     // wider for signed arithmetic
    reg signed [ROW_W:0]    y_new;
    reg signed [DX_WIDTH-1:0] feat_dx;
    reg signed [DY_WIDTH-1:0] feat_dy;

    // Window scan position
    reg signed [COL_W:0]    dx_off;
    reg signed [ROW_W:0]    dy_off;

    // Match result
    reg                     match_found;
    reg [GRID_ADDR_W-1:0]   match_addr;
    reg [COL_W-1:0]         match_x;      // actual matched grid X
    reg [ROW_W-1:0]         match_y;      // actual matched grid Y

    // Track end condition
    reg                     gf_stream_done;

    // =========================================================================
    // FIFO entry unpacking: {1'b0, id[31:0], px[10:0], py[9:0], dx[4:0], dy[4:0]}
    // =========================================================================
    wire [31:0]              fifo_id = fifo_dout[62:31];
    wire [COL_W-1:0]         fifo_px = fifo_dout[30:20];
    wire [ROW_W-1:0]         fifo_py = fifo_dout[19:10];
    wire signed [DX_WIDTH-1:0] fifo_dx = fifo_dout[9:5];
    wire signed [DY_WIDTH-1:0] fifo_dy = fifo_dout[4:0];

    // =========================================================================
    // Compute grid address for window scan
    // =========================================================================
    // Fix unsigned + signed bug by explicitly casting the zero-extended unsigned coords
    wire signed [COL_W:0] scan_x = $signed({1'b0, x_new}) + dx_off;
    wire signed [ROW_W:0] scan_y = $signed({1'b0, y_new}) + dy_off;
    wire scan_in_bounds = (scan_x >= 0) && (scan_x < IMG_WIDTH) &&
                          (scan_y >= 0) && (scan_y < IMG_HEIGHT);
    wire [GRID_ADDR_W-1:0] scan_addr = scan_y[ROW_W-1:0] * IMG_WIDTH + scan_x[COL_W-1:0];

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= V_IDLE;
            fifo_rd_en     <= 1'b0;
            grid_addr      <= 0;
            grid_we        <= 1'b0;
            grid_din       <= 1'b0;
            flist_wr_addr  <= 0;
            flist_wr_data  <= 0;
            flist_wr_en    <= 1'b0;
            tracked_count  <= 0;
            idle           <= 1'b1;
            feat_id        <= 0;
            x_new          <= 0;
            y_new          <= 0;
            feat_dx        <= 0;
            feat_dy        <= 0;
            dx_off         <= 0;
            dy_off         <= 0;
            match_found    <= 1'b0;
            match_addr     <= 0;
            match_x        <= 0;
            match_y        <= 0;
            gf_stream_done <= 1'b0;
        end else begin
            // Defaults
            fifo_rd_en  <= 1'b0;
            grid_we     <= 1'b0;
            flist_wr_en <= 1'b0;

            // Latch stream_done
            if (stream_done)
                gf_stream_done <= 1'b1;

            if (!enable) begin
                state          <= V_IDLE;
                tracked_count  <= 0;
                idle           <= 1'b1;
                gf_stream_done <= 1'b0;
            end else begin

                case (state)

                V_IDLE: begin
                    // Only start processing features once the frame stream is complete
                    // and the entire grid map has been populated with corners!
                    if (!fifo_empty && gf_stream_done) begin
                        idle  <= 1'b0;
                        state <= V_POP;
                    end else if (gf_stream_done && fifo_empty) begin
                        idle <= 1'b1;
                    end
                end

                // ── Pop FIFO entry ──────────────────────────────────────
                V_POP: begin
                    // Pulse rd_en to advance FWFT FIFO for next cycle
                    fifo_rd_en <= 1'b1;

                    // Latch data from current valid FIFO word
                    feat_id <= fifo_id;
                    feat_dx <= fifo_dx;
                    feat_dy <= fifo_dy;
                    x_new <= $signed({1'b0, fifo_px}) + $signed(fifo_dx);
                    y_new <= $signed({1'b0, fifo_py}) + $signed(fifo_dy);

                    // Reset window scan
                    dx_off      <= W_NEG;
                    dy_off      <= W_NEG;
                    match_found <= 1'b0;

                    state <= V_SCAN;
                end

                // ── Bounds check + issue grid read ──────────────────────
                V_SCAN: begin
                    if (match_found) begin
                        // Already found a match, proceed to write
                        state <= V_WRITE;
                    end else if (scan_in_bounds) begin
                        // Issue grid read at window position
                        grid_addr <= scan_addr;
                        state     <= V_SWAIT;
                    end else begin
                        // Out of bounds window position — skip it
                        if (dx_off == W_POS) begin
                            dx_off <= W_NEG;
                            if (dy_off == W_POS) begin
                                // Window scan complete, no match
                                state <= V_IDLE;
                            end else begin
                                dy_off <= dy_off + 1;
                            end
                        end else begin
                            dx_off <= dx_off + 1;
                        end
                    end
                end

                // ── Wait for grid BRAM read latency ─────────────────────
                V_SWAIT: begin
                    state <= V_CHECK;
                end

                // ── Check grid value ────────────────────────────────────
                V_CHECK: begin
                    $display("[TV] check scan_x=%0d scan_y=%0d grid_dout=%b match_found=%b", scan_x, scan_y, grid_dout, match_found);
                    if (grid_dout == 1'b1) begin
                        // Match found — store actual matched position
                        match_found <= 1'b1;
                        match_addr  <= grid_addr;
                        match_x     <= scan_x[COL_W-1:0];
                        match_y     <= scan_y[ROW_W-1:0];
                        state       <= V_WRITE;
                        $display("[TV] -> MATCH FOUND!");
                    end else begin
                        // No match at this cell, advance window
                        if (dx_off == W_POS) begin
                            dx_off <= W_NEG;
                            if (dy_off == W_POS) begin
                                // Window scan complete, no match
                                state <= V_IDLE;
                            end else begin
                                dy_off <= dy_off + 1;
                                state  <= V_SCAN;
                            end
                        end else begin
                            dx_off <= dx_off + 1;
                            state  <= V_SCAN;
                        end
                    end
                end

                // ── Write tracked feature to flist ──────────────────────
                V_WRITE: begin
                    if (tracked_count < MAX_FEATURES) begin
                        flist_wr_en   <= 1'b1;
                        flist_wr_addr <= tracked_count[ADDR_W-1:0];
                        flist_wr_data <= {
                            11'b0,                  // [63:53]
                            feat_id,                // [52:21]
                            match_x[COL_W-1:0],     // [20:10]
                            match_y[ROW_W-1:0]      // [9:0]
                        };
                        tracked_count <= tracked_count + 1'b1;
                        state         <= V_CONSUME;
                    end else begin
                        // Feature list full, still consume grid cell
                        state <= V_CONSUME;
                    end
                end

                // ── Consume grid cell (write 0) ─────────────────────────
                V_CONSUME: begin
                    // Clear the matched grid point to avoid harvesting it again
                    grid_we   <= 1'b1;
                    grid_addr <= match_addr;
                    grid_din  <= 1'b0;
                    $display("[TV] CLEARING Grid at addr=%0d (X=%0d, Y=%0d)", match_addr, match_x, match_y);
                    state     <= V_IDLE;
                end

                default: state <= V_IDLE;

                endcase
            end
        end
    end

endmodule
