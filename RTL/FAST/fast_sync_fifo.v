// =============================================================================
// Module  : fast_sync_fifo
// Purpose : Parameterized synchronous FIFO using a circular buffer.
//           Used to decouple the GF stream filter (1 cycle/pixel) from the
//           track validator (multi-cycle per feature).
// =============================================================================

module fast_sync_fifo #(
    parameter DATA_WIDTH = 64,
    parameter DEPTH      = 32,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  flush,     // synchronous clear

    // Write side
    input  wire [DATA_WIDTH-1:0] din,
    input  wire                  wr_en,

    // Read side
    output wire [DATA_WIDTH-1:0] dout,
    input  wire                  rd_en,

    // Status
    output wire                  full,
    output wire                  empty
);

    // ── Memory ──────────────────────────────────────────────────────────────
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // ── Pointers (extra MSB for full/empty detection) ───────────────────────
    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;

    // ── Status ──────────────────────────────────────────────────────────────
    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
                   (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

    // ── Read data (combinational, available before rd_en) ───────────────────
    assign dout = mem[rd_ptr[ADDR_WIDTH-1:0]];

    // ── Write logic ─────────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (wr_en && !full && !flush)
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= din;
    end

    // ── Pointer logic ───────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {(ADDR_WIDTH+1){1'b0}};
            rd_ptr <= {(ADDR_WIDTH+1){1'b0}};
        end else if (flush) begin
            wr_ptr <= {(ADDR_WIDTH+1){1'b0}};
            rd_ptr <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            if (wr_en && !full)
                wr_ptr <= wr_ptr + 1'b1;
            if (rd_en && !empty)
                rd_ptr <= rd_ptr + 1'b1;
        end
    end

endmodule
