module nms_3x3 #(
    parameter SCORE_WIDTH = 12,
    parameter LINE_WIDTH  = 1280,
    parameter IMG_HEIGHT  = 720
)(
    input  wire        clk,
    input  wire        rst_n,

    // ── Score stream from fast_top pipeline register ───────────────────────
    input  wire [SCORE_WIDTH-1:0] score_in,      
    input  wire                   score_valid,   
    input  wire [$clog2(LINE_WIDTH) -1:0] col_in,
    input  wire [$clog2(IMG_HEIGHT)-1:0] row_in,

    // ── Final corner output ────────────────────────────────────────────────
    output reg        corner_valid,
    output reg [SCORE_WIDTH-1:0]        corner_score,
    output reg [$clog2(LINE_WIDTH) -1:0] corner_col,
    output reg [$clog2(IMG_HEIGHT)-1:0] corner_row,
    output reg        frame_done
);
    localparam COL_W = $clog2(LINE_WIDTH);
    localparam ROW_W = $clog2(IMG_HEIGHT);
    localparam SW    = SCORE_WIDTH;

    // =========================================================================
    // Line buffer output wires 
    // =========================================================================
    wire [SW-1:0] lb_out_prev1;
    wire          lb_vld_prev1;
    wire [SW-1:0] lb_out_prev2;
    wire          lb_vld_prev2;

    reg [COL_W-1:0] col_prev;
    reg [ROW_W-1:0] row_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_prev <= {COL_W{1'b1}};
            row_prev <= {ROW_W{1'b1}};
        end else begin
            col_prev <= col_in;
            row_prev <= row_in;
        end
    end

    wire new_pixel = (col_in != col_prev) || (row_in != row_prev);

    line_buffer #(.DATA_WIDTH(SW), .LINE_WIDTH(LINE_WIDTH)) u_lb_prev1 (
        .clk(clk), .rst_n(rst_n), .din(score_in), 
        .din_valid(new_pixel), .dout(lb_out_prev1), .dout_valid(lb_vld_prev1)
    );

    line_buffer #(.DATA_WIDTH(SW), .LINE_WIDTH(LINE_WIDTH)) u_lb_prev2 (
        .clk(clk), .rst_n(rst_n), .din(lb_out_prev1), 
        .din_valid(lb_vld_prev1), .dout(lb_out_prev2), .dout_valid(lb_vld_prev2)
    );

    // =========================================================================
    // Vertical Alignment & Coordinate Pipeline (2 clock delay)
    // =========================================================================
    reg [SW-1:0] score_d1, score_d2;
    reg [SW-1:0] lb1_d1;
    reg [COL_W-1:0] col_d1, col_d2;
    reg [ROW_W-1:0] row_d1, row_d2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            score_d1 <= 0; score_d2 <= 0;
            lb1_d1 <= 0;
            col_d1 <= 0; col_d2 <= 0;
            row_d1 <= 0; row_d2 <= 0;
        end 
        else if (new_pixel) begin
            score_d1 <= score_in;     score_d2 <= score_d1;
            lb1_d1   <= lb_out_prev1;
            
            col_d1   <= col_in;       col_d2 <= col_d1;
            row_d1   <= row_in;       row_d2 <= row_d1;
        end
    end

    // =========================================================================
    // 3x3 horizontal shift registers
    // =========================================================================
    reg [SW-1:0] sr_upper  [1:2];
    reg [SW-1:0] sr_middle [1:2];
    reg [SW-1:0] sr_lower  [1:2];

    wire [SW-1:0] right_upper  = lb_out_prev2; 
    wire [SW-1:0] right_middle = lb1_d1;       
    wire [SW-1:0] right_lower  = score_d2;     

    wire [SW-1:0] left_upper   = sr_upper[1];
    wire [SW-1:0] center_upper = sr_upper[2];
    wire [SW-1:0] left_middle  = sr_middle[1];
    wire [SW-1:0] center_middle= sr_middle[2];
    wire [SW-1:0] left_lower   = sr_lower[1];
    wire [SW-1:0] center_lower = sr_lower[2];

    wire is_local_max = (center_middle != 0) &&
                        (center_middle > left_upper)   && (center_middle > center_upper)   && (center_middle > right_upper)   &&
                        (center_middle > left_middle)  &&                                     (center_middle > right_middle)  &&
                        (center_middle > left_lower)   && (center_middle > center_lower)   && (center_middle > right_lower);

    // =========================================================================
    // Output registers 
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sr_upper[1] <= 0;  sr_upper[2] <= 0;
            sr_middle[1] <= 0; sr_middle[2] <= 0;
            sr_lower[1] <= 0;  sr_lower[2] <= 0;
        end else if (new_pixel) begin
            sr_upper[1]  <= sr_upper[2];
            sr_upper[2]  <= right_upper;

            sr_middle[1] <= sr_middle[2];
            sr_middle[2] <= right_middle;

            sr_lower[1]  <= sr_lower[2];
            sr_lower[2]  <= right_lower;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            corner_valid <= 1'b0;
            corner_score <= {SW{1'b0}};
            corner_col   <= {COL_W{1'b0}};
            corner_row   <= {ROW_W{1'b0}};
            frame_done   <= 1'b0;
        end else if (new_pixel) begin
            corner_valid <= is_local_max && lb_vld_prev2;
            corner_score <= center_middle;
            
            corner_col   <= (col_d2 >= 1) ? col_d2 - 1'b1 : {COL_W{1'b0}};
            corner_row   <= (row_d2 >= 1) ? row_d2 - 1'b1 : {ROW_W{1'b0}};
      
            frame_done   <= (col_in == LINE_WIDTH - 1) && (row_in == IMG_HEIGHT - 1);
        end else begin
            frame_done   <= 1'b0; 
        end
    end

endmodule