// =============================================================================
// mwm_acu.v  —  Memory Write Module Address Calculation Unit
//
// Computes the DDR write-back base address and total pixel count for the
// current layer.  Mirrors the MRM_ACU addressing scheme:
//   write_addr = FLOW_OUT_BASE + layer_offset
//
// The flow output region lives after all frame pyramid data.
// Each pixel produces a 16-bit delta (dx[7:0], dy[7:0]) = 2 bytes.
// =============================================================================
module mwm_acu #(
    parameter IMG_WIDTH       = 1280,
    parameter IMG_HEIGHT      = 720,
    parameter AXI_ADDR_WIDTH  = 32,
    parameter FLOW_OUT_BASE   = 32'h5000_0000   // base for writing computed flow
)(
    input  wire                       clk,
    input  wire                       rst_n,

    // From SPU FSM
    input  wire [2:0]                 current_layer,
    input  wire                       write_start,      // pulse: begin new layer

    // Outputs to AXI write master
    output reg  [AXI_ADDR_WIDTH-1:0]  write_base_addr,
    output reg  [31:0]                total_pixels,     // W × H for this layer
    output reg                        acu_valid         // pulse when outputs are latched
);

    // -------------------------------------------------------------------------
    // Pre-calculated layer offsets (in BYTES, 2 bytes per pixel for flow)
    // -------------------------------------------------------------------------
    localparam BYTES_PER_FLOW_PIXEL = 2;  // {dy, dx} = 16 bits = 2 bytes

    localparam OFFSET_L0 = 32'd0;
    localparam OFFSET_L1 = OFFSET_L0 + (IMG_WIDTH       * IMG_HEIGHT       * BYTES_PER_FLOW_PIXEL);
    localparam OFFSET_L2 = OFFSET_L1 + ((IMG_WIDTH >> 1) * (IMG_HEIGHT >> 1) * BYTES_PER_FLOW_PIXEL);
    localparam OFFSET_L3 = OFFSET_L2 + ((IMG_WIDTH >> 2) * (IMG_HEIGHT >> 2) * BYTES_PER_FLOW_PIXEL);
    localparam OFFSET_L4 = OFFSET_L3 + ((IMG_WIDTH >> 3) * (IMG_HEIGHT >> 3) * BYTES_PER_FLOW_PIXEL);

    // -------------------------------------------------------------------------
    // Combinational: layer dimensions and offset
    // -------------------------------------------------------------------------
    reg [31:0] layer_offset;
    reg [31:0] layer_pixels;

    always @(*) begin
        case (current_layer)
            3'd0: begin layer_pixels = IMG_WIDTH       * IMG_HEIGHT;       layer_offset = OFFSET_L0; end
            3'd1: begin layer_pixels = (IMG_WIDTH >> 1) * (IMG_HEIGHT >> 1); layer_offset = OFFSET_L1; end
            3'd2: begin layer_pixels = (IMG_WIDTH >> 2) * (IMG_HEIGHT >> 2); layer_offset = OFFSET_L2; end
            3'd3: begin layer_pixels = (IMG_WIDTH >> 3) * (IMG_HEIGHT >> 3); layer_offset = OFFSET_L3; end
            3'd4: begin layer_pixels = (IMG_WIDTH >> 4) * (IMG_HEIGHT >> 4); layer_offset = OFFSET_L4; end
            default: begin layer_pixels = 32'd0; layer_offset = 32'd0; end
        endcase
    end

    // -------------------------------------------------------------------------
    // Sequential: latch on write_start pulse
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_base_addr <= {AXI_ADDR_WIDTH{1'b0}};
            total_pixels    <= 32'd0;
            acu_valid       <= 1'b0;
        end else begin
            acu_valid <= 1'b0;  // default: 1-cycle pulse
            if (write_start) begin
                write_base_addr <= FLOW_OUT_BASE + layer_offset;
                total_pixels    <= layer_pixels;
                acu_valid       <= 1'b1;
            end
        end
    end

endmodule
