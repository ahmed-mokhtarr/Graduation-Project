module spu_fsm (
    input  wire        clk,
    input  wire        rst_n,

    // Control Inputs
    input  wire [3:0]  frame_nums, // {frame_i[1:0], frame_i_minus_1[1:0]}
    input  wire        start_spu,
    input  wire        layer_done, // Indicates read/write for current layer is complete

    // Outputs
    output reg         idle_spu,
    output reg         operation_start, //all operations start
    
    // Configuration Outputs to Memory Read Module
    output wire [1:0]  curr_frame_idx,
    output wire [1:0]  prev_frame_idx,
    output reg  [2:0]  current_layer,

);

    // -------------------------------------------------------------------------
    // FSM State Encoding
    // -------------------------------------------------------------------------
    localparam IDLE               = 2'b00;
    localparam PYRAMID_PROCESSING = 2'b01;
    localparam LAYER_SWITCHING    = 2'b10;

    reg [1:0] current_state;
    
    // Internal registers to hold the assigned frames during the entire processing
    reg [1:0] curr_frame;
    reg [1:0] prev_frame;

    // -------------------------------------------------------------------------
    // Combinational Configuration Logic
    // -------------------------------------------------------------------------

    
    // Pass the saved frame indices directly to the outputs
    assign curr_frame_idx = curr_frame;
    assign prev_frame_idx = prev_frame;

    // -------------------------------------------------------------------------
    // FSM Sequential Logic
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state         <= IDLE;
            idle_spu              <= 1'b1;
            operation_start          <= 1'b0;
            current_layer         <= 3'd0;
            curr_frame         <= 2'b00;
            prev_frame <= 2'b00;
        end else begin
            // Default pulse clear
            operation_start <= 1'b0;

            case (current_state)
                IDLE: begin
                    idle_spu <= 1'b1;
                    if (start_spu) begin
                        idle_spu              <= 1'b0;
                        curr_frame         <= frame_nums[3:2];
                        prev_frame <= frame_nums[1:0];
                        current_layer         <= 3'd4; // Start at the smallest layer
                        current_state         <= PYRAMID_PROCESSING;
                    end
                end

                PYRAMID_PROCESSING: begin
                    // Trigger memory read module using the output configuration
                    operation_start  <= 1'b1;
                    current_state <= LAYER_SWITCHING;
                end

                LAYER_SWITCHING: begin
                    // Wait for the memory read (and downstream processing) to finish the layer
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