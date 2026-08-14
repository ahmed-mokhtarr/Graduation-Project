// =============================================================================
// Module  : feature_harvester
// Purpose : After TRACK, iterates the Harvest Queue. Any Grid Map entry still
//           set to 1 is a genuinely new feature. Assigns a new ID and appends
//           to flist. Consumes all grid entries (writes 0).
// =============================================================================

module feature_harvester #(
    parameter IMG_WIDTH    = 1280,
    parameter MAX_FEATURES = 2048,
    parameter FEAT_W       = 64,
    parameter ADDR_W       = 11,
    parameter COL_W        = 11,
    parameter ROW_W        = 10,
    parameter DATA_WIDTH   = COL_W + ROW_W,
    parameter GRID_ADDR_W  = 20
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // ── Control ─────────────────────────────────────────────────────────────
    input  wire                   start,
    input  wire [ADDR_W:0]        harvest_limit,   // harvest_count from feature_saving
    input  wire [ADDR_W:0]        base_wr_idx,     // flist offset = tracked_count
    input  wire [ADDR_W:0]        max_total,       // MAX_FEATURES
    output reg                    done,
    output reg                    busy,

    // ── Harvest Queue read port ─────────────────────────────────────────────
    output reg  [ADDR_W-1:0]      harvest_rd_addr,
    input  wire [DATA_WIDTH-1:0]  harvest_rd_data, // {col[10:0], row[9:0]}

    // ── Grid Map (read + consume) ───────────────────────────────────────────
    output reg  [GRID_ADDR_W-1:0] grid_addr,
    output reg                    grid_we,
    output reg                    grid_din,
    input  wire                   grid_dout,

    // ── Feature List write port ─────────────────────────────────────────────
    output reg  [ADDR_W-1:0]      flist_wr_addr,
    output reg  [FEAT_W-1:0]      flist_wr_data,
    output reg                    flist_wr_en,

    // ── ID counter ──────────────────────────────────────────────────────────
    input  wire [31:0]            id_counter_in,
    output reg  [31:0]            id_counter_out,

    // ── Status ──────────────────────────────────────────────────────────────
    output reg  [ADDR_W:0]        harvested_count
);

    // =========================================================================
    // FSM states
    // =========================================================================
    localparam [2:0]
        H_IDLE    = 3'd0,
        H_READ    = 3'd1,   // issue harvest queue read
        H_WAIT    = 3'd2,   // BRAM latency
        H_GRID_RD = 3'd3,   // issue grid map read
        H_GWAIT   = 3'd4,   // BRAM latency
        H_DECIDE  = 3'd5,   // check grid, decide new/consumed
        H_WRITE   = 3'd6,   // write to flist + consume grid
        H_DONE    = 3'd7;

    reg [2:0]        state;
    reg [ADDR_W:0]   h_idx;         // harvest queue index
    reg [ADDR_W:0]   wr_idx;        // current flist write index
    reg [COL_W-1:0]  h_col;
    reg [ROW_W-1:0]  h_row;
    reg [31:0]       id_cnt;

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= H_IDLE;
            done            <= 1'b0;
            busy            <= 1'b0;
            harvest_rd_addr <= 0;
            grid_addr       <= 0;
            grid_we         <= 1'b0;
            grid_din        <= 1'b0;
            flist_wr_addr   <= 0;
            flist_wr_data   <= 0;
            flist_wr_en     <= 1'b0;
            id_counter_out  <= 0;
            harvested_count <= 0;
            h_idx           <= 0;
            wr_idx          <= 0;
            h_col           <= 0;
            h_row           <= 0;
            id_cnt          <= 0;
        end else begin
            // Defaults
            done        <= 1'b0;
            grid_we     <= 1'b0;
            flist_wr_en <= 1'b0;

            case (state)

            H_IDLE: begin
                if (start) begin
                    busy            <= 1'b1;
                    h_idx           <= 0;
                    wr_idx          <= base_wr_idx;
                    harvested_count <= 0;
                    id_cnt          <= id_counter_in;
                    state           <= H_READ;
                end
            end

            // ── Read harvest queue entry ────────────────────────────────
            H_READ: begin
                if (h_idx >= harvest_limit) begin
                    state <= H_DONE;
                end else begin
                    harvest_rd_addr <= h_idx[ADDR_W-1:0];
                    state           <= H_WAIT;
                end
            end

            H_WAIT: begin
                state <= H_GRID_RD;
            end

            // ── Issue grid map read ─────────────────────────────────────
            H_GRID_RD: begin
                h_col     <= harvest_rd_data[DATA_WIDTH-1:ROW_W]; // col
                h_row     <= harvest_rd_data[ROW_W-1:0];          // row
                grid_addr <= harvest_rd_data[ROW_W-1:0] * IMG_WIDTH +
                             harvest_rd_data[DATA_WIDTH-1:ROW_W];
                state     <= H_GWAIT;
            end

            H_GWAIT: begin
                state <= H_DECIDE;
            end

            // ── Check grid ──────────────────────────────────────────────
            H_DECIDE: begin
                if (grid_dout == 1'b0) begin
                    // Already consumed during TRACK → skip
                    $display("[FH] SKIPPING consumed feature at X=%0d Y=%0d", h_col, h_row);
                    h_idx <= h_idx + 1'b1;
                    state <= H_READ;
                end else if (wr_idx >= max_total) begin
                    // Feature list full — still consume grid cell
                    grid_we   <= 1'b1;
                    grid_din  <= 1'b0;
                    // grid_addr already set from H_GRID_RD
                    h_idx     <= h_idx + 1'b1;
                    state     <= H_READ;
                end else begin
                    // New feature!
                    $display("[FH] HARVESTING feature at X=%0d Y=%0d", h_col, h_row);
                    state <= H_WRITE;
                end
            end

            // ── Write new feature + consume grid ────────────────────────
            H_WRITE: begin
                // Write to flist
                flist_wr_en   <= 1'b1;
                flist_wr_addr <= wr_idx[ADDR_W-1:0];
                flist_wr_data <= {
                    11'b0,                  // [63:53]
                    id_cnt,                 // [52:21]
                    h_col[COL_W-1:0],       // [20:10]
                    h_row[ROW_W-1:0]        // [9:0]
                };

                // Consume grid cell
                grid_we  <= 1'b1;
                grid_din <= 1'b0;
                // grid_addr still valid from H_GRID_RD

                // Advance
                id_cnt          <= id_cnt + 1'b1;
                wr_idx          <= wr_idx + 1'b1;
                harvested_count <= harvested_count + 1'b1;
                h_idx           <= h_idx + 1'b1;
                state           <= H_READ;
            end

            H_DONE: begin
                done           <= 1'b1;
                busy           <= 1'b0;
                id_counter_out <= id_cnt;
                state          <= H_IDLE;
            end

            default: state <= H_IDLE;

            endcase
        end
    end

endmodule
