`timescale 1ns / 1ps

module fifo_asym #(
    parameter W_WIDTH = 64,
    parameter R_WIDTH = 8,
    parameter R_DEPTH = 4096
)(
    input  wire clk,
    input  wire srst,
    
    input  wire [W_WIDTH-1:0] din,
    input  wire wr_en,
    output wire full,
    
    input  wire rd_en,
    output wire [R_WIDTH-1:0] dout,
    output wire empty
);
    localparam RATIO       = W_WIDTH / R_WIDTH;
    localparam WORD_DEPTH  = (R_DEPTH * R_WIDTH) / W_WIDTH;
    localparam WORD_ADDR_W = $clog2(WORD_DEPTH);
    localparam SUB_W       = $clog2(RATIO);

    wire               word_fifo_full;
    wire               word_fifo_empty;
    wire [W_WIDTH-1:0] word_fifo_dout;
    wire               word_fifo_rd_en;

    gf_sync_fifo #(
        .DATA_WIDTH(W_WIDTH),
        .ADDR_WIDTH(WORD_ADDR_W)
    ) u_word_fifo (
        .clk  (clk),
        .rst_n(~srst),
        .flush(srst),
        .wr_en(wr_en),
        .din  (din),
        .full (word_fifo_full),
        .rd_en(word_fifo_rd_en),
        .dout (word_fifo_dout),
        .empty(word_fifo_empty)
    );

    assign full  = word_fifo_full;
    assign empty = word_fifo_empty;
    wire [$clog2(R_DEPTH)+1:0] count = (u_word_fifo.wr_ptr - u_word_fifo.bram_rd_ptr) * RATIO; // alias for tb probing

    reg [SUB_W-1:0] sub_ptr;

    assign dout = word_fifo_dout[sub_ptr * R_WIDTH +: R_WIDTH];

    assign word_fifo_rd_en = (rd_en && !empty && (sub_ptr == RATIO - 1));

    always @(posedge clk) begin
        if (srst) begin
            sub_ptr <= 0;
        end else if (rd_en && !empty) begin
            if (sub_ptr == RATIO - 1) begin
                sub_ptr <= 0;
            end else begin
                sub_ptr <= sub_ptr + 1;
            end
        end
    end
endmodule

// Wrapper for image pixels
module fifo_generator_img (
    input  wire        clk,
    input  wire        srst,
    input  wire [63:0] din,
    input  wire        wr_en,
    input  wire        rd_en,
    output wire [7:0]  dout,
    output wire        full,
    output wire        empty
);
    fifo_asym #(
        .W_WIDTH(64),
        .R_WIDTH(8),
        .R_DEPTH(4096)
    ) inst (
        .clk  (clk),
        .srst (srst),
        .din  (din),
        .wr_en(wr_en),
        .full (full),
        .rd_en(rd_en),
        .dout (dout),
        .empty(empty)
    );
endmodule

// Wrapper for flow vectors
module fifo_generator_flow (
    input  wire        clk,
    input  wire        srst,
    input  wire [63:0] din,
    input  wire        wr_en,
    input  wire        rd_en,
    output wire [15:0] dout,
    output wire        full,
    output wire        empty
);
    fifo_asym #(
        .W_WIDTH(64),
        .R_WIDTH(16),
        .R_DEPTH(4096)
    ) inst (
        .clk  (clk),
        .srst (srst),
        .din  (din),
        .wr_en(wr_en),
        .full (full),
        .rd_en(rd_en),
        .dout (dout),
        .empty(empty)
    );
endmodule
