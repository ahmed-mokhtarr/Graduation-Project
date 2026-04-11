module mem_read_acu #(
    // Image Dimensions for Offset Calculation
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,

    // Base Addresses for Frame Slots and Flow Data
    parameter FRAME0_BASE = 32'h1000_0000,
    parameter FRAME1_BASE = 32'h2000_0000,
    parameter FRAME2_BASE = 32'h3000_0000,
    parameter FRAME3_BASE = 32'h4000_0000,
)(
    input  wire        clk,
    input  wire        rst_n,

    // Inputs from SPU FSM
    input  wire [1:0]  curr_frame_idx,
    input  wire [1:0]  prev_frame_idx,
    input  wire [2:0]  current_layer, 
    input  wire        mem_read_start,

    // Outputs to downstream Memory Read logic
    output reg  [31:0] curr_frame_addr,
    output reg  [31:0] prev_frame_addr,
    output reg  [31:0] flow_addr,
    output reg         flow_enable,
    output reg         start_read,
    output reg  [2:0]  current_layer_out
);

    // -------------------------------------------------------------------------
    // Pre-calculated Layer Offsets
    // Calculated sequentially based on downsampling (W * H >> 2 per layer)
    // -------------------------------------------------------------------------
    localparam OFFSET_L0 = 32'd0;
    localparam OFFSET_L1 = OFFSET_L0 + (IMG_WIDTH * IMG_HEIGHT);
    localparam OFFSET_L2 = OFFSET_L1 + ((IMG_WIDTH >> 1) * (IMG_HEIGHT >> 1));
    localparam OFFSET_L3 = OFFSET_L2 + ((IMG_WIDTH >> 2) * (IMG_HEIGHT >> 2));
    localparam OFFSET_L4 = OFFSET_L3 + ((IMG_WIDTH >> 3) * (IMG_HEIGHT >> 3));
    
    // Total size of all frame data (Original + 4 thumbnails)
    localparam TOTAL_FRAME_SIZE = OFFSET_L4 + ((IMG_WIDTH >> 4) * (IMG_HEIGHT >> 4));

    // -------------------------------------------------------------------------
    // Combinational Logic for Address Decoding
    // -------------------------------------------------------------------------
    reg [31:0] base_addr_curr;
    reg [31:0] base_addr_prev;
    reg [31:0] layer_offset;

    // Decode base address for current frame
    always @(*) begin
        case (curr_frame_idx)
            2'd0: base_addr_curr = FRAME0_BASE;
            2'd1: base_addr_curr = FRAME1_BASE;
            2'd2: base_addr_curr = FRAME2_BASE;
            2'd3: base_addr_curr = FRAME3_BASE;
            default: base_addr_curr = FRAME0_BASE;
        endcase
    end

    // Decode base address for previous frame
    always @(*) begin
        case (prev_frame_idx)
            2'd0: base_addr_prev = FRAME0_BASE;
            2'd1: base_addr_prev = FRAME1_BASE;
            2'd2: base_addr_prev = FRAME2_BASE;
            2'd3: base_addr_prev = FRAME3_BASE;
            default: base_addr_prev = FRAME0_BASE;
        endcase
    end

    // Decode layer offset
    always @(*) begin
        case (current_layer)
            3'd0: layer_offset = OFFSET_L0;
            3'd1: layer_offset = OFFSET_L1;
            3'd2: layer_offset = OFFSET_L2;
            3'd3: layer_offset = OFFSET_L3;
            3'd4: layer_offset = OFFSET_L4;
            default: layer_offset = OFFSET_L0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Sequential Logic: Latch and Output
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_frame_addr   <= 32'd0;
            prev_frame_addr   <= 32'd0;
            flow_addr         <= 32'd0;
            flow_enable       <= 1'b0;
            start_read        <= 1'b0;
            current_layer_out <= 3'd0;
        end else begin
            // Default: clear the start_read pulse after 1 clock cycle
            start_read <= 1'b0;

            if (mem_read_start) begin
                // Calculate and latch Frame Addresses
                curr_frame_addr <= base_addr_curr + layer_offset;
                prev_frame_addr <= base_addr_prev + layer_offset;
                
                // Calculate and latch Flow Address
                // It points to the region following the total frame data
                flow_addr <= base_addr_curr + TOTAL_FRAME_SIZE; 

                // Flow Enable Logic: Active for all except layer 4
                if (current_layer == 3'd4) begin
                    flow_enable <= 1'b0;
                end else begin
                    flow_enable <= 1'b1;
                end
                
                // Register the current layer and generate start pulse
                current_layer_out <= current_layer;
                start_read        <= 1'b1;
            end
        end
    end

endmodule