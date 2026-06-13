// ============================================================================
// Horizontal 1x7 Convolution - Row Buffer with Centered BORDER_REFLECT_101
// ============================================================================
// Stores one full row of vertical conv output in a buffer, then computes
// the centered horizontal convolution for all W pixels using reflected
// border indices. No drain state machine needed.
//
// Interface:
//   Input:  Simple wires (in_data, in_valid, in_last) — from vertical conv
//   Output: AXI-Stream (m_axis_*) — final output of blur pipeline
// ============================================================================

module horizontal_conv_1x7 #(
    parameter IMG_WIDTH = 1280
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
    // Backpressure: high during S_COMPUTE to stall upstream
    output wire        busy
);

    localparam [9:0] C0 = 10'd528;
    localparam [9:0] C1 = 10'd584;
    localparam [9:0] C2 = 10'd620;
    localparam [9:0] C3 = 10'd632;
    localparam W = IMG_WIDTH;

    // Row buffer
    (* ram_style = "distributed" *) reg [20:0] rbuf [0:W-1];

    // FSM: STORE row, then COMPUTE centered output
    localparam S_STORE   = 1'b0;
    localparam S_COMPUTE = 1'b1;
    reg state;

    // Assert busy during S_COMPUTE, AND during the S_STORE cycle that
    // receives the last pixel (in_valid && in_last). This prevents the
    // line buffer from advancing one extra cycle at the boundary, which
    // would cause a 1-column shift (the vertical conv would produce a
    // pixel that nobody consumes). No combinational loop because in_valid
    // and in_last come from vertical conv's registered outputs.
    assign busy = (state == S_COMPUTE) ||
                  (state == S_STORE && in_valid && in_last);

    reg [$clog2(W)-1:0] wr_col;
    reg [$clog2(W)-1:0] rd_col;

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

    // 7 tap indices for centered conv at rd_col
    wire signed [12:0] si0 = $signed({1'b0, rd_col}) - 13'sd3;
    wire signed [12:0] si1 = $signed({1'b0, rd_col}) - 13'sd2;
    wire signed [12:0] si2 = $signed({1'b0, rd_col}) - 13'sd1;
    wire signed [12:0] si3 = $signed({1'b0, rd_col});
    wire signed [12:0] si4 = $signed({1'b0, rd_col}) + 13'sd1;
    wire signed [12:0] si5 = $signed({1'b0, rd_col}) + 13'sd2;
    wire signed [12:0] si6 = $signed({1'b0, rd_col}) + 13'sd3;

    wire [20:0] t0 = rbuf[reflect(si0)];
    wire [20:0] t1 = rbuf[reflect(si1)];
    wire [20:0] t2 = rbuf[reflect(si2)];
    wire [20:0] t3 = rbuf[reflect(si3)];
    wire [20:0] t4 = rbuf[reflect(si4)];
    wire [20:0] t5 = rbuf[reflect(si5)];
    wire [20:0] t6 = rbuf[reflect(si6)];

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
            state  <= S_STORE;
            wr_col <= 0;
            rd_col <= 0;
            m_axis_tvalid <= 0;
            m_axis_tdata  <= 0;
            m_axis_tlast  <= 0;
        end else begin
            case (state)
                S_STORE: begin
                    m_axis_tvalid <= 0;
                    if (in_valid) begin
                        rbuf[wr_col] <= in_data;
                        if (in_last || wr_col == W - 1) begin
                            wr_col <= 0;
                            rd_col <= 0;
                            state  <= S_COMPUTE;
                        end else begin
                            wr_col <= wr_col + 1;
                        end
                    end
                end

                S_COMPUTE: begin
                    if (m_axis_tready | ~m_axis_tvalid) begin
                        m_axis_tvalid <= 1;
                        m_axis_tdata  <= pixel_out;
                        m_axis_tlast  <= (rd_col == W - 1);
                        if (rd_col == W - 1) begin
                            rd_col <= 0;
                            state  <= S_STORE;
                        end else begin
                            rd_col <= rd_col + 1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
