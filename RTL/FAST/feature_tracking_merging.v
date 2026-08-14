// =============================================================================
// Module  : feature_tracking_merging
// Purpose : Top-level module for feature tracking and merging.
//           FSM: IDLE → INIT → TRACK → DRAIN → HARVEST → SEND → SWAP
//           Validator runs concurrently in TRACK (once grid ready) and DRAIN,
//           enabling a small 64-entry FIFO between matcher and validator.
//
//           Grid Map / Harvest Queue ping-pong is managed by feature_saving
//           (toggles at frame_done). This module only manages Feature List pp.
// =============================================================================

module feature_tracking_merging #(
    parameter IMG_WIDTH    = 1280,
    parameter IMG_HEIGHT   = 720,
    parameter MAX_FEATURES = 2048,
    parameter WINDOW_HALF  = 1,
    parameter DX_WIDTH     = 5,
    parameter DY_WIDTH     = 5,
    parameter FEAT_W       = 64,
    parameter ADDR_W       = 11,
    parameter COL_W        = 11,
    parameter ROW_W        = 10,
    parameter GRID_ADDR_W  = 20,
    parameter FIFO_W       = 64,
    parameter FIFO_DEPTH   = 2048
)(
    input  wire                          clk,
    input  wire                          rst_n,

    // ── AXI-Stream from GF Module ───────────────────────────────────────────
    input  wire [DX_WIDTH+DY_WIDTH-1:0]  s_axis_gf_tdata,
    input  wire                          s_axis_gf_tvalid,
    output wire                          s_axis_gf_tready,
    input  wire                          s_axis_gf_tlast,

    // ── Grid Map ports (to/from feature_saving — OLD bank) ──────────────────
    output wire [GRID_ADDR_W-1:0]        grid_rd_addr,
    input  wire                          grid_rd_data,
    output wire [GRID_ADDR_W-1:0]        grid_wr_addr,
    output wire                          grid_wr_data,
    output wire                          grid_wr_en,

    // ── Harvest Queue (from feature_saving — OLD bank) ──────────────────────
    output wire [ADDR_W-1:0]             harvest_rd_addr,
    input  wire [COL_W+ROW_W-1:0]        harvest_rd_data,
    input  wire [ADDR_W:0]               harvest_count,

    // ── Frame synchronization from feature_saving ───────────────────────────
    input  wire                          frame_ready,

    // ── AXI-Stream Master (to DMA → DDR) ────────────────────────────────────
    output wire [63:0]           m_axis_feat_tdata,
    output wire                  m_axis_feat_tvalid,
    input  wire                  m_axis_feat_tready,
    output wire                  m_axis_feat_tlast,
    output wire                  tracking_bank_sel,

    // ── Tracking busy (to feature_saving for grid toggle deferral) ─────────
    output wire                  tracking_busy,

    // ── Status / IRQ ────────────────────────────────────────────────────────
    output reg                           frame_done_irq,
    output reg  [ADDR_W:0]              total_feat_count
);

    // =========================================================================
    // Main FSM
    // =========================================================================
    localparam [2:0]
        FSM_IDLE    = 3'd0,
        FSM_INIT    = 3'd1,
        FSM_TRACK   = 3'd2,
        FSM_DRAIN   = 3'd3,
        FSM_HARVEST = 3'd4,
        FSM_SEND    = 3'd5,
        FSM_SWAP    = 3'd6;

    reg [2:0] fsm_state;
    reg [ADDR_W:0] dbg_match_count; // debug: count FIFO writes per frame

    assign tracking_busy = (fsm_state != FSM_IDLE);

    // =========================================================================
    // Feature List — 2× TDP BRAM (ping-pong) (prev list)
    // =========================================================================
    // flist_pp=0: Bank 0 = prevList (src), Bank 1 = flist (dst)
    // flist_pp=1: Bank 1 = prevList (src), Bank 0 = flist (dst)
    reg flist_pp;
    assign tracking_bank_sel = ~flist_pp;

    // ── Bank 0 ──────────────────────────────────────────────────────────────
    reg  [ADDR_W-1:0]  b0_addr_a; 
    reg  [FEAT_W-1:0]  b0_din_a; 
    reg  b0_we_a;
    wire [FEAT_W-1:0]  b0_dout_a;

    reg  [ADDR_W-1:0]  b0_addr_b; 
    reg  [FEAT_W-1:0]  b0_din_b; 
    reg  b0_we_b;
    wire [FEAT_W-1:0]  b0_dout_b;

    true_dual_port_bram #(.DATA_WIDTH(FEAT_W), .ADDR_WIDTH(ADDR_W))
    u_flist_bank0 (
        .clk(clk),
        .we_a(b0_we_a), .addr_a(b0_addr_a), .din_a(b0_din_a), .dout_a(b0_dout_a),
        .we_b(b0_we_b), .addr_b(b0_addr_b), .din_b(b0_din_b), .dout_b(b0_dout_b)
    );

    // ── Bank 1 ──────────────────────────────────────────────────────────────
    reg  [ADDR_W-1:0]  b1_addr_a; 
    reg  [FEAT_W-1:0]  b1_din_a; 
    reg  b1_we_a;
    wire [FEAT_W-1:0]  b1_dout_a;

    reg  [ADDR_W-1:0]  b1_addr_b; 
    reg  [FEAT_W-1:0]  b1_din_b; 
    reg  b1_we_b;
    wire [FEAT_W-1:0]  b1_dout_b;

    true_dual_port_bram #(.DATA_WIDTH(FEAT_W), .ADDR_WIDTH(ADDR_W))
    u_flist_bank1 (
        .clk(clk),
        .we_a(b1_we_a), .addr_a(b1_addr_a), .din_a(b1_din_a), .dout_a(b1_dout_a),
        .we_b(b1_we_b), .addr_b(b1_addr_b), .din_b(b1_din_b), .dout_b(b1_dout_b)
    );

    // =========================================================================
    // Sub-module wires
    // =========================================================================
    // init_sorter
    wire               sort_done, sort_busy;

    reg                sort_start;
    wire [ADDR_W-1:0]  sort_src_addr_a;
    wire [FEAT_W-1:0]  sort_src_din_a;
    wire               sort_src_we_a;

    wire [ADDR_W-1:0]  sort_dst_addr_a;
    wire [FEAT_W-1:0]  sort_dst_din_a;
    wire               sort_dst_we_a;
    wire [ADDR_W-1:0]  sort_dst_addr_b;

    // gf_feature_matcher
    wire               matcher_stream_done;
    wire [ADDR_W-1:0]  matcher_sorted_rd_addr;
    wire [FIFO_W-1:0]  matcher_fifo_din;
    wire               matcher_fifo_wr_en;

    // fast_sync_fifo
    wire [FIFO_W-1:0]  fifo_dout;
    wire               fifo_full, fifo_empty;

    // track_validator
    wire               tv_fifo_rd_en;
    wire [GRID_ADDR_W-1:0] tv_grid_addr;
    wire               tv_grid_we, tv_grid_din;
    wire [ADDR_W-1:0]  tv_flist_wr_addr;
    wire [FEAT_W-1:0]  tv_flist_wr_data;
    wire               tv_flist_wr_en;
    wire [ADDR_W:0]    tv_tracked_count;
    wire               tv_idle;

    // feature_harvester
    wire               harv_done, harv_busy;
    reg                harv_start;
    wire [ADDR_W-1:0]  harv_harvest_rd_addr;
    wire [GRID_ADDR_W-1:0] harv_grid_addr;


    wire               harv_grid_we, harv_grid_din;
    wire [ADDR_W-1:0]  harv_flist_wr_addr;
    wire [FEAT_W-1:0]  harv_flist_wr_data;

    wire               harv_flist_wr_en;
    wire [31:0]        harv_id_out;
    wire [ADDR_W:0]    harv_harvested_count;

    // feature_sender
    wire               send_done, send_busy;
    reg                send_start;
    wire [ADDR_W-1:0]  send_bram_rd_addr;

    // Persistent state
    reg [31:0]         id_counter;
    reg [ADDR_W:0]     prev_feat_count;
    reg                frame_ready_latched;
    reg [ADDR_W:0]     latched_tracked_count;
    reg                is_first_frame;

    // =========================================================================
    // Sub-module instantiations
    // =========================================================================
    init_sorter #(
        .IMG_WIDTH(IMG_WIDTH), .IMG_HEIGHT(IMG_HEIGHT), .MAX_FEATURES(MAX_FEATURES),
        .FEAT_W(FEAT_W), .ADDR_W(ADDR_W), .COL_W(COL_W), .ROW_W(ROW_W)
    ) u_init_sorter (
        .clk(clk), 
        .rst_n(rst_n),
        .start(sort_start), 
        .feat_count(prev_feat_count),
        .done(sort_done), 
        .busy(sort_busy),
        .src_addr_a(sort_src_addr_a), 
        .src_din_a(sort_src_din_a),
        .src_we_a(sort_src_we_a),
        .src_dout_a(flist_pp ? b1_dout_a : b0_dout_a),
        .dst_addr_a(sort_dst_addr_a), 
        .dst_din_a(sort_dst_din_a),
        .dst_we_a(sort_dst_we_a),
        .dst_addr_b(sort_dst_addr_b),
        .dst_dout_b(flist_pp ? b0_dout_b : b1_dout_b)
    );

    gf_feature_matcher #(
        .IMG_WIDTH(IMG_WIDTH), .IMG_HEIGHT(IMG_HEIGHT),
        .DX_WIDTH(DX_WIDTH), .DY_WIDTH(DY_WIDTH),
        .FEAT_W(FEAT_W), .COL_W(COL_W), .ROW_W(ROW_W),
        .ADDR_W(ADDR_W), .FIFO_W(FIFO_W)
    ) u_gf_matcher (
        .clk(clk), .rst_n(rst_n),
        .enable(fsm_state == FSM_TRACK),
        .s_axis_tdata(s_axis_gf_tdata), .s_axis_tvalid(s_axis_gf_tvalid),
        .s_axis_tready(s_axis_gf_tready), .s_axis_tlast(s_axis_gf_tlast),
        .sorted_rd_addr(matcher_sorted_rd_addr),
        .sorted_rd_data(flist_pp ? b1_dout_a : b0_dout_a),
        .prev_feat_count(prev_feat_count),
        .fifo_din(matcher_fifo_din), .fifo_wr_en(matcher_fifo_wr_en),
        .fifo_full(fifo_full),
        .stream_done(matcher_stream_done)
    );

    // Flush FIFO at the start of each new frame (during sort) to clear stale data
    wire fifo_flush = (fsm_state == FSM_INIT);

    fast_sync_fifo #(.DATA_WIDTH(FIFO_W), .DEPTH(FIFO_DEPTH))
    u_fifo (
        .clk(clk), .rst_n(rst_n), .flush(fifo_flush),
        .din(matcher_fifo_din), .wr_en(matcher_fifo_wr_en),
        .dout(fifo_dout), .rd_en(tv_fifo_rd_en),
        .full(fifo_full), .empty(fifo_empty)
    );

    // Validator enable: runs as soon as grid map is ready (frame_ready_latched),
    // during both TRACK and DRAIN.  This allows a small 64-entry FIFO.
    wire tv_enable = frame_ready_latched &&
                     (fsm_state == FSM_TRACK || fsm_state == FSM_DRAIN);

    track_validator #(
        .IMG_WIDTH   (IMG_WIDTH),
        .IMG_HEIGHT  (IMG_HEIGHT),
        .MAX_FEATURES(MAX_FEATURES),
        .WINDOW_HALF (WINDOW_HALF),
        .ADDR_W      (ADDR_W),
        .COL_W       (COL_W),
        .ROW_W       (ROW_W),
        .GRID_ADDR_W (GRID_ADDR_W),
        .DX_WIDTH    (DX_WIDTH),
        .DY_WIDTH    (DY_WIDTH)
    ) u_track_validator (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (tv_enable),
        .fifo_empty (fifo_empty),
        .fifo_dout  (fifo_dout),
        .fifo_rd_en (tv_fifo_rd_en),
        .grid_addr  (tv_grid_addr),
        .grid_we    (tv_grid_we),
        .grid_din   (tv_grid_din),
        .grid_dout  (grid_rd_data),
        .flist_wr_addr(tv_flist_wr_addr), .flist_wr_data(tv_flist_wr_data),
        .flist_wr_en(tv_flist_wr_en),
        .stream_done(frame_ready_latched),
        .tracked_count(tv_tracked_count),
        .idle(tv_idle)
    );

    feature_harvester #(
        .IMG_WIDTH(IMG_WIDTH), .MAX_FEATURES(MAX_FEATURES),
        .FEAT_W(FEAT_W), .ADDR_W(ADDR_W), .COL_W(COL_W), .ROW_W(ROW_W),
        .GRID_ADDR_W(GRID_ADDR_W)
    ) u_harvester (
        .clk(clk), .rst_n(rst_n),
        .start(harv_start), .harvest_limit(harvest_count),
        .base_wr_idx(latched_tracked_count), .max_total(12'd2048),
        .done(harv_done), .busy(harv_busy),
        .harvest_rd_addr(harv_harvest_rd_addr), .harvest_rd_data(harvest_rd_data),
        .grid_addr(harv_grid_addr), .grid_we(harv_grid_we), .grid_din(harv_grid_din),
        .grid_dout(grid_rd_data),
        .flist_wr_addr(harv_flist_wr_addr), .flist_wr_data(harv_flist_wr_data),
        .flist_wr_en(harv_flist_wr_en),
        .id_counter_in(id_counter), .id_counter_out(harv_id_out),
        .harvested_count(harv_harvested_count)
    );

    feature_sender #(.FEAT_W(FEAT_W), .ADDR_W(ADDR_W), .MAX_FEATURES(MAX_FEATURES))
    u_sender (
        .clk(clk), .rst_n(rst_n),
        .start(send_start), .feat_count(total_feat_count),
        .done(send_done), .busy(send_busy),
        .bram_rd_addr(send_bram_rd_addr),
        .bram_rd_data(flist_pp ? b0_dout_b : b1_dout_b),
        .m_axis_tdata(m_axis_feat_tdata), .m_axis_tvalid(m_axis_feat_tvalid),
        .m_axis_tready(m_axis_feat_tready), .m_axis_tlast(m_axis_feat_tlast)
    );

    // =========================================================================
    // BRAM port muxing
    // =========================================================================
    always @(*) begin
        b0_addr_a = 0; 
        b0_din_a = 0; 
        b0_we_a = 1'b0;

        b0_addr_b = 0; 
        b0_din_b = 0; 
        b0_we_b = 1'b0;

        b1_addr_a = 0; 
        b1_din_a = 0; 
        b1_we_a = 1'b0;

        b1_addr_b = 0; 
        b1_din_b = 0; 
        b1_we_b = 1'b0;

        case (fsm_state)

        FSM_INIT: begin
            if (flist_pp == 1'b0) begin
                b0_addr_a = sort_src_addr_a; 
                b0_din_a = sort_src_din_a; 
                b0_we_a = sort_src_we_a;

                b1_addr_a = sort_dst_addr_a; 
                b1_din_a = sort_dst_din_a; 
                b1_we_a = sort_dst_we_a;

                b1_addr_b = sort_dst_addr_b;
            end else begin
                b1_addr_a = sort_src_addr_a; 
                b1_din_a = sort_src_din_a; 
                b1_we_a = sort_src_we_a;

                b0_addr_a = sort_dst_addr_a; 
                b0_din_a = sort_dst_din_a; 
                b0_we_a = sort_dst_we_a;

                b0_addr_b = sort_dst_addr_b;
            end
        end

        FSM_TRACK, FSM_DRAIN: begin
            if (flist_pp == 1'b0) begin
                b0_addr_a = matcher_sorted_rd_addr;

                b1_addr_a = tv_flist_wr_addr; 
                b1_din_a = tv_flist_wr_data; 
                b1_we_a = tv_flist_wr_en;
            end else begin
                b1_addr_a = matcher_sorted_rd_addr;

                b0_addr_a = tv_flist_wr_addr; 
                b0_din_a = tv_flist_wr_data; 
                b0_we_a = tv_flist_wr_en;
            end
        end

        FSM_HARVEST: begin
            if (flist_pp == 1'b0) begin
                b1_addr_a = harv_flist_wr_addr; 
                b1_din_a = harv_flist_wr_data; 
                b1_we_a = harv_flist_wr_en;
            end else begin
                b0_addr_a = harv_flist_wr_addr; 
                b0_din_a = harv_flist_wr_data; 
                b0_we_a = harv_flist_wr_en;
            end
        end

        FSM_SEND: begin
            if (flist_pp == 1'b0) begin
                b1_addr_b = send_bram_rd_addr;
            end else begin
                b0_addr_b = send_bram_rd_addr;
            end
        end

        default: ;
        endcase
    end

    // =========================================================================
    // Grid Map + Harvest Queue port muxing
    // =========================================================================
    assign grid_rd_addr = (fsm_state == FSM_HARVEST) ? harv_grid_addr : tv_grid_addr;
    assign grid_wr_addr = (fsm_state == FSM_HARVEST) ? harv_grid_addr : tv_grid_addr;
    assign grid_wr_en   = (fsm_state == FSM_HARVEST) ? harv_grid_we   : tv_grid_we;
    assign grid_wr_data = (fsm_state == FSM_HARVEST) ? harv_grid_din  : tv_grid_din;
    assign harvest_rd_addr = harv_harvest_rd_addr;

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state        <= FSM_IDLE;
            flist_pp         <= 1'b0;
            frame_done_irq   <= 1'b0;
            total_feat_count <= 0;
            id_counter       <= 0;
            prev_feat_count  <= 0;
            sort_start       <= 1'b0;
            harv_start       <= 1'b0;
            send_start       <= 1'b0;
            frame_ready_latched    <= 1'b0;
            latched_tracked_count  <= 0;
            dbg_match_count        <= 0;
            is_first_frame   <= 1'b1;
        end else begin
            sort_start     <= 1'b0;
            harv_start     <= 1'b0;
            send_start     <= 1'b0;
            frame_done_irq <= 1'b0;

            // Latch frame_ready (it's a single-cycle pulse from feature_saving)
            if (frame_ready)
                frame_ready_latched <= 1'b1;

            case (fsm_state)

            FSM_IDLE: begin
                if (is_first_frame && frame_ready_latched) begin
                    // Frame 0: No GF flow, skip tracking and jump straight to harvest
                    harv_start          <= 1'b1;
                    frame_ready_latched <= 1'b0;
                    fsm_state           <= FSM_HARVEST;
                end else if (!is_first_frame && frame_ready_latched) begin
                    // Frame 1+: Start sorting immediately. Gives plenty of time before GF starts.
                    $display("[FTM DEBUG] IDLE->INIT: prev_feat_count=%0d, flist_pp=%0b, frame_ready_latched=%0b",
                             prev_feat_count, flist_pp, frame_ready_latched);
                    sort_start          <= 1'b1;
                    dbg_match_count     <= 0;
                    // DO NOT clear frame_ready_latched here! It's needed for FSM_DRAIN!
                    fsm_state           <= FSM_INIT;
                end
            end

            FSM_INIT: begin
                if (sort_done) begin
                    $display("[FTM DEBUG] INIT->TRACK: sort done, fifo_empty=%0b", fifo_empty);
                    fsm_state <= FSM_TRACK;
                end
            end

            FSM_TRACK: begin
                // Matcher runs; validator drains FIFO concurrently once
                // frame_ready_latched is set (grid map valid).
                if (matcher_fifo_wr_en) 
                  dbg_match_count <= dbg_match_count + 1;
                if (matcher_stream_done) begin
                    $display("[FTM DEBUG] TRACK->DRAIN: matches_pushed=%0d, fifo_empty=%0b, frame_ready_latched=%0b, tv_idle=%0b",
                             dbg_match_count, fifo_empty, frame_ready_latched, tv_idle);
                    fsm_state <= FSM_DRAIN;
                end
            end

            FSM_DRAIN: begin
                // Matcher done. Validator keeps draining FIFO.
                // Wait for grid ready + FIFO empty + validator idle.
                if (frame_ready_latched && fifo_empty && tv_idle) begin
                    latched_tracked_count <= tv_tracked_count;
                    harv_start            <= 1'b1;
                    frame_ready_latched   <= 1'b0;
                    $display("[FTM DEBUG] Entering HARVEST state, tracked=%0d out of %0d matches", tv_tracked_count, dbg_match_count);
                    fsm_state             <= FSM_HARVEST;
                end
            end

            FSM_HARVEST: begin
                if (harv_done) begin
                    total_feat_count <= latched_tracked_count + harv_harvested_count;
                    id_counter       <= harv_id_out;
                    send_start       <= 1'b1;
                    fsm_state        <= FSM_SEND;
                end
            end

            FSM_SEND: begin
                if (send_done)
                    fsm_state <= FSM_SWAP;
            end

            FSM_SWAP: begin
                flist_pp         <= ~flist_pp;
                prev_feat_count  <= total_feat_count;
                frame_done_irq   <= 1'b1;
                is_first_frame   <= 1'b0;
                fsm_state        <= FSM_IDLE;
            end

            default: fsm_state <= FSM_IDLE;
            endcase
        end
    end

endmodule
