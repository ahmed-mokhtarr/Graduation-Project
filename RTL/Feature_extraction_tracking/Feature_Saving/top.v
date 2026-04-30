module top #(
    parameter IMG_WIDTH    = 1280,
    parameter IMG_HEIGHT   = 720,
    parameter THRESHOLD    = 35,
    parameter N_CONSEC     = 9,
    parameter SCORE_WIDTH  = 12,
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 32
)(
    input  wire        clk,
    input  wire        rst_n,

    // ── AXI4-Stream slave (Image Input) ────────────────────────────────────
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    input  wire        s_axis_tuser,

    // ── Feature Tracking Read Interface ────────────────────────────────────
    input  wire [ADDR_WIDTH-1:0] read_addr,
    input  wire        read_en,
    output wire [DATA_WIDTH-1:0] read_data,        // {16'd_row, 16'd_col}
    output wire [ADDR_WIDTH:0] prev_feature_count,
    
    // Optional: expose corner outputs directly if needed
    output wire        corner_valid,
    output wire [$clog2(IMG_WIDTH) -1:0] corner_col,
    output wire [$clog2(IMG_HEIGHT)-1:0] corner_row,
    output wire [SCORE_WIDTH-1:0]        corner_score,
    output wire        frame_done
);

    // =========================================================================
    // Feature Extraction (FAST)
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
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tuser  (s_axis_tuser),
        
        .corner_valid  (corner_valid),
        .corner_col    (corner_col),
        .corner_row    (corner_row),
        .corner_score  (corner_score),
        .frame_done    (frame_done)
    );

    // =========================================================================
    // Feature Saving
    // =========================================================================
    
    feature_saving #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .IMG_WIDTH    (IMG_WIDTH),
        .IMG_HEIGHT   (IMG_HEIGHT)
    ) u_feature_saving (
        .clk                (clk),
        .rst_n              (rst_n),
        .corner_valid       (corner_valid),
        .corner_col         (corner_col),
        .corner_row         (corner_row),
        .frame_done         (frame_done),
        .read_addr          (read_addr),
        .read_en            (read_en),
        .read_data          (read_data),
        .prev_feature_count (prev_feature_count)
    );

endmodule