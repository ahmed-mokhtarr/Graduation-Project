module spu_fsm #(
    // Image Parameters
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter D_VECTOR_SIZE = 32, // Size of optical flow vector data

    // Hardcoded Base Addresses in Memory for the 4 frame slots and the flow buffer
    parameter FRAME0_BASE = 32'h1000_0000,
    parameter FRAME1_BASE = 32'h2000_0000,
    parameter FRAME2_BASE = 32'h3000_0000,
    parameter FRAME3_BASE = 32'h4000_0000,
    parameter FLOW_BASE   = 32'h5000_0000 
)(
    input  wire        clk,
    input  wire        rst_n,

    // Control Inputs
    input  wire [3:0]  frame_nums, // {frame_i[1:0], frame_i_minus_1[1:0]}
    input  wire        start_spu,
    input  wire        layer_done, // Indicates write/processing for current layer is complete

    // Outputs
    output reg         idle_spu,
    output reg         mem_read_cmd,
    output wire [31:0] addr_frame_i,
    output wire [31:0] addr_frame_i_minus_1,
    output wire [31:0] addr_upper_opt_flow,
    
    // layer_config: {has_flow (1 bit), current_layer_idx (3 bits)}
    // Read module uses this to know dimensions and whether to fetch upper flow
    output wire [3:0]  layer_config 
);

    // -------------------------------------------------------------------------
    // Local Parameters for Layer Offsets
    // Calculated sequentially based on downsampling (1/4 area per layer)
    // -------------------------------------------------------------------------
    localparam OFFSET_L0 = 32'd0;
    localparam OFFSET_L1 = OFFSET_L0 + (IMG_WIDTH * IMG_HEIGHT);
    localparam OFFSET_L2 = OFFSET_L1 + ((IMG_WIDTH/2) * (IMG_HEIGHT/2));
    localparam OFFSET_L3 = OFFSET_L2 + ((IMG_WIDTH/4) * (IMG_HEIGHT/4));
    localparam OFFSET_L4 = OFFSET_L3 + ((IMG_WIDTH/8) * (IMG_HEIGHT/8));

    // -------------------------------------------------------------------------
    // FSM State Encoding
    // -------------------------------------------------------------------------
    localparam IDLE               = 2'b00;
    localparam PYRAMID_PROCESSING = 2'b01;
    localparam LAYER_SWITCHING    = 2'b10;

    reg [1:0] current_state;
    reg [2:0] current_layer;
    
    // Internal registers to hold the assigned frames during the entire frame processing
    reg [1:0] saved_frame_i;
    reg [1:0] saved_frame_i_minus_1;

    // -------------------------------------------------------------------------
    // Combinational Address & Config Calculation
    // -------------------------------------------------------------------------
    reg [31:0] base_addr_i;
    reg [31:0] base_addr_i_minus_1;
    reg [31:0] layer_offset;
    reg        has_flow;

    // Decode base address for current frame
    always @(*) begin
        case (saved_frame_i)
            2'd0: base_addr_i = FRAME0_BASE;
            2'd1: base_addr_i = FRAME1_BASE;
            2'd2: base_addr_i = FRAME2_BASE;
            2'd3: base_addr_i = FRAME3_BASE;
            default: base_addr_i = FRAME0_BASE;
        caseend
    end

    // Decode base address for previous frame
    always @(*) begin
        case (saved_frame_i_minus_1)
            2'd0: base_addr_i_minus_1 = FRAME0_BASE;
            2'd1: base_addr_i_minus_1 = FRAME1_BASE;
            2'd2: base_addr_i_minus_1 = FRAME2_BASE;
            2'd3: base_addr_i_minus_1 = FRAME3_BASE;
            default: base_addr_i_minus_1 = FRAME0_BASE;
        caseend
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
        caseend
    end

    // Determine if upper optical flow exists
    // Layer 4 is the smallest (top of pyramid), so it has no upper flow to read
    always @(*) begin
        has_flow = (current_layer < 3'd4) ? 1'b1 : 1'b0;
    end

    // Assign final combinational outputs
    assign addr_frame_i         = base_addr_i + layer_offset;
    assign addr_frame_i_minus_1 = base_addr_i_minus_1 + layer_offset;
    assign addr_upper_opt_flow  = has_flow ? FLOW_BASE : 32'd0;
    assign layer_config         = {has_flow, current_layer};

    // -------------------------------------------------------------------------
    // FSM Sequential Logic
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state         <= IDLE;
            idle_spu              <= 1'b1;
            mem_read_cmd          <= 1'b0;
            current_layer         <= 3'd0;
            saved_frame_i         <= 2'b00;
            saved_frame_i_minus_1 <= 2'b00;
        end else begin
            // Default pulse clear
            mem_read_cmd <= 1'b0;

            case (current_state)
                IDLE: begin
                    idle_spu <= 1'b1;
                    if (start_spu) begin
                        idle_spu              <= 1'b0;
                        saved_frame_i         <= frame_nums[3:2];
                        saved_frame_i_minus_1 <= frame_nums[1:0];
                        current_layer         <= 3'd4; // Start at the smallest layer
                        current_state         <= PYRAMID_PROCESSING;
                    end
                end

                PYRAMID_PROCESSING: begin
                    // Trigger memory read module using the combinational addresses/config
                    mem_read_cmd  <= 1'b1;
                    current_state <= LAYER_SWITCHING;
                end

                LAYER_SWITCHING: begin
                    if (layer_done) begin
                        if (current_layer > 3'd0) begin
                            // Move down the pyramid to the next larger layer
                            current_layer <= current_layer - 3'd1;
                            current_state <= PYRAMID_PROCESSING;
                        end else begin
                            // Layer 0 finished, full GF flow vector calculated
                            idle_spu      <= 1'b1;
                            current_state <= IDLE;
                        end
                    end
                end

                default: current_state <= IDLE;
            endcase
        end
    end

endmodule