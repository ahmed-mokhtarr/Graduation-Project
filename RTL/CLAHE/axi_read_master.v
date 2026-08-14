module axi_read_master #(
    parameter FRAME_PIXELS   = 921600,   // 1280 x 720
    parameter AXI_DATA_WIDTH = 32,
    parameter BURST_LEN      = 16        // words per burst
)(
    input  wire        clk,
    input  wire        rst_n,

    // Control
    input  wire        read_start,          // pulse: begin reading a frame
    input  wire [31:0] frame_base_addr,     // DDR base address (stable before read_start)
    output reg         read_done,           // pulse: all pixels output

    // Pixel output stream  (to pixel_counter -> bilinear)
    output reg  [7:0]  pixel_out,
    output reg         pixel_v_out,

    // AXI4 Read Address Channel
    output reg  [31:0] m_axi_araddr,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,

    // AXI4 Read Data Channel
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready
);

// -----------------------------------------------------------------
// Fixed AXI parameters
// -----------------------------------------------------------------
assign m_axi_arlen   = BURST_LEN - 1;
assign m_axi_arsize  = 3'b010;              // 4 bytes
assign m_axi_arburst = 2'b01;               // INCR

localparam TOTAL_WORDS  = FRAME_PIXELS / 4;  // 230 400
localparam TOTAL_BURSTS = TOTAL_WORDS / BURST_LEN;  // 14 400

// =================================================================
// Read Data FIFO  (depth 64, FWFT)
// =================================================================
localparam FIFO_DEPTH = 64;
localparam FIFO_AW    = 6;

reg  [31:0] fifo_mem [0:FIFO_DEPTH-1];
reg  [FIFO_AW:0] fifo_wr_ptr, fifo_rd_ptr;

wire fifo_empty = (fifo_wr_ptr == fifo_rd_ptr);
wire fifo_full  = (fifo_wr_ptr[FIFO_AW] != fifo_rd_ptr[FIFO_AW]) &&
                  (fifo_wr_ptr[FIFO_AW-1:0] == fifo_rd_ptr[FIFO_AW-1:0]);
wire [FIFO_AW:0] fifo_count = fifo_wr_ptr - fifo_rd_ptr;

// Accept AXI data when FIFO has room
assign m_axi_rready = !fifo_full;

wire fifo_wr_en = m_axi_rvalid && m_axi_rready;
wire fifo_rd_en;  // from pixel output FSM

always @(posedge clk) begin
    if (fifo_wr_en)
        fifo_mem[fifo_wr_ptr[FIFO_AW-1:0]] <= m_axi_rdata;
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)           fifo_wr_ptr <= 0;
    else if (read_start)  fifo_wr_ptr <= 0;
    else if (fifo_wr_en)  fifo_wr_ptr <= fifo_wr_ptr + 1;
end

wire [31:0] fifo_rd_data = fifo_mem[fifo_rd_ptr[FIFO_AW-1:0]];
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)                          fifo_rd_ptr <= 0;
    else if (read_start)                 fifo_rd_ptr <= 0;
    else if (fifo_rd_en && !fifo_empty)  fifo_rd_ptr <= fifo_rd_ptr + 1;
end

// =================================================================
// AXI Read Request FSM  (issues AR back-to-back)
// =================================================================
localparam AR_IDLE  = 2'd0,
           AR_REQ   = 2'd1,
           AR_WAIT  = 2'd2,
           AR_DONE  = 2'd3;

reg  [1:0]  ar_state;
reg  [31:0] ar_next_addr;
reg  [13:0] bursts_issued;

// Don't issue if FIFO could overflow with outstanding data
wire can_issue = (fifo_count < FIFO_DEPTH - BURST_LEN) &&
                 (bursts_issued < TOTAL_BURSTS);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ar_state      <= AR_IDLE;
        ar_next_addr  <= 32'd0;
        bursts_issued <= 14'd0;
        m_axi_araddr  <= 32'd0;
        m_axi_arvalid <= 1'b0;
    end else begin
        case (ar_state)
            AR_IDLE: begin
                m_axi_arvalid <= 1'b0;
                if (read_start) begin
                    ar_next_addr  <= frame_base_addr;
                    bursts_issued <= 14'd0;
                    ar_state      <= AR_REQ;
                end
            end

            AR_REQ: begin
                if (can_issue) begin
                    m_axi_araddr  <= ar_next_addr;
                    m_axi_arvalid <= 1'b1;
                    ar_state      <= AR_WAIT;
                end
            end

            AR_WAIT: begin
                if (m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    ar_next_addr  <= ar_next_addr + (BURST_LEN * 4);
                    bursts_issued <= bursts_issued + 14'd1;

                    if (bursts_issued + 1 >= TOTAL_BURSTS)
                        ar_state <= AR_DONE;
                    else
                        ar_state <= AR_REQ;
                end
            end

            AR_DONE: begin
                ar_state <= AR_IDLE;
            end

            default: ar_state <= AR_IDLE;
        endcase
    end
end

// =================================================================
// Pixel Output FSM  (unpack 32-bit words → 4 x 8-bit pixels)
// =================================================================
reg  [1:0]  byte_sel;
reg  [19:0] pixels_out_cnt;
reg         output_active;

// Advance FIFO read pointer after the 4th byte of each word
assign fifo_rd_en = output_active && !fifo_empty && (byte_sel == 2'd3);

// Combinational byte selection from FIFO head
reg [7:0] selected_byte;
always @(*) begin
    case (byte_sel)
        2'd0: selected_byte = fifo_rd_data[7:0];
        2'd1: selected_byte = fifo_rd_data[15:8];
        2'd2: selected_byte = fifo_rd_data[23:16];
        2'd3: selected_byte = fifo_rd_data[31:24];
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pixel_out      <= 8'd0;
        pixel_v_out    <= 1'b0;
        byte_sel       <= 2'd0;
        pixels_out_cnt <= 20'd0;
        output_active  <= 1'b0;
        read_done      <= 1'b0;
    end else if (read_start) begin
        pixel_out      <= 8'd0;
        pixel_v_out    <= 1'b0;
        byte_sel       <= 2'd0;
        pixels_out_cnt <= 20'd0;
        output_active  <= 1'b0;
        read_done      <= 1'b0;
    end else begin
        read_done <= 1'b0;

        if (!output_active) begin
            // Wait for FIFO to accumulate before starting
            pixel_v_out <= 1'b0;
            if (fifo_count >= 4)     // 16 pixels of head-start
                output_active <= 1'b1;
        end
        else if (pixels_out_cnt >= FRAME_PIXELS) begin
            // Entire frame output
            pixel_v_out   <= 1'b0;
            output_active <= 1'b0;
            read_done     <= 1'b1;
        end
        else if (!fifo_empty || byte_sel != 2'd0) begin
            // Output next pixel
            pixel_v_out    <= 1'b1;
            pixel_out      <= selected_byte;
            byte_sel       <= byte_sel + 2'd1;
            pixels_out_cnt <= pixels_out_cnt + 20'd1;
        end
        else begin
            // FIFO underflow at word boundary – stall
            pixel_v_out <= 1'b0;
        end
    end
end

endmodule
