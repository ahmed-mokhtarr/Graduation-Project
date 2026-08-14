// =============================================================================
// mwm_top.v  —  Memory Write Module Top
//
// Receives valid 16-bit delta outputs {dy[7:0], dx[7:0]} from gf_pipeline_top,
// packs 4 deltas into a 64-bit word, buffers them in a write FIFO, and issues
// AXI4 write bursts to DDR via axi_write_flow.
//
// Packing:  64-bit word = {delta3, delta2, delta1, delta0}
//           where delta0 arrives first (LSB-first packing).
//
// Burst strategy:
//   burst_len selected per layer so that we get ~10 bursts for small layers
//   and ~40 for large layers.  The write controller handles partial final
//   bursts precisely so it never stalls waiting for a full burst when the
//   layer has already finished.
//
// Flow:
//   1. Pipeline asserts valid_out + out_delta
//   2. MWM packs 4 deltas → 64-bit word → writes to FIFO
//   3. When FIFO has >= burst_len entries (or layer is done),
//      axi_write_flow drains the FIFO via AXI write bursts
//   4. After all pixels written to DDR, asserts layer_done pulse
// =============================================================================
module mwm_top #(
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ADDR_WIDTH = 32,
    parameter IMG_WIDTH      = 1280,
    parameter IMG_HEIGHT     = 720,
    parameter FIFO_DEPTH     = 512,
    parameter FIFO_ADDR_W    = 9,
    parameter FLOW_OUT_BASE  = 32'h5000_0000
)(
    input  wire                       clk,
    input  wire                       rst_n,

    // ── SPU FSM interface ───────────────────────────────────────────────────
    input  wire [2:0]                 current_layer,
    input  wire                       write_start,     // pulse: begin accepting data for this layer
    output wire                       layer_done,      // pulse: all data written to DDR

    // ── GF pipeline output ──────────────────────────────────────────────────
    input  wire                       pipeline_valid,
    input  wire [15:0]                pipeline_delta,  // {dy[7:0], dx[7:0]}

    // ── AXI4 Write Master interface ─────────────────────────────────────────
    output wire [AXI_ADDR_WIDTH-1:0]  m_axi_awaddr,
    output wire [7:0]                 m_axi_awlen,
    output wire [2:0]                 m_axi_awsize,
    output wire [1:0]                 m_axi_awburst,
    output wire                       m_axi_awvalid,
    input  wire                       m_axi_awready,

    output wire [AXI_DATA_WIDTH-1:0]  m_axi_wdata,
    output wire [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output wire                       m_axi_wlast,
    output wire                       m_axi_wvalid,
    input  wire                       m_axi_wready,

    input  wire [1:0]                 m_axi_bresp,
    input  wire                       m_axi_bvalid,
    output wire                       m_axi_bready
);

    // =========================================================================
    // 1. Address Calculation Unit
    // =========================================================================
    wire [AXI_ADDR_WIDTH-1:0] acu_write_addr;
    wire [31:0]               acu_total_pixels;
    wire                      acu_valid;

    mwm_acu #(
        .IMG_WIDTH      (IMG_WIDTH),
        .IMG_HEIGHT     (IMG_HEIGHT),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .FLOW_OUT_BASE  (FLOW_OUT_BASE)
    ) u_acu (
        .clk            (clk),
        .rst_n          (rst_n),
        .current_layer  (current_layer),
        .write_start    (write_start),
        .write_base_addr(acu_write_addr),
        .total_pixels   (acu_total_pixels),
        .acu_valid      (acu_valid)
    );

    // =========================================================================
    // 2. Layer configuration latching & pixel counting
    // =========================================================================
    reg [31:0] total_pixels_r;
    reg [31:0] total_beats_r;       // = total_pixels / 4
    reg [7:0]  burst_len_r;
    reg        layer_active;
    reg [31:0] pixel_count;         // pixels received from pipeline

    // Burst length selection per layer
    reg [7:0] burst_len_sel;
    always @(*) begin
        case (current_layer)
            3'd4:    burst_len_sel = 8'd90;    // 900 total beats, ~10 bursts
            3'd3:    burst_len_sel = 8'd90;    // 3600 total beats, ~40 bursts
            3'd2:    burst_len_sel = 8'd128;   // 14400 total beats
            3'd1:    burst_len_sel = 8'd128;   // 57600 total beats
            3'd0:    burst_len_sel = 8'd200;   // 230400 total beats
            default: burst_len_sel = 8'd128;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_count    <= 0;
            total_pixels_r <= 0;
            total_beats_r  <= 0;
            burst_len_r    <= 0;
            layer_active   <= 0;
        end else begin
            if (write_start) begin
                pixel_count  <= 0;
                layer_active <= 1;
            end
            if (acu_valid) begin
                total_pixels_r <= acu_total_pixels;
                total_beats_r  <= acu_total_pixels >> 2;  // /4
                burst_len_r    <= burst_len_sel;
            end
            if (pipeline_valid && layer_active) begin
                pixel_count <= pixel_count + 1;
            end
            // Clear layer_active when write controller signals done
            if (layer_done) begin
                layer_active <= 0;
            end
        end
    end

    // All pixels received from pipeline
    wire all_pixels_received = layer_active && (pixel_count >= total_pixels_r) && (total_pixels_r != 0);

    // =========================================================================
    // 3. 4:1 Delta Packer  (4 × 16-bit → 1 × 64-bit)
    // =========================================================================
    reg [1:0]  pack_cnt;            // 0..3
    reg [47:0] pack_reg;            // holds first 3 deltas
    reg        pack_wr_en;
    wire       fifo_full;

    // The 64-bit word to write: {current_delta, pack_reg[47:0]}
    reg [63:0] fifo_din_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pack_cnt   <= 2'd0;
            pack_reg   <= 48'd0;
            pack_wr_en <= 1'b0;
            fifo_din_r <= 64'd0;
        end else begin
            pack_wr_en <= 1'b0;

            if (write_start) begin
                pack_cnt <= 2'd0;
                pack_reg <= 48'd0;
            end else if (pipeline_valid && layer_active && current_layer != 3'd0) begin
                case (pack_cnt)
                    2'd0: pack_reg[15:0]  <= pipeline_delta;
                    2'd1: pack_reg[31:16] <= pipeline_delta;
                    2'd2: pack_reg[47:32] <= pipeline_delta;
                    2'd3: begin
                        fifo_din_r <= {pipeline_delta, pack_reg[47:0]};
                        pack_wr_en <= 1'b1;
                    end
                endcase
                pack_cnt <= pack_cnt + 2'd1;
            end
        end
    end

    // =========================================================================
    // 4. Write FIFO (64-bit wide)
    // =========================================================================
    wire        fifo_empty;
    wire [63:0] fifo_dout;
    wire        fifo_rd_en;

    gf_sync_fifo #(
        .DATA_WIDTH (64),
        .ADDR_WIDTH (FIFO_ADDR_W)
    ) u_write_fifo (
        .clk   (clk),
        .rst_n (rst_n),
        .flush (1'b0),
        .wr_en (pack_wr_en),
        .din   (fifo_din_r),
        .rd_en (fifo_rd_en),
        .dout  (fifo_dout),
        .empty (fifo_empty),
        .full  (fifo_full)
    );

    // =========================================================================
    // 5. FIFO level counter
    // =========================================================================
    reg [FIFO_ADDR_W:0] fifo_count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            fifo_count <= 0;
        else if (write_start)
            fifo_count <= 0;
        else begin
            case ({pack_wr_en && !fifo_full, fifo_rd_en && !fifo_empty})
                2'b10:   fifo_count <= fifo_count + 1;
                2'b01:   fifo_count <= fifo_count - 1;
                default: fifo_count <= fifo_count;
            endcase
        end
    end

    // =========================================================================
    // 6. Write Controller FSM
    // =========================================================================
    localparam WC_IDLE     = 3'd0;
    localparam WC_WAIT     = 3'd1;
    localparam WC_ISSUE    = 3'd2;
    localparam WC_WRITING  = 3'd3;
    localparam WC_DONE     = 3'd4;

    reg [2:0]  wc_state;
    reg [31:0] beats_issued;
    reg        axi_start_write;
    reg [31:0] axi_total_beats;
    reg [7:0]  axi_burst_len;
    wire       axi_write_done;

    reg        layer_done_r;
    assign     layer_done = layer_done_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wc_state        <= WC_IDLE;
            beats_issued    <= 0;
            axi_start_write <= 0;
            axi_total_beats <= 0;
            axi_burst_len   <= 0;
            layer_done_r    <= 0;
        end else begin
            axi_start_write <= 1'b0;
            layer_done_r    <= 1'b0;

            case (wc_state)
                WC_IDLE: begin
                    if (write_start) begin
                        beats_issued <= 0;
                        wc_state     <= WC_WAIT;
                    end
                end

                WC_WAIT: begin
                    if (fifo_count >= {1'b0, burst_len_r} && burst_len_r != 0) begin
                        // Enough data for a full burst
                        axi_total_beats <= {24'd0, burst_len_r};
                        axi_burst_len   <= burst_len_r;
                        axi_start_write <= 1'b1;
                        wc_state        <= WC_WRITING;
                    end else if (all_pixels_received && fifo_count > 0) begin
                        // Layer finished, flush residual
                        axi_total_beats <= {22'd0, fifo_count};
                        axi_burst_len   <= (fifo_count > 256) ? 8'd256 : fifo_count[7:0];
                        axi_start_write <= 1'b1;
                        wc_state        <= WC_WRITING;
                    end else if (all_pixels_received && fifo_count == 0 && pack_cnt == 2'd0) begin
                        // All data flushed to DDR
                        wc_state <= WC_DONE;
                    end
                end

                WC_WRITING: begin
                    if (axi_write_done) begin
                        beats_issued <= beats_issued + axi_total_beats;
                        wc_state     <= WC_WAIT;
                    end
                end

                WC_DONE: begin
                    layer_done_r <= 1'b1;
                    wc_state     <= WC_IDLE;
                end

                default: wc_state <= WC_IDLE;
            endcase
        end
    end

    // =========================================================================
    // 7. AXI Write Master
    // =========================================================================
    wire [AXI_ADDR_WIDTH-1:0] cur_write_addr = acu_write_addr + (beats_issued * 8);

    axi_write_flow #(
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH)
    ) u_axi_write (
        .clk         (clk),
        .rst_n       (rst_n),
        .base_addr   (cur_write_addr),
        .total_beats (axi_total_beats),
        .burst_len   (axi_burst_len),
        .start_write (axi_start_write),
        .write_done  (axi_write_done),
        .fifo_dout   (fifo_dout),
        .fifo_empty  (fifo_empty),
        .fifo_rd_en  (fifo_rd_en),
        .awaddr      (m_axi_awaddr),
        .awlen       (m_axi_awlen),
        .awsize      (m_axi_awsize),
        .awburst     (m_axi_awburst),
        .awvalid     (m_axi_awvalid),
        .awready     (m_axi_awready),
        .wdata       (m_axi_wdata),
        .wstrb       (m_axi_wstrb),
        .wlast       (m_axi_wlast),
        .wvalid      (m_axi_wvalid),
        .wready      (m_axi_wready),
        .bresp       (m_axi_bresp),
        .bvalid      (m_axi_bvalid),
        .bready      (m_axi_bready)
    );

endmodule
