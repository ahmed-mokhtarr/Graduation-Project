// ============================================================================
// Line Buffer Bank with Drain Support
// ============================================================================
// After normal H*W input, supports 3 drain rows feeding reflected pixel data
// back through the pipeline for bottom-border handling.
// Memories use synchronous reads with pre-read addressing for BRAM inference.
//
// Interface:
//   Input:  AXI-Stream (s_axis_*)
//   Output: Simple wires (out_data, out_valid, out_last) — no backpressure
// ============================================================================

module line_buffer_bank #(
    parameter IMG_WIDTH = 1280
)(
    input  wire        clk,
    input  wire        rst_n,
    // AXI-Stream slave (input pixels)
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    // Simple wire output to vertical convolution
    output wire [55:0] out_data,
    output wire        out_valid,
    output wire        out_last,

    // Drain interface
    input  wire        drain_en,
    input  wire [1:0]  drain_sel,    // 0=lb_1, 1=lb_2, 2=lb_3
    output wire [7:0]  drain_pixel,  // reflected pixel for drain

    // Stall from downstream (horizontal conv computing)
    input  wire        stall
);

    reg [$clog2(IMG_WIDTH)-1:0] col_cnt;

    (* ram_style = "block" *) reg [7:0] lb_0 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] lb_1 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] lb_2 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] lb_3 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] lb_4 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] lb_5 [0:IMG_WIDTH-1];

    // Registered read outputs for BRAM inference
    reg [7:0] rd_0, rd_1, rd_2, rd_3, rd_4, rd_5;

    // Drain pixel: uses registered reads aligned with current col_cnt
    // Accounts for the +1 row shift that happens every drain row
    assign drain_pixel = (drain_sel == 2'd0) ? rd_1 :
                         (drain_sel == 2'd1) ? rd_3 :
                                               rd_5;

    // Select actual input: external or drain
    wire [7:0] pixel_in = drain_en ? drain_pixel : s_axis_tdata;
    wire       valid_in  = drain_en ? 1'b1 : s_axis_tvalid;
    wire       last_in   = (col_cnt == IMG_WIDTH - 1);

    // Handshake gated by stall from downstream
    wire handshake = valid_in && !stall;

    always @(posedge clk) begin
        if (!rst_n)
            col_cnt <= 0;
        else if (handshake) begin
            if (col_cnt == IMG_WIDTH - 1)
                col_cnt <= 0;
            else
                col_cnt <= col_cnt + 1;
        end
    end

    // Pre-read address: when handshake fires, read the NEXT column so
    // registered data is ready by the time col_cnt advances.
    // When idle, keep reading current column to stay primed.
    wire [$clog2(IMG_WIDTH)-1:0] next_col = (col_cnt == IMG_WIDTH - 1) ?
                                             {$clog2(IMG_WIDTH){1'b0}} : (col_cnt + 1'b1);
    wire [$clog2(IMG_WIDTH)-1:0] read_addr = handshake ? next_col : col_cnt;

    // Synchronous reads (BRAM-inferable, SDP read port)
    always @(posedge clk) begin
        rd_0 <= lb_0[read_addr];
        rd_1 <= lb_1[read_addr];
        rd_2 <= lb_2[read_addr];
        rd_3 <= lb_3[read_addr];
        rd_4 <= lb_4[read_addr];
        rd_5 <= lb_5[read_addr];
    end

    // Synchronous writes (BRAM-inferable, SDP write port)
    always @(posedge clk) begin
        if (handshake) begin
            lb_0[col_cnt] <= pixel_in;
            lb_1[col_cnt] <= rd_0;
            lb_2[col_cnt] <= rd_1;
            lb_3[col_cnt] <= rd_2;
            lb_4[col_cnt] <= rd_3;
            lb_5[col_cnt] <= rd_4;
        end
    end

    wire [7:0] tap0 = pixel_in;
    wire [7:0] tap1 = rd_0;
    wire [7:0] tap2 = rd_1;
    wire [7:0] tap3 = rd_2;
    wire [7:0] tap4 = rd_3;
    wire [7:0] tap5 = rd_4;
    wire [7:0] tap6 = rd_5;

    assign out_data  = {tap6, tap5, tap4, tap3, tap2, tap1, tap0};
    assign out_valid = valid_in && !stall;
    assign s_axis_tready = drain_en ? 1'b0 : !stall;
    assign out_last  = last_in;

endmodule
