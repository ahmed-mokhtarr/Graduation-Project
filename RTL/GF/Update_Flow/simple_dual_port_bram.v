module simple_dual_port_bram #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 12 // 2^12 = 4096 addresses
)(
    input  wire                  clk,
    
    // Write Port (Port A)
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data,
    
    // Read Port (Port B)
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  [DATA_WIDTH-1:0] rd_data
);

    // Mmeory
    reg [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    // Reset memory
    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
            ram[i] = 0;
        end
    end
    // -------------------------------

    // Write Logic
    always @(posedge clk) begin
        if (we) begin
            ram[wr_addr] <= wr_data;
        end
    end

    // Read Logic 
    always @(posedge clk) begin
        rd_data <= ram[rd_addr];
    end

endmodule