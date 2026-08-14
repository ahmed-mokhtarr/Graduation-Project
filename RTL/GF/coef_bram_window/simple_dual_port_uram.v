// =============================================================================
// simple_dual_port_uram.v
//
// Simple dual-port memory mapped to UltraRAM (URAM) on UltraScale+ FPGAs.
// Each URAM is 72-bit × 4096 deep (288Kb). Vivado cascades for deeper/wider.
//
// Key differences from BRAM:
//   - (* ram_style = "ultra" *) attribute forces URAM mapping
//   - No initial block (URAM does not support initialization)
//   - Synchronous read with registered output (same as BRAM)
// =============================================================================
module simple_dual_port_uram #(
    parameter DATA_WIDTH = 72,
    parameter ADDR_WIDTH = 12  // 2^12 = 4096 addresses (1 URAM deep)
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

    // Force Vivado to map this to UltraRAM
    (* ram_style = "ultra" *)
    reg [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    // Zero memory for simulation (Vivado ignores initial for URAM)
    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1)
            ram[i] = {DATA_WIDTH{1'b0}};
    end

    // Write Logic
    always @(posedge clk) begin
        if (we) begin
            ram[wr_addr] <= wr_data;
        end
    end

    // Read Logic (synchronous, registered output — required for URAM)
    always @(posedge clk) begin
        rd_data <= ram[rd_addr];
    end

endmodule
