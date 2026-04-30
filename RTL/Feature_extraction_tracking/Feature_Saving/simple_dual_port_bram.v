module simple_dual_port_bram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 12
) (
    input  wire              clk,
    
    // Write port
    input  wire              we,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data,
    
    // Read port
    input  wire              re,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  [DATA_WIDTH-1:0] rd_data
);

    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    always @(posedge clk) begin
        if (we) begin
            mem[wr_addr] <= wr_data;
        end
        if (re) begin
            rd_data <= mem[rd_addr];
        end
    end

endmodule