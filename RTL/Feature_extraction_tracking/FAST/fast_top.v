// =============================================================================
// Module  : fast_top
// Purpose : Top-level FAST feature detector.
// =============================================================================

module fast_top #(
    parameter IMG_WIDTH   = 1280,
    parameter IMG_HEIGHT  = 720,
    parameter THRESHOLD   = 35,
    parameter N_CONSEC    = 9,
    parameter SCORE_WIDTH = 12
)(
    input  wire        clk,
    input  wire        rst_n,

    // ── AXI4-Stream slave ─────────────────────────────────────────────────
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    input  wire        s_axis_tuser,

    // ── Corner output (to feature_saving submodule) ───────────────────────
    output wire        corner_valid,
    output wire [$clog2(IMG_WIDTH) -1:0] corner_col,
    output wire [$clog2(IMG_HEIGHT)-1:0] corner_row,
    output wire [SCORE_WIDTH-1:0]        corner_score,
    output wire        frame_done
);

    localparam COL_W = $clog2(IMG_WIDTH);
    localparam ROW_W = $clog2(IMG_HEIGHT);
    localparam DATA_WIDTH = 8;

    // =========================================================================
    // Stage 1: AXI Stream
    // =========================================================================
    wire [DATA_WIDTH-1:0]     pix_data;
    wire             pix_valid;
    wire [COL_W-1:0] col_raw;
    wire [ROW_W-1:0] row_raw;

    axi_stream_slave #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_axis (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tuser  (s_axis_tuser),
        .pixel_data    (pix_data),
        .pixel_valid   (pix_valid),
        .col_cnt       (col_raw),
        .row_cnt       (row_raw)
    );

    // =========================================================================
    // Stage 2: Row buffering + window extraction 
    // =========================================================================
    wire [16*DATA_WIDTH-1:0]  circle_bus;
    wire [DATA_WIDTH-1:0]     center_pix;
    wire             win_valid;
    wire [COL_W-1:0] win_col;
    wire [ROW_W-1:0] win_row;

    row_window_extractor #(
        .DATA_WIDTH(DATA_WIDTH),
        .LINE_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_rwe (
        .clk         (clk),
        .rst_n       (rst_n),
        .din         (pix_data),
        .din_valid   (pix_valid),
        .col_cnt_in  (col_raw),
        .row_cnt_in  (row_raw),
        .circle      (circle_bus),
        .center_pixel(center_pix),
        .window_valid(win_valid),
        .out_col     (win_col),
        .out_row     (win_row)
    );

    // =========================================================================
    // Stage 3a: Full circle test (combinational)
    // =========================================================================
    wire is_corner;

    fast_circle_test #(
        .DATA_WIDTH(DATA_WIDTH),
        .THRESHOLD (THRESHOLD),
        .N_CONSEC  (N_CONSEC)       
    ) u_circle (
        .Ip       (center_pix),
        .circle   (circle_bus),
        .is_corner(is_corner)
    );

    // =========================================================================
    // Stage 3b: Score calculation (combinational)
    // =========================================================================
    wire [SCORE_WIDTH-1:0] raw_score;

    fast_score_calc #(
        .DATA_WIDTH (DATA_WIDTH),
        .THRESHOLD  (THRESHOLD),
        .SCORE_WIDTH(SCORE_WIDTH)
    ) u_score (
        .Ip    (center_pix),
        .circle(circle_bus),
        .score (raw_score)
    );

    // Non-corners → score 0 (NMS uses 0 as "no candidate")
    wire [SCORE_WIDTH-1:0] score_gated =
        is_corner ? raw_score : {SCORE_WIDTH{1'b0}};

    // =========================================================================
    // Stage 4: Pipeline register 
    // =========================================================================
    reg [SCORE_WIDTH-1:0] score_r;
    reg [COL_W-1:0]       col_r;
    reg [ROW_W-1:0]       row_r;
    reg                   valid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            score_r <= {SCORE_WIDTH{1'b0}};
            col_r   <= {COL_W{1'b0}};
            row_r   <= {ROW_W{1'b0}};
            valid_r <= 1'b0;
        end else begin
            score_r <= score_gated;
            col_r   <= win_col;
            row_r   <= win_row;
            valid_r <= win_valid;
        end
    end

    // when close NMS, oepn this
    // assign corner_valid = valid_r && (score_r > 0); 
    // assign corner_score = score_r;
    // assign corner_col   = col_r;
    // assign corner_row   = row_r;
    // =========================================================================
    // Stage 5: NMS 3×3
    // =========================================================================
    nms_3x3 #(
        .SCORE_WIDTH(SCORE_WIDTH),
        .LINE_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT)
    ) u_nms (
        .clk         (clk),
        .rst_n       (rst_n),
        .score_in    (score_r),
        .score_valid (valid_r),
        .col_in      (col_r),
        .row_in      (row_r),
        .corner_valid(corner_valid),
        .corner_score(corner_score),
        .corner_col  (corner_col),
        .corner_row  (corner_row),
        .frame_done  (frame_done)
    );

endmodule