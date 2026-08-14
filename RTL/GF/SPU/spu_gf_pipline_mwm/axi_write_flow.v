// =============================================================================
// axi_write_flow.v  —  AXI4 Write Master for Computed Flow Vectors
//
// Writes 64-bit words from the MWM write FIFO to DDR via AXI4 bursts.
//
// Burst strategy (configurable per layer via burst_len input):
//   - Smallest layer (L4, 3600 pixels):    burst_len = 10  → 10 beats/burst
//   - Layer L3 (14400 pixels):              burst_len = 20
//   - Layer L2 (57600 pixels):              burst_len = 40
//   - Layer L1 (230400 pixels):             burst_len = 80
//   - Layer L0 (921600 pixels):             burst_len = 128
//
// Each beat = 64 bits = 8 bytes = 4 packed flow pixels.
// The module issues bursts of `burst_len` beats, except the final burst
// which may be shorter (handles the remainder precisely).
//
// Protocol:
//   1. Wait for fifo_count >= burst_len OR layer_last signal
//   2. Issue AW with computed address and length
//   3. Stream W data from FIFO
//   4. Wait for B response
//   5. Repeat until all beats written
//   6. Assert write_done pulse
// =============================================================================
module axi_write_flow #(
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ADDR_WIDTH = 32
)(
    input  wire                       clk,
    input  wire                       rst_n,

    // ── Control (from MWM top) ──────────────────────────────────────────────
    input  wire [AXI_ADDR_WIDTH-1:0]  base_addr,
    input  wire [31:0]                total_beats,   // total 64-bit words to write
    input  wire [7:0]                 burst_len,     // beats per burst (1–256)
    input  wire                       start_write,   // pulse to begin
    output reg                        write_done,    // pulse when complete

    // ── Write FIFO interface ────────────────────────────────────────────────
    input  wire [AXI_DATA_WIDTH-1:0]  fifo_dout,
    input  wire                       fifo_empty,
    output wire                       fifo_rd_en,

    // ── AXI4 Write Address Channel ──────────────────────────────────────────
    output reg  [AXI_ADDR_WIDTH-1:0]  awaddr,
    output reg  [7:0]                 awlen,
    output wire [2:0]                 awsize,
    output wire [1:0]                 awburst,
    output reg                        awvalid,
    input  wire                       awready,

    // ── AXI4 Write Data Channel ─────────────────────────────────────────────
    output wire [AXI_DATA_WIDTH-1:0]  wdata,
    output wire [AXI_DATA_WIDTH/8-1:0] wstrb,
    output wire                       wlast,
    output wire                       wvalid,
    input  wire                       wready,

    // ── AXI4 Write Response Channel ─────────────────────────────────────────
    input  wire [1:0]                 bresp,
    input  wire                       bvalid,
    output reg                        bready
);

    // -------------------------------------------------------------------------
    // Constants & Combinational Logic
    // -------------------------------------------------------------------------
    localparam BYTES_PER_BEAT = AXI_DATA_WIDTH / 8;   // 8

    assign awsize  = 3'b011;    // 8 bytes per beat (64-bit)
    assign awburst = 2'b01;     // INCR
    assign wstrb   = {(AXI_DATA_WIDTH/8){1'b1}};  // all bytes valid
    assign wdata   = fifo_dout;

    // FSM States
    localparam S_IDLE       = 3'd0;
    localparam S_AW         = 3'd1;
    localparam S_WRITE      = 3'd2;
    localparam S_BRESP      = 3'd3;
    localparam S_NEXT_BURST = 3'd4;
    localparam S_DONE       = 3'd5;

    reg [2:0]  state;
    reg [31:0] beats_written;       // total beats written so far
    reg [31:0] target_beats;        // latched total_beats
    reg [7:0]  cur_burst_len;       // beats in current burst (0-based for awlen)
    reg [7:0]  burst_beat_cnt;      // beats sent in current burst
    reg [AXI_ADDR_WIDTH-1:0] cur_addr;
    reg [7:0]  cfg_burst_len;       // latched burst_len

    wire [31:0] remaining = target_beats - beats_written;

    // AXI W channel and FIFO read enable are combinational
    assign wvalid     = (state == S_WRITE) && !fifo_empty;
    assign wlast      = (state == S_WRITE) && (burst_beat_cnt == cur_burst_len);
    assign fifo_rd_en = wvalid && wready;

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            write_done     <= 1'b0;
            awaddr         <= 0;
            awlen          <= 0;
            awvalid        <= 1'b0;
            bready         <= 1'b0;
            beats_written  <= 0;
            target_beats   <= 0;
            cur_burst_len  <= 0;
            burst_beat_cnt <= 0;
            cur_addr       <= 0;
            cfg_burst_len  <= 0;
        end else begin
            write_done <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    if (start_write) begin
                        target_beats   <= total_beats;
                        cur_addr       <= base_addr;
                        beats_written  <= 0;
                        cfg_burst_len  <= burst_len;
                        state          <= S_NEXT_BURST;
                    end
                end

                // ---------------------------------------------------------
                S_NEXT_BURST: begin
                    if (remaining == 0) begin
                        state <= S_DONE;
                    end else begin
                        // Determine current burst length
                        if (remaining >= {24'd0, cfg_burst_len})
                            cur_burst_len <= cfg_burst_len - 8'd1;   // awlen is 0-based
                        else
                            cur_burst_len <= remaining[7:0] - 8'd1;

                        awaddr  <= cur_addr;
                        awvalid <= 1'b1;
                        awlen   <= (remaining >= {24'd0, cfg_burst_len}) ?
                                   (cfg_burst_len - 8'd1) :
                                   (remaining[7:0] - 8'd1);
                        burst_beat_cnt <= 0;
                        state   <= S_AW;
                    end
                end

                // ---------------------------------------------------------
                S_AW: begin
                    if (awvalid && awready) begin
                        awvalid <= 1'b0;
                        state   <= S_WRITE;
                    end
                end

                // ---------------------------------------------------------
                S_WRITE: begin
                    // Handshake logic is handled combinationally via wvalid/fifo_rd_en
                    if (wvalid && wready) begin
                        beats_written  <= beats_written + 1;
                        burst_beat_cnt <= burst_beat_cnt + 1;

                        if (burst_beat_cnt == cur_burst_len) begin
                            // Burst complete
                            cur_addr <= cur_addr + ({24'd0, cur_burst_len} + 1) * BYTES_PER_BEAT;
                            bready   <= 1'b1;
                            state    <= S_BRESP;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_BRESP: begin
                    if (bvalid && bready) begin
                        bready <= 1'b0;
                        state  <= S_NEXT_BURST;
                    end
                end

                // ---------------------------------------------------------
                S_DONE: begin
                    write_done <= 1'b1;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
