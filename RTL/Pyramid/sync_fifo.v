`timescale 1ns / 1ps

module pyr_sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 9 
)(
    input wire clk,
    input wire rst_n,
    
    input wire wr_en,
    input wire [DATA_WIDTH-1:0] din,
    output wire full,
    
    input wire rd_en,
    output wire [DATA_WIDTH-1:0] dout, 
    output wire empty,
    
    output wire [ADDR_WIDTH:0] data_count 
);
    reg [DATA_WIDTH-1:0] mem [(1<<ADDR_WIDTH)-1:0];
    
    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;

    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) && 
                   (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    assign data_count = wr_ptr - rd_ptr;

    assign dout = mem[rd_ptr[ADDR_WIDTH-1:0]];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            wr_ptr <= wr_ptr + 1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
        end else if (rd_en && !empty) begin
            rd_ptr <= rd_ptr + 1;
        end
    end

    always @(posedge clk)
     begin
      if (wr_en && !full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= din;  
      end   
     end   

    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
            mem[i] = 0;
        end
    end
endmodule