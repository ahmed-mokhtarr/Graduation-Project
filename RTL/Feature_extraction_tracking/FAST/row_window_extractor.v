module row_window_extractor #(
    parameter DATA_WIDTH = 8,
    parameter LINE_WIDTH = 1280,
    parameter IMG_HEIGHT = 720
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire [DATA_WIDTH-1:0]         din,
    input  wire                          din_valid,
    input  wire [$clog2(LINE_WIDTH)-1:0] col_cnt_in,
    input  wire [$clog2(IMG_HEIGHT)-1:0] row_cnt_in,

    output reg  [16*DATA_WIDTH-1:0]      circle,
    output reg  [DATA_WIDTH-1:0]         center_pixel,
    output reg                           window_valid,
    output reg  [$clog2(LINE_WIDTH)-1:0] out_col,
    output reg  [$clog2(IMG_HEIGHT)-1:0] out_row
);
    localparam COL_W = $clog2(LINE_WIDTH);
    localparam ROW_W = $clog2(IMG_HEIGHT);
    localparam D     = DATA_WIDTH;

    // --- Line Buffers ---
    wire [D-1:0] lb_out_0, lb_out_1, lb_out_2, lb_out_3, lb_out_4, lb_out_5;
    wire         lb_vld_0, lb_vld_1, lb_vld_2, lb_vld_3, lb_vld_4, lb_vld_5;

    line_buffer #(.DATA_WIDTH(D), .LINE_WIDTH(LINE_WIDTH)) u_lb0 (.clk(clk), .rst_n(rst_n), .din(din),      .din_valid(din_valid), .dout(lb_out_0),.dout_valid(lb_vld_0));
    line_buffer #(.DATA_WIDTH(D), .LINE_WIDTH(LINE_WIDTH)) u_lb1 (.clk(clk), .rst_n(rst_n), .din(lb_out_0), .din_valid(lb_vld_0),  .dout(lb_out_1),.dout_valid(lb_vld_1));
    line_buffer #(.DATA_WIDTH(D), .LINE_WIDTH(LINE_WIDTH)) u_lb2 (.clk(clk), .rst_n(rst_n), .din(lb_out_1), .din_valid(lb_vld_1),  .dout(lb_out_2),.dout_valid(lb_vld_2));
    line_buffer #(.DATA_WIDTH(D), .LINE_WIDTH(LINE_WIDTH)) u_lb3 (.clk(clk), .rst_n(rst_n), .din(lb_out_2), .din_valid(lb_vld_2),  .dout(lb_out_3),.dout_valid(lb_vld_3));
    line_buffer #(.DATA_WIDTH(D), .LINE_WIDTH(LINE_WIDTH)) u_lb4 (.clk(clk), .rst_n(rst_n), .din(lb_out_3), .din_valid(lb_vld_3),  .dout(lb_out_4),.dout_valid(lb_vld_4));
    line_buffer #(.DATA_WIDTH(D), .LINE_WIDTH(LINE_WIDTH)) u_lb5 (.clk(clk), .rst_n(rst_n), .din(lb_out_4), .din_valid(lb_vld_4),  .dout(lb_out_5),.dout_valid(lb_vld_5));

    wire tap_valid = lb_vld_5;

    // =========================================================================
    // Vertical Alignment Pipeline
    // =========================================================================
    reg [D-1:0] t6_d1, t6_d2, t6_d3, t6_d4, t6_d5, t6_d6;
    reg [D-1:0] t5_d1, t5_d2, t5_d3, t5_d4, t5_d5;
    reg [D-1:0] t4_d1, t4_d2, t4_d3, t4_d4;
    reg [D-1:0] t3_d1, t3_d2, t3_d3;
    reg [D-1:0] t2_d1, t2_d2;
    reg [D-1:0] t1_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t6_d1<=0; t6_d2<=0; t6_d3<=0; t6_d4<=0; t6_d5<=0; t6_d6<=0;
            t5_d1<=0; t5_d2<=0; t5_d3<=0; t5_d4<=0; t5_d5<=0;
            t4_d1<=0; t4_d2<=0; t4_d3<=0; t4_d4<=0;
            t3_d1<=0; t3_d2<=0; t3_d3<=0;
            t2_d1<=0; t2_d2<=0;
            t1_d1<=0;
        end else if (din_valid) begin 
            t6_d1 <= din; t6_d2 <= t6_d1; t6_d3 <= t6_d2; t6_d4 <= t6_d3; t6_d5 <= t6_d4; t6_d6 <= t6_d5;
            t5_d1 <= lb_out_0; t5_d2 <= t5_d1; t5_d3 <= t5_d2; t5_d4 <= t5_d3; t5_d5 <= t5_d4;
            t4_d1 <= lb_out_1; t4_d2 <= t4_d1; t4_d3 <= t4_d2; t4_d4 <= t4_d3;
            t3_d1 <= lb_out_2; t3_d2 <= t3_d1; t3_d3 <= t3_d2;
            t2_d1 <= lb_out_3; t2_d2 <= t2_d1;
            t1_d1 <= lb_out_4;
        end
    end

    wire [D-1:0] tap_aligned [0:6];
    assign tap_aligned[6] = t6_d6;
    assign tap_aligned[5] = t5_d5;
    assign tap_aligned[4] = t4_d4;
    assign tap_aligned[3] = t3_d3;
    assign tap_aligned[2] = t2_d2;
    assign tap_aligned[1] = t1_d1;
    assign tap_aligned[0] = lb_out_5; 

    // --- Shift Registers ---
    reg [D-1:0] sr [0:6][0:6];
    integer rr, cc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (rr = 0; rr < 7; rr = rr + 1)
                for (cc = 0; cc < 7; cc = cc + 1)
                    sr[rr][cc] <= {D{1'b0}};
        end else if (din_valid) begin
            for (rr = 0; rr < 7; rr = rr + 1) begin
                sr[rr][0] <= sr[rr][1];
                sr[rr][1] <= sr[rr][2];
                sr[rr][2] <= sr[rr][3];
                sr[rr][3] <= sr[rr][4];
                sr[rr][4] <= sr[rr][5];
                sr[rr][5] <= sr[rr][6];
                sr[rr][6] <= tap_aligned[rr]; 
            end
        end
    end

    // =========================================================================
    // 11-Stage Coordinate Pipeline
    // =========================================================================
    reg [COL_W-1:0] col_d [1:11];
    reg [ROW_W-1:0] row_d [1:11];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=1; i<=11; i=i+1) begin
                col_d[i] <= 0;
                row_d[i] <= 0;
            end
        end else if (din_valid) begin
            col_d[1] <= col_cnt_in;
            row_d[1] <= row_cnt_in;
            for (i=2; i<=11; i=i+1) begin
                col_d[i] <= col_d[i-1];
                row_d[i] <= row_d[i-1];
            end
        end
    end

    wire [COL_W-1:0] center_col_val = col_d[11]; 
    wire [ROW_W-1:0] center_row_val = (row_d[11] >= 3) ? row_d[11] - 3 : 0;

    wire in_col_range = (center_col_val >= 3) && (center_col_val < LINE_WIDTH - 3);
    wire in_row_range = (center_row_val >= 3) && (center_row_val < IMG_HEIGHT  - 3);

    // --- Output Alignment ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_valid  <= 1'b0;
            center_pixel  <= {D{1'b0}};
            out_col       <= {COL_W{1'b0}};
            out_row       <= {ROW_W{1'b0}};
            circle        <= {16*D{1'b0}};
        end else if (din_valid) begin
            window_valid <= tap_valid & in_col_range & in_row_range;
            
            out_col      <= center_col_val;
            out_row      <= center_row_val;
            center_pixel <= sr[3][3];   

            circle[ 0*D +: D] <= sr[0][3];
            circle[ 1*D +: D] <= sr[0][4];
            circle[ 2*D +: D] <= sr[1][5];
            circle[ 3*D +: D] <= sr[2][6];
            circle[ 4*D +: D] <= sr[3][6];
            circle[ 5*D +: D] <= sr[4][6];
            circle[ 6*D +: D] <= sr[5][5];
            circle[ 7*D +: D] <= sr[6][4];
            circle[ 8*D +: D] <= sr[6][3];
            circle[ 9*D +: D] <= sr[6][2];
            circle[10*D +: D] <= sr[5][1];
            circle[11*D +: D] <= sr[4][0];
            circle[12*D +: D] <= sr[3][0];
            circle[13*D +: D] <= sr[2][0];
            circle[14*D +: D] <= sr[1][1];
            circle[15*D +: D] <= sr[0][2];
        end
    end
endmodule