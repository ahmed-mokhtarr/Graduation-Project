// =============================================================================
// Module  : true_dual_port_bram
// Purpose : True Dual-Port BRAM with independent read/write on both ports.
//           Used for the Feature List ping-pong pair where the FSM writes on
//           Port A while the feature_sender reads on Port B.
// =============================================================================

module true_dual_port_bram #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 11   // 2^11 = 2048 addresses
)(
    input  wire                  clk,

    // Port A
    input  wire                  we_a,
    input  wire [ADDR_WIDTH-1:0] addr_a,
    input  wire [DATA_WIDTH-1:0] din_a,
    output reg  [DATA_WIDTH-1:0] dout_a,

    // Port B
    input  wire                  we_b,
    input  wire [ADDR_WIDTH-1:0] addr_b,
    input  wire [DATA_WIDTH-1:0] din_b,
    output reg  [DATA_WIDTH-1:0] dout_b
);

    // Memory
    reg [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    // Reset memory
    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1)
            ram[i] = {DATA_WIDTH{1'b0}};
    end

    // Port A — write-first
    always @(posedge clk) begin
        if (we_a) begin
            ram[addr_a] <= din_a;
            dout_a      <= din_a;
        end else begin
            dout_a <= ram[addr_a];
        end
    end

    // Port B — write-first
    always @(posedge clk) begin
        if (we_b) begin
            ram[addr_b] <= din_b;
            dout_b      <= din_b;
        end else begin
            dout_b <= ram[addr_b];
        end
    end

endmodule
