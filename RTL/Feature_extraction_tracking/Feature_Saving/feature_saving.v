module feature_saving #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 12,
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
)(
    input  wire        clk,
    input  wire        rst_n,

    // ── FAST Corner input ──────────────────────────────────────────────────
    input  wire        corner_valid,
    input  wire [$clog2(IMG_WIDTH)-1:0]  corner_col,
    input  wire [$clog2(IMG_HEIGHT)-1:0] corner_row,
    input  wire        frame_done,

    // ── Ping-Pong Read Interface (for Feature Tracking) ────────────────────
    // Feature Tracking will read from the inactive buffer.
    input  wire [ADDR_WIDTH-1:0] read_addr,
    input  wire        read_en,
    output wire [DATA_WIDTH-1:0] read_data,        // {16'd_row, 16'd_col}
    output reg  [ADDR_WIDTH:0] prev_feature_count // How many features are available to read
);

    // Coordinate packing: [31:16] = row, [15:0] = col
    wire [31:0] write_data = { {16-$clog2(IMG_HEIGHT){1'b0}}, corner_row,
                               {16-$clog2(IMG_WIDTH){1'b0}},  corner_col};

    // BRAM Control signals
    reg [ADDR_WIDTH-1:0] feature_count;
    reg        ping_pong_sel; // 0 = Write to BRAM 0, 1 = Write to BRAM 1

    wire we_0 = corner_valid && (ping_pong_sel == 1'b0) && (feature_count < (1<<ADDR_WIDTH));
    wire we_1 = corner_valid && (ping_pong_sel == 1'b1) && (feature_count < (1<<ADDR_WIDTH));

    // The BRAM not being written to is available for reading
    wire re_0 = read_en && (ping_pong_sel == 1'b1);
    wire re_1 = read_en && (ping_pong_sel == 1'b0);

    wire [DATA_WIDTH-1:0] rdata_0;
    wire [DATA_WIDTH-1:0] rdata_1;

    // Output mux
    assign read_data = (ping_pong_sel == 1'b1) ? rdata_0 : rdata_1;

    // BRAM instances
    simple_dual_port_bram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_0 (
        .clk  (clk),
        .we   (we_0),
        .wr_addr(feature_count),
        .wr_data(write_data),
        .re   (re_0),
        .rd_addr(read_addr),
        .rd_data(rdata_0)
    );

    simple_dual_port_bram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_1 (
        .clk  (clk),
        .we   (we_1),
        .wr_addr(feature_count),
        .wr_data(write_data),
        .re   (re_1),
        .rd_addr(read_addr),
        .rd_data(rdata_1)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            feature_count      <= 0;
            ping_pong_sel      <= 0;
            prev_feature_count <= 0;
        end else begin
            if (frame_done) begin
                prev_feature_count <= feature_count;
                ping_pong_sel      <= ~ping_pong_sel;
                feature_count      <= 0;
            end else if (corner_valid && (feature_count < (1<<ADDR_WIDTH))) begin
                feature_count <= feature_count + 1;
            end
        end
    end

endmodule