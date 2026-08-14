// =============================================================================
// Module  : fast_system_top
// Purpose : Top module for the complete FAST feature tracking system.
//           Instantiates the FAST detector (fast_top), feature_saving,
//           and feature_tracking_merging modules.
// =============================================================================

module fast_system_top #(
    parameter IMG_WIDTH    = 1280,
    parameter IMG_HEIGHT   = 720,
    parameter THRESHOLD    = 35,
    parameter N_CONSEC     = 9,
    parameter SCORE_WIDTH  = 12,
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

    // ── AXI-Stream from CLAHE ────────────────────────────────
    input  wire [7:0]                    s_axis_pixels_tdata,
    input  wire                          s_axis_pixels_tvalid,
    output wire                          s_axis_pixels_tready,
    input  wire                          s_axis_pixels_tlast,
    input  wire                          s_axis_pixels_tuser,

    // ── AXI-Stream from GF Module (Optical Flow) ────────────────────────────
    input  wire [DX_WIDTH+DY_WIDTH-1:0]  s_axis_gf_tdata,
    input  wire                          s_axis_gf_tvalid,
    output wire                          s_axis_gf_tready,
    input  wire                          s_axis_gf_tlast,

    // ── AXI-Stream Master (to DMA → DDR) for output features ────────────────
    output wire [FEAT_W-1:0]             m_axis_feat_tdata,
    output wire                          m_axis_feat_tvalid,
    input  wire                          m_axis_feat_tready,
    output wire                          m_axis_feat_tlast,

    // ── Status / IRQ ────────────────────────────────────────────────────────
    output wire                          frame_done_irq,
    output wire [ADDR_W:0]               total_feat_count,
    output wire                          fs_overflow
);

    // =========================================================================
    // Internal Connections
    // =========================================================================
    // Detector to Saving
    wire                           corner_valid;
    wire [$clog2(IMG_WIDTH)-1:0]   corner_col;
    wire [$clog2(IMG_HEIGHT)-1:0]  corner_row;
    wire [SCORE_WIDTH-1:0]         corner_score;
    wire                           fast_frame_done;
    wire                           tracking_bank_sel;

    // Saving to FTM
    wire [GRID_ADDR_W-1:0]         grid_rd_addr;
    wire                           grid_rd_data;
    wire [GRID_ADDR_W-1:0]         grid_wr_addr;
    wire                           grid_wr_data;
    wire                           grid_wr_en;
    
    wire [ADDR_W-1:0]              harvest_rd_addr;
    wire [COL_W+ROW_W-1:0]         harvest_rd_data;
    wire [ADDR_W:0]                harvest_count;
    wire                           fs_frame_ready;
    wire                           tracking_busy;

    // =========================================================================
    // FAST Detector (Extraction Module)
    // =========================================================================
    fast_top #(
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .THRESHOLD  (THRESHOLD),
        .N_CONSEC   (N_CONSEC),
        .SCORE_WIDTH(SCORE_WIDTH)
    ) u_fast_top (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axis_tdata  (s_axis_pixels_tdata),
        .s_axis_tvalid (s_axis_pixels_tvalid),
        .s_axis_tready (s_axis_pixels_tready),
        .s_axis_tlast  (s_axis_pixels_tlast),
        .s_axis_tuser  (s_axis_pixels_tuser),
        .corner_valid  (corner_valid),
        .corner_col    (corner_col),
        .corner_row    (corner_row),
        .corner_score  (corner_score),
        .frame_done    (fast_frame_done)
    );

    // =========================================================================
    // Feature Saving
    // =========================================================================
    feature_saving #(
        .IMG_WIDTH   (IMG_WIDTH),
        .IMG_HEIGHT  (IMG_HEIGHT),
        .MAX_FEATURES(MAX_FEATURES),
        .ADDR_WIDTH  (ADDR_W),
        .COL_W       (COL_W),
        .ROW_W       (ROW_W),
        .GRID_ADDR_W (GRID_ADDR_W)
    ) u_feature_saving (
        .clk            (clk),
        .rst_n          (rst_n),
        .corner_valid   (corner_valid),
        .corner_col     (corner_col),
        .corner_row     (corner_row),
        .frame_done     (fast_frame_done),
        .tracking_busy  (tracking_busy),
        .grid_rd_addr   (grid_rd_addr),
        .grid_rd_data   (grid_rd_data),
        .grid_wr_addr   (grid_wr_addr),
        .grid_wr_data   (grid_wr_data),
        .grid_wr_en     (grid_wr_en),
        .harvest_rd_addr(harvest_rd_addr),
        .harvest_rd_data(harvest_rd_data),
        .harvest_count  (harvest_count),
        .frame_ready    (fs_frame_ready),
        .track_bank_sel (tracking_bank_sel),
        .overflow       (fs_overflow)
    );

    // =========================================================================
    // Feature Tracking and Merging
    // =========================================================================
    feature_tracking_merging #(
        .IMG_WIDTH   (IMG_WIDTH),
        .IMG_HEIGHT  (IMG_HEIGHT),
        .MAX_FEATURES(MAX_FEATURES),
        .WINDOW_HALF (WINDOW_HALF),
        .DX_WIDTH    (DX_WIDTH),
        .DY_WIDTH    (DY_WIDTH),
        .FEAT_W      (FEAT_W),
        .ADDR_W      (ADDR_W),
        .COL_W       (COL_W),
        .ROW_W       (ROW_W),
        .GRID_ADDR_W (GRID_ADDR_W),
        .FIFO_W      (FIFO_W),
        .FIFO_DEPTH  (FIFO_DEPTH)
    ) u_tracking (
        .clk              (clk),
        .rst_n            (rst_n),
        .s_axis_gf_tdata  (s_axis_gf_tdata),
        .s_axis_gf_tvalid (s_axis_gf_tvalid),
        .s_axis_gf_tready (s_axis_gf_tready),
        .s_axis_gf_tlast  (s_axis_gf_tlast),
        .grid_rd_addr     (grid_rd_addr),
        .grid_rd_data     (grid_rd_data),
        .grid_wr_addr     (grid_wr_addr),
        .grid_wr_data     (grid_wr_data),
        .grid_wr_en       (grid_wr_en),
        .harvest_rd_addr  (harvest_rd_addr),
        .harvest_rd_data  (harvest_rd_data),
        .harvest_count    (harvest_count),
        .frame_ready      (fs_frame_ready),
        .m_axis_feat_tdata (m_axis_feat_tdata),
        .m_axis_feat_tvalid(m_axis_feat_tvalid),
        .m_axis_feat_tready(m_axis_feat_tready),
        .m_axis_feat_tlast (m_axis_feat_tlast),
        .tracking_bank_sel (tracking_bank_sel),
        .tracking_busy    (tracking_busy),
        .frame_done_irq   (frame_done_irq),
        .total_feat_count (total_feat_count)
    );

endmodule
