module TAU (
    input wire clk,
    input wire rst_n,
    input wire idle_spu1,
    input wire idle_spu2,
    input wire write_valid,
    input wire [1:0] frame_num,

    output reg [3:0] spu1_frames,
    output reg [3:0] spu2_frames,
    output reg start_spu1,
    output reg start_spu2,
    output reg overflow_flag
);

    // State Encoding
    localparam IDLE       = 2'b00;
    localparam S_1_FRAME  = 2'b01;
    localparam S_2_FRAMES = 2'b10;
    localparam S_3_FRAMES = 2'b11;

    reg [1:0] current_state;
    reg [1:0] frame_i_minus_1;
    reg [1:0] frame_i;
    reg [1:0] frame_i_plus_1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state   <= IDLE;
            frame_i_minus_1 <= 2'b00;
            frame_i         <= 2'b00;
            frame_i_plus_1  <= 2'b00;
            spu1_frames     <= 4'b0000;
            spu2_frames     <= 4'b0000;
            start_spu1      <= 1'b0;
            start_spu2      <= 1'b0;
            overflow_flag   <= 1'b0;
        end else begin
            // Default pulse signals (auto-clear next cycle)
            start_spu1    <= 1'b0;
            start_spu2    <= 1'b0;
            overflow_flag <= 1'b0;

            case (current_state)
                IDLE: begin
                    if (write_valid) begin
                        frame_i       <= frame_num;
                        current_state <= S_1_FRAME;
                    end
                end

                S_1_FRAME: begin
                    if (write_valid) begin
                        frame_i_minus_1 <= frame_i;
                        frame_i         <= frame_num;
                        current_state   <= S_2_FRAMES;
                    end
                end

                S_2_FRAMES: begin
                    if (idle_spu1 || idle_spu2) begin
                        // Assign task to an idle SPU
                        if (idle_spu1) begin
                            spu1_frames <= {frame_i, frame_i_minus_1};
                            start_spu1  <= 1'b1;
                        end else begin
                            spu2_frames <= {frame_i, frame_i_minus_1};
                            start_spu2  <= 1'b1;
                        end

                        // Check concurrent notification
                        if (write_valid) begin
                            frame_i_minus_1 <= frame_i;
                            frame_i         <= frame_num;
                            current_state   <= S_2_FRAMES; // Stay here, buffer depth remains the same
                        end else begin
                            current_state   <= S_1_FRAME;  // Task consumed, fallback to 1 frame waiting
                        end
                    end else begin
                        // No SPU is idle
                        if (write_valid) begin
                            frame_i_plus_1 <= frame_num;
                            current_state  <= S_3_FRAMES;
                        end
                    end
                end

                S_3_FRAMES: begin
                    // Raise overflow if a new frame attempts to write into a full state
                    if (write_valid) begin
                        overflow_flag <= 1'b1;
                    end

                    if (idle_spu1 && idle_spu2) begin
                        // Both SPUs are idle, assign two pairs simultaneously
                        spu1_frames <= {frame_i, frame_i_minus_1};
                        start_spu1  <= 1'b1;
                        
                        spu2_frames <= {frame_i_plus_1, frame_i};
                        start_spu2  <= 1'b1;

                        frame_i       <= frame_i_plus_1;
                        current_state <= S_1_FRAME;

                    end else if (idle_spu1 || idle_spu2) begin
                        // Only one SPU is idle
                        if (idle_spu1) begin
                            spu1_frames <= {frame_i, frame_i_minus_1};
                            start_spu1  <= 1'b1;
                        end else begin
                            spu2_frames <= {frame_i, frame_i_minus_1};
                            start_spu2  <= 1'b1;
                        end

                        // Shift buffer down
                        frame_i_minus_1 <= frame_i;
                        frame_i         <= frame_i_plus_1;
                        current_state   <= S_2_FRAMES;
                    end
                end

                default: current_state <= IDLE;
            endcase
        end
    end

endmodule