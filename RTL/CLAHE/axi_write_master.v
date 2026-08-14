module axi_write_master #(
    parameter FRAME_PIXELS   = 921600,   // 1280 x 720
    parameter AXI_DATA_WIDTH = 32,
    parameter BURST_LEN      = 16        // words per AXI burst (awlen = BURST_LEN-1)
)(
    input  wire        clk,
    input  wire        rst_n,

    // Pixel input stream (directly from camera)
    input  wire        pixel_v,
    input  wire [7:0]  pixel_in,

    // Control
    input  wire        frame_start,         // SOF pulse – resets packer & FSM
    input  wire [31:0] frame_base_addr,     // DDR base address (stable before frame_start)
    output reg         write_done,          // single-cycle pulse: entire frame written

    // AXI4 Write Address Channel
    output reg  [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,

    // AXI4 Write Data Channel
    output wire [31:0] m_axi_wdata,
    output wire [3:0]  m_axi_wstrb,
    output reg         m_axi_wlast,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,

    // AXI4 Write Response Channel
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready
);

// -----------------------------------------------------------------
// Fixed AXI parameters
// -----------------------------------------------------------------
assign m_axi_awlen   = BURST_LEN - 1;      // N+1 beats
assign m_axi_awsize  = 3'b010;             // 4 bytes per beat
assign m_axi_awburst = 2'b01;              // INCR
assign m_axi_wstrb   = 4'b1111;            // all byte lanes
assign m_axi_bready  = 1'b1;              // always accept responses

localparam TOTAL_WORDS = FRAME_PIXELS / 4;  // 230 400

// =================================================================
// Pixel Packer:  4 x 8-bit pixels -> 32-bit word
// =================================================================
reg  [1:0]  pack_cnt;
reg  [23:0] pack_reg;           // holds first 3 pixels
wire        pack_valid;
wire [31:0] packed_word;

assign pack_valid  = pixel_v && (pack_cnt == 2'd3);
assign packed_word = {pixel_in, pack_reg};  // MSB = pixel 3

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pack_cnt <= 2'd0;
        pack_reg <= 24'd0;
    end else if (frame_start) begin
        pack_cnt <= 2'd0;
        pack_reg <= 24'd0;
    end else if (pixel_v) begin
        case (pack_cnt)
            2'd0: pack_reg[7:0]   <= pixel_in;
            2'd1: pack_reg[15:8]  <= pixel_in;
            2'd2: pack_reg[23:16] <= pixel_in;
            2'd3: ;  // 4th pixel read combinationally via packed_word
        endcase
        pack_cnt <= pack_cnt + 2'd1;
    end
end

// =================================================================
// Write FIFO  (synchronous, FWFT, depth = 32)
// =================================================================
localparam FIFO_DEPTH  = 32;
localparam FIFO_AW     = 5;

reg  [31:0] fifo_mem [0:FIFO_DEPTH-1];
reg  [FIFO_AW:0] fifo_wr_ptr, fifo_rd_ptr;      // extra MSB for wrap

wire fifo_empty = (fifo_wr_ptr == fifo_rd_ptr);
wire fifo_full  = (fifo_wr_ptr[FIFO_AW] != fifo_rd_ptr[FIFO_AW]) &&
                  (fifo_wr_ptr[FIFO_AW-1:0] == fifo_rd_ptr[FIFO_AW-1:0]);
wire [FIFO_AW:0] fifo_count = fifo_wr_ptr - fifo_rd_ptr;

wire fifo_wr_en = pack_valid && !fifo_full;
wire fifo_rd_en;                                   // driven by AXI FSM

// FIFO write
always @(posedge clk) begin
    if (fifo_wr_en)
        fifo_mem[fifo_wr_ptr[FIFO_AW-1:0]] <= packed_word;
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)           fifo_wr_ptr <= 0;
    else if (frame_start) fifo_wr_ptr <= 0;
    else if (fifo_wr_en)  fifo_wr_ptr <= fifo_wr_ptr + 1;
end

// FIFO read  (combinational output – first-word-fall-through)
wire [31:0] fifo_rd_data = fifo_mem[fifo_rd_ptr[FIFO_AW-1:0]];
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)                        fifo_rd_ptr <= 0;
    else if (frame_start)              fifo_rd_ptr <= 0;
    else if (fifo_rd_en && !fifo_empty) fifo_rd_ptr <= fifo_rd_ptr + 1;
end

// =================================================================
// AXI Write FSM
// =================================================================
localparam S_IDLE   = 3'd0,
           S_ACTIVE = 3'd1,
           S_AW     = 3'd2,
           S_W      = 3'd3,
           S_B      = 3'd4,
           S_DONE   = 3'd5;

reg [2:0]  axi_state;
reg [31:0] next_addr;
reg [7:0]  beat_cnt;
reg [17:0] words_written;      // max 230 400

// wdata comes directly from FIFO read port (combinational)
assign m_axi_wdata = fifo_rd_data;

// FIFO is read on each accepted W-channel beat
assign fifo_rd_en = (axi_state == S_W) && m_axi_wvalid && m_axi_wready;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        axi_state     <= S_IDLE;
        next_addr     <= 32'd0;
        beat_cnt      <= 8'd0;
        words_written <= 18'd0;
        write_done    <= 1'b0;
        m_axi_awaddr  <= 32'd0;
        m_axi_awvalid <= 1'b0;
        m_axi_wvalid  <= 1'b0;
        m_axi_wlast   <= 1'b0;
    end else begin
        write_done <= 1'b0;  // default

        case (axi_state)
            // -------------------------------------------------
            S_IDLE: begin
                m_axi_awvalid <= 1'b0;
                m_axi_wvalid  <= 1'b0;
                m_axi_wlast   <= 1'b0;
                if (frame_start) begin
                    next_addr     <= frame_base_addr;
                    words_written <= 18'd0;
                    axi_state     <= S_ACTIVE;
                end
            end

            // -------------------------------------------------
            S_ACTIVE: begin
                // Wait for a full burst in the FIFO
                if (fifo_count >= BURST_LEN) begin
                    m_axi_awaddr  <= next_addr;
                    m_axi_awvalid <= 1'b1;
                    beat_cnt      <= 8'd0;
                    axi_state     <= S_AW;
                end
            end

            // -------------------------------------------------
            S_AW: begin
                if (m_axi_awready) begin
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b1;
                    m_axi_wlast   <= (BURST_LEN == 1);
                    axi_state     <= S_W;
                end
            end

            // -------------------------------------------------
            S_W: begin
                if (m_axi_wready) begin
                    words_written <= words_written + 18'd1;

                    if (beat_cnt == BURST_LEN - 1) begin
                        // last beat accepted
                        m_axi_wvalid <= 1'b0;
                        m_axi_wlast  <= 1'b0;
                        next_addr    <= next_addr + (BURST_LEN * 4);
                        axi_state    <= S_B;
                    end else begin
                        beat_cnt <= beat_cnt + 8'd1;
                        if (beat_cnt == BURST_LEN - 2)
                            m_axi_wlast <= 1'b1;
                    end
                end
            end

            // -------------------------------------------------
            S_B: begin
                if (m_axi_bvalid) begin
                    if (words_written >= TOTAL_WORDS)
                        axi_state <= S_DONE;
                    else
                        axi_state <= S_ACTIVE;
                end
            end

            // -------------------------------------------------
            S_DONE: begin
                write_done <= 1'b1;
                axi_state  <= S_IDLE;
            end

            default: axi_state <= S_IDLE;
        endcase
    end
end

endmodule
