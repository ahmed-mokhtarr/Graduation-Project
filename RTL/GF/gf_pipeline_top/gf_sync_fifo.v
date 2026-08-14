`timescale 1ns / 1ps

module gf_sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 9 
)(
    input wire clk,
    input wire rst_n,
    input wire flush,
    
    input wire wr_en,
    input wire [DATA_WIDTH-1:0] din,
    output wire full,
    
    input wire rd_en,
    output wire [DATA_WIDTH-1:0] dout, 
    output wire empty
);

    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] bram_rd_ptr;
    wire [ADDR_WIDTH:0] rd_ptr = bram_rd_ptr; // alias for debug/tb probing

    wire bram_empty = (wr_ptr == bram_rd_ptr);
    assign full = (wr_ptr[ADDR_WIDTH] != bram_rd_ptr[ADDR_WIDTH]) && 
                  (wr_ptr[ADDR_WIDTH-1:0] == bram_rd_ptr[ADDR_WIDTH-1:0]);

    wire [DATA_WIDTH-1:0] bram_dout;

    simple_dual_port_bram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_bram (
        .clk    (clk),
        .we     (wr_en && !full),
        .wr_addr(wr_ptr[ADDR_WIDTH-1:0]),
        .wr_data(din),
        .rd_addr(bram_rd_ptr[ADDR_WIDTH-1:0]),
        .rd_data(bram_dout)
    );

    // FWFT Skid Buffer registers
    reg [DATA_WIDTH-1:0] dout_r;
    reg                  dout_valid;
    reg [DATA_WIDTH-1:0] skid_r;
    reg                  skid_valid;
    reg                  bram_rd_valid;

    assign empty = !dout_valid;
    assign dout  = dout_r;

    wire [1:0] committed = {1'b0, dout_valid} + {1'b0, skid_valid} + {1'b0, bram_rd_valid} - {1'b0, rd_en && dout_valid};
    wire can_pop_bram = !bram_empty && (committed < 2'd2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else if (flush) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            wr_ptr <= wr_ptr + 1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bram_rd_ptr   <= 0;
            bram_rd_valid <= 1'b0;
        end else if (flush) begin
            bram_rd_ptr   <= 0;
            bram_rd_valid <= 1'b0;
        end else begin
            bram_rd_valid <= can_pop_bram;
            if (can_pop_bram) begin
                bram_rd_ptr <= bram_rd_ptr + 1;
            end
        end
    end

    // Skid buffer FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout_valid <= 1'b0;
            skid_valid <= 1'b0;
            dout_r     <= 0;
            skid_r     <= 0;
        end else if (flush) begin
            dout_valid <= 1'b0;
            skid_valid <= 1'b0;
            dout_r     <= 0;
            skid_r     <= 0;
        end else begin
            if (rd_en && dout_valid) begin
                if (skid_valid) begin
                    dout_r     <= skid_r;
                    skid_valid <= 1'b0;
                    if (bram_rd_valid) begin
                        skid_r     <= bram_dout;
                        skid_valid <= 1'b1;
                    end
                end else if (bram_rd_valid) begin
                    dout_r <= bram_dout;
                end else begin
                    dout_valid <= 1'b0;
                end
            end else begin
                if (!dout_valid && bram_rd_valid) begin
                    dout_r     <= bram_dout;
                    dout_valid <= 1'b1;
                end else if (dout_valid && !skid_valid && bram_rd_valid) begin
                    skid_r     <= bram_dout;
                    skid_valid <= 1'b1;
                end
            end
        end
    end

endmodule