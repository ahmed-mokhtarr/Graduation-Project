// ============================================================================
// Horizontal 1x7 Convolution - Double-Buffered, Full Throughput
// ============================================================================
// Uses two row buffers: while storing row N+1 into one buffer, computes
// and outputs row N from the other. This achieves 1 pixel/clock throughput
// (no stalling of upstream).
//
// FSM:
//   S_FIRST_ROW    → Store first row (no output)
//   S_PIPE         → Overlap: store row N+1 + compute row N (1 px/clk)
//   S_LAST_COMPUTE → Compute final row (no more input)
//   S_DONE         → Idle until reset
//
// Interface:
//   Input:  Simple wires (in_data, in_valid, in_last) — from vertical conv
//   Output: AXI-Stream (m_axis_*) — final output of blur pipeline
// ============================================================================

module horizontal_conv_1x7 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
)(
    input  wire        clk,
    input  wire        rst_n,
    // Simple wire input from vertical convolution
    input  wire [20:0] in_data,
    input  wire        in_valid,
    input  wire        in_last,
    // AXI-Stream master (output pixels)
    output reg  [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast,
    // Backpressure: always 0 (double-buffered, never stalls upstream)
    output wire        busy
);

    localparam [9:0] C0 = 10'd528;
    localparam [9:0] C1 = 10'd584;
    localparam [9:0] C2 = 10'd620;
    localparam [9:0] C3 = 10'd632;
    localparam W = IMG_WIDTH;

    // Double row buffers
    (* ram_style = "distributed" *) reg [20:0] rbuf_0 [0:W-1];
    (* ram_style = "distributed" *) reg [20:0] rbuf_1 [0:W-1];

    // FSM states
    localparam [1:0] S_FIRST_ROW    = 2'd0;
    localparam [1:0] S_PIPE         = 2'd1;
    localparam [1:0] S_LAST_COMPUTE = 2'd2;
    localparam [1:0] S_DONE         = 2'd3;
    reg [1:0] state;

    // sel: 0 = write buf_0, read buf_1  |  1 = write buf_1, read buf_0
    reg sel;
    reg [$clog2(W)-1:0] col;
    reg [$clog2(IMG_HEIGHT)-1:0] row_cnt;  // counts completed rows stored

    // Never stall upstream — double-buffered
    assign busy = 1'b0;

    // Reflect index for BORDER_REFLECT_101
    function [$clog2(W)-1:0] reflect;
        input signed [12:0] idx;
        begin
            if (idx < 0)
                reflect = -idx;
            else if (idx >= W)
                reflect = 2 * (W - 1) - idx;
            else
                reflect = idx[$clog2(W)-1:0];
        end
    endfunction

    // 7 tap indices centered on col (for compute from read buffer)
    wire signed [12:0] si0 = $signed({1'b0, col}) - 13'sd3;
    wire signed [12:0] si1 = $signed({1'b0, col}) - 13'sd2;
    wire signed [12:0] si2 = $signed({1'b0, col}) - 13'sd1;
    wire signed [12:0] si3 = $signed({1'b0, col});
    wire signed [12:0] si4 = $signed({1'b0, col}) + 13'sd1;
    wire signed [12:0] si5 = $signed({1'b0, col}) + 13'sd2;
    wire signed [12:0] si6 = $signed({1'b0, col}) + 13'sd3;

    // Read from the appropriate buffer based on sel
    wire [20:0] t0 = sel ? rbuf_0[reflect(si0)] : rbuf_1[reflect(si0)];
    wire [20:0] t1 = sel ? rbuf_0[reflect(si1)] : rbuf_1[reflect(si1)];
    wire [20:0] t2 = sel ? rbuf_0[reflect(si2)] : rbuf_1[reflect(si2)];
    wire [20:0] t3 = sel ? rbuf_0[reflect(si3)] : rbuf_1[reflect(si3)];
    wire [20:0] t4 = sel ? rbuf_0[reflect(si4)] : rbuf_1[reflect(si4)];
    wire [20:0] t5 = sel ? rbuf_0[reflect(si5)] : rbuf_1[reflect(si5)];
    wire [20:0] t6 = sel ? rbuf_0[reflect(si6)] : rbuf_1[reflect(si6)];

    // Symmetric pre-add and MAC
    wire [21:0] sym0 = {1'b0, t0} + {1'b0, t6};
    wire [21:0] sym1 = {1'b0, t1} + {1'b0, t5};
    wire [21:0] sym2 = {1'b0, t2} + {1'b0, t4};
    wire [31:0] p0 = C0 * sym0;
    wire [31:0] p1 = C1 * sym1;
    wire [31:0] p2 = C2 * sym2;
    wire [31:0] p3 = C3 * t3;
    wire [32:0] conv_result = ({1'b0, p0} + {1'b0, p1}) + ({1'b0, p2} + {1'b0, p3});
    wire [7:0] pixel_out = conv_result[31:24];

    // FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= S_FIRST_ROW;
            sel           <= 1'b0;
            col           <= 0;
            row_cnt       <= 0;
            m_axis_tvalid <= 0;
            m_axis_tdata  <= 0;
            m_axis_tlast  <= 0;
        end else begin
            case (state)
                // ── Store first row into buf_0, no output ──
                S_FIRST_ROW: begin
                    m_axis_tvalid <= 1'b0;
                    if (in_valid) begin
                        rbuf_0[col] <= in_data;
                        if (col == W - 1) begin
                            col     <= 0;
                            sel     <= 1'b1;  // next: write buf_1, read buf_0
                            row_cnt <= row_cnt + 1;
                            state   <= S_PIPE;
                        end else begin
                            col <= col + 1;
                        end
                    end
                end

                // ── Overlapped: store row N+1 to write buf, compute row N from read buf ──
                S_PIPE: begin
                    if (in_valid) begin
                        // Store to write buffer
                        if (sel)
                            rbuf_1[col] <= in_data;
                        else
                            rbuf_0[col] <= in_data;

                        // Compute from read buffer and output
                        m_axis_tvalid <= 1'b1;
                        m_axis_tdata  <= pixel_out;
                        m_axis_tlast  <= (col == W - 1);

                        if (col == W - 1) begin
                            col     <= 0;
                            sel     <= ~sel;     // swap buffers
                            row_cnt <= row_cnt + 1;
                            // Last row stored → compute it next
                            if (row_cnt == IMG_HEIGHT - 1)
                                state <= S_LAST_COMPUTE;
                        end else begin
                            col <= col + 1;
                        end
                    end else begin
                        m_axis_tvalid <= 1'b0;
                    end
                end

                // ── Compute final row from read buffer (no more input) ──
                S_LAST_COMPUTE: begin
                    if (m_axis_tready | ~m_axis_tvalid) begin
                        m_axis_tvalid <= 1'b1;
                        m_axis_tdata  <= pixel_out;
                        m_axis_tlast  <= (col == W - 1);
                        if (col == W - 1) begin
                            col   <= 0;
                            state <= S_DONE;
                        end else begin
                            col <= col + 1;
                        end
                    end
                end

                // ── Idle until reset ──
                S_DONE: begin
                    m_axis_tvalid <= 1'b0;
                end
            endcase
        end
    end

endmodule
