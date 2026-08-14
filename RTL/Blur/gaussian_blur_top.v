// ============================================================================
// Top Module: Centered Gaussian Blur with BORDER_REFLECT_101
// ============================================================================
// Outputs H*W pixels in natural order (0,0) to (H-1,W-1), centered.
// After H*W input pixels, feeds 3 reflected drain rows for bottom border.
//
// Multi-frame support: pulse frame_start high before each new frame to
// reset internal state (input_cnt, drain FSM, and sub-module state).
//
// AXI-Stream is used ONLY at the top-level I/O:
//   - Input:  s_axis_* (pixels entering the line buffer bank)
//   - Output: m_axis_* (blurred pixels leaving the horizontal convolution)
// Internal sub-blocks are connected with simple wires (no AXI handshaking).
// ============================================================================

module gaussian_blur_top #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,   // pulse to reset for new frame
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast
);

    localparam TOTAL_PIX = IMG_WIDTH * IMG_HEIGHT;

    // =====================================================================
    //  Per-frame internal reset
    //  Pulse sub_rst_n low for 4 cycles on frame_start.
    //  Sub-modules use sub_rst_n as their rst_n.
    // =====================================================================
    reg [2:0] frame_rst_cnt;
    reg       frame_rst_active;
    wire      sub_rst_n = rst_n & ~frame_rst_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_rst_cnt    <= 3'd0;
            frame_rst_active <= 1'b0;
        end else if (frame_start) begin
            frame_rst_cnt    <= 3'd4;
            frame_rst_active <= 1'b1;
        end else if (frame_rst_cnt != 3'd0) begin
            frame_rst_cnt <= frame_rst_cnt - 3'd1;
            if (frame_rst_cnt == 3'd1)
                frame_rst_active <= 1'b0;
        end
    end

    // ── Drain state machine for bottom border ──
    reg [19:0] input_cnt;
    reg        input_done;
    reg        drain_en;
    reg [1:0]  drain_row;
    reg        drain_finished;

    always @(posedge clk) begin
        if (!sub_rst_n) begin
            input_cnt  <= 0;
            input_done <= 0;
        end else if (s_axis_tvalid && s_axis_tready && !input_done) begin
            if (input_cnt == TOTAL_PIX - 1)
                input_done <= 1;
            else
                input_cnt <= input_cnt + 1;
        end
    end

    wire [55:0] lb_data;
    wire        lb_valid;
    wire        lb_last;
    wire [20:0] vc_data;
    wire        vc_valid;
    wire        vc_last;
    wire [7:0]  drain_pixel;
    wire        hc_busy;  // stall signal from horizontal conv

    // Drain: feed 3 reflected rows after input completes
    // drain_sel: 0→lb_1(row H-2), 1→lb_2(row H-3), 2→lb_3(row H-4)
    always @(posedge clk) begin
        if (!sub_rst_n) begin
            drain_en       <= 0;
            drain_row      <= 0;
            drain_finished <= 0;
        end else if (input_done && !drain_en && !drain_finished) begin
            drain_en  <= 1;
            drain_row <= 0;
        end else if (drain_en && lb_valid && lb_last) begin
            if (drain_row == 2'd2) begin
                drain_en       <= 0;
                drain_finished <= 1;
            end else
                drain_row <= drain_row + 1;
        end
    end

    // Block 1: Line Buffer Bank
    //   Input:  AXI-Stream (s_axis_*)
    //   Output: Simple wires (out_data, out_valid, out_last)
    line_buffer_bank #(.IMG_WIDTH(IMG_WIDTH)) u_lb (
        .clk(clk), .rst_n(sub_rst_n),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
        .out_data(lb_data), .out_valid(lb_valid),
        .out_last(lb_last),
        .drain_en(drain_en), .drain_sel(drain_row), .drain_pixel(drain_pixel),
        .stall(hc_busy)
    );

    // Block 2: Vertical 7x1 Convolution
    //   Input:  Simple wires from line buffer bank
    //   Output: Simple wires to horizontal convolution
    vertical_conv_7x1 u_vc (
        .clk(clk), .rst_n(sub_rst_n),
        .in_data(lb_data), .in_valid(lb_valid),
        .in_last(lb_last),
        .out_data(vc_data), .out_valid(vc_valid),
        .out_last(vc_last)
    );

    // Block 3: Horizontal 1x7 Convolution (double-buffered row buffer)
    //   Input:  Simple wires from vertical convolution
    //   Output: AXI-Stream (m_axis_*)
    horizontal_conv_1x7 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_hc (
        .clk(clk), .rst_n(sub_rst_n),
        .in_data(vc_data), .in_valid(vc_valid),
        .in_last(vc_last),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
        .busy(hc_busy)
    );

endmodule
