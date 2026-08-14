// =============================================================================
// Module  : feature_sender
// Purpose : Reads the completed Feature List BRAM and streams it out via
//           AXI-Stream to a DMA for DDR transfer.
// =============================================================================

module feature_sender #(
    parameter FEAT_W       = 64,
    parameter ADDR_W       = 11,
    parameter MAX_FEATURES = 2048
)(
    input  wire                clk,
    input  wire                rst_n,

    // ── Control ─────────────────────────────────────────────────────────────
    input  wire                start,
    input  wire [ADDR_W:0]     feat_count,   // total features to send
    output reg                 done,
    output reg                 busy,

    // ── Feature List BRAM read port ─────────────────────────────────────────
    output reg  [ADDR_W-1:0]   bram_rd_addr,
    input  wire [FEAT_W-1:0]   bram_rd_data,

    // ── AXI-Stream Master ───────────────────────────────────────────────────
    output wire [FEAT_W-1:0]   m_axis_tdata,
    output wire                m_axis_tvalid,
    input  wire                m_axis_tready,
    output wire                m_axis_tlast
);

    // =========================================================================
    // FSM states
    // =========================================================================
    localparam [1:0]
        S_IDLE = 2'd0,
        S_READ = 2'd1,
        S_SEND = 2'd2,
        S_DONE = 2'd3;

    reg [1:0]      state;
    reg [ADDR_W:0] send_idx;
    reg [ADDR_W:0] feat_count_r;  // latched feat_count

    // =========================================================================
    // Combinational AXI-Stream outputs — valid only in S_SEND
    // =========================================================================
    assign m_axis_tvalid = (state == S_SEND);
    assign m_axis_tdata  = bram_rd_data;
    assign m_axis_tlast  = (state == S_SEND) && (send_idx == feat_count_r - 1);

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            done          <= 1'b0;
            busy          <= 1'b0;
            bram_rd_addr  <= 0;
            send_idx      <= 0;
            feat_count_r  <= 0;
        end else begin
            done <= 1'b0;

            case (state)

            S_IDLE: begin
                if (start) begin
                    if (feat_count == 0) begin
                        done <= 1'b1;
                    end else begin
                        busy         <= 1'b1;
                        send_idx     <= 0;
                        feat_count_r <= feat_count;
                        bram_rd_addr <= 0;
                        state        <= S_READ;
                    end
                end
            end

            // ── Wait 1 cycle for BRAM read latency ─────────────────────
            S_READ: begin
                state <= S_SEND;
            end

            // ── Present data on AXI-Stream, wait for handshake ─────────
            // tvalid/tdata/tlast are combinational from state & bram_rd_data
            S_SEND: begin
                if (m_axis_tready) begin
                    if (send_idx == feat_count_r - 1) begin
                        // Last word accepted
                        state <= S_DONE;
                    end else begin
                        // Advance to next feature
                        send_idx     <= send_idx + 1'b1;
                        bram_rd_addr <= send_idx[ADDR_W-1:0] + 1'b1;
                        state        <= S_READ;
                    end
                end
                // If !tready, stay in S_SEND (backpressure)
            end

            S_DONE: begin
                done  <= 1'b1;
                busy  <= 1'b0;
                state <= S_IDLE;
            end

            default: state <= S_IDLE;

            endcase
        end
    end

endmodule
