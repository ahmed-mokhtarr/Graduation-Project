// =============================================================================
// prev_coef_fifo.v
//
// Simple synchronous FIFO for delaying the prev-frame polynomial coefficients
// to align with coef_bram_window's output timing.
//
// Write: driven by coef_gen_top prev_valid_out
// Read:  driven by coef_bram_window valid_out (1-cycle read latency from BRAM)
//
// Implementation: Uses simple_dual_port_bram for synthesizable BRAM inference.
// Data is split across 3 BRAM instances (26+26+26 = 78 bits) since each
// 36K BRAM supports up to 36-bit wide data.
//
// Depth: 2^ADDR_W (power-of-2 for natural pointer wrapping).
// ADDR_W = 15 → 32768 entries, sufficient for L0: (DLIMIT+1)*1280 = 16640.
// =============================================================================
module prev_coef_fifo #(
    parameter DLIMIT = 12
)(
    input  wire        clk,
    input  wire        rst_n,

    // Write interface (from coef_gen prev channel)
    input  wire        wr_en,
    input  wire signed [14:0] wr_r2,
    input  wire signed [16:0] wr_r3,
    input  wire signed [13:0] wr_r4,
    input  wire signed [16:0] wr_r5,
    input  wire signed [14:0] wr_r6,

    // Read interface (rd_en = coef_bram_window valid_out)
    input  wire        rd_en,
    output wire signed [14:0] rd_r2,
    output wire signed [16:0] rd_r3,
    output wire signed [13:0] rd_r4,
    output wire signed [16:0] rd_r5,
    output wire signed [14:0] rd_r6,
    output reg                rd_valid   // 1-cycle delayed rd_en
);

    localparam DATA_W = 78;   // 15+17+14+17+15
    localparam ADDR_W = 15;   // 2^15 = 32768 entries (> 16640 needed for L0)

    // ── Pointer management ──────────────────────────────────────────────
    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] rd_ptr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wr_ptr <= {ADDR_W{1'b0}};
        else if (wr_en)
            wr_ptr <= wr_ptr + 1'b1;   // natural wrap at 2^ADDR_W
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr   <= {ADDR_W{1'b0}};
            rd_valid <= 1'b0;
        end else begin
            rd_valid <= rd_en;
            if (rd_en)
                rd_ptr <= rd_ptr + 1'b1;   // natural wrap at 2^ADDR_W
        end
    end

    // ── Pack write data ─────────────────────────────────────────────────
    wire [DATA_W-1:0] wr_data = {wr_r6, wr_r5, wr_r4, wr_r3, wr_r2};

    // ── Single URAM instance (78 bits × 32K deep) ────────────────────────
    // URAM is 72-bit native; Vivado cascades 2 URAMs wide for 78 bits.
    // Much more efficient than 3 × 26-bit BRAMs (saves ~90 BRAM36s).
    wire [DATA_W-1:0] rd_data;

    simple_dual_port_uram #(.DATA_WIDTH(DATA_W), .ADDR_WIDTH(ADDR_W)) u_uram (
        .clk     (clk),
        .we      (wr_en),
        .wr_addr (wr_ptr),
        .wr_data (wr_data),
        .rd_addr (rd_ptr),
        .rd_data (rd_data)
    );

    // ── Unpack read data ────────────────────────────────────────────────
    assign rd_r2 = rd_data[14:0];
    assign rd_r3 = rd_data[31:15];
    assign rd_r4 = rd_data[45:32];
    assign rd_r5 = rd_data[62:46];
    assign rd_r6 = rd_data[77:63];

endmodule
